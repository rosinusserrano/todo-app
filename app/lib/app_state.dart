// Application state.
//
// The Tauri build kept state in module-level variables in main.ts and re-read
// the database after every mutation. That shape survives here as a
// ChangeNotifier: mutate the local store, reload, notify. Reads are cheap
// (local SQLite, small lists) and it keeps the UI a pure function of the DB,
// which is what made focus mode survivable across restarts.

import 'dart:io' show File;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'journal_crypto.dart';
import 'notifications.dart';
import 'sync/attachment_store.dart';
import 'sync/ics.dart';
import 'sync/local_store.dart';
import 'sync/models.dart';
import 'theme.dart';

const _kLastWorkspace = 'ui:last-workspace';
const _kNudge = 'ui:nudge-enabled';
const _kCalendarMode = 'ui:calendar-mode';
const _kCalendarScope = 'ui:calendar-scope';
const _kCalendarHidden = 'ui:calendar-hidden';
const _kCalendarBlock = 'ui:calendar-block';

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
    currentWorkspaceUuid = await _store.setting(_kLastWorkspace);
    await refreshWorkspaces();
    await refreshTasks();
    await refreshThoughts();
    await restoreFocus();
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

  Future<void> selectWorkspace(String uuid) async {
    currentWorkspaceUuid = uuid;
    await _store.setSetting(_kLastWorkspace, uuid);
    // History, the parked shelves and the journal are per-workspace views, so
    // they cannot survive the switch. Side thoughts are global and deliberately
    // do: switching workspace is not a reason to lose sight of them.
    showHistory = false;
    showParked = false;
    showJournal = false;
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

    // The workspace's calendar and everything on it. Its uuid is the
    // workspace's, so it is found by id rather than by scanning.
    for (final e in await _store.eventsOnCalendar(uuid)) {
      await _store.putEvent(e.copyWith(deletedAt: stamp, updatedAt: stamp));
    }
    for (final c in await _store.calendars()) {
      if (c.workspaceUuid != uuid) continue;
      await _store.putCalendar(c.copyWith(deletedAt: stamp, updatedAt: stamp));
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
  Future<void> addTask(
    String text, {
    String notes = '',
    int priority = 0,
    DateTime? remindAt,
    String? recur,
  }) async {
    final ws = currentWorkspaceUuid;
    if (ws == null || text.trim().isEmpty) return;
    await _store.putTask(
      Task(
        uuid: newId(),
        workspaceUuid: ws,
        text: text.trim(),
        createdAt: nowStamp(),
        sortOrder: await _store.nextSortOrder(ws),
        notes: notes.trim(),
        priority: priority,
        remindAt: remindAt == null ? null : reminderStamp(remindAt),
        // Meaningless without something to count from, so it follows the
        // reminder - the same rule saveTaskDetails applies.
        recur: remindAt == null ? null : recur,
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
  Future<void> saveTaskDetails(
    Task t, {
    required String text,
    required String notes,
    required int priority,
    DateTime? remindAt,
    String? recur,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _store.putTask(
      t.copyWith(
        text: trimmed,
        notes: notes.trim(),
        priority: priority,
        remindAt: remindAt == null ? null : reminderStamp(remindAt),
        clearReminder: remindAt == null,
        // A recurrence with nothing to count from would never produce a second
        // occurrence, so clearing the reminder clears the rule with it rather
        // than leaving a rule that silently does nothing.
        recur: remindAt == null ? null : recur,
        clearRecur: recur == null || remindAt == null,
        updatedAt: nowStamp(),
      ),
    );
    await refreshTasks();
    _mutated();
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
    await _store.putTask(
      t.copyWith(
        completedAt: nowStamp(),
        inProgress: false,
        updatedAt: nowStamp(),
      ),
    );

    final next = t.nextOccurrence();
    if (next != null) await _store.putTask(next);

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

  /// Capture a todo straight into a block of time.
  ///
  /// The workspace comes from the *block's* calendar rather than from whatever
  /// list happens to be on screen: a session can be running on a calendar you
  /// are not currently looking at, and a todo written into that block belongs
  /// with the rest of that workspace's work. A standalone calendar has no
  /// workspace, so there the current one is the only sensible answer - the same
  /// guess [plannableTasks] makes.
  Future<void> addTaskForEvent(CalendarEvent e, String text) async {
    final ws = workspaceForEvent(e) ?? currentWorkspaceUuid;
    if (ws == null || text.trim().isEmpty) return;
    await _store.putTask(
      Task(
        uuid: newId(),
        workspaceUuid: ws,
        text: text.trim(),
        createdAt: nowStamp(),
        sortOrder: await _store.nextSortOrder(ws),
        eventUuid: e.uuid,
        updatedAt: nowStamp(),
      ),
    );
    await refreshTasks();
    _mutated();
  }

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

  void _closeOtherViews({
    bool keepHistory = false,
    bool keepThoughts = false,
    bool keepParked = false,
    bool keepJournal = false,
    bool keepSession = false,
  }) {
    showHistory = keepHistory;
    showThoughts = keepThoughts;
    showParked = keepParked;
    showJournal = keepJournal;
    showSession = keepSession;
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

  /// Back onto the current list, at the bottom rather than wherever its old
  /// sort_order happens to land it.
  Future<void> unparkTask(Task t) async {
    final ws = t.workspaceUuid;
    await _store.putTask(
      t.copyWith(
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
    for (final t in tasks) {
      await _store.putTask(
        t.copyWith(clearGroup: true, sortOrder: order++, updatedAt: stamp),
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
    for (final t in await _store.allTasksInGroup(g.uuid)) {
      await _store.putTask(t.copyWith(clearGroup: true, updatedAt: stamp));
    }
    await _store.putGroup(g.copyWith(deletedAt: stamp, updatedAt: stamp));
    await refreshTasks();
    _mutated();
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
  Future<JournalItem?> addJournalEntry(String title, String body) async {
    final ws = currentWorkspaceUuid;
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

  /// Turn the mode on for one calendar, or off with null.
  ///
  /// Device-local like the other calendar prefs: which calendar you are filling
  /// in right now is about this sitting, not about the account.
  Future<void> setTimeBlockCalendar(String? uuid) async {
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
    final (from, to) = calendarRange;
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
      _closeOtherViews();
      await loadCalendarPrefs();
      await refreshCalendars();
    }
    notifyListeners();
  }

  Future<void> setCalendarMode(CalendarViewMode mode) async {
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
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;
    // A backwards drag, or a click that never moved. Either way the block needs
    // a positive length or it cannot be drawn, let alone grabbed again.
    final from = start.isBefore(end) ? start : end;
    var to = start.isBefore(end) ? end : start;
    if (!to.isAfter(from)) to = from.add(const Duration(minutes: 15));

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
            updatedAt: stamp,
          );

    await _store.putEvent(row);
    await refreshEvents();
    await _rescheduleNotifications();
    _mutated();
    return row;
  }

  /// Add events read out of an .ics file to [calendarUuid].
  ///
  /// Goes through [saveEvent] rather than writing rows directly, so an imported
  /// block is an ordinary event in every respect - same validation, same
  /// notification reschedule, same sync. There is deliberately no "imported"
  /// flag: a block that behaved differently from one you dragged would be a
  /// second kind of event to reason about for no gain.
  ///
  /// The description carries the location and a note when the source was
  /// recurring, because only the first occurrence comes across and silently
  /// importing one of a series is the kind of thing that is discovered late.
  Future<int> importIcsEvents(
    List<IcsEvent> events, {
    required String calendarUuid,
  }) async {
    var added = 0;
    for (final e in events) {
      final notes = [
        if (e.location.isNotEmpty) e.location,
        if (e.description.isNotEmpty) e.description,
        if (e.recurring) 'Repeats — only this occurrence was imported.',
      ].join('\n\n');

      final row = await saveEvent(
        calendarUuid: calendarUuid,
        title: e.summary,
        description: notes,
        start: e.start,
        end: e.end,
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

  // ---------------------------------------------------------------- tint

  Color get workspaceColor {
    final ws = currentWorkspace;
    return ws == null ? T.accent : T.parseHex(ws.color);
  }
}
