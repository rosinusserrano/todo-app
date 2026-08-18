// Row models shared by the local database and the sync protocol.
//
// Every model carries the three sync columns described in server/db.js:
// a client-generated `uuid`, an `updatedAt` used for last-write-wins conflict
// resolution, and a `deletedAt` tombstone. Nothing is ever hard-deleted, so a
// peer can always tell "removed" from "not yet seen".

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// Timestamps are RFC 3339 **with an offset**, matching what the Rust backend
/// wrote (`chrono::Local::now().to_rfc3339()`), so existing rows migrate
/// without reformatting.
///
/// The offset has to be written explicitly, because Dart will not do it:
/// `DateTime.now().toIso8601String()` appends `Z` for a UTC value and
/// **nothing at all** for a local one, so it produced a naive wall-clock
/// reading - `2026-08-14T10:40:25.991547` - that says nothing about which
/// clock read it. That is not an instant, and last-write-wins needs an
/// instant: a phone in New York editing a row at 09:30 (13:30 UTC) wrote a
/// stamp that sorts *below* a desktop in Madrid that had edited it half an
/// hour earlier at 15:00 (13:00 UTC), so the older edit won and the newer one
/// was silently dropped. [compareStamps] was already written to parse rather
/// than compare as text for exactly this reason - it just had no offset to
/// read.
///
/// The wall-clock part is unchanged, which is what makes this safe to start
/// doing to a database full of the old naive stamps: anything still comparing
/// these as strings (the server's merge did until it learned to parse them)
/// orders a new stamp against an old one exactly as it did before, while
/// everything that parses now gets the real instant.
String nowStamp() => stampOf(DateTime.now());

/// [nowStamp] for an arbitrary time. Local reading plus the offset that was in
/// force *at that time*, so a stamp written either side of a DST change
/// carries its own offset rather than today's.
String stampOf(DateTime at) {
  final local = at.toLocal();
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  final hh = abs.inHours.toString().padLeft(2, '0');
  final mm = (abs.inMinutes % 60).toString().padLeft(2, '0');
  return '${local.toIso8601String()}$sign$hh:$mm';
}

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

/// How a task repeats.
///
/// A small closed vocabulary rather than an RRULE: this is a todo widget, and
/// "every second Tuesday except in August" is a calendar's problem. The rule
/// carries the *period* only - the time of day is [Task.remindAt]'s, so there
/// is one place a recurring reminder's clock is stored and it is the same place
/// a one-off's is.
class Recur {
  static const daily = 'daily';
  static const weekdays = 'weekdays';
  static const weekly = 'weekly';
  static const monthly = 'monthly';
  static const yearly = 'yearly';

  static const rules = [daily, weekdays, weekly, monthly, yearly];

  static const labels = {
    daily: 'Every day',
    weekdays: 'Every weekday',
    weekly: 'Every week',
    monthly: 'Every month',
    yearly: 'Every year',
  };

  static String label(String rule) => labels[rule] ?? rule;

