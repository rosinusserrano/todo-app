// One-time import of the Tauri-era database.
//
// The old build kept integer primary keys and no sync columns; this one keys
// everything by UUID and carries updated_at/deleted_at/dirty. The two schemas
// cannot be reconciled in place, so the old database is read as a source and
// left completely untouched - if this goes wrong, the original is still there.
//
// Imported rows are marked dirty, so the history the old app accumulated is
// pushed to the sync server and reaches the phone like any other local edit.

import 'dart:io' show File, Platform;

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'local_store.dart';
import 'models.dart';

/// What an import attempt did, so the caller can log it and tests can assert on
/// it. [ranAlready] and [noSource] are the two ordinary no-ops - neither is an
/// error, and both are the expected outcome on every launch after the first.
class LegacyImportResult {
  const LegacyImportResult({
    this.workspaces = 0,
    this.tasks = 0,
    this.thoughts = 0,
    this.ranAlready = false,
    this.noSource = false,
  });

  final int workspaces;
  final int tasks;
  final int thoughts;
  final bool ranAlready;
  final bool noSource;

  bool get importedAnything => workspaces + tasks + thoughts > 0;

  @override
  String toString() => ranAlready
      ? 'legacy import: already done'
      : noSource
          ? 'legacy import: no old database found'
          : 'legacy import: $workspaces workspaces, $tasks tasks, '
              '$thoughts side thoughts';
}

class LegacyImport {
  /// Recorded in sync_state, which is device-local and never synced - exactly
  /// the right scope. The import is a fact about *this* machine's disk, not
  /// about the todo list, and a second device must not conclude it has already
  /// imported its own old database because this one did.
  static const settingKey = 'legacy_import_v1';

  /// Where the Tauri build kept its database: `app_data_dir()/todo.db`, which
  /// on Windows resolves to `%APPDATA%\<bundle identifier>\`. The old app only
  /// ever ran on Windows, so there is nothing to look for anywhere else.
  static String? defaultSourcePath() {
    if (!Platform.isWindows) return null;
    final appData = Platform.environment['APPDATA'];
    if (appData == null) return null;
    return p.join(appData, 'com.marco.todowidget', 'todo.db');
  }

  /// Copies the old database into [store] if it exists and has not been
  /// imported before. Safe to call on every launch.
  ///
  /// The whole import is one transaction *including* the flag that records it,
  /// so a failure halfway leaves the database exactly as it was rather than
  /// half-populated with no way to tell.
  static Future<LegacyImportResult> run(LocalStore store, {String? path}) async {
    if (await store.setting(settingKey) != null) {
      return const LegacyImportResult(ranAlready: true);
    }

    final source = path ?? defaultSourcePath();
    if (source == null || !File(source).existsSync()) {
      // Not marked as done: there is nothing to import *yet*, and the check is
      // a single stat on a path we already have.
      return const LegacyImportResult(noSource: true);
    }

    final old = await databaseFactory.openDatabase(
      source,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );

    try {
      final oldWorkspaces =
          await old.query('workspaces', orderBy: 'sort_order, id');
      final oldTasks = await old.query('tasks', orderBy: 'id');
      final oldThoughts = await old.query('side_thoughts', orderBy: 'id');

      final now = nowStamp();
      var counts = const LegacyImportResult();

      await store.raw.transaction((txn) async {
        // Old integer ids mean nothing in the new schema, so every row gets a
        // fresh UUID and the foreign keys are rewritten through this map.
        final wsUuid = <int, String>{};

        for (final w in oldWorkspaces) {
          final uuid = newId();
          wsUuid[w['id'] as int] = uuid;
          await txn.insert('workspaces', {
            'uuid': uuid,
            'name': w['name'] as String,
            'color': w['color'] as String,
            'sort_order': w['sort_order'] as int? ?? 0,
            'created_at': w['created_at'] as String,
            'updated_at': now,
            'deleted_at': null,
            'dirty': 1,
          });
        }

        // Focus mode is globally exclusive, and the new schema relies on that.
        // The old one enforced it too, but a database is a database - if two
        // rows somehow carry the flag, only the first keeps it.
        var focusTaken = false;
        var tasks = 0;

        // A task pointing at a workspace that is not in the old database would
        // otherwise vanish; it lands in the first workspace instead, where it
        // is at least visible and can be moved.
        final fallbackWs = wsUuid.isEmpty ? null : wsUuid.values.first;

        for (final t in oldTasks) {
          final ws = wsUuid[t['workspace_id'] as int?] ?? fallbackWs;
          // Only reachable if the old database had tasks but no workspaces at
          // all. Nothing sensible to point them at, so they are skipped rather
          // than inserted somewhere they could never be found.
          if (ws == null) continue;

          final wantsFocus =
              (t['in_progress'] as int? ?? 0) == 1 && t['completed_at'] == null;
          final focus = wantsFocus && !focusTaken;
          if (focus) focusTaken = true;

          await txn.insert('tasks', {
            'uuid': newId(),
            'workspace_uuid': ws,
            'text': t['text'] as String,
            'created_at': t['created_at'] as String,
            'completed_at': t['completed_at'] as String?,
            'sort_order': t['sort_order'] as int? ?? 0,
            'in_progress': focus ? 1 : 0,
            'remind_at': null, // the old build had no reminders
            'updated_at': now,
            'deleted_at': null,
            'dirty': 1,
          });
          tasks++;
        }

        for (final s in oldThoughts) {
          await txn.insert('side_thoughts', {
            'uuid': newId(),
            'text': s['text'] as String,
            'created_at': s['created_at'] as String,
            'resolved_at': s['resolved_at'] as String?,
            'updated_at': now,
            'deleted_at': null,
            'dirty': 1,
          });
        }

        await txn.insert(
          'sync_state',
          {'key': settingKey, 'value': now},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        counts = LegacyImportResult(
          workspaces: oldWorkspaces.length,
          tasks: tasks,
          thoughts: oldThoughts.length,
        );
      });

      return counts;
    } finally {
      await old.close();
    }
  }
}
