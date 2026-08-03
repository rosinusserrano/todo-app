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

/// Reminders and calendar events are stored as an instant, in UTC, unlike the
/// local-time stamps above. Both are a moment ("in an hour", or the instant
/// 18:00 resolved to on the device that set it), so the instant is the part
/// that has to survive travelling to another timezone - the wall-clock reading
/// is not.
///
/// Truncated to milliseconds, which is what makes these safe to compare **as
/// strings** in SQL - the way [LocalStore.eventsBetween] does. `toIso8601String`
/// prints three fractional digits when the microseconds are zero and six when
/// they are not, and "…00.000Z" sorts *after* "…00.000500Z" because 'Z' is
/// greater than '1'. Every instant printed at the same precision removes that
/// entirely.
String reminderStamp(DateTime at) {
  final utc = at.toUtc();
  final ms = DateTime.fromMillisecondsSinceEpoch(
    utc.millisecondsSinceEpoch,
    isUtc: true,
  );
  return ms.toIso8601String();
}

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

/// A titled shelf of tasks inside one workspace - "Backlog", "Future ideas".
///
/// The point of a parked group is that it is *not* your current list, so
/// nothing in it competes with the tasks you actually mean to do today. What
/// stops that from becoming a place things go to die is [reviewEveryDays]: the
/// group goes overdue on its own schedule and says so, and clearing that is a
/// deliberate act rather than something time does for you.
class ParkedGroup implements SyncRow {
  @override
  final String uuid;
  final String workspaceUuid;
  final String title;

  /// How often the group asks to be looked at. Monthly by default.
  final int reviewEveryDays;

  /// When it was last reviewed, or null if never - in which case the clock runs
  /// from [createdAt] instead, so a group made today is not instantly overdue.
  final String? lastReviewedAt;

  final int sortOrder;
  final String createdAt;
  @override
  final String updatedAt;
  @override
  final String? deletedAt;

  static const defaultReviewEveryDays = 30;