  /// The occurrence after [from] under [rule], or null if the rule is unknown.
  ///
  /// **Calendar arithmetic, not duration arithmetic, and in local time.** A
  /// reminder is set at a wall-clock time - "every day at 09:00" - and adding
  /// `Duration(days: 1)` to an instant shifts that reading by an hour across a
  /// DST boundary, so a daily 09:00 alarm would drift to 08:00 for half the
  /// year. Building the next DateTime from its parts keeps the reading and lets
  /// Dart normalise the overflow (month 13 becomes January).
  ///
  /// Day-of-month overflow clamps the same way: `DateTime(2026, 2, 31)`
  /// normalises to 3 March, which is not what "monthly" means to anyone with a
  /// task on the 31st, so [monthly] pulls it back to the last day of the target
  /// month instead.
  static DateTime? next(DateTime from, String rule) {
    final l = from.toLocal();
    DateTime at(int year, int month, int day) =>
        DateTime(year, month, day, l.hour, l.minute, l.second);

    switch (rule) {
      case daily:
        return at(l.year, l.month, l.day + 1);

      case weekdays:
        // Friday, Saturday and Sunday all land on the following Monday.
        var d = at(l.year, l.month, l.day + 1);
        while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
          d = at(d.year, d.month, d.day + 1);
        }
        return d;

      case weekly:
        return at(l.year, l.month, l.day + 7);

      case monthly:
        final lastDay = DateTime(l.year, l.month + 2, 0).day;
        return at(l.year, l.month + 1, l.day > lastDay ? lastDay : l.day);

      case yearly:
        // 29 February in a common year becomes the 28th, for the same reason.
        final lastDay = DateTime(l.year + 1, l.month + 1, 0).day;
        return at(l.year + 1, l.month, l.day > lastDay ? lastDay : l.day);
    }
    return null;
  }

  /// The occurrence [n] steps after [anchor], counted **from the anchor** and
  /// not from the one before it.
  ///
  /// That distinction is the whole reason this exists beside [next]. Clamping
  /// is per step, so walking a monthly rule from 31 January lands on 28
  /// February and then, because the walk continues from *there*, on 28 March
  /// and the 28th of every month after it: one short February silently rewrites
  /// the rule. Measuring each occurrence from the anchor gives 31 January,
  /// 28 February, 31 March, which is what "monthly on the 31st" means and what
  /// every other calendar draws.
  ///
  /// [Task.nextOccurrence] goes on using [next], and should: a task spawns its
  /// successor when the current one is completed, so there is no anchor left to
  /// count from - the row in front of you *is* the series.
  static DateTime? nth(DateTime anchor, String rule, int n) {
    final a = anchor.toLocal();
    DateTime at(int year, int month, int day) =>
        DateTime(year, month, day, a.hour, a.minute, a.second);

    /// The last day of the month [month] of [year] falls in, after Dart has
    /// normalised any overflow (month 13 is January of the next year).
    int lastDayOf(int year, int month) => DateTime(year, month + 1, 0).day;

    switch (rule) {
      case daily:
        return at(a.year, a.month, a.day + n);

      case weekly:
        return at(a.year, a.month, a.day + 7 * n);

      case weekdays:
        // Anchor on a weekend means the series starts on the Monday; from
        // there it is five occurrences per seven days, exactly.
        var first = a;
        while (first.weekday == DateTime.saturday ||
            first.weekday == DateTime.sunday) {
          first = at(first.year, first.month, first.day + 1);
        }
        final w = first.weekday - DateTime.monday; // 0..4
        final idx = w + n;
        final days = (idx ~/ 5) * 7 + (idx % 5) - w;
        return at(first.year, first.month, first.day + days);

      case monthly:
        final month = a.month + n;
        final year = a.year + (month - 1) ~/ 12;
        final normalised = (month - 1) % 12 + 1;
        final last = lastDayOf(year, normalised);
        return at(year, normalised, a.day > last ? last : a.day);

      case yearly:
        final year = a.year + n;
        final last = lastDayOf(year, a.month);
        return at(year, a.month, a.day > last ? last : a.day);
    }
    return null;
  }

  /// Namespace for [Task.nextOccurrence]'s derived uuids. A fixed constant, so
  /// two devices deriving the same occurrence agree.
  static const occurrenceNamespace = '6f9a1c2e-4d3b-5a7f-8e10-2b6c4d9f1a35';
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

  /// How this task repeats, or null for a one-off. One of [Recur.rules].
  ///
  /// The rule is the *period* only - the time of day comes from [remindAt],
  /// which keeps its exact meaning of "the next time this nags". That is what
  /// makes recurrence cheap: ReminderService, describeReminder, the overdue
  /// styling and NotificationService all go on reading one instant and needed
  /// no changes for this.
  ///
  /// Completing a recurring task spawns the next occurrence as a *new row*
  /// rather than re-arming this one - see [nextOccurrence]. An occurrence is a
  /// todo in its own right, so the completed row lands in History by having a
  /// `completed_at` like any other, and History needed no changes either.
  /// Re-arming and logging completions separately would mean a second table
  /// and two answers to "what did I finish".
  final String? recur;

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

  /// The long form: everything that did not fit on the line. Empty for the vast
  /// majority of tasks, which is why it is a column on the row rather than a
  /// table of its own - a nullable-by-convention text field costs an empty
  /// string per task, where a second table would cost a join, a migration, a
  /// sync entry and a garbage-collection rule.
  final String notes;

  /// How loudly this one is asking. `0` is an ordinary task and
  /// [priorityHigh] is a flagged one.
  ///
  /// An integer rather than a boolean because "urgent above high" is the
  /// obvious next request, and answering it with a second column would leave
  /// two flags that can disagree after a merge. The UI offers two values; the
  /// column can carry more without another migration.
  final int priority;

  @override
  final String updatedAt;
  @override
  final String? deletedAt;

  /// The one flagged level the UI currently sets.
  static const priorityHigh = 1;

  const Task({
    required this.uuid,
    required this.workspaceUuid,
    required this.text,
    required this.createdAt,
    this.completedAt,
    this.sortOrder = 0,
    this.inProgress = false,
    this.remindAt,
    this.recur,
    this.groupUuid,
    this.eventUuid,
    this.notes = '',
    this.priority = 0,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isActive => completedAt == null && deletedAt == null;

  bool get isPlanned => eventUuid != null;

  bool get hasNotes => notes.trim().isNotEmpty;

  bool get isHighPriority => priority >= priorityHigh;

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

  /// The occurrence that follows this one, or null when this task does not
  /// recur, has no reminder to count from, or carries a rule this build does
  /// not know (a newer device's, arrived by sync).
  ///
  /// **The uuid is derived, never generated.** Spawning happens on completion,
  /// completion is a write, and a write syncs - so two devices that both see
  /// the same task completed will both spawn its successor. With a generated
  /// id those are two rows that sync can only keep as siblings, which is how
  /// one account collected seven "Tasks" workspaces; derived from the parent
  /// and the occurrence instant, both devices produce the same row and the
  /// second spawn merges into the first. Same rule as [Calendar.forWorkspace]
  /// and [LocalStore.defaultWorkspaceUuid].
  ///
  /// Only the uuid has to agree. `created_at` and `updated_at` are each
  /// device's own clock, and last-write-wins settles them.
  ///
  /// The next occurrence is deliberately **not** planned into this one's block
  /// ([eventUuid] is dropped): a block of time is a specific moment, so
  /// inheriting it would plan next week's task into last week's afternoon.
  Task? nextOccurrence() {
    final rule = recur;
    final from = remindAtTime;
    if (rule == null || from == null) return null;

    final at = Recur.next(from, rule);
    if (at == null) return null;

    final stamp = reminderStamp(at);
    final now = nowStamp();
    return Task(
      uuid: _uuid.v5(Recur.occurrenceNamespace, '$uuid:$stamp'),
      workspaceUuid: workspaceUuid,
      text: text,
      createdAt: now,
      sortOrder: sortOrder,
      remindAt: stamp,
      recur: rule,
      // A recurring task parked in a group stays parked; that is a statement
      // about where it lives, not about this occurrence.
      groupUuid: groupUuid,
      notes: notes,
      priority: priority,
      updatedAt: now,
    );
  }

  Task copyWith({
    String? workspaceUuid,
    String? text,
    String? completedAt,
    int? sortOrder,
    bool? inProgress,
    String? remindAt,
    String? recur,
    String? groupUuid,
    String? eventUuid,
    String? notes,
    int? priority,
    String? updatedAt,
    String? deletedAt,
    bool clearCompleted = false,
    bool clearDeleted = false,
    bool clearReminder = false,
    bool clearRecur = false,
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
        recur: clearRecur ? null : (recur ?? this.recur),
        groupUuid: clearGroup ? null : (groupUuid ?? this.groupUuid),
        eventUuid: clearEvent ? null : (eventUuid ?? this.eventUuid),
        // No "clear" flag for these two: the empty string and 0 *are* the
        // cleared values, so passing them says it outright.
        notes: notes ?? this.notes,
        priority: priority ?? this.priority,
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
        'recur': recur,
        'group_uuid': groupUuid,
        'event_uuid': eventUuid,
        'notes': notes,
        'priority': priority,
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
        recur: m['recur'] as String?,
        groupUuid: m['group_uuid'] as String?,
        eventUuid: m['event_uuid'] as String?,
        // Null-tolerant: a row that arrived from a server still carrying the
        // pre-v11 column list has neither of these.
        notes: (m['notes'] as String?) ?? '',
        priority: (m['priority'] as num?)?.toInt() ?? 0,
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

  /// How this block repeats, or null for a one-off. One of [Recur.rules].
  ///
  /// The stored row is the **series**, and its `start_at` / `end_at` are the
  /// first occurrence. Every later occurrence is produced on the way out of the
  /// store by [occurrencesBetween] and is never written, which is what keeps a
  /// weekly stand-up one row rather than fifty-two.
  ///
  /// Deliberately unlike [Task.recur], which spawns each occurrence as a real
  /// row. A task occurrence has state of its own - it gets completed, and that
  /// completion is what History is made of - so it has to exist. A block has
  /// none: it is a span of time with a title, identical every week, and writing
  /// out a year of them would be a year of rows to migrate the day the title
  /// changes.
  final String? recur;

  /// The stored row this was expanded from, or null if this *is* the stored
  /// row (including for the first occurrence of a series, which is).
  ///
  /// Not a column and never written. It exists so that a write reached through
  /// an occurrence - deleting it, editing it - lands on the series with the
  /// series' own times, instead of quietly moving the series to whichever
  /// Tuesday the user happened to be looking at. Use [stored] for that; the
  /// uuid is the same either way, so anything keyed on uuid (its attachments,
  /// the todos planned into it) needs no special handling at all.
  final CalendarEvent? series;

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
    this.recur,
    this.series,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  bool get isDeleted => deletedAt != null;

  /// True for an occurrence that was expanded out of a series.
  bool get isOccurrence => series != null;

  /// True for a row that repeats - the series itself, or one of its
  /// occurrences.
  bool get repeats => recur != null;

  /// The row to write when a change is made through this event. For an
  /// occurrence that is the series it came from; for anything else, itself.
  CalendarEvent get stored => series ?? this;

  /// A key that distinguishes two occurrences of one series, which share a
  /// uuid. Occurrence uuids are deliberately *not* derived the way
  /// [Task.nextOccurrence]'s are: derivation exists so that two devices writing
  /// the same row agree on its id, and nothing here is ever written.
  String get instanceKey => '$uuid@$startAt';

  /// The occurrences of this event that overlap `[from, to)`, in order.
  ///
  /// A one-off yields itself when it overlaps and nothing when it does not, so
  /// callers can run everything through this without asking which kind they
  /// hold.
  ///
  /// Each occurrence keeps the series' duration and is stepped with
  /// [Recur.next], which is calendar arithmetic in local time - so a 09:00
  /// block is still at 09:00 on the far side of a DST boundary rather than
  /// sliding to 08:00 for half the year.
  List<CalendarEvent> occurrencesBetween(DateTime from, DateTime to) {
    final rule = recur;
    if (rule == null) {
      return start.isBefore(to) && end.isAfter(from) ? [this] : const [];
    }

    final length = duration;
    final anchor = start;
    final out = <CalendarEvent>[];

    // Counted from the anchor rather than walked one at a time - see
    // [Recur.nth], which is what keeps a monthly block on the 31st.
    //
    // Two caps, because a series has no end date and the window can be a long
    // way from where it started. Neither is reachable with a real calendar: a
    // year view of a daily block is 365 occurrences, and 20000 steps is a
    // daily block started fifty years ago.
    for (var n = 0; n < _maxSteps; n++) {
      // An unknown rule yields nothing beyond the first occurrence rather than
      // looping: a row written by a newer version reads as a one-off here, not
      // as an error. The first occurrence is the stored row itself, so it does
      // not depend on understanding the rule at all.
      final at = n == 0 ? anchor : Recur.nth(anchor, rule, n);
      if (at == null) break;
      if (!at.isBefore(to)) break;
      if (at.add(length).isAfter(from)) {
        out.add(n == 0 ? this : _occurrenceAt(at, length));
        if (out.length >= _maxOccurrences) break;
      }
    }
    return out;
  }

  static const _maxSteps = 20000;
  static const _maxOccurrences = 500;

  CalendarEvent _occurrenceAt(DateTime at, Duration length) => CalendarEvent(
        uuid: uuid,
        calendarUuid: calendarUuid,
        title: title,
        description: description,
        startAt: reminderStamp(at),
        endAt: reminderStamp(at.add(length)),
        notifyMinutes: notifyMinutes,
        recur: recur,
        series: stored,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );

  /// The first occurrence that has not finished by [now], or null for a series
  /// whose rule is unknown. This is what the notification schedule arms: only
  /// ever one instant per series, because handing the OS a year of them would
  /// be a year of alarms to cancel every time the row is touched.
  CalendarEvent? nextOccurrence([DateTime? now]) {
    final at = now ?? DateTime.now();
    if (recur == null) return end.isAfter(at) ? this : null;
    final found = occurrencesBetween(at, at.add(const Duration(days: 366)));
    return found.isEmpty ? null : found.first;
  }

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

  /// Always builds from [stored], so a change made through an occurrence edits
  /// the series and keeps the series' own times unless it is explicitly given
  /// new ones.
  CalendarEvent copyWith({
    String? calendarUuid,
    String? title,
    String? description,
    String? startAt,
    String? endAt,
    int? notifyMinutes,
    bool clearNotify = false,
    String? recur,
    bool clearRecur = false,
    String? updatedAt,
    String? deletedAt,
    bool clearDeleted = false,
  }) {
    final base = stored;
    return CalendarEvent(
      uuid: base.uuid,
      calendarUuid: calendarUuid ?? base.calendarUuid,
      title: title ?? base.title,
      description: description ?? base.description,
      startAt: startAt ?? base.startAt,
      endAt: endAt ?? base.endAt,
      notifyMinutes:
          clearNotify ? null : (notifyMinutes ?? base.notifyMinutes),
      recur: clearRecur ? null : (recur ?? base.recur),
      createdAt: base.createdAt,
      updatedAt: updatedAt ?? nowStamp(),
      deletedAt: clearDeleted ? null : (deletedAt ?? base.deletedAt),
    );
  }

  @override
  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'calendar_uuid': calendarUuid,
        'title': title,
        'description': description,
        'start_at': stored.startAt,
        'end_at': stored.endAt,
        'notify_minutes': notifyMinutes,
        'recur': recur,
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
        recur: m['recur'] as String?,
        createdAt: m['created_at']! as String,
        updatedAt: m['updated_at']! as String,
        deletedAt: m['deleted_at'] as String?,
      );
}
