// Application state.
//
// The Tauri build kept state in module-level variables in main.ts and re-read
// the database after every mutation. That shape survives here as a
// ChangeNotifier: mutate the local store, reload, notify. Reads are cheap
// (local SQLite, small lists) and it keeps the UI a pure function of the DB,
// which is what made focus mode survivable across restarts.

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'sync/local_store.dart';
import 'sync/models.dart';
import 'theme.dart';

const _kLastWorkspace = 'ui:last-workspace';
const _kNudge = 'ui:nudge-enabled';

class AppState extends ChangeNotifier {
  AppState(this._store);

  final LocalStore _store;

  LocalStore get store => _store;

  /// Called after any change that produces dirty rows, so sync can be
  /// scheduled. Left null in tests, which have no server.
  void Function()? onMutated;

  void _mutated() => onMutated?.call();

  List<Workspace> workspaces = [];
  String? currentWorkspaceUuid;

  List<Task> tasks = [];
  List<Task> historyTasks = [];
  List<SideThought> thoughts = [];

  /// The task owning the focus view, or null when the list is showing. Mirrors
  /// `in_progress` in the database, which is exclusive and global.
  Task? focusTask;

  bool nudgeEnabled = true;
  bool showHistory = false;

  Workspace? get currentWorkspace {
    for (final w in workspaces) {
      if (w.uuid == currentWorkspaceUuid) return w;
    }
    return workspaces.isEmpty ? null : workspaces.first;
  }

  int get thoughtCount => thoughts.length;

  Future<void> load() async {
    nudgeEnabled = (await _store.setting(_kNudge)) != '0';
    currentWorkspaceUuid = await _store.setting(_kLastWorkspace);
    await refreshWorkspaces();
    await refreshTasks();
    await refreshThoughts();
    await restoreFocus();
  }

  // ----------------------------------------------------------- workspaces

  Future<void> refreshWorkspaces() async {
    workspaces = await _store.workspaces();
    final known = workspaces.any((w) => w.uuid == currentWorkspaceUuid);
    if (!known) {
      currentWorkspaceUuid = workspaces.isEmpty ? null : workspaces.first.uuid;
    }
    notifyListeners();
  }

  Future<void> selectWorkspace(String uuid) async {
    currentWorkspaceUuid = uuid;
    await _store.setSetting(_kLastWorkspace, uuid);
    showHistory = false;
    await refreshTasks();
    _mutated();
  }

  Future<void> saveWorkspace({
    String? uuid,
    required String name,
    required String color,
  }) async {
    if (uuid == null) {
      final ws = Workspace(
        uuid: newId(),
        name: name,
        color: color,
        sortOrder: workspaces.length,
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );
      await _store.putWorkspace(ws);
      await refreshWorkspaces();
      await selectWorkspace(ws.uuid);
      return;
    }

    final existing = workspaces.firstWhere((w) => w.uuid == uuid);
    await _store.putWorkspace(
      existing.copyWith(name: name, color: color, updatedAt: nowStamp()),
    );
    await refreshWorkspaces();
  }

  /// Tombstones the workspace and everything in it.
  ///
  /// The cascade covers completed tasks as well as active ones, otherwise
  /// history would keep pointing at a workspace that no longer exists. Every
  /// row is tombstoned rather than dropped, so the deletion reaches other
  /// devices - and note that it reaches them irreversibly, since there is no
  /// undo once a peer has merged it.
  Future<void> deleteWorkspace(String uuid) async {
    if (workspaces.length <= 1) return;
    final stamp = nowStamp();

    for (final t in await _store.allTasksInWorkspace(uuid)) {
      await _store.putTask(t.copyWith(deletedAt: stamp, updatedAt: stamp));
    }

    final ws = workspaces.firstWhere((w) => w.uuid == uuid);
    await _store.putWorkspace(ws.copyWith(deletedAt: stamp, updatedAt: stamp));

    if (focusTask?.workspaceUuid == uuid) focusTask = null;
    currentWorkspaceUuid = null;
    await refreshWorkspaces();
    await refreshTasks();
    _mutated();
  }

  // ---------------------------------------------------------------- tasks

  Future<void> refreshTasks() async {
    final ws = currentWorkspaceUuid;
    if (ws == null) {
      tasks = [];
      historyTasks = [];
    } else {
      tasks = await _store.activeTasks(ws);
      if (showHistory) historyTasks = await _store.history(ws);
    }
    notifyListeners();
  }