  const ParkedGroup({
    required this.uuid,
    required this.workspaceUuid,
    required this.title,
    this.reviewEveryDays = defaultReviewEveryDays,
    this.lastReviewedAt,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  bool get isDeleted => deletedAt != null;

  /// When the next review falls due. Parsed as instants for the same reason
  /// [compareStamps] exists - the stamps can come from another timezone.
  DateTime? get reviewDueAt {
    final from = DateTime.tryParse(lastReviewedAt ?? createdAt);
    if (from == null || reviewEveryDays <= 0) return null;
    return from.toLocal().add(Duration(days: reviewEveryDays));
  }

  bool isReviewDue([DateTime? now]) {
    final at = reviewDueAt;
    if (at == null) return false;
    return !at.isAfter(now ?? DateTime.now());
  }

  ParkedGroup copyWith({
    String? title,
    int? reviewEveryDays,
    String? lastReviewedAt,
    int? sortOrder,
    String? updatedAt,
    String? deletedAt,
    bool clearDeleted = false,
  }) =>
      ParkedGroup(
        uuid: uuid,
        workspaceUuid: workspaceUuid,
        title: title ?? this.title,
        reviewEveryDays: reviewEveryDays ?? this.reviewEveryDays,
        lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: updatedAt ?? nowStamp(),
        deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      );

  @override
  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'workspace_uuid': workspaceUuid,
        'title': title,
        'review_every_days': reviewEveryDays,
        'last_reviewed_at': lastReviewedAt,
        'sort_order': sortOrder,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static ParkedGroup fromMap(Map<String, Object?> m) => ParkedGroup(
        uuid: m['uuid']! as String,
        workspaceUuid: m['workspace_uuid']! as String,
        title: m['title']! as String,
        reviewEveryDays: (m['review_every_days'] as num?)?.toInt() ??
            defaultReviewEveryDays,
        lastReviewedAt: m['last_reviewed_at'] as String?,
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

  /// The [ParkedGroup] this task is shelved in, or null for a task on the
  /// current list. One nullable column rather than a second table: a parked
  /// task is the same row with the same history, just not on today's list, and
  /// splitting it in two would mean moving rows back and forth - losing the
  /// uuid, and with it the reminder and everything sync knows about it.
  final String? groupUuid;

  /// The [CalendarEvent] this task is planned into, or null for one that is not
  /// tied to a block of time.
  ///
  /// One nullable column for the same reason [groupUuid] is one: a planned task
  /// is the same row, with the same history, reminder and uuid - it has simply
  /// been said *when*. The cost is that a task belongs to at most one block,
  /// which a join table would not impose; that is the right trade here, because
  /// "do this twice" is two tasks, and a second table would have to be created,
  /// migrated, synced and garbage-collected to express it.
  ///
  /// Unlike parking, this does **not** take the task off the list: it is still
  /// something to do today, and hiding it until its block came round would make
  /// planning a week a way to lose things.
  final String? eventUuid;

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
    this.groupUuid,
    this.eventUuid,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isActive => completedAt == null && deletedAt == null;

  bool get isParked => groupUuid != null;

  bool get isPlanned => eventUuid != null;

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
    String? groupUuid,
    String? eventUuid,
    String? updatedAt,
    String? deletedAt,
    bool clearCompleted = false,
    bool clearDeleted = false,
    bool clearReminder = false,
    bool clearGroup = false,
    bool clearEvent = false,
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
        groupUuid: clearGroup ? null : (groupUuid ?? this.groupUuid),
        eventUuid: clearEvent ? null : (eventUuid ?? this.eventUuid),
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
        'group_uuid': groupUuid,
        'event_uuid': eventUuid,
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
        groupUuid: m['group_uuid'] as String?,
        eventUuid: m['event_uuid'] as String?,
        updatedAt: m['updated_at']! as String,
        deletedAt: m['deleted_at'] as String?,
      );
}

/// A document attached to a task.
///
/// This row is *metadata only*. The bytes live outside the database, in a
/// content-addressed file named after [sha256], and they are deliberately not
/// part of sync: the protocol is one JSON round trip of rows, and pushing
/// megabytes through it would make every sync wait on the largest file anyone
/// ever attached.
///
/// So the row syncs and the file does not, which means a device can hold an
/// attachment it has no bytes for. That state is shown rather than hidden -
/// see [AttachmentStore.hasLocal]. It is also what a later blob channel would
/// resolve, and [sha256] is already the address it would fetch by.
class Attachment implements SyncRow {
  @override
  final String uuid;

  /// The task this belongs to, or empty when it belongs to a calendar event.
  ///
  /// Two nullable owner columns rather than one polymorphic pair of
  /// (owner_type, owner_id): the sync protocol copies columns verbatim and has
  /// no notion of a discriminator, so a typo'd type string would sync happily
  /// and orphan the row on the peer. Exactly one of these is set; [ownerUuid]
  /// is the accessor that does not care which.
  final String taskUuid;

  /// The calendar event this belongs to, or null when it belongs to a task.
  final String? eventUuid;

  /// The name as the user chose it. Not what the file is called on disk - that
  /// is [sha256], so two tasks attaching the same document share one copy.
  final String filename;

  final int size;
  final String sha256;
  final String createdAt;
  @override
  final String updatedAt;
  @override
  final String? deletedAt;

  const Attachment({
    required this.uuid,
    this.taskUuid = '',
    this.eventUuid,
    required this.filename,
    required this.size,
    required this.sha256,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  /// Whichever row owns this attachment.
  String get ownerUuid => eventUuid ?? taskUuid;

  bool get isForEvent => eventUuid != null;

  @override
  bool get isDeleted => deletedAt != null;

  /// The extension, uppercased, for the little type tag on the row. Empty for a
  /// file with no extension, which is rare enough not to deserve a placeholder.
  String get kind {
    final dot = filename.lastIndexOf('.');
    if (dot <= 0 || dot == filename.length - 1) return '';
    return filename.substring(dot + 1).toUpperCase();
  }

  Attachment copyWith({
    String? filename,
    String? updatedAt,
    String? deletedAt,
  }) =>
      Attachment(
        uuid: uuid,
        taskUuid: taskUuid,
        eventUuid: eventUuid,
        filename: filename ?? this.filename,
        size: size,
        sha256: sha256,
        createdAt: createdAt,
        updatedAt: updatedAt ?? nowStamp(),
        deletedAt: deletedAt ?? this.deletedAt,
      );

  @override
  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'task_uuid': taskUuid,
        'event_uuid': eventUuid,
        'filename': filename,
        'size': size,
        'sha256': sha256,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static Attachment fromMap(Map<String, Object?> m) => Attachment(
        uuid: m['uuid']! as String,
        taskUuid: (m['task_uuid'] as String?) ?? '',
        eventUuid: m['event_uuid'] as String?,
        filename: m['filename']! as String,
        size: (m['size'] as num?)?.toInt() ?? 0,
        sha256: m['sha256']! as String,
        createdAt: m['created_at']! as String,
        updatedAt: m['updated_at']! as String,
        deletedAt: m['deleted_at'] as String?,
      );
}

/// A titled, timestamped note in a workspace's journal.
///
/// Unlike a task, a journal entry is not something to *do* - it is a record of
/// what happened, or what you were thinking, kept in the order it was written.
/// It is per-workspace, like a [ParkedGroup] and unlike a global [SideThought]:
/// a running log belongs to the thing you are working on.
///
/// Encryption is **optional**: the journal is plaintext until the user sets a
/// password, at which point every entry is re-encrypted and new ones follow.
/// [encrypted] records, per row, which of the two [title]/[text] are: AES-GCM
/// ciphertext when true (see `journal_crypto.dart`), plain UTF-8 when false. The
/// model itself stays oblivious to the crypto - it stores and moves opaque
/// strings and a flag - which keeps the crypto in one place and the sync path
/// unchanged. The flag matters for mixed and synced state: a device without the
/// password can still tell an encrypted row it cannot read from a plaintext one
/// it can.
///
/// [createdAt] is both the timestamp shown and the sort key. Editing an entry
/// moves [updatedAt] but deliberately leaves [createdAt] where it was, so fixing
/// a typo an hour later does not reshuffle the log or relabel when the thing was
/// actually written.
class JournalEntry implements SyncRow {
  @override
  final String uuid;
  final String workspaceUuid;

  /// The entry's title - ciphertext when [encrypted], plaintext otherwise.
  final String title;

  /// The entry's body - ciphertext when [encrypted], plaintext otherwise.
  final String text;

  /// Whether [title] and [text] are AES-GCM ciphertext (a password was set when
  /// this row was last written) rather than plain UTF-8.
  final bool encrypted;

  final String createdAt;
  @override
  final String updatedAt;
  @override
  final String? deletedAt;

  const JournalEntry({
    required this.uuid,
    required this.workspaceUuid,
    this.title = '',
    required this.text,
    this.encrypted = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  bool get isDeleted => deletedAt != null;

  /// Local time, for display and grouping. The stored stamp is already a
  /// local-offset RFC 3339 (see [nowStamp]); parsing back to local keeps the
  /// wall-clock reading intact even when the entry was written in another zone.
  DateTime? get createdAtTime => DateTime.tryParse(createdAt)?.toLocal();

  JournalEntry copyWith({
    String? title,
    String? text,
    bool? encrypted,
    String? updatedAt,
    String? deletedAt,
    bool clearDeleted = false,
  }) =>
      JournalEntry(
        uuid: uuid,
        workspaceUuid: workspaceUuid,
        title: title ?? this.title,
        text: text ?? this.text,
        encrypted: encrypted ?? this.encrypted,
        createdAt: createdAt,
        updatedAt: updatedAt ?? nowStamp(),
        deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      );

  @override
  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'workspace_uuid': workspaceUuid,
        'title': title,
        'text': text,
        'encrypted': encrypted ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static JournalEntry fromMap(Map<String, Object?> m) => JournalEntry(
        uuid: m['uuid']! as String,
        workspaceUuid: m['workspace_uuid']! as String,
        title: (m['title'] as String?) ?? '',
        text: m['text']! as String,
        encrypted: ((m['encrypted'] as num?)?.toInt() ?? 0) != 0,
        createdAt: m['created_at']! as String,
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

/// A named, coloured container for calendar events.
///
/// Two kinds, distinguished by [workspaceUuid]:
///
///   - **A workspace's calendar** carries that workspace's uuid, and takes its
///     name and colour from the workspace rather than from its own columns -
///     one source of truth, so renaming a workspace cannot leave a stale
///     calendar name behind.
///   - **A standalone calendar** ("Workout") has no workspace and owns its name
///     and colour outright.
///
/// A workspace calendar's [uuid] *is* its workspace's uuid. That looks like a
/// shortcut and is actually the point: the row is provisioned lazily, and
/// deriving the id means two devices that each provision it while offline
/// produce the same row rather than two duplicates sync can only keep as
/// siblings.
class Calendar implements SyncRow {
  @override
  final String uuid;

  /// The workspace this mirrors, or null for a standalone calendar.
  final String? workspaceUuid;

  /// Ignored for a workspace calendar - see the class comment.
  final String name;
  final String color;

  /// Default lead time for this calendar's events, in minutes before the start.
  /// Null means this calendar never notifies. An event can override either way.
  final int? notifyMinutes;

  final int sortOrder;
  final String createdAt;
  @override
  final String updatedAt;
  @override
  final String? deletedAt;

  const Calendar({
    required this.uuid,
    this.workspaceUuid,
    required this.name,
    required this.color,
    this.notifyMinutes,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  bool get isDeleted => deletedAt != null;

  bool get isWorkspaceCalendar => workspaceUuid != null;

  /// The calendar a workspace owns. Deterministic, so two devices agree.
  static Calendar forWorkspace(Workspace ws, {String? at}) {
    final stamp = at ?? nowStamp();
    return Calendar(
      uuid: ws.uuid,
      workspaceUuid: ws.uuid,
      name: ws.name,
      color: ws.color,
      sortOrder: ws.sortOrder,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  Calendar copyWith({
    String? name,
    String? color,
    int? notifyMinutes,
    bool clearNotify = false,
    int? sortOrder,
    String? updatedAt,
    String? deletedAt,
    bool clearDeleted = false,
  }) =>
      Calendar(
        uuid: uuid,
        workspaceUuid: workspaceUuid,
        name: name ?? this.name,
        color: color ?? this.color,
        notifyMinutes:
            clearNotify ? null : (notifyMinutes ?? this.notifyMinutes),
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: updatedAt ?? nowStamp(),
        deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      );

  @override
  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'workspace_uuid': workspaceUuid,
        'name': name,
        'color': color,
        'notify_minutes': notifyMinutes,
        'sort_order': sortOrder,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static Calendar fromMap(Map<String, Object?> m) => Calendar(
        uuid: m['uuid']! as String,
        workspaceUuid: m['workspace_uuid'] as String?,
        name: (m['name'] as String?) ?? '',
        color: (m['color'] as String?) ?? '#6c8cff',
        notifyMinutes: (m['notify_minutes'] as num?)?.toInt(),
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        createdAt: m['created_at']! as String,
        updatedAt: m['updated_at']! as String,
        deletedAt: m['deleted_at'] as String?,
      );
}

/// One block of time on a calendar.
///
/// [startAt] and [endAt] are instants in UTC, for the same reason reminders are
/// (see [reminderStamp]): an event is a moment, so the moment is what has to
/// survive travelling to another timezone - not the wall-clock reading.
class CalendarEvent implements SyncRow {
  @override
  final String uuid;
  final String calendarUuid;

  /// Required, unlike the description: an untitled block on a week grid is
  /// unreadable at the size these are drawn at.
  final String title;

  final String description;

  final String startAt;
  final String endAt;

  /// Minutes before [startAt] to notify.
  ///
  /// Null inherits the calendar's rule; [notifySilent] means this event stays
  /// quiet even when its calendar notifies. A sentinel rather than a second
  /// boolean column because it syncs as one value - two columns can disagree
  /// after a merge, and "override = true, minutes = null" has no meaning.
  final int? notifyMinutes;

  static const notifySilent = -1;

  final String createdAt;
  @override
  final String updatedAt;
  @override
  final String? deletedAt;

  const CalendarEvent({
    required this.uuid,
    required this.calendarUuid,
    required this.title,
    this.description = '',
    required this.startAt,
    required this.endAt,
    this.notifyMinutes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  bool get isDeleted => deletedAt != null;

  DateTime get start => DateTime.tryParse(startAt)?.toLocal() ?? DateTime.now();
  DateTime get end => DateTime.tryParse(endAt)?.toLocal() ?? start;

  Duration get duration => end.difference(start);

  /// Whether this covers more than one calendar day, which is what moves it out
  /// of the hour grid and into the spanning band at the top.
  bool get spansDays {
    final s = start;
    final e = end;
    return e.year != s.year || e.month != s.month || e.day != s.day;
  }

  /// Resolved lead time, given the calendar this sits on. Null means silent.
  Duration? notifyLead(Calendar? calendar) {
    final own = notifyMinutes;
    if (own == notifySilent) return null;
    final minutes = own ?? calendar?.notifyMinutes;
    if (minutes == null || minutes < 0) return null;
    return Duration(minutes: minutes);
  }

  /// When the OS should fire for this event, or null if it should not.
  DateTime? notifyAt(Calendar? calendar) {
    final lead = notifyLead(calendar);
    if (lead == null) return null;
    return start.subtract(lead);
  }

  CalendarEvent copyWith({
    String? calendarUuid,
    String? title,
    String? description,
    String? startAt,
    String? endAt,
    int? notifyMinutes,
    bool clearNotify = false,
    String? updatedAt,
    String? deletedAt,
    bool clearDeleted = false,
  }) =>
      CalendarEvent(
        uuid: uuid,
        calendarUuid: calendarUuid ?? this.calendarUuid,
        title: title ?? this.title,
        description: description ?? this.description,
        startAt: startAt ?? this.startAt,
        endAt: endAt ?? this.endAt,
        notifyMinutes:
            clearNotify ? null : (notifyMinutes ?? this.notifyMinutes),
        createdAt: createdAt,
        updatedAt: updatedAt ?? nowStamp(),
        deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      );

  @override
  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'calendar_uuid': calendarUuid,
        'title': title,
        'description': description,
        'start_at': startAt,
        'end_at': endAt,
        'notify_minutes': notifyMinutes,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static CalendarEvent fromMap(Map<String, Object?> m) => CalendarEvent(
        uuid: m['uuid']! as String,
        calendarUuid: m['calendar_uuid']! as String,
        title: m['title']! as String,
        description: (m['description'] as String?) ?? '',
        startAt: m['start_at']! as String,
        endAt: m['end_at']! as String,
        notifyMinutes: (m['notify_minutes'] as num?)?.toInt(),
        createdAt: m['created_at']! as String,
        updatedAt: m['updated_at']! as String,
        deletedAt: m['deleted_at'] as String?,
      );
}
