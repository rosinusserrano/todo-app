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
import 'sync/local_store.dart';
import 'sync/models.dart';
import 'theme.dart';

const _kLastWorkspace = 'ui:last-workspace';
const _kNudge = 'ui:nudge-enabled';

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
    // Every task mutation and every merge from sync lands here, which makes
    // this the one place the OS schedule can be kept honest.
    await _rescheduleNotifications();
    notifyListeners();
  }

  Future<void> _rescheduleNotifications() async {
    final n = notifications;
    if (n == null) return;
    await n.reschedule(await _store.pendingReminders());
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
  }) {
    showHistory = keepHistory;
    showThoughts = keepThoughts;
    showParked = keepParked;
    showJournal = keepJournal;
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
    await _store.putTask(t.copyWith(
      groupUuid: groupUuid,
      inProgress: false,
      updatedAt: nowStamp(),
    ));
    if (focusTask?.uuid == t.uuid) focusTask = null;
    await refreshTasks();
    _mutated();
  }

  /// Back onto the current list, at the bottom rather than wherever its old
  /// sort_order happens to land it.
  Future<void> unparkTask(Task t) async {
    final ws = t.workspaceUuid;
    await _store.putTask(t.copyWith(
      clearGroup: true,
      sortOrder: await _store.nextSortOrder(ws),
      updatedAt: nowStamp(),
    ));
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
      await _store.putJournal(e.copyWith(
        title: await c.encrypt(e.title),
        text: await c.encrypt(e.text),
        encrypted: true,
        updatedAt: nowStamp(),
      ));
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
        await _store.putJournal(e.copyWith(
          title: e.title.isEmpty ? '' : await c.decrypt(e.title),
          text: await c.decrypt(e.text),
          encrypted: false,
          updatedAt: nowStamp(),
        ));
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
          items.add(JournalItem(
            entry: e,
            title: e.title.isEmpty ? '' : await c.decrypt(e.title),
            body: await c.decrypt(e.text),
          ));
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
  Future<void> addJournalEntry(String title, String body) async {
    final ws = currentWorkspaceUuid;
    if (ws == null || journalLocked) return;
    if (title.trim().isEmpty && body.trim().isEmpty) return;
    final (t, b, enc) = await _encodeFields(title.trim(), body.trim());
    final now = nowStamp();
    await _store.putJournal(JournalEntry(
      uuid: newId(),
      workspaceUuid: ws,
      title: t,
      text: b,
      encrypted: enc,
      createdAt: now,
      updatedAt: now,
    ));
    await refreshJournal();
    _mutated();
  }

  /// Rewrite an entry. Its [JournalEntry.createdAt] stays put - the log records
  /// when the thing was written, not when it was later edited. Clearing both
  /// fields deletes it. A locked entry cannot be edited (it cannot be read).
  Future<void> editJournalEntry(JournalItem item, String title, String body) async {
    if (item.locked || journalLocked) return;
    if (title.trim().isEmpty && body.trim().isEmpty) {
      await deleteJournalEntry(item);
      return;
    }
    final (t, b, enc) = await _encodeFields(title.trim(), body.trim());
    await _store.putJournal(item.entry.copyWith(
      title: t,
      text: b,
      encrypted: enc,
      updatedAt: nowStamp(),
    ));
    await refreshJournal();
    _mutated();
  }

  /// Encrypt the two fields when the vault is open, or hand them back plaintext.
  /// Returns the stored title, stored body, and whether they are ciphertext.
  Future<(String, String, bool)> _encodeFields(String title, String body) async {
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

  // ---------------------------------------------------------------- tint

  Color get workspaceColor {
    final ws = currentWorkspace;
    return ws == null ? T.accent : T.parseHex(ws.color);
  }
}
