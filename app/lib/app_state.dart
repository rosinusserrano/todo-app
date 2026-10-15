// Application state.
//
// The Tauri build kept state in module-level variables in main.ts and re-read
// the database after every mutation. That shape survives here as a
// ChangeNotifier: mutate the local store, reload, notify. Reads are cheap
// (local SQLite, small lists) and it keeps the UI a pure function of the DB,
// which is what made focus mode survivable across restarts.

import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show File;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'journal_crypto.dart';
import 'task_variables.dart';
import 'notifications.dart';
import 'sync/attachment_store.dart';
import 'sync/feeds.dart';
import 'sync/ics.dart';
import 'sync/local_store.dart';
import 'sync/models.dart';
// For the grid's hour-height constants: the zoom this holds is the grid's own
// geometry, and a second copy of the bounds would drift from the ones the
// pinch clamps to.
import 'ui/calendar/time_grid.dart' show kHourHeight, kHourHeightMin, kHourHeightMax;
import 'ui/dock.dart' show DockEdge;
import 'theme.dart';
import 'whats_new.dart' show ReleaseNote, kReleaseNotes, notesSince;

const _kLastWorkspace = 'ui:last-workspace';
const _kNudge = 'ui:nudge-enabled';
const _kCalendarMode = 'ui:calendar-mode';
const _kCalendarScope = 'ui:calendar-scope';
const _kCalendarZoom = 'ui:calendar-hour-height';
const _kCalendarHidden = 'ui:calendar-hidden';
const _kCalendarBlock = 'ui:calendar-block';
const _kWideDock = 'ui:wide-dock';
const _kWhatsNewSeen = 'whats-new:seen';
const _kSplitFraction = 'ui:split-fraction';
const _kCalendarSplitFraction = 'ui:calendar-split-fraction';
const _kTasksPaneCollapsed = 'ui:tasks-pane-collapsed';
const _kZoom = 'ui:zoom';

/// The three grids. There is deliberately no month view: the year view is
/// twelve months drawn at once, so a single month would be the same thing with
/// less on it.
enum CalendarViewMode { day, week, year }

/// Whose events are on screen.
enum CalendarScope {
  /// The current workspace's calendar, plus the standalone ones.
  workspace,

  /// Every calendar, every workspace.
  all,
}

/// A journal entry ready for the UI: its title and body as plain text, whether
/// they came from a plaintext row or were decrypted. [locked] marks a row that
/// is encrypted but cannot be read here (no key on this device, or a mismatched
/// one) - the UI shows it as a placeholder rather than garbage, and does not let
/// it be opened. This exists only in memory while the journal is on screen.
class JournalItem {
  const JournalItem({
    required this.entry,
    required this.title,
    required this.body,
    this.locked = false,
  });

  final JournalEntry entry;
  final String title;
  final String body;
  final bool locked;

  String get uuid => entry.uuid;
  DateTime? get createdAtTime => entry.createdAtTime;
}

class AppState extends ChangeNotifier {
  AppState(this._store, {this.notifications, this.blobs, this.journalCrypto});

  final LocalStore _store;

  /// Where attachment bytes live. Null in tests that do not touch files; every
  /// attachment path checks for it rather than assuming.
  final AttachmentStore? blobs;

  /// The journal's encryption vault. Null in tests that do not touch the
  /// journal; every journal path checks for it rather than assuming.
  final JournalCrypto? journalCrypto;

  /// Mobile only, and null in tests. Every task refresh hands it the current
  /// armed set - see the header of notifications.dart for why the schedule is
  /// rebuilt from a query rather than hooked onto the writes.
  final NotificationService? notifications;

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

  /// The current workspace's journal, ready to show, newest first. Populated
  /// whenever the view is open and not locked (plaintext needs no password);
  /// cleared on lock, on workspace switch, and when there is no workspace.
  List<JournalItem> journal = [];

  /// The parked shelves of the current workspace, and what is on each.
  List<ParkedGroup> groups = [];
  Map<String, List<Task>> parked = {};

  /// How many attachments each task on screen has, so the row can show a
  /// paperclip without querying per row.
  Map<String, int> attachmentCounts = {};

  /// The task owning the focus view, or null when the list is showing. Mirrors
  /// `in_progress` in the database, which is exclusive and global.
  Task? focusTask;

  bool nudgeEnabled = true;

  /// Which view occupies the content area. All false means the task list.
  /// They are mutually exclusive - each setter clears the others.
  bool showHistory = false;
  bool showThoughts = false;
  bool showParked = false;
  bool showJournal = false;
  bool showSession = false;
  bool showCollections = false;

  Workspace? get currentWorkspace {
    for (final w in workspaces) {
      if (w.uuid == currentWorkspaceUuid) return w;
    }
    return workspaces.isEmpty ? null : workspaces.first;
  }

  int get thoughtCount => thoughts.length;

  /// Groups in this workspace whose review has come due. Drives the badge on
  /// the parked button - a shelf that never asked to be looked at again would
  /// just be a place to lose things.
  List<ParkedGroup> get groupsDueForReview =>
      groups.where((g) => g.isReviewDue()).toList();

  Future<void> load() async {
    nudgeEnabled = (await _store.setting(_kNudge)) != '0';
    await _loadShellPrefs();
    currentWorkspaceUuid = await _store.setting(_kLastWorkspace);
    await refreshWorkspaces();
    await refreshTasks();
    await refreshThoughts();
    await restoreFocus();
    await loadFeeds();
    await loadList();
  }

  // ------------------------------------------------------------ what's new

  /// The release notes this device has not shown yet (whats_new.dart), filled
  /// by [checkWhatsNew]. Empty means nothing to show.
  List<ReleaseNote> whatsNew = const [];

  /// Works out [whatsNew] from the id this device last showed. Called from
  /// `main()` and not from [load], so a test that builds the shell never has
  /// a box open over it.
  ///
  /// No id stored is either a fresh install or a device from before the box
  /// existed. A database with tasks in it is the second, and gets the latest
  /// note; a fresh one has nothing to compare the new version with, so it is
  /// marked as having seen it.
  Future<void> checkWhatsNew() async {
    final seen = await _store.setting(_kWhatsNewSeen);
    if (seen == null) {
      if (await _store.hasAnyTask()) {
        whatsNew = notesSince(null).take(1).toList();
      } else {
        await markWhatsNewSeen();
      }
      return;
    }
    whatsNew = notesSince(seen);
  }

  /// The box was shown: it does not come back until there is a newer note.
  Future<void> markWhatsNewSeen() async {
    whatsNew = const [];
    await _store.setSetting(_kWhatsNewSeen, kReleaseNotes.first.id);
  }

  // -------------------------------------------------------------- sessions
  //
  // A "session" is simply the calendar block happening *now*, and the todos
  // planned into it. It is the payoff for planning a week: having said on
  // Sunday what a block is for, the widget can answer "what am I meant to be
  // doing right now" without you going looking for it.
  //
  // Two decisions worth keeping:
  //
  //   - Sessions ignore the calendar's scope and hidden set. Those are about
  //     what you want to *look at* on the grid; this is about what time it
  //     actually is, and a block you unticked yesterday is still the block you
  //     are in. They are also loaded lazily (only once the calendar has been
  //     opened), so filtering on them would make the banner depend on whether
  //     you had visited the calendar this session.
  //   - Overlapping blocks are all live. Picking one for the user would be
  //     guessing; the view lists them in order and lets the eye do it.

  /// The blocks covering right now, earliest first.
  List<CalendarEvent> liveEvents = [];

  /// What is still open in each of them, keyed by event uuid.
  Map<String, List<Task>> sessionTasks = {};

  bool get hasLiveSession => liveEvents.isNotEmpty;

  /// Everything planned into whatever is running, flattened.
  List<Task> get sessionTaskList => [
    for (final e in liveEvents) ...?sessionTasks[e.uuid],
  ];

  /// What the banner is made of. Compared before and after a poll so that a
  /// tick which found nothing new does not rebuild the whole widget every 20
  /// seconds.
  String get _sessionSignature => [
    for (final e in liveEvents)
      '${e.uuid}:${e.endAt}:'
          '${(sessionTasks[e.uuid] ?? const []).map((t) => t.uuid).join(',')}',
  ].join('|');

  /// Reload the live blocks and their todos.
  ///
  /// Called from [refreshTasks] and [refreshEvents] - so an edit or a merge
  /// from sync is picked up - and from the reminder poll, which is what
  /// notices a block *starting* when nothing at all has been edited.
  Future<void> refreshSessions([DateTime? now]) async {
    final before = _sessionSignature;

    liveEvents = await _store.liveEvents(now);
    sessionTasks = {
      for (final e in liveEvents) e.uuid: await _store.tasksForEvent(e.uuid),
    };
    // [calendars] is normally loaded by opening the calendar view, and the
    // banner can appear on a run where that never happened - a block needs its
    // calendar to know what colour and whose it is. Read-only, and only in the
    // one case that needs it, so it does not turn the poll into a write.
    if (liveEvents.isNotEmpty && calendars.isEmpty) {
      calendars = await _store.calendars();
    }
    // The view is only meaningful while something is running; when the last
    // block ends it hands the content area back rather than showing an empty
    // shell of a session that is over.
    if (showSession && liveEvents.isEmpty) showSession = false;

    // Always while the view is open: it shows a live countdown, which is the
    // one thing that changes when nothing in the database has.
    if (showSession || _sessionSignature != before) notifyListeners();
  }

  void toggleSession() {
    showSession = !showSession;
    if (showSession) _closeOtherViews(keepSession: true);
    notifyListeners();
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

  /// Switch workspace, and land on that workspace's **list**.
  ///
  /// Every view closes, side thoughts included. History, the shelves and the
  /// journal are per-workspace and could never have survived the switch; the
  /// thought pile is global and used to be kept open on exactly that reasoning
  /// - it is not a fact about the workspace, so nothing about it changed.
  ///
  /// That was the wrong question. Picking a workspace is asking *what is on
  /// this list*, and answering it with the pile of thoughts that was already on
  /// screen means the one control whose whole job is to show you a list shows
  /// you something else. The thoughts have not gone anywhere - the footer's
  /// count and the bubble both still say how many are waiting, and one press
  /// brings them back.
  ///
  /// Switching is still deliberately *not* blocked by pending thoughts; only
  /// closing the window is. See `_switchWorkspace` in main.dart.
  Future<void> selectWorkspace(String uuid) async {
    currentWorkspaceUuid = uuid;
    await _store.setSetting(_kLastWorkspace, uuid);
    _closeOtherViews();
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
    // The shelves go with the workspace for the same reason history does: a
    // group left behind would point at a workspace that no longer exists.
    for (final g in await _store.parkedGroups(uuid)) {
      await _store.putGroup(g.copyWith(deletedAt: stamp, updatedAt: stamp));
    }
    // The journal is per-workspace too, and it holds real writing - but the
    // workspace and everything in it is going, so the log goes with it rather
    // than being orphaned against a workspace that no longer exists.
    for (final e in await _store.journalEntries(uuid)) {
      await _store.putJournal(e.copyWith(deletedAt: stamp, updatedAt: stamp));
    }
    // Collections are per-workspace as well, fields and entries with them.
    await _tombstoneCollections(uuid, stamp);

    // The workspace's calendar and everything on it. Its uuid is the
    // workspace's, so it is found by id rather than by scanning.
    for (final e in await _store.eventsOnCalendar(uuid)) {
      await _store.putEvent(e.copyWith(deletedAt: stamp, updatedAt: stamp));
    }
    for (final c in await _store.calendars()) {
      if (c.workspaceUuid != uuid) continue;
      await _store.putCalendar(c.copyWith(deletedAt: stamp, updatedAt: stamp));
    }
    await _dropFeedsOn(uuid, stamp);

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
      groups = [];
      parked = {};
      attachmentCounts = {};
      journal = [];
    } else {
      tasks = await _store.activeTasks(ws);
      attachmentCounts = await _store.attachmentCounts(ws);
      // Unconditionally, unlike history: the review badge has to be right even
      // when the parked view is closed, which is the only time you would see it.
      groups = await _store.parkedGroups(ws);
      parked = await _store.parkedTasks(ws);
      if (showHistory) historyTasks = await _store.history(ws);
    }
    // The journal is loaded separately (see refreshJournal), only while its view
    // is open, so it is not swept up in every task edit. refreshJournal itself
    // handles the locked case by clearing the list.
    if (showJournal) await refreshJournal();
    // Collections likewise load only while their view is open; a sync merge
    // reaches this through refreshTasks too, so an entry added on the phone
    // turns up on the desktop's open table.
    await refreshCollections();
    // Unconditionally, like the parked groups above: checking a task off is one
    // of the things that changes what a live block still has left on it, and
    // the banner has to be right whether or not the session view is open.
    await refreshSessions();
    // Every task mutation and every merge from sync lands here, which makes
    // this the one place the OS schedule can be kept honest.
    await _rescheduleNotifications();
    notifyListeners();
  }