  Future<void> addTask(String text) async {
    final ws = currentWorkspaceUuid;
    if (ws == null || text.trim().isEmpty) return;
    await _store.putTask(Task(
      uuid: newId(),
      workspaceUuid: ws,
      text: text.trim(),
      createdAt: nowStamp(),
      sortOrder: await _store.nextSortOrder(ws),
      updatedAt: nowStamp(),
    ));
    await refreshTasks();
    _mutated();
  }

  /// Check off: keeps the row and stamps completed_at, so it shows in history.
  Future<void> completeTask(Task t) async {
    await _store.putTask(
      t.copyWith(completedAt: nowStamp(), inProgress: false, updatedAt: nowStamp()),
    );
    if (focusTask?.uuid == t.uuid) focusTask = null;
    await refreshTasks();
    _mutated();
  }

  /// Dismiss without logging: tombstoned, so the delete reaches other devices.
  /// The old backend dropped the row outright, which a peer could not tell
  /// apart from a row it had simply never seen.
  Future<void> deleteTask(Task t) async {
    await _store.putTask(
      t.copyWith(deletedAt: nowStamp(), updatedAt: nowStamp()),
    );
    if (focusTask?.uuid == t.uuid) focusTask = null;
    await refreshTasks();
    _mutated();
  }

  Future<void> reorder(List<String> uuids) async {
    await _store.reorderTasks(uuids);
    await refreshTasks();
    _mutated();
  }

  Future<void> toggleHistory() async {
    showHistory = !showHistory;
    if (showHistory && currentWorkspaceUuid != null) {
      historyTasks = await _store.history(currentWorkspaceUuid!);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- focus

  Future<void> enterFocus(Task t) async {
    await _store.setInProgress(t.uuid, true);
    focusTask = t;
    await refreshTasks();
    _mutated();
  }

  Future<void> exitFocus() async {
    final t = focusTask;
    if (t == null) return;
    focusTask = null;
    await _store.setInProgress(t.uuid, false);
    await refreshTasks();
    _mutated();
  }

  /// If a task was still in progress when the app last closed, drop straight
  /// back into focus on it - switching workspace if it lives in another one.
  Future<void> restoreFocus() async {
    final t = await _store.inProgressTask();
    if (t == null) return;
    if (t.workspaceUuid != currentWorkspaceUuid) {
      currentWorkspaceUuid = t.workspaceUuid;
      await _store.setSetting(_kLastWorkspace, t.workspaceUuid);
      await refreshWorkspaces();
      await refreshTasks();
    }
    focusTask = t;
    notifyListeners();
  }

  Future<void> setNudge(bool on) async {
    nudgeEnabled = on;
    await _store.setSetting(_kNudge, on ? '1' : '0');
    notifyListeners();
  }

  // -------------------------------------------------------- side thoughts

  Future<void> refreshThoughts() async {
    thoughts = await _store.pendingThoughts();
    notifyListeners();
  }

  Future<void> addThought(String text) async {
    if (text.trim().isEmpty) return;
    await _store.putThought(SideThought(
      uuid: newId(),
      text: text.trim(),
      createdAt: nowStamp(),
      updatedAt: nowStamp(),
    ));
    await refreshThoughts();
    _mutated();
  }

  /// Tidy a thought into a real task. The thought is resolved rather than
  /// deleted - side thoughts are never hard-removed, so the record survives.
  Future<void> promoteThought(SideThought s) async {
    await addTask(s.text);
    await resolveThought(s);
  }

  Future<void> resolveThought(SideThought s) async {
    await _store.putThought(
      s.copyWith(resolvedAt: nowStamp(), updatedAt: nowStamp()),
    );
    await refreshThoughts();
    _mutated();
  }

  /// The close guard reads the database directly rather than the cached list,
  /// so a resolve still in flight cannot wrongly block or wrongly allow a
  /// close.
  Future<bool> canProceedPastThoughts() async {
    return (await _store.pendingThoughts()).isEmpty;
  }

  // ---------------------------------------------------------------- tint

  Color get workspaceColor {
    final ws = currentWorkspace;
    return ws == null ? T.accent : T.parseHex(ws.color);
  }
}
