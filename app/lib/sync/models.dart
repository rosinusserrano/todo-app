// Row models shared by the local database and the sync protocol.
//
// Every model carries the three sync columns described in server/db.js:
// a client-generated `uuid`, an `updatedAt` used for last-write-wins conflict
// resolution, and a `deletedAt` tombstone. Nothing is ever hard-deleted, so a
// peer can always tell "removed" from "not yet seen".

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// Timestamps are RFC 3339 with an offset, matching what the Rust backend
/// wrote (`chrono::Local::now().to_rfc3339()`), so existing rows migrate
/// without reformatting.
String nowStamp() => DateTime.now().toIso8601String();

/// Reminders are stored as an instant, in UTC, unlike the local-time stamps
/// above. A reminder is a moment ("in an hour", or the instant 18:00 resolved
/// to on the device that set it), so the instant is the part that has to
/// survive travelling to another timezone - the wall-clock reading is not.
String reminderStamp(DateTime at) => at.toUtc().toIso8601String();

/// String comparison is a valid ordering for RFC 3339 only when the offsets
/// match, which is not guaranteed once a phone crosses a timezone. Parsing and
/// comparing as instants is correct everywhere.
int compareStamps(String a, String b) {
  final pa = DateTime.tryParse(a);
  final pb = DateTime.tryParse(b);
  if (pa == null || pb == null) return a.compareTo(b);
  return pa.toUtc().compareTo(pb.toUtc());
}

abstract class SyncRow {
  String get uuid;
  String get updatedAt;
  String? get deletedAt;

  bool get isDeleted => deletedAt != null;

  Map<String, Object?> toMap();
}

class Workspace implements SyncRow {
  @override
  final String uuid;
  final String name;
  final String color;
  final int sortOrder;
  final String createdAt;
  @override
  final String updatedAt;
  @override
  final String? deletedAt;

  const Workspace({
    required this.uuid,
    required this.name,
    required this.color,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  bool get isDeleted => deletedAt != null;

  Workspace copyWith({
    String? name,
    String? color,
    int? sortOrder,
    String? updatedAt,
    String? deletedAt,
    bool clearDeleted = false,
  }) =>
      Workspace(
        uuid: uuid,
        name: name ?? this.name,
        color: color ?? this.color,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: updatedAt ?? nowStamp(),
        deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      );

  @override
  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'name': name,
        'color': color,
        'sort_order': sortOrder,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static Workspace fromMap(Map<String, Object?> m) => Workspace(
        uuid: m['uuid']! as String,
        name: m['name']! as String,
        color: m['color']! as String,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        createdAt: m['created_at']! as String,
        updatedAt: m['updated_at']! as String,
        deletedAt: m['deleted_at'] as String?,
      );
}

class Task implements SyncRow {
  @override
  final String uuid;
  final String workspaceUuid;
  final String text;
  final String createdAt;

  /// Null means active; set means completed, and the value is when it was
  /// checked off. This is the same state flag the Rust backend used, kept so
  /// history survives the migration.
  final String? completedAt;
  final int sortOrder;

  /// Focus mode. Globally exclusive - see the normalization in server/db.js
  /// for why that invariant needs enforcing after a merge.
  final bool inProgress;

  /// When this task should nag, or null for no reminder. Syncs like any other
  /// field, so setting a reminder on the phone arms it on the desktop too.
  ///
  /// Whether it has *already* fired is deliberately not stored here: that is a
  /// per-device fact, and syncing it would mean the first device to remind you
  /// silences all the others.
  final String? remindAt;

  @override
  final String updatedAt;
  @override
  final String? deletedAt;

  const Task({
    required this.uuid,
    required this.workspaceUuid,
    required this.text,
    required this.createdAt,
    this.completedAt,
    this.sortOrder = 0,
    this.inProgress = false,
    this.remindAt,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isActive => completedAt == null && deletedAt == null;

  /// Local time, for display. The stored value is UTC - see [reminderStamp].
  DateTime? get remindAtTime {
    final parsed = remindAt == null ? null : DateTime.tryParse(remindAt!);
    return parsed?.toLocal();
  }

  /// Armed and in the past, on a task still worth nagging about. The row keeps
  /// showing this until the reminder is cleared or the task is checked off -
  /// the alert is a state, not just the instant it fired.
  bool isDue([DateTime? now]) {
    final at = remindAtTime;
    if (at == null || !isActive) return false;
    return !at.isAfter(now ?? DateTime.now());
  }

  @override
  bool get isDeleted => deletedAt != null;

  Task copyWith({
    String? workspaceUuid,
    String? text,
    String? completedAt,
    int? sortOrder,
    bool? inProgress,
    String? remindAt,
    String? updatedAt,
    String? deletedAt,
    bool clearCompleted = false,
    bool clearDeleted = false,
    bool clearReminder = false,
  }) =>
      Task(
        uuid: uuid,
        workspaceUuid: workspaceUuid ?? this.workspaceUuid,
        text: text ?? this.text,
        createdAt: createdAt,
        completedAt: clearCompleted ? null : (completedAt ?? this.completedAt),
        sortOrder: sortOrder ?? this.sortOrder,
        inProgress: inProgress ?? this.inProgress,
        remindAt: clearReminder ? null : (remindAt ?? this.remindAt),
        updatedAt: updatedAt ?? nowStamp(),
        deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      );

  @override
  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'workspace_uuid': workspaceUuid,
        'text': text,
        'created_at': createdAt,
        'completed_at': completedAt,
        'sort_order': sortOrder,
        'in_progress': inProgress ? 1 : 0,
        'remind_at': remindAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static Task fromMap(Map<String, Object?> m) => Task(
        uuid: m['uuid']! as String,
        workspaceUuid: m['workspace_uuid']! as String,
        text: m['text']! as String,
        createdAt: m['created_at']! as String,
        completedAt: m['completed_at'] as String?,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        inProgress: ((m['in_progress'] as num?)?.toInt() ?? 0) != 0,
        remindAt: m['remind_at'] as String?,
        updatedAt: m['updated_at']! as String,
        deletedAt: m['deleted_at'] as String?,
      );
}

class SideThought implements SyncRow {
  @override
  final String uuid;
  final String text;
  final String createdAt;

  /// Side thoughts are never hard-deleted - discarding one resolves it, so the
  /// full history stays in the database.
  final String? resolvedAt;
  @override
  final String updatedAt;
  @override
  final String? deletedAt;

  const SideThought({
    required this.uuid,
    required this.text,
    required this.createdAt,
    this.resolvedAt,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isPending => resolvedAt == null && deletedAt == null;

  @override
  bool get isDeleted => deletedAt != null;

  SideThought copyWith({
    String? text,
    String? resolvedAt,
    String? updatedAt,
    String? deletedAt,
  }) =>
      SideThought(
        uuid: uuid,
        text: text ?? this.text,
        createdAt: createdAt,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        updatedAt: updatedAt ?? nowStamp(),
        deletedAt: deletedAt ?? this.deletedAt,
      );

  @override
  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'text': text,
        'created_at': createdAt,
        'resolved_at': resolvedAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static SideThought fromMap(Map<String, Object?> m) => SideThought(
        uuid: m['uuid']! as String,
        text: m['text']! as String,
        createdAt: m['created_at']! as String,
        resolvedAt: m['resolved_at'] as String?,
        updatedAt: m['updated_at']! as String,
        deletedAt: m['deleted_at'] as String?,
      );
}