  /// Hand the OS the whole schedule: armed task reminders and upcoming calendar
  /// events in one call, because the service cancels everything before it
  /// rewrites (see notifications.dart) and two calls would each wipe the other.
  ///
  /// Reads the events straight from the store rather than using [events], which
  /// holds only whatever range the calendar happens to be showing - and is
  /// empty entirely when the calendar has never been opened.
  Future<void> _rescheduleNotifications() async {
    final n = notifications;
    if (n == null) return;
    await n.reschedule(
      await _store.pendingReminders(),
      events: await _store.upcomingEvents(),
      calendars: {for (final c in await _store.calendars()) c.uuid: c},
    );
  }

  /// Add a task. The extras all default to what the one-line add field means,
  /// so the quick path stays `addTask(text)` and the composer is the same call
  /// with more of it filled in.
  ///
  /// [groupUuid] puts it straight onto a parked shelf instead of onto the list.
  /// One parameter rather than an add-then-park pair, because the pair writes
  /// the row twice and puts the first version on the active list for as long as
  /// it takes the second write to land - which is a task appearing and vanishing
  /// on a list nobody asked to put it on.
  Future<void> addTask(
    String text, {
    String notes = '',
    int priority = 0,
    DateTime? remindAt,
    String? recur,
    String recurFrom = RecurFrom.schedule,
    int? recurLead,
    String? groupUuid,
    String? workspaceUuid,
  }) async {
    // A workspace other than the current one is a capture aimed elsewhere from
    // the add field; the list on screen does not switch to follow it.
    final ws = workspaceUuid ?? currentWorkspaceUuid;
    if (ws == null || text.trim().isEmpty) return;

    final repeat = _resolveRepeat(
      text: text.trim(),
      notes: notes.trim(),
      recur: recur,
      recurFrom: recurFrom,
      recurLead: recurLead,
      remindAt: remindAt,
    );

    await _store.putTask(
      Task(
        uuid: newId(),
        workspaceUuid: ws,
        text: repeat.text,
        createdAt: nowStamp(),
        sortOrder: await _store.nextSortOrder(ws),
        notes: repeat.notes,
        priority: priority,
        remindAt: remindAt == null ? null : reminderStamp(remindAt),
        recur: repeat.recur,
        recurFrom: repeat.recurFrom,
        recurLead: repeat.recurLead,
        recurText: repeat.recurText,
        recurNotes: repeat.recurNotes,
        groupUuid: groupUuid,
        updatedAt: nowStamp(),
      ),
    );
    await refreshTasks();
    _mutated();
  }

  /// Rewrite everything the composer owns, in one write.
  ///
  /// One call rather than a setter per field: the composer hands back a whole
  /// task, and four writes would be four rows on the sync queue and four
  /// rebuilds of the list for one edit. A null [remindAt] clears the reminder,
  /// which is what the composer's "no reminder" chip means.
  ///
  /// [text] and [notes] are the **template** - what the composer was showing,
  /// which for a repeating task is the unexpanded form. What lands on the row
  /// is the expansion; see [_resolveRepeat].
  Future<void> saveTaskDetails(
    Task t, {
    required String text,
    required String notes,
    required int priority,
    DateTime? remindAt,
    String? recur,
    String recurFrom = RecurFrom.schedule,
    int? recurLead,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final repeat = _resolveRepeat(
      text: trimmed,
      notes: notes.trim(),
      recur: recur,
      recurFrom: recurFrom,
      recurLead: recurLead,
      remindAt: remindAt,
    );

    await _store.putTask(
      t.copyWith(
        text: repeat.text,
        notes: repeat.notes,
        priority: priority,
        remindAt: remindAt == null ? null : reminderStamp(remindAt),
        clearReminder: remindAt == null,
        recur: repeat.recur,
        clearRecur: repeat.recur == null,
        recurFrom: repeat.recurFrom,
        recurLead: repeat.recurLead,
        clearLead: repeat.recurLead == null,
        recurText: repeat.recurText,
        recurNotes: repeat.recurNotes,
        updatedAt: nowStamp(),
      ),
    );
    await refreshTasks();
    _mutated();
  }

  /// Work out what a repeat actually means for the row being written: whether
  /// the rule survives, and what the title and notes should say.
  ///
  /// Two rules, both of which exist so that no state can be stored that does
  /// nothing:
  ///
  ///   - **A schedule-anchored rule needs a reminder.** The reminder *is* the
  ///     schedule - it is the instant the period is measured from - so a rule
  ///     without one would never produce a second occurrence. Clearing the
  ///     reminder therefore clears the rule with it. A **completion**-anchored
  ///     rule needs nothing: it counts from the tick, and "back on the list
  ///     every fortnight after I do it" is a perfectly good task with no alarm
  ///     attached.
  ///   - **The template is stored only when there is a variable in it.** Null
  ///     already means "the text is its own template", which is true of every
  ///     task that uses none and of every row written before v15, so storing a
  ///     copy of the title beside the title would be a second thing to keep in
  ///     step for no gain.
  ///
  /// The expansion is against the occurrence's own due date - the reminder for
  /// a scheduled repeat, and today for one that has no clock yet.
  ({
    String text,
    String notes,
    String? recur,
    String recurFrom,
    int? recurLead,
    String? recurText,
    String? recurNotes,
  }) _resolveRepeat({
    required String text,
    required String notes,
    required String? recur,
    required String recurFrom,
    required int? recurLead,
    required DateTime? remindAt,
  }) {
    final keeps = recur != null &&
        (remindAt != null || recurFrom == RecurFrom.completion);

    if (!keeps) {
      return (
        text: text,
        notes: notes,
        recur: null,
        recurFrom: RecurFrom.schedule,
        recurLead: null,
        recurText: null,
        recurNotes: null,
      );
    }

    final due = remindAt ?? DateTime.now();
    return (
      text: expandTaskVariables(text, due),
      notes: expandTaskVariables(notes, due),
      recur: recur,
      recurFrom: recurFrom,
      recurLead: recurLead,
      recurText: hasTaskVariables(text) ? text : null,
      recurNotes: hasTaskVariables(notes) ? notes : null,
    );
  }

  /// Flag or unflag a task from its row.
  ///
  /// Note this does **not** touch [Task.sortOrder]: the order of the list is
  /// the user's, set by dragging, and a flag that quietly jumped a row to the
  /// top would be a second sort fighting the first.
  Future<void> setPriority(Task t, bool high) async {
    await _store.putTask(
      t.copyWith(priority: high ? Task.priorityHigh : 0, updatedAt: nowStamp()),
    );
    await refreshTasks();
    _mutated();
  }

  /// Check off: keeps the row and stamps completed_at, so it shows in history.
  /// Check a task off. A recurring one also lays down its successor.
  ///
  /// The completed row is completed like any other - it goes to History by
  /// having a `completed_at`, which is why recurrence needed no changes there -
  /// and the next occurrence is a *new* row with a derived uuid. See
  /// [Task.nextOccurrence] for why the id is derived rather than generated.
  ///
  /// Spawned on completion rather than when the reminder fires: an unchecked
  /// recurring task then sits overdue as one row instead of piling up thirty
  /// copies of a standup nobody attended.
  Future<void> completeTask(Task t) async {
    final done = t.copyWith(
      completedAt: nowStamp(),
      inProgress: false,
      updatedAt: nowStamp(),
    );
    await _store.putTask(done);

    // From the *completed* row, because that is what the two anchors are asked
    // about: a schedule-anchored series measures from the due date either way,
    // and a completion-anchored one has nothing to measure from until now.
    // The sweep would reach the same answer within twenty seconds; doing it
    // here is what makes a task with no lead reappear the instant it is ticked,
    // which is what recurrence has always looked like.
    await _spawnOccurrences([done]);

    if (focusTask?.uuid == t.uuid) focusTask = null;
    await refreshTasks();
    _mutated();
  }

  /// Lay down every occurrence whose creation moment has passed.
  ///
  /// Runs from [completeTask] with the one row that just changed, and from the
  /// reminder poll with every series in the database ([sweepRecurrences]) -
  /// because a rule-based repeat comes true because *time passed*, and nothing
  /// is written when it does. A monthly report has to appear on the last day of
  /// the month whether or not last month's was ever ticked, and only a clock
  /// can notice that.
  ///
  /// Safe to call from both, and from two devices at once, because the
  /// occurrence's uuid is **derived** from its parent and its own instant: a
  /// row that exists is not written again, and two devices that both spawn
  /// produce the same row rather than siblings. Tombstones count as existing,
  /// so a deleted occurrence stays deleted.
  ///
  /// Returns how many rows it wrote.
  Future<int> _spawnOccurrences(List<Task> seeds, [DateTime? now]) async {
    final at = now ?? DateTime.now();

    // Candidates first, in memory, then **one** question about which of them
    // already exist. Per-candidate lookups would be a query per series per
    // tick, for an answer that is almost always "yes, nothing to do".
    final wanted = <String, Task>{};
    for (final seed in seeds) {
      for (final occurrence in seed.dueOccurrences(at)) {
        wanted[occurrence.uuid] = occurrence;
      }
    }
    if (wanted.isEmpty) return 0;

    final existing = await _store.existingTaskUuids(wanted.keys.toList());
    var written = 0;
    for (final entry in wanted.entries) {
      if (existing.contains(entry.key)) continue;
      await _store.putTask(entry.value);
      written++;
    }
    return written;
  }

  /// The whole database's worth, called from the reminder poll. Refreshes only
  /// when something was actually written, so a quiet tick costs one query.
  Future<int> sweepRecurrences([DateTime? now]) async {
    final written =
        await _spawnOccurrences(await _store.recurringSeeds(now), now);
    if (written > 0) {
      await refreshTasks();
      _mutated();
    }
    return written;
  }

  /// Stop a series without touching the row it is on.
  ///
  /// The way out of a repeat that has no open occurrence left: the rule lives
  /// on the last row the series produced, which after a completion is a row in
  /// History, and taking the rule off it is what stops the next one being laid
  /// down. Not a delete - the completed task is a record of work that was done
  /// and stays in History exactly as it is.
  Future<void> stopRepeating(Task t) async {
    if (t.recur == null) return;
    await _store.putTask(t.copyWith(clearRecur: true, updatedAt: nowStamp()));
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

  /// Arm or clear a reminder. Passing null clears it, which is also how a due
  /// reminder is acknowledged - there is no separate "dismissed" state to keep
  /// in step across devices.
  Future<void> setReminder(Task t, DateTime? at) async {
    await _store.putTask(
      at == null
          ? t.copyWith(clearReminder: true, updatedAt: nowStamp())
          : t.copyWith(remindAt: reminderStamp(at), updatedAt: nowStamp()),
    );
    await refreshTasks();
    _mutated();
  }

  /// Plan a task into a block of time, or take it out again with null.
  ///
  /// Deliberately *not* a park: the task stays on the list. Saying when you
  /// will do something should not make it harder to see, and a plan that hid
  /// its own contents would be a way to lose tasks rather than a way to get
  /// through them.
  Future<void> setTaskEvent(Task t, String? eventUuid) async {
    await _store.putTask(
      eventUuid == null
          ? t.copyWith(clearEvent: true, updatedAt: nowStamp())
          : t.copyWith(eventUuid: eventUuid, updatedAt: nowStamp()),
    );
    await refreshTasks();
    _mutated();
  }

  /// Which workspace a block belongs to, or null for one on a standalone
  /// calendar (which belongs to no workspace by design).
  ///
  /// Reads [calendarsByUuid], which is populated even on a run where the
  /// calendar view was never opened - [refreshSessions] loads the calendars as
  /// soon as anything is live, because a block has to know whose it is.
  String? workspaceForEvent(CalendarEvent e) =>
      calendarsByUuid[e.calendarUuid]?.workspaceUuid;

  /// What can be planned into [e]: the open, unshelved tasks of the workspace
  /// the event's calendar belongs to.
  ///
  /// A standalone calendar has no workspace of its own, so it offers the one
  /// you are in - the same guess the editor makes about where a new event
  /// belongs. Tasks already planned into this block are in here too, marked by
  /// their own [Task.eventUuid]; they are not filtered out, because the list is
  /// how they get *unplanned* again.
  Future<List<Task>> plannableTasks(CalendarEvent e) async {
    final ws =
        calendarsByUuid[e.calendarUuid]?.workspaceUuid ?? currentWorkspaceUuid;
    if (ws == null) return [];
    return _store.activeTasks(ws);
  }

  Future<List<Task>> tasksForEvent(String eventUuid) =>
      _store.tasksForEvent(eventUuid);

  /// Release everything planned into an event that is going away.
  ///
  /// A task pointing at a deleted block is unreachable from any session and
  /// nothing would ever clear it, so the delete has to. Completed and parked
  /// rows are released too - the pointer is just as stale on those.
  ///
  /// Note this only runs for a *local* delete. An event tombstoned on another
  /// device arrives as a merge, and the task keeps a pointer to a block that no
  /// longer exists; that is harmless (the task is still on the list, it simply
  /// never turns up in a session again) which is why there is no sweep for it.
  Future<void> _releaseEventTasks(String eventUuid) async {
    for (final t in await _store.allTasksForEvent(eventUuid)) {
      await _store.putTask(t.copyWith(clearEvent: true, updatedAt: nowStamp()));
    }
  }

  Future<void> reorder(List<String> uuids) async {
    await _store.reorderTasks(uuids);
    await refreshTasks();
    _mutated();
  }

  Future<void> toggleHistory() async {
    showHistory = !showHistory;
    if (showHistory) _closeOtherViews(keepHistory: true);
    if (showHistory && currentWorkspaceUuid != null) {
      historyTasks = await _store.history(currentWorkspaceUuid!);
    }
    notifyListeners();
  }

  void toggleThoughts() {
    showThoughts = !showThoughts;
    if (showThoughts) _closeOtherViews(keepThoughts: true);
    notifyListeners();
  }

  void toggleParked() {
    showParked = !showParked;
    if (showParked) _closeOtherViews(keepParked: true);
    notifyListeners();
  }

  Future<void> toggleJournal() async {
    showJournal = !showJournal;
    if (showJournal) _closeOtherViews(keepJournal: true);
    // refreshJournal loads plaintext directly and clears to empty when the
    // vault is locked, in which case the panel shows the unlock prompt instead.
    if (showJournal) await refreshJournal();
    notifyListeners();
  }

  Future<void> toggleCollections() async {
    showCollections = !showCollections;
    if (showCollections) _closeOtherViews(keepCollections: true);
    await refreshCollections();
    notifyListeners();
  }

  void _closeOtherViews({
    bool keepHistory = false,
    bool keepThoughts = false,
    bool keepParked = false,
    bool keepJournal = false,
    bool keepSession = false,
    bool keepCollections = false,
  }) {
    showHistory = keepHistory;
    showThoughts = keepThoughts;
    showParked = keepParked;
    showJournal = keepJournal;
    showSession = keepSession;
    showCollections = keepCollections;
    // The shopping list is not a per-workspace view, but it owns the same
    // content area, so anything opening there closes it.
    showList = false;
  }

  // ----------------------------------------------------------- attachments

  Future<List<Attachment>> attachmentsFor(Task t) =>
      _store.attachmentsFor(t.uuid);

  /// Copies the file in and records it against the task.
  Future<Attachment?> attachFile(Task t, File source) async {
    final store = blobs;
    if (store == null) return null;

    final a = await store.add(source, t.uuid);
    await _store.putAttachment(a);
    await refreshTasks();
    _mutated();
    return a;
  }

  /// Point an attachment whose bytes never arrived at the file on this device.
  ///
  /// Nothing about the row changes - it already names the bytes it wants, by
  /// their digest - so this is purely local and syncs nothing. False means the
  /// file the user picked is a *different* document, which the caller offers to
  /// attach as a new one rather than filing it under a name it does not match.
  Future<bool> locateAttachment(Attachment a, File source) async {
    final store = blobs;
    if (store == null) return false;
    return store.adopt(source, a);
  }

  /// Tombstones the row, and drops the bytes only if nothing else points at
  /// them - two tasks can share one file, since blobs are content-addressed.
  Future<void> removeAttachment(Attachment a) async {
    await _store.putAttachment(
      a.copyWith(deletedAt: nowStamp(), updatedAt: nowStamp()),
    );
    final store = blobs;
    if (store != null &&
        !await _store.isBlobReferenced(a.sha256, excludingUuid: a.uuid)) {
      await store.removeBlob(a.sha256);
    }
    await refreshTasks();
    _mutated();
  }

  /// Deletes blobs no live row references. Run at startup: a row tombstoned on
  /// another device arrives as a merge, never as a call into [removeAttachment],
  /// so its bytes would otherwise stay on disk forever.
  Future<int> sweepAttachments() async {
    final store = blobs;
    if (store == null) return 0;
    return store.sweep(await _store.referencedBlobs());
  }

  // --------------------------------------------------------- parked groups

  /// A task is parked by being given a group, and unparked by having it taken
  /// away. Both keep the row - so its history, its reminder and its uuid all
  /// survive the round trip.
  ///
  /// Parking drops focus: focus mode is for the thing you are doing now, and
  /// shelving it is the opposite claim.
  Future<void> parkTask(Task t, String groupUuid) async {
    await _store.putTask(
      t.copyWith(
        groupUuid: groupUuid,
        inProgress: false,
        updatedAt: nowStamp(),
      ),
    );
    if (focusTask?.uuid == t.uuid) focusTask = null;
    await refreshTasks();
    _mutated();
  }

  /// Move several tasks at once: to another workspace's list, or onto a shelf
  /// in any workspace (this one included).
  ///
  /// One pass and one refresh rather than a [parkTask] per row, which is the
  /// point of selecting several - five writes each followed by a reload and a
  /// notify is five flickers of a list shrinking one row at a time.
  ///
  /// [groupUuid] null means onto the list of [workspaceUuid], appended at the
  /// bottom in the order given - the order they were in where they came from.
  /// A group must belong to [workspaceUuid]; the caller picks the pair
  /// together from one menu, so this does not look it up again.
  ///
  /// The focus flag is dropped for the same reason [parkTask] drops it: a task
  /// that has left the list on screen cannot be the one you are working on.
  /// Planning into a calendar block is kept - a block says *when*, and that is
  /// no less true of a task that changed lists.
  Future<void> moveTasks(
    List<Task> tasks, {
    required String workspaceUuid,
    String? groupUuid,
  }) async {
    if (tasks.isEmpty) return;
    var order = await _store.nextSortOrder(workspaceUuid);
    final stamp = nowStamp();
    // Shelf to shelf keeps the title as it is: the new shelf is context too.
    final offShelf = groupUuid == null ? await _offShelf() : (Task t) => t;
    for (final t in tasks) {
      await _store.putTask(
        offShelf(t).copyWith(
          workspaceUuid: workspaceUuid,
          groupUuid: groupUuid,
          clearGroup: groupUuid == null,
          inProgress: groupUuid == null ? null : false,
          sortOrder: order++,
          updatedAt: stamp,
        ),
      );
      if (groupUuid != null && focusTask?.uuid == t.uuid) focusTask = null;
    }
    await refreshTasks();
    _mutated();
  }

  /// Complete or delete several tasks with one refresh. [complete] false
  /// deletes (tombstones, like [deleteTask]).
  Future<void> finishTasks(List<Task> tasks, {required bool complete}) async {
    if (tasks.isEmpty) return;
    final stamp = nowStamp();
    final done = <Task>[];
    for (final t in tasks) {
      final row = complete
          ? t.copyWith(completedAt: stamp, inProgress: false, updatedAt: stamp)
          : t.copyWith(deletedAt: stamp, updatedAt: stamp);
      await _store.putTask(row);
      if (complete) done.add(row);
      if (focusTask?.uuid == t.uuid) focusTask = null;
    }
    // A repeating task ticked in a batch comes back exactly as one ticked on
    // its own would - see completeTask.
    if (done.isNotEmpty) await _spawnOccurrences(done);
    await refreshTasks();
    _mutated();
  }

  /// Every workspace's shelves, for the picker that can park into any of them.
  /// A query per workspace: there are a handful, and this is opened by hand.
  Future<Map<String, List<ParkedGroup>>> groupsByWorkspace() async {
    return {
      for (final w in workspaces) w.uuid: await _store.parkedGroups(w.uuid),
    };
  }

  /// "Shelf: title", for a task coming off a shelf onto a list.
  ///
  /// On the shelf the shelf *is* the context - "remove concentration sounds"
  /// under "Todo Widget" says which app - and on a list of fifty it is gone.
  /// Not doubled when the title already starts with it (parked, moved back,
  /// parked again), and nothing for an untitled shelf.
  static String shelfPrefixed(String text, String? shelf) {
    final name = shelf?.trim() ?? '';
    if (name.isEmpty) return text;
    final prefix = '$name: ';
    return text.startsWith(prefix) ? text : '$prefix$text';
  }

  /// The rewrite for each task in a batch leaving its shelf for a list. Async
  /// once, for the one query that reads the titles; the returned function is
  /// then applied per row. The template a repeat is regenerated from gets the
  /// prefix too, or the next occurrence would arrive without it.
  Future<Task Function(Task)> _offShelf() async {
    final titles = await _store.groupTitles();
    return (Task t) {
      final shelf = t.groupUuid == null ? null : titles[t.groupUuid];
      if (shelf == null) return t;
      final template = t.recurText;
      return t.copyWith(
        text: shelfPrefixed(t.text, shelf),
        recurText: template == null ? null : shelfPrefixed(template, shelf),
      );
    };
  }

  /// Back onto the current list, at the bottom rather than wherever its old
  /// sort_order happens to land it.
  Future<void> unparkTask(Task t) async {
    final ws = t.workspaceUuid;
    final offShelf = await _offShelf();
    await _store.putTask(
      offShelf(t).copyWith(
        clearGroup: true,
        sortOrder: await _store.nextSortOrder(ws),
        updatedAt: nowStamp(),
      ),
    );
    await refreshTasks();
    _mutated();
  }

  Future<ParkedGroup?> saveGroup({
    String? uuid,
    required String title,
    required int reviewEveryDays,
  }) async {
    final ws = currentWorkspaceUuid;
    if (ws == null || title.trim().isEmpty) return null;

    if (uuid == null) {
      final g = ParkedGroup(
        uuid: newId(),
        workspaceUuid: ws,
        title: title.trim(),
        reviewEveryDays: reviewEveryDays,
        sortOrder: await _store.nextGroupSortOrder(ws),
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );
      await _store.putGroup(g);
      await refreshTasks();
      _mutated();
      return g;
    }

    final existing = groups.firstWhere((g) => g.uuid == uuid);
    final updated = existing.copyWith(
      title: title.trim(),
      reviewEveryDays: reviewEveryDays,
      updatedAt: nowStamp(),
    );
    await _store.putGroup(updated);
    await refreshTasks();
    _mutated();
    return updated;
  }

  /// Marks a shelf as looked at, restarting its clock.
  Future<void> markGroupReviewed(ParkedGroup g) async {
    final stamp = nowStamp();
    await _store.putGroup(g.copyWith(lastReviewedAt: stamp, updatedAt: stamp));
    await refreshTasks();
    _mutated();
  }

  /// Everything open on one shelf, back onto the list at the bottom, in the
  /// order it was shelved. The shelf itself stays.
  ///
  /// This is [deleteGroup] without the tombstone, and the two are deliberately
  /// different things: emptying a backlog is not the same as deciding you no
  /// longer keep a backlog. It is also [unparkTask] N times, except that the
  /// sort orders are handed out in one pass - asking the store for the next one
  /// per task would work, but only because each write moves the maximum.
  ///
  /// **Open tasks only.** [LocalStore.allTasksInGroup] returns completed rows
  /// too, because a group being deleted has to release those as well; putting
  /// them on the active list would be un-finishing work nobody asked to reopen.
  ///
  /// Returns how many moved, which is what the confirmation counted.
  Future<int> unparkGroup(ParkedGroup g) async {
    final ws = currentWorkspaceUuid;
    if (ws == null) return 0;
    final tasks = (await _store.allTasksInGroup(g.uuid))
        .where((t) => t.completedAt == null)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (tasks.isEmpty) return 0;

    var order = await _store.nextSortOrder(ws);
    final stamp = nowStamp();
    final offShelf = await _offShelf();
    for (final t in tasks) {
      await _store.putTask(
        offShelf(t).copyWith(
          clearGroup: true,
          sortOrder: order++,
          updatedAt: stamp,
        ),
      );
    }
    await refreshTasks();
    _mutated();
    return tasks.length;
  }

  /// Removes the shelf, not what was on it: everything it held comes back onto
  /// the current list. Deleting a group is a statement about the grouping, and
  /// silently taking a dozen tasks down with it would be the kind of loss this
  /// app exists to avoid.
  Future<void> deleteGroup(ParkedGroup g) async {
    final stamp = nowStamp();
    final offShelf = await _offShelf();
    for (final t in await _store.allTasksInGroup(g.uuid)) {
      await _store.putTask(
        offShelf(t).copyWith(clearGroup: true, updatedAt: stamp),
      );
    }
    await _store.putGroup(g.copyWith(deletedAt: stamp, updatedAt: stamp));
    await refreshTasks();
    _mutated();
  }

  /// Add one line to the end of a task's notes.
  ///
  /// Written as an *append* rather than as an edit, and the row is re-read from
  /// the store first, because of where this is called from: the home-screen
  /// quick action, whose whole point is that it lands on a task you have not
  /// looked at. The [Task] the caller is holding may be minutes old and may
  /// have been edited on another device since - saving its `notes` back
  /// wholesale would then quietly drop whatever else had arrived.
  ///
  /// Returns the task it wrote to, or null when there was nothing to write to
  /// (the row is gone) or nothing to write.
  Future<Task?> appendToNotes(Task t, String line) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    final live = await _store.taskByUuid(t.uuid);
    if (live == null || live.isDeleted) return null;

    final notes =
        live.notes.isEmpty ? trimmed : '${live.notes}\n$trimmed';
    final row = live.copyWith(notes: notes, updatedAt: nowStamp());
    await _store.putTask(row);
    // The focus tile prints the notes under the title, so the copy the shell is
    // holding has to move with the row or the line lands invisibly.
    if (focusTask?.uuid == row.uuid) focusTask = row;
    await refreshTasks();
    _mutated();
    return row;
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

  // ------------------------------------------------------- shell layout
  //
  // How the window is carved up, as opposed to what is in it. Device-local
  // `settings` rows like the calendar's zoom, and for the same reason: a phone
  // and a 4K monitor do not want each other's split, so none of this syncs.

  /// Where the dock goes once the window is wide enough not to need it at the
  /// bottom ([Layout.isWide]). A narrow window always has it at the bottom,
  /// where a thumb is; past that the two placements are a matter of taste,
  /// and Marco chose to keep the choice.
  DockEdge wideDock = DockEdge.top;

  /// The task list's share of the width when a view opens beside it, or null
  /// for the shell's default. A fraction rather than pixels so a resized window
  /// keeps the proportion that was chosen.
  double? splitFraction;

  /// The same, for the task pane beside the calendar. Separate, because the
  /// two splits want different things: a notes pane is reading width, a week
  /// grid wants every pixel it can get.
  double? calendarSplitFraction;

  /// The task list is folded away wherever something sits beside it, so the
  /// view has the whole width. It is a standing preference rather than a
  /// per-view one - "only show me the notes" should still be true the next
  /// time the notes are opened.
  bool tasksPaneCollapsed = false;

  /// How much larger than its own sizes the whole widget is drawn, 1.0 for
  /// as designed. Device-local like the rest of these: 130% is about the
  /// screen in front of you, and a phone's answer is not a desktop's.
  ///
  /// A notifier as well as a field, because the one thing that draws it -
  /// [UiScale], above the Navigator - is built by `TodoApp`, which has no
  /// reason to rebuild on every other change this class announces.
  final zoom = ValueNotifier<double>(1.0);

  /// Snapped to [T.zoomSteps], so a stored value from a future build with
  /// finer steps still lands on one this build offers.
  Future<void> setZoom(double value) async {
    final next = T.zoomSteps.reduce(
      (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
    );
    if (next == zoom.value) return;
    zoom.value = next;
    notifyListeners();
    await _store.setSetting(_kZoom, next.toStringAsFixed(2));
  }

  /// One step bigger or smaller; does nothing at either end.
  Future<void> stepZoom(int by) async {
    final i = T.zoomSteps.indexOf(zoom.value);
    final j = (i < 0 ? T.zoomSteps.indexOf(1.0) : i) + by;
    if (j < 0 || j >= T.zoomSteps.length) return;
    await setZoom(T.zoomSteps[j]);
  }

  Future<void> _loadShellPrefs() async {
    final stored = double.tryParse(await _store.setting(_kZoom) ?? '');
    if (stored != null) {
      zoom.value = T.zoomSteps.reduce(
        (a, b) => (a - stored).abs() <= (b - stored).abs() ? a : b,
      );
    }
    wideDock = DockEdge.parse(await _store.setting(_kWideDock)) ?? DockEdge.top;
    tasksPaneCollapsed = (await _store.setting(_kTasksPaneCollapsed)) == '1';
    splitFraction = double.tryParse(await _store.setting(_kSplitFraction) ?? '');
    calendarSplitFraction =
        double.tryParse(await _store.setting(_kCalendarSplitFraction) ?? '');
  }

  Future<void> setWideDock(DockEdge edge) async {
    if (edge == wideDock) return;
    wideDock = edge;
    notifyListeners();
    await _store.setSetting(_kWideDock, edge.name);
  }

  Future<void> setTasksPaneCollapsed(bool collapsed) async {
    tasksPaneCollapsed = collapsed;
    notifyListeners();
    await _store.setSetting(_kTasksPaneCollapsed, collapsed ? '1' : '0');
  }

  /// Null puts the split back to the shell's default.
  Future<void> setSplitFraction(double? fraction, {bool calendar = false}) async {
    if (calendar) {
      calendarSplitFraction = fraction;
    } else {
      splitFraction = fraction;
    }
    notifyListeners();
    await _store.setSetting(
      calendar ? _kCalendarSplitFraction : _kSplitFraction,
      fraction?.toStringAsFixed(4) ?? '',
    );
  }

  Future<void> setNudge(bool on) async {
    nudgeEnabled = on;
    await _store.setSetting(_kNudge, on ? '1' : '0');
    notifyListeners();
  }

  // -------------------------------------------------------- side thoughts

  Future<void> refreshThoughts() async {
    thoughts = await _store.pendingThoughts();
    // The panel is opened from the count badge, which is itself hidden at zero
    // - leaving it open on an empty list would strand the user in a view with
    // no way back to the tasks.
    if (thoughts.isEmpty) showThoughts = false;
    notifyListeners();
  }

  Future<void> addThought(String text) async {
    if (text.trim().isEmpty) return;
    await _store.putThought(
      SideThought(
        uuid: newId(),
        text: text.trim(),
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      ),
    );
    await refreshThoughts();
    _mutated();
  }

  /// Tidy a thought into a real task. The thought is resolved rather than
  /// deleted - side thoughts are never hard-removed, so the record survives.
  Future<void> promoteThought(SideThought s) async {
    await addTask(s.text);
    await resolveThought(s);
  }

  /// Several thoughts at once, onto any workspace's list or shelf - each
  /// becomes a task there and the thought is resolved, as [promoteThought]
  /// does for one onto this list. One pass and one refresh, the same shape as
  /// [moveTasks].
  Future<void> moveThoughts(
    List<SideThought> thoughts, {
    required String workspaceUuid,
    String? groupUuid,
  }) async {
    final keep = [
      for (final t in thoughts)
        if (t.text.trim().isNotEmpty) t,
    ];
    if (keep.isEmpty) return;
    var order = await _store.nextSortOrder(workspaceUuid);
    final stamp = nowStamp();
    for (final t in keep) {
      await _store.putTask(
        Task(
          uuid: newId(),
          workspaceUuid: workspaceUuid,
          text: t.text.trim(),
          createdAt: stamp,
          sortOrder: order++,
          groupUuid: groupUuid,
          updatedAt: stamp,
        ),
      );
      await _store.putThought(t.copyWith(resolvedAt: stamp, updatedAt: stamp));
    }
    await refreshTasks();
    await refreshThoughts();
    _mutated();
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

  // --------------------------------------------------------------- journal
  //
  // The journal is plaintext by default. A password is *optional*; setting one
  // turns on encryption and re-encrypts what is already there, and removing it
  // decrypts everything back (see journal_crypto.dart). Each row records its own
  // [JournalEntry.encrypted] state, so mixed and synced rows stay honest.

  /// A password has been set on this device (encryption is on).
  bool get journalConfigured => journalCrypto?.isConfigured ?? false;

  /// The vault is open this session (or there is no password at all, in which
  /// case nothing is locked).
  bool get journalUnlocked => journalCrypto?.isUnlocked ?? false;

  /// Password set but not yet entered this session - the one state that hides
  /// the entries behind an unlock prompt.
  bool get journalLocked => journalConfigured && !journalUnlocked;

  /// Turn encryption on: set the password, then re-encrypt every existing entry
  /// so nothing readable is left behind. Leaves the vault unlocked.
  Future<void> setupJournalPassword(String password) async {
    final c = journalCrypto;
    if (c == null || password.isEmpty) return;
    await c.setup(password);
    for (final e in await _store.allJournalEntries()) {
      if (e.encrypted) continue;
      await _store.putJournal(
        e.copyWith(
          title: await c.encrypt(e.title),
          text: await c.encrypt(e.text),
          encrypted: true,
          updatedAt: nowStamp(),
        ),
      );
    }
    await refreshJournal();
    _mutated();
  }

  /// Turn encryption off: decrypt every entry back to plaintext, then forget the
  /// key material. Requires the vault to be unlocked (we need the key to read
  /// the entries in order to write them back).
  Future<void> removeJournalPassword() async {
    final c = journalCrypto;
    if (c == null || !c.isUnlocked) return;
    for (final e in await _store.allJournalEntries()) {
      if (!e.encrypted) continue;
      try {
        await _store.putJournal(
          e.copyWith(
            title: e.title.isEmpty ? '' : await c.decrypt(e.title),
            text: await c.decrypt(e.text),
            encrypted: false,
            updatedAt: nowStamp(),
          ),
        );
      } catch (_) {
        // A foreign row this key cannot read is left encrypted; there is
        // nothing to decrypt it to.
      }
    }
    await c.disable();
    await refreshJournal();
    _mutated();
  }

  /// Open the vault for the session. Returns false on a wrong password, so the
  /// panel can say so without treating it as an error.
  Future<bool> unlockJournal(String password) async {
    final c = journalCrypto;
    if (c == null) return false;
    final ok = await c.unlock(password);
    if (ok) {
      await refreshJournal();
    } else {
      notifyListeners();
    }
    return ok;
  }

  /// Drop the in-memory key. The entries stay on disk, encrypted, and need the
  /// password again to read.
  void lockJournal() {
    journalCrypto?.lock();
    journal = [];
    notifyListeners();
  }

  /// Load the current workspace's entries into [journal], decrypting the ones
  /// that need it. Clears to empty when locked or when there is no workspace. An
  /// encrypted row this device cannot read is surfaced as [JournalItem.locked]
  /// rather than crashing or leaking garbage.
  Future<void> refreshJournal() async {
    final ws = currentWorkspaceUuid;
    if (ws == null || journalLocked) {
      journal = [];
      notifyListeners();
      return;
    }
    final c = journalCrypto;
    final items = <JournalItem>[];
    for (final e in await _store.journalEntries(ws)) {
      if (!e.encrypted) {
        items.add(JournalItem(entry: e, title: e.title, body: e.text));
        continue;
      }
      // Encrypted. If the vault is open, decrypt; otherwise it is a foreign
      // encrypted row and stays locked.
      if (c != null && c.isUnlocked) {
        try {
          items.add(
            JournalItem(
              entry: e,
              title: e.title.isEmpty ? '' : await c.decrypt(e.title),
              body: await c.decrypt(e.text),
            ),
          );
          continue;
        } catch (_) {
          // Wrong key for this row - fall through to locked.
        }
      }
      items.add(JournalItem(entry: e, title: 'Locked', body: '', locked: true));
    }
    journal = items;
    notifyListeners();
  }

  /// Write a titled note into the current workspace's journal, stamped now.
  /// Encrypted only if a password is set and the vault is open; plaintext
  /// otherwise. An entry with neither a title nor a body is dropped rather than
  /// logging an empty stamp.
  ///
  /// Returns what was written, or null if nothing was. The panel needs it: it
  /// shows the *rendered* entry after a save, and a second edit from there has
  /// to go back to the same row rather than write a new one - which it can only
  /// do if it learns the uuid this call minted.
  ///
  /// [workspaceUuid] overrides the current workspace. The journal panel saves a
  /// draft when it is closed from underneath - a workspace switch among other
  /// things - and by the time that save runs the current workspace is the new
  /// one, which is not where the note was being written.
  Future<JournalItem?> addJournalEntry(
    String title,
    String body, {
    String? workspaceUuid,
  }) async {
    final ws = workspaceUuid ?? currentWorkspaceUuid;
    if (ws == null || journalLocked) return null;
    if (title.trim().isEmpty && body.trim().isEmpty) return null;
    final (t, b, enc) = await _encodeFields(title.trim(), body.trim());
    final now = nowStamp();
    final uuid = newId();
    await _store.putJournal(
      JournalEntry(
        uuid: uuid,
        workspaceUuid: ws,
        title: t,
        text: b,
        encrypted: enc,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refreshJournal();
    _mutated();
    return journalItem(uuid);
  }

  /// The loaded entry with this uuid, or null if it is not in [journal] - it
  /// was deleted, or belongs to another workspace, or the vault was locked
  /// between the write and the lookup.
  JournalItem? journalItem(String uuid) {
    for (final item in journal) {
      if (item.uuid == uuid) return item;
    }
    return null;
  }

  /// Rewrite an entry. Its [JournalEntry.createdAt] stays put - the log records
  /// when the thing was written, not when it was later edited. Clearing both
  /// fields deletes it. A locked entry cannot be edited (it cannot be read).
  ///
  /// Returns the entry as it now reads, or null when the edit deleted it or was
  /// refused - see [addJournalEntry] for why the caller wants it back.
  Future<JournalItem?> editJournalEntry(
    JournalItem item,
    String title,
    String body,
  ) async {
    if (item.locked || journalLocked) return null;
    if (title.trim().isEmpty && body.trim().isEmpty) {
      await deleteJournalEntry(item);
      return null;
    }
    final (t, b, enc) = await _encodeFields(title.trim(), body.trim());
    await _store.putJournal(
      item.entry.copyWith(
        title: t,
        text: b,
        encrypted: enc,
        updatedAt: nowStamp(),
      ),
    );
    await refreshJournal();
    _mutated();
    return journalItem(item.uuid);
  }

  /// Encrypt the two fields when the vault is open, or hand them back plaintext.
  /// Returns the stored title, stored body, and whether they are ciphertext.
  Future<(String, String, bool)> _encodeFields(
    String title,
    String body,
  ) async {
    final c = journalCrypto;
    if (c == null || !c.isUnlocked) return (title, body, false);
    return (await c.encrypt(title), await c.encrypt(body), true);
  }

  /// Tombstoned, not dropped, so the removal reaches other devices instead of
  /// resurrecting the moment they next sync.
  Future<void> deleteJournalEntry(JournalItem item) async {
    await _store.putJournal(
      item.entry.copyWith(deletedAt: nowStamp(), updatedAt: nowStamp()),
    );
    await refreshJournal();
    _mutated();
  }

  // -------------------------------------------------------------- calendar

  /// Every live calendar, workspace-backed and standalone alike.
  List<Calendar> calendars = [];

  /// The events overlapping whatever range the calendar is showing. Loaded per
  /// range rather than wholesale: a year view of a well-used calendar is
  /// thousands of rows, and only the visible window is ever drawn.
  List<CalendarEvent> events = [];

  /// Which of those have a file on them, for the paperclip on the blob.
  Set<String> eventsWithAttachments = {};

  /// How many open todos each event carries, for the count on the blob. Every
  /// event, not just the visible range - it is one grouped query either way,
  /// and the session view asks about blocks the grid is not showing.
  Map<String, int> eventTaskCounts = {};

  bool showCalendar = false;
  CalendarViewMode calendarMode = CalendarViewMode.week;
  CalendarScope calendarScope = CalendarScope.workspace;

  /// The day the view is built around: the day shown, the week containing it,
  /// or the year containing it.
  DateTime calendarAnchor = DateTime.now();

  /// Calendars the user has unticked. Device-local, like the other UI prefs -
  /// which calendars you want to look at is a property of where you are
  /// sitting, not of the account.
  Set<String> hiddenCalendars = {};

  /// The calendars whose events belong on screen right now.
  ///
  /// Scope first, then the hidden set, so unticking something in the all view
  /// does not silently follow you into the workspace view.
  List<Calendar> get visibleCalendars {
    final ws = currentWorkspaceUuid;
    return [
      for (final c in calendars)
        if (!hiddenCalendars.contains(c.uuid))
          if (calendarScope == CalendarScope.all ||
              c.workspaceUuid == null ||
              c.workspaceUuid == ws)
            c,
    ];
  }

  Map<String, Calendar> get calendarsByUuid => {
    for (final c in calendars) c.uuid: c,
  };

  /// The calendar time-block mode drags onto, or null when the mode is off.
  ///
  /// Planning a week is one gesture repeated twenty times - drag, name it,
  /// save - and nineteen of those names are the same word. Picking the calendar
  /// *once* and then dragging turns the editor from something you dismiss on
  /// every block into something you only open when a block needs more than a
  /// span. Blocks are titled after the calendar, which for a workspace calendar
  /// is the workspace name, so the plan reads as "Client work, 09:00-11:00".
  String? timeBlockCalendarUuid;

  /// Resolved against what is *on screen*, not just against [calendars]: the
  /// target is stored as a uuid and it can go away underneath the setting - the
  /// calendar is unticked, the scope narrows, the workspace is deleted. Every
  /// one of those means the chip the user picked is gone from the strip, so the
  /// mode reading as off is what the screen already says.
  Calendar? get timeBlockCalendar {
    final uuid = timeBlockCalendarUuid;
    if (uuid == null) return null;
    for (final c in visibleCalendars) {
      if (c.uuid == uuid) return c;
    }
    return null;
  }

  bool get timeBlocking => timeBlockCalendar != null;

  /// Edit mode on or off - the calendar toolbar's pencil and Ctrl+E.
  ///
  /// Turning it on has to choose where new blocks go, and the same guess the
  /// editor makes for a fresh drag is the right one: the workspace you are
  /// in. Turning it off goes through [setTimeBlockCalendar], which is what
  /// writes the blocks laid out while it was on.
  Future<void> toggleCalendarEditing() async {
    if (timeBlocking) {
      await setTimeBlockCalendar(null);
      return;
    }
    final visible = visibleCalendars;
    if (visible.isEmpty) return;
    final preferred = visible.firstWhere(
      (c) => c.workspaceUuid == currentWorkspaceUuid,
      orElse: () => visible.first,
    );
    await setTimeBlockCalendar(preferred.uuid);
  }

  // ------------------------------------------------------- pending blocks

  /// Blocks placed in quick-add mode that have not been written yet.
  ///
  /// The point of the mode is laying out a week in one pass: tap, tap, tap,
  /// adjust, done. Writing each tap straight to the database would make every
  /// one of them a row that syncs, notifies and has to be deleted again if the
  /// shape of the afternoon turns out wrong - so they are held here until the
  /// mode ends, and only then written.
  ///
  /// Deliberately **not** in the database and deliberately not synced: an
  /// unfinished thought about Tuesday is not something another device should
  /// receive. That also means they do not survive the app closing, which is the
  /// right trade for something whose whole life is one sitting.
  ///
  /// Absolute instants rather than day-plus-minutes, so a block keeps its
  /// meaning when the view moves to another week underneath it.
  final List<({DateTime start, DateTime end})> pendingBlocks = [];

  /// The default a tap lays down. An hour is the unit people think in when
  /// blocking out a day; anything shorter and every block needs adjusting.
  static const pendingBlockLength = Duration(hours: 1);

  void placePendingBlock(DateTime start, [DateTime? end]) {
    pendingBlocks.add((start: start, end: end ?? start.add(pendingBlockLength)));
    notifyListeners();
  }

  void adjustPendingBlock(int index, DateTime start, DateTime end) {
    if (index < 0 || index >= pendingBlocks.length) return;
    // A block dragged shorter than one snap is one you can no longer grab.
    if (!end.isAfter(start)) return;
    pendingBlocks[index] = (start: start, end: end);
    notifyListeners();
  }

  void removePendingBlock(int index) {
    if (index < 0 || index >= pendingBlocks.length) return;
    pendingBlocks.removeAt(index);
    notifyListeners();
  }

  /// Write everything placed, and clear.
  ///
  /// Called when the mode ends *however* it ends - the bolt going off, the view
  /// changing, the calendar closing. One rule, so a block you placed is never
  /// silently discarded by leaving in a way you did not think of.
  ///
  /// The title is the calendar's name, the same as a dragged block in this mode
  /// gets: the calendar is the thing being filled in, so its name is what the
  /// blocks are for.
  Future<void> commitPendingBlocks() async {
    if (pendingBlocks.isEmpty) return;
    final target = timeBlockCalendar;
    final placed = List.of(pendingBlocks);
    pendingBlocks.clear();

    // No target left - the calendar was unticked or deleted underneath the
    // mode. Dropping them is the only honest answer, and clearing first means
    // this cannot loop on a target it will never get.
    if (target == null) {
      notifyListeners();
      return;
    }

    for (final block in placed) {
      await saveEvent(
        calendarUuid: target.uuid,
        title: calendarName(target),
        start: block.start,
        end: block.end,
      );
    }
  }

  /// Turn the mode on for one calendar, off with null, or move it to another.
  ///
  /// Device-local like the other calendar prefs: which calendar you are filling
  /// in right now is about this sitting, not about the account.
  ///
  /// **Commits first, always**, because this is the only way the target ever
  /// changes and [commitPendingBlocks] writes whatever is placed against the
  /// target *at the moment it runs*. Leaving that to the call sites meant the
  /// bolt committed and the block strip did not: turning the mode off from the
  /// strip left the blocks behind with no target, and the calendar closing then
  /// found none and discarded them - an afternoon's planning gone for picking
  /// the wrong control. Switching target had the matching bug, writing blocks
  /// laid out on one calendar onto another under its name. Turning the mode
  /// *on* commits nothing, because nothing can be pending with the mode off.
  Future<void> setTimeBlockCalendar(String? uuid) async {
    await commitPendingBlocks();
    timeBlockCalendarUuid = uuid;
    await _store.setSetting(_kCalendarBlock, uuid ?? '');
    notifyListeners();
  }

  /// A calendar's display name. A workspace calendar reads its name from the
  /// workspace, so renaming the workspace renames the calendar too rather than
  /// leaving a stale copy behind.
  String calendarName(Calendar c) {
    final wsUuid = c.workspaceUuid;
    if (wsUuid == null) return c.name;
    for (final w in workspaces) {
      if (w.uuid == wsUuid) return w.name;
    }
    return c.name;
  }

  /// Same rule as [calendarName], for the colour every event of this calendar
  /// is drawn in.
  Color calendarColor(Calendar c) {
    final wsUuid = c.workspaceUuid;
    if (wsUuid != null) {
      for (final w in workspaces) {
        if (w.uuid == wsUuid) return T.parseHex(w.color);
      }
    }
    return T.parseHex(c.color);
  }

  Color colorForEvent(CalendarEvent e) {
    for (final c in calendars) {
      if (c.uuid == e.calendarUuid) return calendarColor(c);
    }
    return T.accent;
  }

  /// The half-open window the current mode needs, in local time.
  (DateTime, DateTime) get calendarRange {
    final a = DateTime(
      calendarAnchor.year,
      calendarAnchor.month,
      calendarAnchor.day,
    );
    return switch (calendarMode) {
      CalendarViewMode.day => (a, a.add(const Duration(days: 1))),
      CalendarViewMode.week => (
        startOfWeek(a),
        startOfWeek(a).add(const Duration(days: 7)),
      ),
      CalendarViewMode.year => (DateTime(a.year), DateTime(a.year + 1)),
    };
  }

  /// What [refreshEvents] loads: the visible window and, in the day and week
  /// views, one step either side of it. The swipe draws the neighbouring page
  /// under the finger (see time_swipe.dart), and a glimpse of next week that
  /// arrived empty and then filled would be worse than none. Every view
  /// filters to its own days, so the extra events are simply not drawn until
  /// they are on a page. Built from the parts, not with [Duration], so a step
  /// across a clock change is still a whole day.
  (DateTime, DateTime) get calendarLoadRange {
    final (from, to) = calendarRange;
    final pad = switch (calendarMode) {
      CalendarViewMode.day => 1,
      CalendarViewMode.week => 7,
      CalendarViewMode.year => 0,
    };
    return (
      DateTime(from.year, from.month, from.day - pad),
      DateTime(to.year, to.month, to.day + pad),
    );
  }

  /// Monday. Fixed rather than locale-driven: the grid is drawn for one person,
  /// and a week that starts on a different day depending on the phone's region
  /// would make the same calendar read differently on two of their devices.
  static DateTime startOfWeek(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  Future<void> loadCalendarPrefs() async {
    final mode = await _store.setting(_kCalendarMode);
    calendarMode = CalendarViewMode.values.firstWhere(
      (m) => m.name == mode,
      orElse: () => CalendarViewMode.week,
    );
    final scope = await _store.setting(_kCalendarScope);
    calendarScope = CalendarScope.values.firstWhere(
      (s) => s.name == scope,
      orElse: () => CalendarScope.workspace,
    );
    final hidden = await _store.setting(_kCalendarHidden) ?? '';
    hiddenCalendars = hidden.split(',').where((s) => s.isNotEmpty).toSet();
    final block = await _store.setting(_kCalendarBlock) ?? '';
    timeBlockCalendarUuid = block.isEmpty ? null : block;
    final zoom = double.tryParse(await _store.setting(_kCalendarZoom) ?? '');
    hourHeight = (zoom ?? kHourHeight).clamp(kHourHeightMin, kHourHeightMax);
  }

  /// How tall an hour is drawn on the day and week grids.
  ///
  /// A device-local preference, in `settings` beside the mode and the scope,
  /// and deliberately **not** synced: how far you are zoomed in is about the
  /// screen in front of you, and a phone's answer is not a desktop's.
  double hourHeight = kHourHeight;

  /// Called continuously while two fingers are pinching, so it writes the
  /// setting but does not wait for it: the grid has to follow the fingers.
  void setHourHeight(double height) {
    final next = height.clamp(kHourHeightMin, kHourHeightMax);
    if (next == hourHeight) return;
    hourHeight = next;
    notifyListeners();
    unawaited(_store.setSetting(_kCalendarZoom, next.toStringAsFixed(1)));
  }

  /// Give every workspace a calendar, and drop the ones whose workspace is gone.
  ///
  /// Lazy provisioning rather than a hook on workspace creation: sync can bring
  /// a workspace in from another device without any local write path running,
  /// and that workspace still needs somewhere to put events. The uuid is the
  /// workspace's own, so two devices doing this independently agree on the row
  /// instead of producing a duplicate each.
  Future<void> ensureWorkspaceCalendars() async {
    final existing = {
      for (final c in calendars)
        if (c.workspaceUuid != null) c.workspaceUuid!: c,
    };
    var added = false;
    for (final ws in workspaces) {
      if (existing.containsKey(ws.uuid)) continue;
      await _store.putCalendar(Calendar.forWorkspace(ws));
      added = true;
    }
    if (added) {
      calendars = await _store.calendars();
      _mutated();
    }
  }

  Future<void> refreshCalendars() async {
    calendars = await _store.calendars();
    await ensureWorkspaceCalendars();
    await refreshEvents();
  }

  /// Reload the events for the visible window.
  Future<void> refreshEvents() async {
    final (from, to) = calendarLoadRange;
    final all = await _store.eventsBetween(from, to);
    final visible = {for (final c in visibleCalendars) c.uuid};
    events = [
      for (final e in all)
        if (visible.contains(e.calendarUuid)) e,
    ];
    eventsWithAttachments = await _store.eventsWithAttachments();
    eventTaskCounts = await _store.eventTaskCounts();
    notifyListeners();
    // Moving or deleting a block changes what is running now, and the banner
    // outlives the calendar view that changed it.
    await refreshSessions();
  }

  Future<void> toggleCalendar() async {
    showCalendar = !showCalendar;
    if (showCalendar) {
      _closeOtherViews(); // the shopping list too
      await loadCalendarPrefs();
      await refreshCalendars();
    }
    notifyListeners();
  }

  /// **Commits first**, for the same structural reason [setTimeBlockCalendar]
  /// does: changing view is one of the ways a quick-add sitting ends, and the
  /// rule has to live where it cannot be bypassed rather than at each call
  /// site. It used to sit in the calendar view's own swipe handler, which meant
  /// *swiping* to another mode wrote the blocks and *tapping* D/W/Y did not -
  /// the same split that once lost an afternoon's planning through the block
  /// strip. Nothing can be pending when the mode is off, so this costs nothing
  /// the rest of the time.
  Future<void> setCalendarMode(CalendarViewMode mode) async {
    await commitPendingBlocks();
    calendarMode = mode;
    await _store.setSetting(_kCalendarMode, mode.name);
    await refreshEvents();
  }

  Future<void> setCalendarScope(CalendarScope scope) async {
    calendarScope = scope;
    await _store.setSetting(_kCalendarScope, scope.name);
    await refreshEvents();
  }

  Future<void> setCalendarAnchor(DateTime day) async {
    calendarAnchor = DateTime(day.year, day.month, day.day);
    await refreshEvents();
  }

  /// Step one day, week or year, whichever the current mode is built on.
  Future<void> stepCalendar(int delta) async {
    final a = calendarAnchor;
    calendarAnchor = switch (calendarMode) {
      CalendarViewMode.day => a.add(Duration(days: delta)),
      CalendarViewMode.week => a.add(Duration(days: 7 * delta)),
      CalendarViewMode.year => DateTime(a.year + delta, a.month, a.day),
    };
    await refreshEvents();
  }

  Future<void> toggleCalendarHidden(String uuid) async {
    if (!hiddenCalendars.remove(uuid)) hiddenCalendars.add(uuid);
    await _store.setSetting(_kCalendarHidden, hiddenCalendars.join(','));
    await refreshEvents();
  }

  /// Create or update a standalone calendar. Workspace calendars are not
  /// editable here - their name and colour belong to the workspace.
  Future<Calendar?> saveCalendar({
    Calendar? existing,
    required String name,
    required String color,
    int? notifyMinutes,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final stamp = nowStamp();

    final row = existing == null
        ? Calendar(
            uuid: newId(),
            name: trimmed,
            color: color,
            notifyMinutes: notifyMinutes,
            sortOrder: calendars.length,
            createdAt: stamp,
            updatedAt: stamp,
          )
        : existing.copyWith(
            name: trimmed,
            color: color,
            notifyMinutes: notifyMinutes,
            clearNotify: notifyMinutes == null,
            updatedAt: stamp,
          );

    await _store.putCalendar(row);
    await refreshCalendars();
    await _rescheduleNotifications();
    _mutated();
    return row;
  }

  /// Tombstone a standalone calendar and everything on it.
  ///
  /// Refuses a workspace calendar: deleting it would leave the workspace with
  /// nowhere to put events and [ensureWorkspaceCalendars] would recreate it on
  /// the next refresh anyway. Deleting the workspace is the way to do that, and
  /// it cascades here.
  Future<void> deleteCalendar(Calendar c) async {
    if (c.isWorkspaceCalendar) return;
    final stamp = nowStamp();
    for (final e in await _store.eventsOnCalendar(c.uuid)) {
      await _releaseEventTasks(e.uuid);
      await _store.putEvent(e.copyWith(deletedAt: stamp, updatedAt: stamp));
    }
    await _store.putCalendar(c.copyWith(deletedAt: stamp, updatedAt: stamp));
    await _dropFeedsOn(c.uuid, stamp);
    hiddenCalendars.remove(c.uuid);
    await refreshCalendars();
    await refreshTasks();
    await _rescheduleNotifications();
    _mutated();
  }

  Future<CalendarEvent?> saveEvent({
    CalendarEvent? existing,
    required String calendarUuid,
    required String title,
    String description = '',
    required DateTime start,
    required DateTime end,
    int? notifyMinutes,
    bool clearNotify = false,
    String? recur,
    bool clearRecur = false,
    bool allDay = false,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;
    // A backwards drag, or a click that never moved. Either way the block needs
    // a positive length or it cannot be drawn, let alone grabbed again.
    var from = start.isBefore(end) ? start : end;
    var to = start.isBefore(end) ? end : start;
    if (!to.isAfter(from)) to = from.add(const Duration(minutes: 15));

    // An all-day event is stored as real instants like any other: midnight on
    // its first day to midnight on the day *after* its last. That exclusive end
    // is what .ics uses, and it is what lets every existing overlap test - the
    // window query, the spanning band, the session - go on working with no idea
    // this flag exists.
    //
    // [end] is therefore **exclusive** for an all-day event, which is what
    // `parseIcs` already produces; the editor is the one that has to convert,
    // because a person picking "ends 20 Aug" means the 20th included.
    if (allDay) {
      from = DateTime(from.year, from.month, from.day);
      final lastDay = DateTime(to.year, to.month, to.day);
      to = lastDay.isAfter(from)
          ? lastDay
          : from.add(const Duration(days: 1));
    }

    final stamp = nowStamp();
    final row = existing == null
        ? CalendarEvent(
            uuid: newId(),
            calendarUuid: calendarUuid,
            title: trimmed,
            description: description,
            startAt: reminderStamp(from),
            endAt: reminderStamp(to),
            notifyMinutes: notifyMinutes,
            recur: recur,
            allDay: allDay,
            createdAt: stamp,
            updatedAt: stamp,
          )
        : existing.copyWith(
            calendarUuid: calendarUuid,
            title: trimmed,
            description: description,
            startAt: reminderStamp(from),
            endAt: reminderStamp(to),
            notifyMinutes: notifyMinutes,
            clearNotify: clearNotify,
            recur: recur,
            clearRecur: clearRecur,
            allDay: allDay,
            updatedAt: stamp,
          );

    await _store.putEvent(row);
    await refreshEvents();
    await _rescheduleNotifications();
    _mutated();
    return row;
  }

  /// A block was dragged on the grid: the piece that started at [from] was
  /// let go at [to]. Moves the event - its series, for an occurrence - by
  /// that distance and keeps its length. A feed's event is the feed's to
  /// move, so it is left alone (the grid does not offer it either).
  Future<void> moveEvent(
    CalendarEvent e, {
    required DateTime from,
    required DateTime to,
  }) async {
    if (e.fromFeed || from == to) return;
    await _store.putEvent(e.shiftedBy(from, to, stamp: nowStamp()));
    await refreshEvents();
    await _rescheduleNotifications();
    _mutated();
  }

  /// Drag one end of a block: its start ([start]) or its end, from the instant
  /// it was at to [to]. The series when [e] is an occurrence, like a move.
  Future<void> resizeEvent(
    CalendarEvent e, {
    required bool start,
    required DateTime from,
    required DateTime to,
  }) async {
    if (e.fromFeed || from == to) return;
    final resized = e.resizedBy(from, to, start: start, stamp: nowStamp());
    if (resized == null) return;
    await _store.putEvent(resized);
    await refreshEvents();
    await _rescheduleNotifications();
    _mutated();
  }

  /// Add events read out of an .ics file to [calendarUuid].
  ///
  /// Goes through [saveEvent] rather than writing rows directly, so an imported
  /// block is an ordinary event in every respect - same validation, same
  /// notification reschedule, same sync. There is deliberately no "imported"
  /// flag: a block that behaved differently from one you dragged would be a
  /// second kind of event to reason about for no gain.
  ///
  /// A repeat rule comes across when the .ics said something this app can say
  /// (see `icsRecurRule`). When it did not, the description carries a note that
  /// only the first occurrence was imported - silently importing one of a
  /// series is the kind of thing that is discovered late. The location goes
  /// into the description the same way, having no column of its own.
  Future<int> importIcsEvents(
    List<IcsEvent> events, {
    required String calendarUuid,
  }) async {
    var added = 0;
    for (final e in events) {
      final notes = [
        if (e.location.isNotEmpty) e.location,
        if (e.description.isNotEmpty) e.description,
        if (e.recurring && e.recur == null)
          'Repeats on a rule this app cannot store — only this occurrence '
              'was imported.',
      ].join('\n\n');

      final row = await saveEvent(
        calendarUuid: calendarUuid,
        title: e.summary,
        description: notes,
        start: e.start,
        end: e.end,
        recur: e.recur,
        allDay: e.allDay,
      );
      if (row != null) added++;
    }
    return added;
  }

  Future<void> deleteEvent(CalendarEvent e) async {
    final stamp = nowStamp();
    // The attachments go with it, for the same reason a deleted task's do: a
    // row pointing at an event that no longer exists is unreachable, and its
    // bytes would never be collected.
    for (final a in await _store.eventAttachments(e.uuid)) {
      await _store.putAttachment(
        a.copyWith(deletedAt: stamp, updatedAt: stamp),
      );
    }
    // The tasks do *not* go with it - they are still things to do, they have
    // simply lost the time that was set aside for them. Only the pointer goes.
    await _releaseEventTasks(e.uuid);
    await _store.putEvent(e.copyWith(deletedAt: stamp, updatedAt: stamp));
    await refreshEvents();
    // The rows that were just released are on the list with a stale "planned"
    // mark until this runs.
    await refreshTasks();
    await _rescheduleNotifications();
    _mutated();
  }

  Future<List<Attachment>> eventAttachments(CalendarEvent e) =>
      _store.eventAttachments(e.uuid);

  /// Copy a file into the blob store and attach it to an event. Mirrors
  /// [attachFile] for tasks - same content addressing, same dedup.
  Future<Attachment?> attachFileToEvent(CalendarEvent e, File source) async {
    final store = blobs;
    if (store == null) return null;
    final row = await store.addForEvent(source, e.uuid);
    await _store.putAttachment(row);
    await refreshEvents();
    _mutated();
    return row;
  }

  /// Tombstones an event's attachment, dropping the bytes only if nothing else
  /// points at them. Mirrors [removeAttachment], which refreshes the task list
  /// instead - the same call would rebuild the wrong screen here.
  Future<void> removeEventAttachment(Attachment a) async {
    final stamp = nowStamp();
    await _store.putAttachment(a.copyWith(deletedAt: stamp, updatedAt: stamp));
    final store = blobs;
    if (store != null &&
        !await _store.isBlobReferenced(a.sha256, excludingUuid: a.uuid)) {
      await store.removeBlob(a.sha256);
    }
    await refreshEvents();
    _mutated();
  }

  // -------------------------------------------------------- subscriptions
  //
  // A subscribed calendar is a [CalendarFeed] row plus the events it wrote;
  // feeds.dart has the reasoning. What lives here is the bookkeeping: when to
  // fetch, what happened last time, and what subscribing and unsubscribing
  // write.

  /// Every live subscription. Loaded with the app, not with the calendar,
  /// because refreshing them is not something the calendar has to be open for.
  List<CalendarFeed> feeds = [];

  /// How each feed's last refresh on *this device* went, keyed by feed uuid.
  /// Device-local, in settings - see [CalendarFeed] for why it is not a column.
  Map<String, FeedStatus> feedStatus = {};

  /// How a feed's text is fetched, which depends on the platform (see
  /// [FeedFetcher]). Null in tests that do not fetch, and on the web before a
  /// sync server is set up - there is no way for a browser to fetch a calendar
  /// without one.
  FeedFetcher? fetchFeed;

  /// The feeds being refreshed right now. A tick arriving while a slow fetch
  /// is still out must not start a second one of the same feed.
  final Set<String> _refreshing = {};

  bool isRefreshingFeed(String uuid) => _refreshing.contains(uuid);

  /// Subscriptions writing into [calendarUuid].
  List<CalendarFeed> feedsOn(String calendarUuid) =>
      [for (final f in feeds) if (f.calendarUuid == calendarUuid) f];

  CalendarFeed? feedByUuid(String? uuid) {
    for (final f in feeds) {
      if (f.uuid == uuid) return f;
    }
    return null;
  }

  static String _feedKey(String uuid) => 'feed:$uuid';

  Future<void> loadFeeds() async {
    feeds = await _store.calendarFeeds();
    for (final f in feeds) {
      if (feedStatus.containsKey(f.uuid)) continue;
      feedStatus[f.uuid] =
          FeedStatus.decode(await _store.setting(_feedKey(f.uuid)));
    }
    feedStatus.removeWhere((k, _) => !feeds.any((f) => f.uuid == k));
    notifyListeners();
  }

  /// Fetch a calendar address without subscribing to it, for the subscribe
  /// form to show what is there. Throws a [FeedError] in words.
  Future<String> previewFeed(String url) async {
    final uri = feedUri(url);
    if (uri == null) throw const FeedError('That is not a web address.');
    final fetch = fetchFeed;
    if (fetch == null) {
      throw const FeedError('In the browser, subscribing goes through your '
          'sync server - set one up in Settings first.');
    }
    return fetch(uri);
  }

  /// Subscribe to [url], into [calendarUuid] when given and otherwise into a
  /// new calendar called [name] in [color].
  ///
  /// [text] is the fetch the form already made, so subscribing does not ask
  /// the address twice.
  Future<CalendarFeed?> subscribe({
    required String url,
    required String name,
    String? calendarUuid,
    String color = '#6c8cff',
    bool alerts = false,
    String? text,
  }) async {
    final trimmed = name.trim();
    var target = calendarUuid;
    if (target == null) {
      final made = await saveCalendar(
        name: trimmed.isEmpty ? 'Subscribed' : trimmed,
        color: color,
      );
      if (made == null) return null;
      target = made.uuid;
    }
    final stamp = nowStamp();
    final feed = CalendarFeed(
      uuid: newId(),
      calendarUuid: target,
      name: trimmed.isEmpty ? 'Subscribed' : trimmed,
      url: url.trim(),
      alerts: alerts,
      createdAt: stamp,
      updatedAt: stamp,
    );
    await _store.putFeed(feed);
    await loadFeeds();
    _mutated();
    await refreshFeed(feed, text: text);
    return feed;
  }

  /// Rename, retarget or change the alerts of a subscription. The events
  /// follow on the refresh this triggers: they are the feed's rows, and the
  /// refresh is what writes them.
  Future<void> updateFeed(
    CalendarFeed feed, {
    String? name,
    String? calendarUuid,
    bool? alerts,
  }) async {
    final next = feed.copyWith(
      name: name?.trim().isEmpty ?? true ? null : name!.trim(),
      calendarUuid: calendarUuid,
      alerts: alerts,
    );
    await _store.putFeed(next);
    await loadFeeds();
    _mutated();
    await refreshFeed(next);
  }

  /// Stop subscribing: its events go, and so does the calendar it was given if
  /// nothing else is on it.
  ///
  /// The calendar goes only when it is a standalone one holding nothing but
  /// this feed's events - which is exactly the calendar subscribing made. A
  /// feed that was merged into an existing calendar leaves that calendar and
  /// everything you put on it alone.
  Future<void> unsubscribe(CalendarFeed feed) async {
    final stamp = nowStamp();
    await _dropFeed(feed, stamp);

    Calendar? calendar;
    for (final c in await _store.calendars()) {
      if (c.uuid == feed.calendarUuid) calendar = c;
    }
    final emptied = calendar != null &&
        !calendar.isWorkspaceCalendar &&
        (await _store.eventsOnCalendar(calendar.uuid)).isEmpty &&
        !feeds.any((f) => f.calendarUuid == calendar!.uuid);
    if (emptied) {
      await deleteCalendar(calendar);
    } else {
      await refreshCalendars();
    }
    await refreshTasks();
    await _rescheduleNotifications();
    _mutated();
  }

  Future<void> _dropFeed(CalendarFeed feed, String stamp) async {
    for (final e in await _store.feedEvents(feed.uuid)) {
      await _releaseEventTasks(e.uuid);
      await _store.putEvent(e.copyWith(deletedAt: stamp, updatedAt: stamp));
    }
    await _store.putFeed(feed.copyWith(deletedAt: stamp, updatedAt: stamp));
    await _store.clearSetting(_feedKey(feed.uuid));
    feedStatus.remove(feed.uuid);
    await loadFeeds();
  }

  /// A calendar going away takes its subscriptions with it - otherwise the
  /// next refresh would go on writing events into a calendar nobody can see.
  Future<void> _dropFeedsOn(String calendarUuid, String stamp) async {
    for (final f in await _store.calendarFeeds()) {
      if (f.calendarUuid == calendarUuid) await _dropFeed(f, stamp);
    }
  }

  /// Refresh every feed that is due, or all of them when [force]d.
  ///
  /// Called from the poll, so it is cheap when nothing is due: a comparison of
  /// timestamps per feed, and no fetch at all.
  Future<void> refreshFeeds({bool force = false, DateTime? now}) async {
    final at = now ?? DateTime.now();
    for (final f in List.of(feeds)) {
      if (force || (feedStatus[f.uuid] ?? const FeedStatus()).isDue(at)) {
        await refreshFeed(f, now: at);
      }
    }
  }

  /// Fetch one feed and bring its events in line with it.
  ///
  /// A failure keeps what is there. A calendar that cannot be fetched for an
  /// afternoon should go on showing this morning's meetings, not none.
  Future<void> refreshFeed(CalendarFeed feed, {String? text, DateTime? now}) async {
    if (!_refreshing.add(feed.uuid)) return;
    final at = now ?? DateTime.now();
    final before = feedStatus[feed.uuid] ?? const FeedStatus();
    feedStatus[feed.uuid] = before.copyWith(triedAt: at);
    notifyListeners();

    FeedStatus result;
    var wrote = false;
    try {
      if (!(await _store.calendars()).any((c) => c.uuid == feed.calendarUuid)) {
        throw const FeedError('Its calendar was deleted.');
      }
      final uri = feed.fetchUri;
      if (uri == null) throw const FeedError('That is not a web address.');
      String body;
      if (text != null) {
        body = text;
      } else {
        final fetch = fetchFeed;
        if (fetch == null) {
          throw const FeedError('Needs a sync server to fetch through in the '
              'browser.');
        }
        body = await fetch(uri);
      }
      final window = feedWindow(at);
      final rows = feedRows(feed, body, from: window.from, to: window.to);
      final applied = await _store.applyFeedRows(
        feed.uuid,
        rows,
        from: window.from,
        to: window.to,
      );
      wrote = applied.added + applied.changed + applied.removed > 0;
      result = FeedStatus(
        fetchedAt: at,
        triedAt: at,
        count: rows.length,
      );
    } on FeedError catch (e) {
      result = before.copyWith(triedAt: at, error: e.message);
    } catch (e) {
      result = before.copyWith(triedAt: at, error: 'Could not read it: $e');
    } finally {
      _refreshing.remove(feed.uuid);
    }

    feedStatus[feed.uuid] = result;
    await _store.setSetting(_feedKey(feed.uuid), result.encode());
    if (wrote) {
      if (showCalendar) await refreshEvents();
      await refreshSessions();
      await _rescheduleNotifications();
      _mutated();
    }
    notifyListeners();
  }

  // -------------------------------------------------------- shopping list
  //
  // One throwaway list the app opens on while it exists - see *The shopping
  // list* in ROADMAP.md. "Current" is derived (the newest list that is not
  // archived), never stored, so there is no flag for two devices to disagree
  // about and nothing for the server to keep exclusive.

  /// Whether the list owns the content area. Like the calendar it replaces
  /// the whole body; the two are never open at once.
  bool showList = false;

  /// The open list, or null when there is none and the screen offers to start
  /// one.
  ShoppingList? currentList;

  /// Open lists older than [currentList]. Only two devices each starting a
  /// list offline produce one; they are offered for merging, never hidden.
  List<ShoppingList> otherOpenLists = [];

  /// [currentList]'s items, in their order, ticked and unticked alike.
  List<ListItem> listItems = [];

  /// Default name for a new list. It is a shopping list nine times out of ten,
  /// and the tenth is one tap in Edit away.
  static const defaultListName = 'Shopping';

  Future<void> loadList() async {
    final open = await _store.openLists();
    currentList = open.isEmpty ? null : open.first;
    otherOpenLists = open.length > 1 ? open.sublist(1) : [];
    final current = currentList;
    listItems = current == null ? [] : await _store.listItems(current.uuid);
    notifyListeners();
  }

  /// Open or close the list. Opening closes every other view and the calendar,
  /// for the same reason [toggleCalendar] does: it owns the content area.
  Future<void> toggleList() => setListOpen(!showList);

  Future<void> setListOpen(bool open) async {
    if (open == showList) return;
    if (open) {
      _closeOtherViews();
      // Leaving the calendar this way ends quick-add like every other way out
      // does - see commitPendingBlocks.
      if (showCalendar) await commitPendingBlocks();
      showCalendar = false;
      await loadList();
    }
    showList = open;
    notifyListeners();
  }

  /// The list this edit lands on, starting one if there is none: typing the
  /// first item into the empty screen *is* starting a list.
  Future<ShoppingList> _ensureList() async {
    final current = currentList;
    if (current != null) return current;
    final stamp = nowStamp();
    final made = ShoppingList(
      uuid: newId(),
      name: defaultListName,
      createdAt: stamp,
      updatedAt: stamp,
    );
    await _store.putList(made);
    currentList = made;
    return made;
  }

  Future<void> _listChanged() async {
    await loadList();
    _mutated();
  }

  Future<void> renameList(String name) async {
    final current = currentList;
    final trimmed = name.trim();
    if (current == null || trimmed.isEmpty || trimmed == current.name) return;
    await _store.putList(current.copyWith(name: trimmed));
    await _listChanged();
  }

  /// Add an item at the end of what is still to get.
  Future<void> addListItem(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final list = await _ensureList();
    final last = listItems.fold<int>(-1, (m, i) => i.sortOrder > m ? i.sortOrder : m);
    final stamp = nowStamp();
    await _store.putListItem(ListItem(
      uuid: newId(),
      listUuid: list.uuid,
      text: trimmed,
      sortOrder: last + 1,
      createdAt: stamp,
      updatedAt: stamp,
    ));
    await _listChanged();
  }

  /// Retitle an item; clearing it to nothing deletes it, as a task's does.
  Future<void> editListItem(ListItem item, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return deleteListItem(item);
    if (trimmed == item.text) return;
    await _store.putListItem(item.copyWith(text: trimmed));
    await _listChanged();
  }

  Future<void> deleteListItem(ListItem item) async {
    final stamp = nowStamp();
    await _store.putListItem(item.copyWith(deletedAt: stamp, updatedAt: stamp));
    await _listChanged();
  }

  /// Tick or untick. An unticked item goes back to the place it had: its
  /// sort order never changed while it was ticked.
  Future<void> setListItemChecked(ListItem item, bool checked) async {
    if (item.isChecked == checked) return;
    await _store.putListItem(checked
        ? item.copyWith(checkedAt: nowStamp())
        : item.copyWith(clearChecked: true));
    await _listChanged();
  }

  /// Put the still-to-get items in this order. Ticked ones keep theirs.
  Future<void> reorderListItems(List<String> uuids) async {
    final byUuid = {for (final i in listItems) i.uuid: i};
    for (final (index, uuid) in uuids.indexed) {
      final item = byUuid[uuid];
      if (item == null || item.sortOrder == index) continue;
      await _store.putListItem(item.copyWith(sortOrder: index));
    }
    await _listChanged();
  }

  /// Done with it: archived exactly as it is, ticks and all, and the next
  /// list starts empty.
  Future<void> finishList([ShoppingList? list]) async {
    final target = list ?? currentList;
    if (target == null) return;
    await _store.putList(target.copyWith(archivedAt: nowStamp()));
    await _listChanged();
  }

  /// Fold an older open list into the current one: its items move over (ticks
  /// kept, placed after what is here) and it is archived, so nothing written
  /// on either device is lost.
  Future<void> mergeListIntoCurrent(ShoppingList other) async {
    final current = currentList;
    if (current == null || other.uuid == current.uuid) return;
    var next = listItems.fold<int>(-1, (m, i) => i.sortOrder > m ? i.sortOrder : m) + 1;
    for (final item in await _store.listItems(other.uuid)) {
      await _store.putListItem(
          item.copyWith(listUuid: current.uuid, sortOrder: next++));
    }
    await _store.putList(other.copyWith(archivedAt: nowStamp()));
    await _listChanged();
  }

  Future<List<ShoppingList>> archivedLists() => _store.archivedLists();

  Future<Map<String, int>> listItemCounts() => _store.listItemCounts();

  Future<List<ListItem>> itemsOfList(String listUuid) =>
      _store.listItems(listUuid);

  /// Remove an archived list for good, items and all (tombstoned, so the
  /// removal reaches the other devices).
  Future<void> deleteList(ShoppingList list) async {
    final stamp = nowStamp();
    for (final item in await _store.listItems(list.uuid)) {
      await _store.putListItem(item.copyWith(deletedAt: stamp, updatedAt: stamp));
    }
    await _store.putList(list.copyWith(deletedAt: stamp, updatedAt: stamp));
    await _listChanged();
  }

  // ---------------------------------------------------------- collections
  //
  // A workspace's tables with fields decided first - recipes, movies. See
  // *Collections* in ROADMAP.md. The whole workspace's worth is held in memory
  // while the view is open: they are small, and holding them whole is what
  // lets search and sort be done without a query per keystroke.

  /// The current workspace's collections, in their order. Empty while the
  /// view is closed.
  List<Collection> collections = [];

  /// Each collection's live fields, in field order.
  Map<String, List<CollectionField>> collectionFields = {};

  /// Each collection's live entries, newest first.
  Map<String, List<CollectionEntry>> collectionEntries = {};

  /// Loads the current workspace's collections while the view is open, and
  /// lets go of them when it is not.
  Future<void> refreshCollections() async {
    final ws = currentWorkspaceUuid;
    if (!showCollections || ws == null) {
      collections = [];
      collectionFields = {};
      collectionEntries = {};
      return;
    }
    collections = await _store.collections(ws);
    collectionFields = {for (final c in collections) c.uuid: []};
    for (final f in await _store.collectionFields(ws)) {
      collectionFields[f.collectionUuid]?.add(f);
    }
    collectionEntries = {for (final c in collections) c.uuid: []};
    for (final e in await _store.collectionEntries(ws)) {
      collectionEntries[e.collectionUuid]?.add(e);
    }
  }

  Future<void> _collectionsChanged() async {
    await refreshCollections();
    notifyListeners();
    _mutated();
  }

  /// Create a collection, or rename one and bring its fields in line with
  /// [fields]: a field with a uuid is kept (renamed, retyped, moved), one
  /// without is new, and an existing field missing from the list is removed.
  /// A removed field's values stay in the entries and are simply not drawn.
  Future<Collection?> saveCollection({
    Collection? existing,
    required String name,
    required List<FieldDraft> fields,
    String? workspaceUuid,
  }) async {
    final trimmed = name.trim();
    final ws = workspaceUuid ?? existing?.workspaceUuid ?? currentWorkspaceUuid;
    if (trimmed.isEmpty || ws == null) return null;
    final stamp = nowStamp();

    final Collection saved;
    if (existing == null) {
      saved = Collection(
        uuid: newId(),
        workspaceUuid: ws,
        name: trimmed,
        sortOrder: collections.length,
        createdAt: stamp,
        updatedAt: stamp,
      );
      await _store.putCollection(saved);
    } else {
      saved = existing.name == trimmed
          ? existing
          : existing.copyWith(name: trimmed);
      if (saved != existing) await _store.putCollection(saved);
    }

    final before = {
      for (final f in collectionFields[saved.uuid] ?? const <CollectionField>[])
        f.uuid: f,
    };
    final kept = <String>{};
    var order = 0;
    for (final draft in fields) {
      final fieldName = draft.name.trim();
      if (fieldName.isEmpty) continue;
      final old = draft.uuid == null ? null : before[draft.uuid];
      if (old == null) {
        await _store.putCollectionField(CollectionField(
          uuid: newId(),
          collectionUuid: saved.uuid,
          name: fieldName,
          kind: draft.kind,
          sortOrder: order,
          createdAt: stamp,
          updatedAt: stamp,
        ));
      } else {
        kept.add(old.uuid);
        if (old.name != fieldName ||
            old.kind != draft.kind ||
            old.sortOrder != order) {
          await _store.putCollectionField(
              old.copyWith(name: fieldName, kind: draft.kind, sortOrder: order));
        }
      }
      order++;
    }
    for (final old in before.values) {
      if (kept.contains(old.uuid)) continue;
      await _store.putCollectionField(
          old.copyWith(deletedAt: stamp, updatedAt: stamp));
    }

    await _collectionsChanged();
    return saved;
  }

  /// A collection, its fields and its entries, tombstoned so the removal
  /// reaches the other devices.
  Future<void> deleteCollection(Collection c) async {
    final stamp = nowStamp();
    await _tombstoneCollection(c, stamp);
    await _collectionsChanged();
  }

  Future<void> _tombstoneCollection(Collection c, String stamp) async {
    final ws = c.workspaceUuid;
    for (final f in await _store.collectionFields(ws)) {
      if (f.collectionUuid != c.uuid) continue;
      await _store.putCollectionField(
          f.copyWith(deletedAt: stamp, updatedAt: stamp));
    }
    for (final e in await _store.collectionEntries(ws)) {
      if (e.collectionUuid != c.uuid) continue;
      await _store.putCollectionEntry(
          e.copyWith(deletedAt: stamp, updatedAt: stamp));
    }
    await _store.putCollection(c.copyWith(deletedAt: stamp, updatedAt: stamp));
  }

  Future<void> _tombstoneCollections(String workspaceUuid, String stamp) async {
    for (final c in await _store.collections(workspaceUuid)) {
      await _tombstoneCollection(c, stamp);
    }
  }

  /// Add an entry, or rewrite [existing]. [values] is field uuid to value for
  /// the fields the form showed; values are trimmed and an empty one is
  /// dropped. A value under a field the form did not show - one removed from
  /// the collection - is kept, so putting the field back is not the only way
  /// to lose it.
  ///
  /// Returns the row written. Null means nothing was: a new entry with
  /// nothing in it is not one, and an existing entry cleared to nothing is
  /// deleted, as a task cleared to nothing is.
  Future<CollectionEntry?> saveEntry(
    Collection c,
    Map<String, String> values, {
    CollectionEntry? existing,
  }) async {
    final cleaned = <String, String>{
      for (final e in values.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    };
    if (cleaned.isEmpty) {
      if (existing != null) await deleteEntry(existing);
      return null;
    }

    final CollectionEntry saved;
    if (existing == null) {
      final stamp = nowStamp();
      saved = CollectionEntry(
        uuid: newId(),
        collectionUuid: c.uuid,
        data: cleaned,
        createdAt: stamp,
        updatedAt: stamp,
      );
    } else {
      final data = {
        for (final e in existing.data.entries)
          if (!values.containsKey(e.key)) e.key: e.value,
        ...cleaned,
      };
      saved = existing.copyWith(data: data);
    }
    await _store.putCollectionEntry(saved);
    await _collectionsChanged();
    return saved;
  }

  Future<void> deleteEntry(CollectionEntry e) async {
    final stamp = nowStamp();
    await _store.putCollectionEntry(
        e.copyWith(deletedAt: stamp, updatedAt: stamp));
    await _collectionsChanged();
  }

  /// Tick or untick one checkbox field on an entry, in place from the list.
  Future<void> setEntryChecked(
    CollectionEntry e,
    CollectionField field,
    bool checked,
  ) async {
    if (e.isChecked(field.uuid) == checked) return;
    final data = Map<String, String>.of(e.data);
    if (checked) {
      data[field.uuid] = CollectionEntry.checked;
    } else {
      data.remove(field.uuid);
    }
    await _store.putCollectionEntry(e.copyWith(data: data));
    await _collectionsChanged();
  }

  // ---------------------------------------------------------------- tint

  Color get workspaceColor {
    final ws = currentWorkspace;
    return ws == null ? T.accent : T.parseHex(ws.color);
  }
}


/// How a feed's refreshes have gone on this device.
class FeedStatus {
  const FeedStatus({this.fetchedAt, this.triedAt, this.error, this.count = 0});

  /// The last refresh that worked.
  final DateTime? fetchedAt;

  /// The last attempt, worked or not.
  final DateTime? triedAt;

  /// Why the last attempt failed, or null when it did not.
  final String? error;

  /// How many occurrences the last good fetch had in the window.
  final int count;

  bool isDue(DateTime now) {
    final last = triedAt;
    if (last == null) return true;
    return !now.isBefore(last.add(error == null ? feedInterval : feedRetry));
  }

  FeedStatus copyWith({DateTime? triedAt, String? error}) => FeedStatus(
        fetchedAt: fetchedAt,
        triedAt: triedAt ?? this.triedAt,
        error: error,
        count: count,
      );

  String encode() => jsonEncode({
        'fetched': fetchedAt?.toUtc().toIso8601String(),
        'tried': triedAt?.toUtc().toIso8601String(),
        'error': error,
        'count': count,
      });

  static FeedStatus decode(String? raw) {
    if (raw == null) return const FeedStatus();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      DateTime? at(Object? v) =>
          v is String ? DateTime.tryParse(v)?.toLocal() : null;
      return FeedStatus(
        fetchedAt: at(m['fetched']),
        triedAt: at(m['tried']),
        error: m['error'] as String?,
        count: (m['count'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const FeedStatus();
    }
  }
}

/// One field as the collection form hands it back. [uuid] is the existing
/// field it edits, or null for a new one.
class FieldDraft {
  const FieldDraft({this.uuid, required this.name, this.kind = FieldKind.text});

  final String? uuid;
  final String name;
  final FieldKind kind;
}
