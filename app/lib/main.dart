// Todo Widget - Flutter client.
//
// Ported from the Tauri build (src/main.ts + src/styles.css). The window
// behaviour is the part that is not allowed to regress on Windows: frameless,
// transparent, acrylic, and always on top *while unfocused*.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:media_kit/media_kit.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'journal_crypto.dart';
import 'layout.dart';
import 'notifications.dart';
import 'quick_actions.dart';
import 'reminders.dart';
import 'shortcuts.dart';
import 'sound/sound_service.dart';
import 'sound/taskbar_transport.dart';
import 'startup.dart';
import 'sync/attachment_store.dart';
import 'sync/legacy_import.dart';
import 'sync/local_store.dart';
import 'sync/models.dart';
import 'sync/sync_service.dart';
import 'theme.dart';
import 'tray.dart';
import 'ui/attachment_sheet.dart';
import 'ui/calendar/calendar_form.dart';
import 'ui/calendar/calendar_view.dart';
import 'ui/calendar/event_details.dart';
import 'ui/calendar/event_editor.dart';
import 'ui/calendar/time_grid.dart' show hhmm;
import 'ui/footer.dart';
import 'ui/journal_panel.dart';
import 'ui/panel_header.dart';
import 'ui/parked_panel.dart';
import 'ui/session_view.dart';
import 'ui/settings_sheet.dart';
import 'ui/sound_sheet.dart';
import 'ui/task_composer.dart';
import 'ui/sublist_sheet.dart';
import 'ui/task_row.dart';
import 'ui/title_bar.dart';
import 'ui/workspace_bar.dart';
import 'ui/workspace_rail.dart';

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Must run before any Player is constructed.
  MediaKit.ensureInitialized();

  if (isDesktop) {
    await acrylic.Window.initialize();
    await windowManager.ensureInitialized();

    const options = WindowOptions(
      size: Size(340, 480),
      minimumSize: Size(260, 200),
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      title: 'Todo Widget',
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setHasShadow(true);
      // The close guard needs every close path to route through our handler,
      // including Alt+F4 and the OS close - not just our own button.
      await windowManager.setPreventClose(true);
      await windowManager.show();
    });

    await acrylic.Window.setEffect(
      effect: acrylic.WindowEffect.acrylic,
      dark: true,
    );
  }

  final store = await LocalStore.open();

  // Before the first read, so the Tauri-era history is already there when the
  // UI paints rather than appearing a frame later. It is a no-op on every
  // launch after the first.
  debugPrint((await LegacyImport.run(store)).toString());

  // Before AppState, which hands it the armed reminders on every task refresh -
  // including the one inside load() below, so the schedule is correct from the
  // first frame rather than from the first edit.
  final notifications = NotificationService();
  await notifications.init();

  final blobs = await AttachmentStore.open();

  // Reads whether a journal password has been set, so the panel opens straight
  // to "unlock" rather than "set one" on a device that already has a vault.
  final journalCrypto = JournalCrypto(store);
  await journalCrypto.load();

  final state = AppState(
    store,
    notifications: notifications,
    blobs: blobs,
    journalCrypto: journalCrypto,
  );
  await state.load();

  // Bytes whose row was tombstoned on another device arrive here as a merge,
  // never as a local delete, so this is the only thing that ever collects them.
  // Not awaited: it is a directory listing, and nothing on screen depends on it.
  state.sweepAttachments();

  // Sync pulls the UI, not the other way round: a merge that brings rows in
  // has to refresh whatever is on screen, or the user sees stale lists until
  // they happen to switch workspace.
  final sync = SyncService(
    store,
    onChangesApplied: () async {
      await state.refreshWorkspaces();
      await state.refreshTasks();
      await state.refreshThoughts();
      // A journal entry merged in from another device should appear if the
      // journal is on screen; refreshJournal clears to empty when it is locked.
      if (state.showJournal) await state.refreshJournal();
    },
  );
  state.onMutated = sync.scheduleSync;
  await sync.load();

  final sound = SoundService(store);
  await sound.load();

  runApp(TodoApp(
    state: state,
    sync: sync,
    sound: sound,
    notifications: notifications,
  ));
}

class TodoApp extends StatelessWidget {
  const TodoApp({
    super.key,
    required this.state,
    required this.sync,
    required this.sound,
    required this.notifications,
  });

  final AppState state;
  final SyncService sync;
  final SoundService sound;
  final NotificationService notifications;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: T.themeData(),
      // Above the Navigator, so dialogs and menus are scaled with everything
      // else rather than staying desktop-sized on top of a zoomed widget.
      builder: (context, child) => UiScale(
        scale: isDesktop ? 1.0 : T.mobileScale,
        child: child ?? const SizedBox.shrink(),
      ),
      home: WidgetShell(
        state: state,
        sync: sync,
        sound: sound,
        notifications: notifications,
      ),
    );
  }
}

/// Which stage of the focus transition we are in. The flight and the resting
/// state are distinct because the tile is absolutely positioned mid-flight and
/// handed back to normal layout once it lands.
enum _Focus { none, flyingIn, resting, flyingOut }

class WidgetShell extends StatefulWidget {
  const WidgetShell({
    super.key,
    required this.state,
    required this.sync,
    required this.sound,
    required this.notifications,
  });

  final AppState state;
  final SyncService sync;
  final SoundService sound;
  final NotificationService notifications;

  @override
  State<WidgetShell> createState() => _WidgetShellState();
}

class _WidgetShellState extends State<WidgetShell>
    with
        TickerProviderStateMixin,
        WindowListener,
        TrayListener,
        WidgetsBindingObserver {
  AppState get s => widget.state;

  final _addController = TextEditingController();
  final _addFocus = FocusNode();
  final _stackKey = GlobalKey();
  final _footerKey = GlobalKey<ThoughtFooterState>();

  /// Focus mode's own side-thought field. The footer's is behind the overlay,
  /// and capturing a thought must not cost you the task you are focused on.
  final _focusThoughtController = TextEditingController();
  final _focusThoughtFocus = FocusNode();
  bool _focusThoughtOpen = false;

  bool _soundOpen = false;

  /// Settings is a sheet in this Stack, not a dialog route: a route's modal
  /// barrier covers the title bar, and the title bar is how the window is
  /// dragged. See settings_sheet.dart.
  bool _settingsOpen = false;

  /// The block whose sublist is open, and what that sheet is showing. Loaded
  /// rather than read off [AppState.sessionTasks]: the sheet is also reachable
  /// from a block that is not running, where there is no session to read.
  CalendarEvent? _sublist;
  List<Task> _sublistPlanned = [];
  List<Task> _sublistCandidates = [];

  /// One key per visible row, so a row can be measured for the hero flight.
  final _rowKeys = <String, GlobalKey>{};

  late final AnimationController _hero = AnimationController(
    vsync: this,
    duration: T.heroDur,
  );

  late final GlobalShortcuts _shortcuts = GlobalShortcuts(
    onAddTask: _jumpToAddTask,
    onAddThought: _jumpToAddThought,
  );

  /// The phone's equivalent of the global shortcuts: the same two capture
  /// paths, reached by long-pressing the app icon.
  late final AppQuickActions _quickActions = AppQuickActions(
    onAddTask: _jumpToAddTask,
    onAddThought: _jumpToAddThought,
  );

  late final AppTray _tray = AppTray(
    onShow: _surfaceWindow,
    onHide: _hideToTray,
    onAddTask: _jumpToAddTask,
    // Not destroy(): the close guard decides whether the app may go.
    onQuit: () async => windowManager.close(),
  );

  final _startup = StartupSetting();

  late final ReminderService _reminders = ReminderService(
    s.store,
    onDue: _onRemindersDue,
    // A block starting writes nothing, so only the clock can notice it.
    onTick: s.refreshSessions,
  );

  _Focus _phase = _Focus.none;
  Rect? _fromRect;
  Rect? _toRect;
  String? _blockedMessage;
  bool _pinned = true;

  /// The close was accepted and teardown is running. Tearing the window down
  /// is not instant - see [_closeNow] - and without this the widget just sat
  /// there looking alive and ignoring the ✕, which reads as a hang.
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    s.addListener(_onState);
    widget.sync.addListener(_onState);
    widget.sound.addListener(_onState);
    WidgetsBinding.instance.addObserver(this);
    if (isDesktop) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _tray.install();
      _startup.init();
      _taskbar.start();
    }
    // A task left in progress at last close reopens straight into focus, with
    // no flight - there is no row for it to have flown from.
    if (s.focusTask != null) _phase = _Focus.resting;
    _registerShortcuts();
    _quickActions.install();
    widget.notifications.onTapped = _openTappedReminder;
    widget.notifications.onEventTapped = _openTappedEvent;
    // Sweep once before polling starts, so anything that came due while the app
    // was closed lands now rather than up to an interval later.
    _reminders.tick();
    _reminders.start();
  }

  /// Coming back from the background.
  ///
  /// A suspended phone runs neither the sync poll nor the reminder sweep, so
  /// both are nudged here rather than left to fire up to an interval late.
  /// Sync also picks up anything a *peer* wrote while this device was away,
  /// which is the half of it the user never sees happen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    super.didChangeAppLifecycleState(lifecycle);
    if (lifecycle != AppLifecycleState.resumed) return;
    widget.sync.resume();
    _reminders.tick();
  }

  // --------------------------------------------------------------- calendar

  /// Opening the calendar **does not touch the window.**
  ///
  /// It used to grow it to 920x640 and centre it, because a week grid at 340px
  /// gives each day 43 unusable pixels. That fixed the grid by moving the
  /// window: a widget deliberately pinned to a corner jumped to the middle of
  /// the screen at a size nobody had asked for, and closing the calendar was
  /// the only way to get it back.
  ///
  /// The views adapt to the window instead - see [Layout], the agenda fallback
  /// in the week view and the reflowing year. If you want the big grid, make
  /// the window big; it stays big.
  Future<void> _toggleCalendar() async {
    // The calendar covers the add field and the footer, so anything focused
    // behind it has to let go first - the same reason the other views do this.
    if (s.focusTask != null) _exitFocus();
    _closeSound();
    _closeSettings();
    _closeSublist();
    await s.toggleCalendar();
  }

  // ---------------------------------------------------------- block sublists

  /// Open the list belonging to one block of time.
  ///
  /// Switches to the block's workspace on the way in. A block names a workspace
  /// through its calendar, and writing that block's todos while looking at some
  /// other workspace's list is how a todo ends up in the wrong one - the tasks
  /// the sheet offers to plan in are that workspace's, so the list underneath
  /// has to be the same list.
  Future<void> _openSublist(CalendarEvent e) async {
    _closeSound();
    _closeSettings();
    if (s.focusTask != null) await _exitFocus();
    if (!mounted) return;

    final ws = s.workspaceForEvent(e);
    if (ws != null && ws != s.currentWorkspaceUuid) {
      await s.selectWorkspace(ws);
      if (!mounted) return;
    }

    setState(() => _sublist = e);
    await _loadSublist();
  }

  /// Reload what the sheet shows. Called after every write from it rather than
  /// leaning on the state's notify, because the sheet's two lists are a
  /// different question than "what is on the current list".
  Future<void> _loadSublist() async {
    final e = _sublist;
    if (e == null) return;
    final planned = await s.tasksForEvent(e.uuid);
    final candidates = await s.plannableTasks(e);
    // A second sheet may have been opened while these were in flight.
    if (!mounted || _sublist?.uuid != e.uuid) return;
    setState(() {
      _sublistPlanned = planned;
      _sublistCandidates = candidates;
    });
  }

  void _closeSublist() {
    if (_sublist == null) return;
    setState(() {
      _sublist = null;
      _sublistPlanned = [];
      _sublistCandidates = [];
    });
  }

  /// The line under a block's title, wherever one is shown on its own: whose
  /// calendar it is and when it runs.
  String _describeEvent(CalendarEvent e) => [
        if (_calendarNameForEvent(e).isNotEmpty) _calendarNameForEvent(e),
        '${hhmm(e.start)}–${hhmm(e.end)}',
      ].join(' · ');

  Future<void> _createEvent(DateTime start, DateTime end) async {
    final calendars = s.visibleCalendars;
    if (calendars.isEmpty) return;

    // Time-block mode: the calendar was picked once on the strip, so the drag
    // is the whole gesture and the block is titled after it. Laying out a week
    // is the same event twenty times over, and an editor between each of them
    // is twenty dismissals. Anything a block needs beyond a span - a note, a
    // reminder, a different name - is one tap on the block afterwards.
    final block = s.timeBlockCalendar;
    if (block != null) {
      await s.saveEvent(
        calendarUuid: block.uuid,
        title: s.calendarName(block),
        start: start,
        end: end,
      );
      return;
    }

    // The current workspace's calendar if it is on screen, otherwise whatever
    // is - a drag has to land somewhere, and the workspace you are in is the
    // best guess about where.
    final preferred = calendars.firstWhere(
      (c) => c.workspaceUuid == s.currentWorkspaceUuid,
      orElse: () => calendars.first,
    );

    final edit = await showEventForm(
      context,
      calendars: calendars,
      nameFor: s.calendarName,
      colorFor: s.calendarColor,
      initialCalendarUuid: preferred.uuid,
      initialStart: start,
      initialEnd: end,
    );
    if (edit == null || edit.delete) return;

    await s.saveEvent(
      calendarUuid: edit.calendarUuid,
      title: edit.title,
      description: edit.description,
      start: edit.start!,
      end: edit.end!,
      notifyMinutes: edit.notifyMinutes,
    );
  }

  /// A plain click on a block: read it, and choose from there.
  ///
  /// This used to open the edit form outright, which answered the rarer of the
  /// two reasons for clicking - most clicks are asking when it ends, what is in
  /// it, whether the file is on it - and put a form full of live fields one
  /// stray keystroke from changing something nobody meant to touch.
  Future<void> _openEvent(CalendarEvent event) async {
    final action = await showEventDetails(
      context,
      event: event,
      calendarName: _calendarNameForEvent(event),
      color: s.colorForEvent(event),
      loadTasks: () => s.tasksForEvent(event.uuid),
      loadAttachments: () => s.eventAttachments(event),
    );
    if (action == null || !mounted) return;
    await _runEventAction(event, action);
  }

  /// Right-click, or long-press on a phone. The same three things the details
  /// card offers, without having to open it first - which is the whole point of
  /// a context menu: it is for when you already know what you want to do.
  Future<void> _eventMenu(CalendarEvent event, Offset at) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final action = await showMenu<EventAction?>(
      context: context,
      color: T.bgSolid,
      position: RelativeRect.fromLTRB(
        at.dx,
        at.dy,
        overlay.size.width - at.dx,
        overlay.size.height - at.dy,
      ),
      items: [
        PopupMenuItem(
          value: null,
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 15, color: T.muted),
              const SizedBox(width: 9),
              Text(
                event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: T.muted),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        _menuItem(EventAction.edit, Icons.edit_outlined, 'Edit'),
        _menuItem(EventAction.plan, Icons.playlist_add_rounded, 'Todos…'),
        _menuItem(EventAction.delete, Icons.delete_outline, 'Delete',
            color: T.danger),
      ],
    );
    if (action == null || !mounted) return;
    await _runEventAction(event, action);
  }

  PopupMenuItem<EventAction?> _menuItem(
    EventAction action,
    IconData icon,
    String label, {
    Color color = T.text,
  }) {
    return PopupMenuItem<EventAction?>(
      value: action,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 15, color: color == T.text ? T.muted : color),
          const SizedBox(width: 9),
          Text(label, style: TextStyle(fontSize: 12.5, color: color)),
        ],
      ),
    );
  }

  Future<void> _runEventAction(CalendarEvent event, EventAction action) async {
    switch (action) {
      case EventAction.edit:
        await _editEvent(event);
      case EventAction.plan:
        await _openSublist(event);
      case EventAction.delete:
        await s.deleteEvent(event);
    }
  }

  Future<void> _editEvent(CalendarEvent event) async {
    final calendars = s.calendars;
    if (calendars.isEmpty) return;

    final edit = await showEventForm(
      context,
      existing: event,
      calendars: calendars,
      nameFor: s.calendarName,
      colorFor: s.calendarColor,
      initialCalendarUuid: event.calendarUuid,
      initialStart: event.start,
      initialEnd: event.end,
      loadAttachments: () => s.eventAttachments(event),
      onAddAttachment: (file) => s.attachFileToEvent(event, file),
      onRemoveAttachment: s.removeEventAttachment,
      loadTasks: () => s.plannableTasks(event),
      onPlanTask: (task, on) => s.setTaskEvent(task, on ? event.uuid : null),
    );
    if (edit == null) return;

    if (edit.delete) {
      await s.deleteEvent(event);
      return;
    }
    await s.saveEvent(
      existing: event,
      calendarUuid: edit.calendarUuid,
      title: edit.title,
      description: edit.description,
      start: edit.start!,
      end: edit.end!,
      notifyMinutes: edit.notifyMinutes,
      // copyWith cannot tell "leave it alone" from "set it back to inherit",
      // so the form's null has to be passed as an explicit clear.
      clearNotify: edit.notifyMinutes == null,
    );
  }

  Future<void> _editCalendar(Calendar? existing) async {
    final edit = await showCalendarForm(context, existing: existing);
    if (edit == null) return;

    if (edit.delete) {
      if (existing != null) await s.deleteCalendar(existing);
      return;
    }
    await s.saveCalendar(
      existing: existing,
      name: edit.name,
      color: edit.color,
      notifyMinutes: edit.notifyMinutes,
    );
  }

  /// A calendar notification was tapped. Same shape as the reminder path: the
  /// OS has already surfaced the app, so what is left is landing on the thing
  /// it was about.
  Future<void> _openTappedEvent(String eventUuid) async {
    final event = await s.store.eventByUuid(eventUuid);
    if (event == null || !mounted) return;
    if (!s.showCalendar) await _toggleCalendar();
    await s.setCalendarAnchor(event.start);
    if (!mounted) return;
    await _openEvent(event);
  }

  /// A reminder notification was tapped. The OS has already brought the app
  /// forward; what is left is landing on the task it was about, which is the
  /// same job [_onRemindersDue] does for an in-app firing.
  Future<void> _openTappedReminder(String taskUuid) async {
    final task = await s.store.taskByUuid(taskUuid);
    if (task == null || !mounted) return;
    await _onRemindersDue([task]);
  }

  // --------------------------------------------------------------- reminders

  /// A reminder has come due. The widget's whole personality is being in front
  /// of you, so that is the alert: surface the window, switch to where the task
  /// actually lives, and let the row's own due styling carry it from there.
  Future<void> _onRemindersDue(List<Task> due) async {
    await _surfaceWindow();
    if (!mounted) return;

    final first = due.first;
    // A reminder can belong to a workspace that is not on screen. Showing the
    // window without switching would surface a list the task is not even in.
    if (first.workspaceUuid != s.currentWorkspaceUuid) {
      await s.selectWorkspace(first.workspaceUuid);
    }
    if (!mounted) return;
    if (s.showHistory) s.toggleHistory();
    // Focus mode hides the list, so a due reminder would be invisible behind it.
    if (s.focusTask != null && s.focusTask!.uuid != first.uuid) {
      await _exitFocus();
    }
  }

  // -------------------------------------------------------------------- tray

  /// Bring the window back from hidden, minimised or simply buried.
  Future<void> _surfaceWindow() async {
    if (!isDesktop) return;
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
    _taskbar.refresh();
  }

  /// The taskbar toolbar cannot be set while the window is hidden - Windows
  /// drops the call - and this app spends much of its life in the tray. Both
  /// ways back have to re-apply it: this one covers an OS-driven restore
  /// (clicking the taskbar button), [_surfaceWindow] covers ours.
  @override
  void onWindowRestore() => _taskbar.refresh();

  /// Hide rather than minimise: the tray icon is now the way back, so the
  /// widget can leave the taskbar entirely.
  Future<void> _hideToTray() async {
    if (isDesktop) await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => _surfaceWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) => _tray.handleMenuItem(menuItem);

  Future<void> _registerShortcuts() async {
    final failed = await _shortcuts.register();
    if (!mounted || failed.isEmpty) return;
    // Another app already owns the combination. Say so rather than leaving a
    // shortcut that silently does nothing.
    setState(() => _blockedMessage = '${failed.join(' / ')} unavailable');
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _blockedMessage = null);
    });
  }

  /// Raise the window, clear whatever is covering the capture fields, and hand
  /// back control to the caller so it can put the caret where it wants it.
  Future<bool> _surfaceForCapture({required bool leaveFocus}) async {
    await _surfaceWindow();
    if (!mounted) return false;
    _closeSound();
    _closeSettings();
    _closeSublist();
    if (leaveFocus && s.focusTask != null) await _exitFocus();
    return mounted;
  }

  /// The add field sits behind the focus overlay, so this one has to leave it.
  Future<void> _jumpToAddTask() async {
    if (!await _surfaceForCapture(leaveFocus: true)) return;
    // Land on the task list, not on whichever view was covering it.
    if (s.showHistory) s.toggleHistory();
    if (s.showThoughts) s.toggleThoughts();
    if (s.showParked) s.toggleParked();
    if (s.showJournal) s.toggleJournal();
    _addFocus.requestFocus();
  }

  /// Thoughts are capturable from both sides now, so this keeps focus mode
  /// intact and uses whichever field is actually on screen.
  Future<void> _jumpToAddThought() async {
    if (!await _surfaceForCapture(leaveFocus: false)) return;
    if (s.focusTask != null) {
      _openFocusThought();
      return;
    }
    _footerKey.currentState?.openAndFocus();
  }

  // ------------------------------------------------- side thoughts in focus

  void _openFocusThought() {
    setState(() => _focusThoughtOpen = true);
    _focusThoughtFocus.requestFocus();
  }

  void _closeFocusThought() {
    _focusThoughtController.clear();
    if (_focusThoughtOpen) setState(() => _focusThoughtOpen = false);
  }

  Future<void> _submitFocusThought() async {
    // Ctrl+Enter chains another entry, plain Enter collapses the field — the
    // same convention as the footer and the add field.
    final chain = HardwareKeyboard.instance.isControlPressed;
    final text = _focusThoughtController.text.trim();
    _focusThoughtController.clear();
    if (text.isEmpty) {
      _closeFocusThought();
      return;
    }
    await s.addThought(text);
    if (!mounted) return;
    if (chain) {
      _focusThoughtFocus.requestFocus();
    } else {
      _closeFocusThought();
    }
  }

  // ------------------------------------------------------------------ sound

  /// Pause/resume from the taskbar thumbnail, so the sound can be silenced
  /// without hunting down the window first. Windows-only and self-disabling
  /// elsewhere.
  late final _taskbar = TaskbarTransport(widget.sound);

  /// Closes the sublist first: it is added to the shell's `Stack` *after* this
  /// sheet, so opening one behind it would leave ♪ toggling a panel nobody can
  /// see - and the Esc ladder, which checks [_soundOpen] first, would then
  /// spend a press closing it.
  void _toggleSound() {
    _closeSublist();
    setState(() => _soundOpen = !_soundOpen);
  }

  void _closeSound() {
    if (_soundOpen) setState(() => _soundOpen = false);
  }

  @override
  void dispose() {
    s.removeListener(_onState);
    widget.sync.removeListener(_onState);
    widget.sound.removeListener(_onState);
    WidgetsBinding.instance.removeObserver(this);
    _focusThoughtController.dispose();
    _focusThoughtFocus.dispose();
    _shortcuts.dispose();
    widget.notifications.onTapped = null;
    widget.notifications.onEventTapped = null;
    _reminders.dispose();
    if (isDesktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      _tray.dispose();
      _taskbar.dispose();
    }
    _hero.dispose();
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  void _onState() => setState(() {});

  // ------------------------------------------------------------ close guard

  /// Single gatekeeper for every close path. The window stays open until
  /// pending side thoughts are cleared, forcing them into a real planner first.
  /// Tasks themselves do not block - they persist across restarts.
  @override
  void onWindowClose() async {
    // A second ✕ (or Alt+F4, or the tray's Quit) while teardown is already
    // running would start a second one behind the first.
    if (_closing) return;
    if (await s.canProceedPastThoughts()) {
      await _closeNow();
      return;
    }
    // The refusal has to be visible, or a quit from the tray while the window
    // is hidden looks like the app simply ignoring the click. Surface first,
    // then leave focus - the footer flash sits behind the focus overlay too.
    await _surfaceWindow();
    if (!mounted) return;
    _closeSound();
    _closeSettings();
    _closeSublist();
    if (s.focusTask != null) await _exitFocus();
    if (!mounted) return;
    _flashBlocked();
  }

  /// Actually go, with something on screen while it happens.
  ///
  /// `destroy()` is not instant on Windows - the engine, the acrylic surface
  /// and mpv all come down inside it, and that is dead time the user spends
  /// looking at a widget that has apparently ignored their click. Nothing here
  /// can make the platform teardown quick, so this makes it *legible* instead:
  /// paint the closing state, let that frame reach the screen, then go.
  ///
  /// The player is stopped first, and only when it is actually running: an mpv
  /// instance holding a network stream open is the one part of the teardown
  /// this side can get out of the way in advance. It is bounded, because a
  /// stop that hangs must not be the reason the app cannot quit.
  Future<void> _closeNow() async {
    setState(() => _closing = true);
    await WidgetsBinding.instance.endOfFrame;

    if (widget.sound.isPlaying || widget.sound.isPaused) {
      await widget.sound
          .stop()
          .timeout(const Duration(milliseconds: 600), onTimeout: () {});
    }
    await windowManager.destroy();
  }

  /// Covers everything, title bar included: once the close is accepted there is
  /// nothing left to press, and a live-looking ✕ during teardown invites the
  /// second click [onWindowClose] then has to throw away.
  Widget _closingOverlay(Color ws) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: T.bgSolid.withValues(alpha: 0.72),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.8, color: ws),
              ),
              const SizedBox(width: 9),
              const Text(
                'Closing…',
                style: TextStyle(fontSize: 12, color: T.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _flashBlocked() {
    setState(() => _blockedMessage = 'Clear side thoughts first');
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _blockedMessage = null);
    });
  }

  // ----------------------------------------------------------- focus flight

  /// Geometry of the tile at rest. Computed rather than measured: the layout is
  /// fully determined here, and measuring would need an extra frame with the
  /// tile already mounted, which is what the CSS version had to work around.
  ///
  /// The width comes from [Layout.focusTileWidth] and so does the resting
  /// layout's — if those two disagree the tile visibly jumps sideways the
  /// instant the flight ends, which is why neither computes its own.
  Rect _restingTileRect() {
    const tileHeight = 110.0;
    final size = _layout.size;
    final areaTop = TitleBar.height;
    final areaHeight = size.height - areaTop;
    final width = _layout.focusTileWidth;
    return Rect.fromLTWH(
      (size.width - width) / 2,
      areaTop + (areaHeight - tileHeight) / 2 - 30,
      width,
      tileHeight,
    );
  }

  Rect? _rowRect(String uuid) {
    final key = _rowKeys[uuid];
    final rowBox = key?.currentContext?.findRenderObject() as RenderBox?;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (rowBox == null || stackBox == null || !rowBox.hasSize) return null;
    final offset = rowBox.localToGlobal(Offset.zero, ancestor: stackBox);
    return offset & rowBox.size;
  }

  Future<void> _startFocus(Task t) async {
    final from = _rowRect(t.uuid);
    await s.enterFocus(t);
    if (!mounted) return;

    setState(() {
      _fromRect = from;
      _toRect = _restingTileRect();
      _phase = from == null ? _Focus.resting : _Focus.flyingIn;
    });

    if (from != null) {
      await _hero.forward(from: 0);
      if (mounted) setState(() => _phase = _Focus.resting);
    }
  }

  Future<void> _exitFocus() async {
    final t = s.focusTask;
    if (t == null) return;
    _closeFocusThought();

    final tileRect = _restingTileRect();

    await s.exitFocus();
    if (!mounted) return;

    // The row only exists again after the list rebuilds, so wait a frame
    // before measuring where the tile should land.
    setState(() => _phase = _Focus.flyingOut);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final target = _rowRect(t.uuid);
    if (target == null) {
      // Its row is gone (different workspace, or filtered out). Nothing to fly
      // to, so the tile just disappears.
      setState(() => _phase = _Focus.none);
      return;
    }

    setState(() {
      _fromRect = tileRect;
      _toRect = target;
    });
    await _hero.forward(from: 0);
    if (mounted) setState(() => _phase = _Focus.none);
  }

  /// Checked off from the focus view. No fly-back: the row it would land on is
  /// on its way out too.
  Future<void> _completeFromFocus() async {
    final t = s.focusTask;
    if (t == null) return;
    _closeFocusThought();
    setState(() => _phase = _Focus.none);
    await s.completeTask(t);
  }

  // ------------------------------------------------------------------ build

  bool get _focusVisible => _phase != _Focus.none;

  /// The box the content actually got, republished to the subtree as
  /// [LayoutScope] and kept here for the paths that run outside a build - the
  /// focus flight computes its rects from a callback, not from a builder.
  ///
  /// Measured inside the safe area, so it is the same coordinate space the
  /// hero rects are in. Assigned during build, which is safe: nothing here
  /// notifies, it is a record of what layout just decided.
  Layout _layout = const Layout(Size(T.designWidth, 480));

  @override
  Widget build(BuildContext context) {
    final ws = s.workspaceColor;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          // Esc unwinds one layer at a time: the sound sheet, then the
          // focus-mode thought field, then focus mode itself.
          if (event is! KeyDownEvent ||
              event.logicalKey != LogicalKeyboardKey.escape) {
            return KeyEventResult.ignored;
          }
          if (_settingsOpen) {
            _closeSettings();
          } else if (_soundOpen) {
            _closeSound();
          } else if (_sublist != null) {
            _closeSublist();
          } else if (_focusThoughtOpen) {
            _closeFocusThought();
          } else if (s.focusTask != null) {
            _exitFocus();
          } else if (s.showCalendar) {
            _toggleCalendar();
          } else if (s.showThoughts) {
            s.toggleThoughts();
          } else if (s.showParked) {
            s.toggleParked();
          } else if (s.showJournal) {
            s.toggleJournal();
          } else if (s.showSession) {
            s.toggleSession();
          } else if (s.showHistory) {
            s.toggleHistory();
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: T.tintedBackground(ws),
            borderRadius: BorderRadius.circular(T.radius),
            border: Border.all(color: T.tintedBorder(ws)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(T.radius),
            child: _inset(LayoutBuilder(builder: (context, constraints) {
              _layout = Layout(constraints.biggest);
              return LayoutScope(
                layout: _layout,
                child: _shell(ws),
              );
            })),
          ),
        ),
      ),
    );
  }

  /// Everything inside the window frame. Split out from [build] only so the
  /// [LayoutScope] above it is an ancestor of this whole tree - a descendant
  /// asking [Layout.of] from `build`'s own context would get the fallback.
  Widget _shell(Color ws) {
    return Stack(
      key: _stackKey,
      children: [
        // Panels keep their layout and only fade, which is what lets the tile
        // fly back to the exact row it came from.
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _focusVisible ? 0 : 1,
            duration: T.heroDur,
            child: IgnorePointer(
              ignoring: _focusVisible,
              child: _body(ws),
            ),
          ),
        ),

        if (_phase == _Focus.resting) _focusOverlay(ws),
        if (_phase == _Focus.flyingIn || _phase == _Focus.flyingOut)
          _flyingTile(ws),

        // Above the focus overlay, since picking something to listen to is
        // exactly what you do *after* picking a task.
        if (_soundOpen)
          SoundSheet(
            sound: widget.sound,
            accent: ws,
            onClose: _closeSound,
          ),

        if (_settingsOpen)
          SettingsSheet(
            sync: widget.sync,
            accent: ws,
            onClose: _closeSettings,
            startup: isDesktop && StartupSetting.supported ? _startup : null,
          ),

        // Above the focus overlay for the same reason the sound sheet is: it
        // is opened from the tile that sits over the list, and it is about the
        // block you are in rather than about the task you are on.
        if (_sublist != null)
          SublistSheet(
            event: _sublist!,
            subtitle: _describeEvent(_sublist!),
            color: s.colorForEvent(_sublist!),
            accent: ws,
            planned: _sublistPlanned,
            candidates: _sublistCandidates,
            onAdd: (text) async {
              await s.addTaskForEvent(_sublist!, text);
              await _loadSublist();
            },
            onPlan: (t, into) async {
              await s.setTaskEvent(t, into ? _sublist!.uuid : null);
              await _loadSublist();
            },
            onComplete: (t) async {
              await s.completeTask(t);
              await _loadSublist();
            },
            onClose: _closeSublist,
          ),

        // Above everything, so the window stays draggable and closable during
        // focus mode and with the sheet open.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: TitleBar(
            isDesktop: isDesktop,
            pinned: _pinned,
            onTogglePin: _togglePin,
            onToggleSound: _toggleSound,
            soundPlaying: widget.sound.isPlaying,
            soundPaused: widget.sound.isPaused,
            onTogglePause: widget.sound.togglePause,
            volume: widget.sound.volume,
            onVolumeChanged: widget.sound.setVolume,
            accent: ws,
            onClose: () => isDesktop ? windowManager.close() : null,
            onOpenSettings: _openSettings,
            onToggleCalendar: _toggleCalendar,
            calendarOpen: s.showCalendar,
            syncColor: _syncColor(),
            syncTooltip: widget.sync.describe(),
          ),
        ),

        // Last, so it is over the title bar too - see _closingOverlay.
        if (_closing) _closingOverlay(ws),
      ],
    );
  }

  /// On a phone the widget *is* the screen, so the title bar lands under the
  /// status bar and the side-thought footer under the home indicator. Only the
  /// content is inset - the tinted background still runs edge to edge, which
  /// is what makes it read as one surface rather than a letterboxed window.
  ///
  /// On desktop there is nothing to avoid, and a SafeArea there would add the
  /// window's own insets back into a layout that already accounts for them.
  Widget _inset(Widget child) => isDesktop ? child : SafeArea(child: child);

  Future<void> _togglePin() async {
    await windowManager.setAlwaysOnTop(!_pinned);
    final actual = await windowManager.isAlwaysOnTop();
    setState(() => _pinned = actual);
  }

  /// History sits behind both the sound sheet and the focus overlay, so the
  /// first press just clears whatever is covering it.
  void _toggleHistory() {
    if (_clearOverlays()) return;
    s.toggleHistory();
  }

  void _toggleParked() {
    if (_clearOverlays()) return;
    s.toggleParked();
  }

  void _toggleJournal() {
    if (_clearOverlays()) return;
    s.toggleJournal();
  }

  void _toggleThoughts() {
    if (_clearOverlays()) return;
    s.toggleThoughts();
  }

  void _toggleSession() {
    if (_clearOverlays()) return;
    s.toggleSession();
  }

  /// The tile above the list was pressed.
  ///
  /// Two things happen that a plain toggle would not do. It **switches to the
  /// block's workspace** first, because the tile is the one control in the app
  /// that talks about a workspace other than the one on screen - opening its
  /// todos beside a different workspace's list is how you plan into the wrong
  /// one. And when nothing is planned into the block it deliberately does *not*
  /// open the session view: that view's whole body would be the sentence the
  /// tile just said. The list stays, and the tile's own "Sublist" button is the
  /// way to answer it.
  Future<void> _openSession() async {
    if (_clearOverlays()) return;
    final first = s.liveEvents.isEmpty ? null : s.liveEvents.first;
    if (first == null) return;

    // Nothing planned into the running block: hand over to the sublist, which
    // is what the tile's own Sublist button does and what this feature's answer
    // to "nothing planned" is meant to be.
    //
    // Checked *before* the workspace switch below, and it has to be: the tile
    // body is a full-width tap target while the button covers only its right
    // end, so returning here after switching meant a tap could replace the
    // whole list with another workspace's and then open nothing, with no
    // visible cause and nothing on the tile to undo it. ([sessionTaskList] is
    // derived from the live events, not from the current workspace, so it reads
    // the same either side of the switch.) _openSublist does its own switch.
    if (s.sessionTaskList.isEmpty) return _openSublist(first);

    final ws = s.workspaceForEvent(first);
    if (ws != null && ws != s.currentWorkspaceUuid) {
      await s.selectWorkspace(ws);
      if (!mounted) return;
    }
    s.toggleSession();
  }

  /// The name to print beside a live block. Empty when its calendar is not
  /// known here, which the session view then leaves out of the line rather than
  /// printing a blank field.
  String _calendarNameForEvent(CalendarEvent e) {
    final cal = s.calendarsByUuid[e.calendarUuid];
    return cal == null ? '' : s.calendarName(cal);
  }

  /// Back to the task list from the rail.
  ///
  /// The ▾ menu closes a view by re-picking it, which works because the menu
  /// only ever offers the three; a rail lists Tasks as a destination of its
  /// own, and a destination has to be reachable from any of them. Every branch
  /// is a toggle and at most one view is open, so at most one fires.
  void _showTasks() {
    if (_clearOverlays()) return;
    if (s.showHistory) s.toggleHistory();
    if (s.showThoughts) s.toggleThoughts();
    if (s.showParked) s.toggleParked();
    if (s.showJournal) s.toggleJournal();
    if (s.showSession) s.toggleSession();
  }

  /// Dismisses whatever is covering the content area. Returns true if it did,
  /// meaning the press was spent on getting out of the way rather than on the
  /// view the caller wanted.
  bool _clearOverlays() {
    if (_settingsOpen) {
      _closeSettings();
      return true;
    }
    if (_soundOpen) {
      _closeSound();
      return true;
    }
    if (_sublist != null) {
      _closeSublist();
      return true;
    }
    if (s.focusTask != null) {
      _exitFocus();
      return true;
    }
    return false;
  }

  Future<void> _openSettings() async {
    _closeSound();
    // Same reason as _toggleSound: this sheet is below the sublist in the
    // Stack, so it has to take the sublist down rather than open under it.
    _closeSublist();
    if (s.focusTask != null) await _exitFocus();
    if (!mounted) return;
    setState(() => _settingsOpen = !_settingsOpen);
  }

  void _closeSettings() {
    if (_settingsOpen) setState(() => _settingsOpen = false);
  }

  /// Blocked (bad token/address) is red rather than amber: it will not recover
  /// on its own, so it needs to look different from a server that is merely
  /// asleep.
  Color _syncColor() => switch (widget.sync.status) {
        SyncStatus.off => T.muted,
        SyncStatus.idle => T.muted,
        SyncStatus.syncing => T.accent,
        SyncStatus.ok => const Color(0xFF7EE3A1),
        SyncStatus.error => const Color(0xFFFFCF6C),
        SyncStatus.blocked => T.danger,
      };

  Widget _body(Color ws) {
    // The calendar replaces the whole body, workspace bar and footer included:
    // it spans workspaces, so a workspace tab above it would be saying
    // something the grid underneath does not agree with.
    //
    // Given room for both (Layout.splitsCalendar) it stops replacing anything
    // and opens beside the list instead - which is the one arrangement in which
    // a task can be dragged onto a block, because both ends of that gesture
    // have to be on screen at once.
    if (s.showCalendar) {
      if (_layout.splitsCalendar) return _splitCalendar(ws);
      return Column(
        children: [
          const SizedBox(height: TitleBar.height),
          Expanded(child: _calendar()),
        ],
      );
    }

    // Narrow: the workspace bar across the top, with its two ▾ menus. Wide
    // enough and the same controls unroll into a rail down the left, where the
    // workspace list and the views are on screen instead of behind a press.
    final middle = Column(
      children: [
        if (!_layout.hasRail) _workspaceBar(ws),
        if (s.hasLiveSession && !s.showSession) _sessionBanner(),
        Expanded(child: _contentArea(ws)),
      ],
    );

    return Column(
      children: [
        const SizedBox(height: TitleBar.height),
        Expanded(
          child: _layout.hasRail
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WorkspaceRail(
                      workspaces: s.workspaces,
                      currentUuid: s.currentWorkspaceUuid,
                      accent: ws,
                      onSelect: (w) => _switchWorkspace(w),
                      onEdit: (w) => _editWorkspace(w),
                      onCreate: () => _editWorkspace(null),
                      onShowTasks: _showTasks,
                      onOpenNotes: _toggleJournal,
                      onOpenParked: _toggleParked,
                      onOpenHistory: _toggleHistory,
                      onOpenThoughts: _toggleThoughts,
                      thoughtCount: s.thoughtCount,
                      parkedReviewDue: s.groupsDueForReview.isNotEmpty,
                      openView: _openView,
                    ),
                    Expanded(child: middle),
                  ],
                )
              : middle,
        ),
        _footer(ws),
      ],
    );
  }

  /// Outside the rail and outside the split, spanning the whole width: the
  /// pressure meter is about the pile, not about the workspace - or the view -
  /// you happen to be in.
  Widget _footer(Color ws) => ThoughtFooter(
        key: _footerKey,
        thoughts: s.thoughts,
        workspaceColor: ws,
        blockedMessage: _blockedMessage,
        onAdd: s.addThought,
        listOpen: s.showThoughts,
        onToggleList: s.toggleThoughts,
      );

  Widget _workspaceBar(Color ws) => WorkspaceBar(
        workspaces: s.workspaces,
        currentUuid: s.currentWorkspaceUuid,
        accent: ws,
        onSelect: (w) => _switchWorkspace(w),
        onEdit: (w) => _editWorkspace(w),
        onCreate: () => _editWorkspace(null),
        onOpenNotes: _toggleJournal,
        onOpenParked: _toggleParked,
        onOpenHistory: _toggleHistory,
        parkedReviewDue: s.groupsDueForReview.isNotEmpty,
        // The menu holds three of the four, and lighting its ▾ for a view it
        // does not contain would point at the wrong control.
        openView: _openView == WorkspaceView.thoughts ? null : _openView,
      );

  /// The calendar, wherever it is drawn.
  ///
  /// It publishes its **own** [LayoutScope]: beside the list it gets a fraction
  /// of the window, and every question the views ask about whether they fit -
  /// the week grid's fallback to the agenda, the year's column count - has to
  /// be about the box the calendar actually got, not about the window.
  Widget _calendar() {
    return LayoutBuilder(
      builder: (context, constraints) => LayoutScope(
        layout: Layout(constraints.biggest),
        child: CalendarView(
          state: s,
          onClose: _toggleCalendar,
          onOpenEvent: _openEvent,
          onEventMenu: _eventMenu,
          onCreate: _createEvent,
          onNewCalendar: () => _editCalendar(null),
          onEditCalendar: (c) => _editCalendar(c),
          // Only where there is a list beside it to drag out of.
          onPlanTask: _layout.splitsCalendar
              ? (event, task) => s.setTaskEvent(task, event.uuid)
              : null,
        ),
      ),
    );
  }

  /// The calendar and the list, side by side.
  ///
  /// The workspace bar goes *inside* the left pane rather than across the top,
  /// which is the honest place for it here: it names the workspace whose list
  /// that pane is showing, and the calendar beside it can be showing every
  /// workspace at once. The rail is deliberately not used even when the window
  /// is wide enough for one - rail plus pane plus a legible grid needs a metre
  /// of desk, and the bar is the same navigation with the popups on.
  ///
  /// The footer still spans both, because the pile of side thoughts is neither
  /// half's business.
  Widget _splitCalendar(Color ws) {
    return Column(
      children: [
        const SizedBox(height: TitleBar.height),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: Layout.calendarTaskPaneWidth,
                child: LayoutBuilder(
                  builder: (context, constraints) => LayoutScope(
                    layout: Layout(constraints.biggest),
                    child: Column(
                      children: [
                        _workspaceBar(ws),
                        if (s.hasLiveSession && !s.showSession)
                          _sessionBanner(),
                        Expanded(child: _stackedContent(ws)),
                      ],
                    ),
                  ),
                ),
              ),
              const VerticalDivider(
                  width: 1, thickness: 1, color: Color(0x14FFFFFF)),
              Expanded(child: _calendar()),
            ],
          ),
        ),
        _footer(ws),
      ],
    );
  }

  /// The way into the session view, and the only one.
  ///
  /// There is no permanent button for "Now" because for most of the day there
  /// is no answer: the block you are in is a thing that comes and goes, so the
  /// entry point comes and goes with it. It sits above the content area rather
  /// than in the title bar because it is about the list underneath it - and it
  /// deliberately says what is running and what is left on it, so that a glance
  /// is often enough and the view is only opened when it is not.
  ///
  /// The time it prints is the block's end, not a countdown: this rebuilds only
  /// when the live blocks or their todos change (see AppState.refreshSessions),
  /// and a minutes-remaining figure here would sit there going stale. The
  /// countdown lives inside the view, which does rebuild on every poll.
  Widget _sessionBanner() {
    final first = s.liveEvents.first;
    final left = s.sessionTaskList.length;
    final more = s.liveEvents.length - 1;
    final color = s.colorForEvent(first);

    return Padding(
      // The gap above belongs to the banner, not to the workspace bar: the bar
      // is drawn on every screen and this is not, so padding on the bar would
      // be a hole in the layout whenever no block is running. At phone width
      // the tab and the tile are otherwise touching.
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
      child: Material(
        color: Color.lerp(T.bgSolid, color, 0.22),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: _openSession,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        more > 0
                            ? '${first.title}  +$more more'
                            : first.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: T.text,
                        ),
                      ),
                      Text(
                        'until ${hhmm(first.end)} · '
                        '${left == 0 ? 'nothing planned' : '$left to do'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: T.muted),
                      ),
                    ],
                  ),
                ),
                // With something planned, the tile is a way in to that list.
                // With nothing planned there is no list yet, so the tile offers
                // to start one instead of pointing at an empty view.
                if (left == 0)
                  _SublistButton(
                    color: color,
                    onTap: () => _openSublist(first),
                  )
                else
                  const Icon(Icons.chevron_right, size: 16, color: T.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Which view owns the content area, for whichever navigation is on screen.
  WorkspaceView? get _openView => s.showJournal
      ? WorkspaceView.notes
      : s.showParked
          ? WorkspaceView.parked
          : s.showHistory
              ? WorkspaceView.history
              : s.showThoughts
                  ? WorkspaceView.thoughts
                  : null;

  /// The content area.
  ///
  /// In a 340px window it holds exactly one view: Notes, Parked, History and
  /// Thoughts *replace* the task list rather than stacking on top of it, which
  /// is what keeps the widget legible. Given [Layout.splitMinWidth] they stop
  /// replacing it and open beside it instead - the same views, no longer a
  /// trade against seeing what you are meant to be doing.
  Widget _contentArea(Color ws) {
    final secondary = _secondaryView(ws);
    if (secondary == null) return _taskColumn(ws);

    if (!_layout.splitsContent) return _stackedContent(ws);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: _taskColumn(ws)),
        const VerticalDivider(width: 1, thickness: 1, color: Color(0x14FFFFFF)),
        Expanded(flex: 4, child: secondary),
      ],
    );
  }

  /// One view at a time, with the add field above whatever is showing: a task
  /// can be captured without first closing the panel you are reading. This is
  /// what a narrow window gets, and what the left pane of the split calendar
  /// gets - it is 340px wide by construction, so it is the narrow case.
  Widget _stackedContent(Color ws) {
    final secondary = _secondaryView(ws);
    if (secondary == null) return _taskColumn(ws);
    return Column(
      children: [
        _addField(ws),
        Expanded(child: secondary),
      ],
    );
  }

  /// The add field and the task list, capped at a readable column width.
  ///
  /// The cap is why a wide window grows a rail and a second pane rather than
  /// simply stretching: a tick box 900px from the end of its own line is a
  /// worse checklist, not a bigger one.
  Widget _taskColumn(Color ws) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Layout.taskColumnMax),
        child: Column(
          children: [
            _addField(ws),
            Expanded(child: _activeView(ws)),
          ],
        ),
      ),
    );
  }

  /// Whatever has taken the content area over, or null while the tasks have it.
  Widget? _secondaryView(Color ws) {
    if (s.showHistory) return _historyView();
    if (s.showThoughts) {
      return ThoughtsPanel(
        thoughts: s.thoughts,
        onPromote: s.promoteThought,
        onDiscard: s.resolveThought,
      );
    }
    if (s.showParked) {
      return ParkedPanel(
        groups: s.groups,
        parked: s.parked,
        accent: ws,
        onUnpark: s.unparkTask,
        onComplete: s.completeTask,
        onReviewed: s.markGroupReviewed,
        onEditGroup: _editGroup,
        onCreateGroup: () => _editGroup(null),
        onBack: _toggleParked,
      );
    }
    if (s.showSession) {
      return SessionView(
        events: s.liveEvents,
        tasks: s.sessionTasks,
        accent: ws,
        colorFor: s.colorForEvent,
        nameFor: _calendarNameForEvent,
        onComplete: s.completeTask,
        onDelete: s.deleteTask,
        onFocus: (t) => _startFocus(t),
        onUnplan: (t) => s.setTaskEvent(t, null),
        onCreateSublist: _openSublist,
        onBack: _toggleSession,
      );
    }
    if (s.showJournal) {
      return JournalView(
        configured: s.journalConfigured,
        locked: s.journalLocked,
        items: s.journal,
        onSetup: s.setupJournalPassword,
        onUnlock: s.unlockJournal,
        onLock: s.lockJournal,
        onRemovePassword: s.removeJournalPassword,
        onSave: (title, body, existing) => existing == null
            ? s.addJournalEntry(title, body)
            : s.editJournalEntry(existing, title, body),
        onDelete: s.deleteJournalEntry,
        onBack: _toggleJournal,
      );
    }
    return null;
  }

  // ----------------------------------------------------------- attachments

  Future<void> _openAttachments(Task t) async {
    final blobs = s.blobs;
    if (blobs == null) return;
    _closeSound();
    _closeSettings();
    _closeSublist();
    await showAttachments(
      context,
      task: t,
      accent: s.workspaceColor,
      blobs: blobs,
      load: () => s.attachmentsFor(t),
      onAdd: (file) => s.attachFile(t, file),
      onRemove: s.removeAttachment,
    );
  }

  // -------------------------------------------------------- parked groups

  Future<ParkedGroup?> _editGroup(ParkedGroup? existing) async {
    final result = await showGroupForm(context, existing: existing);
    if (result == null) return null;
    if (result.delete && existing != null) {
      await s.deleteGroup(existing);
      return null;
    }
    return s.saveGroup(
      uuid: existing?.uuid,
      title: result.title,
      reviewEveryDays: result.reviewEveryDays,
    );
  }

  /// Park a task from its row. Creating a group from inside the picker parks
  /// straight into it, so the first park does not take two passes.
  Future<void> _parkTask(Task t, RelativeRect anchor) async {
    final groupUuid = await showParkPicker(
      context,
      position: anchor,
      groups: s.groups,
      onCreate: () => _editGroup(null),
    );
    if (groupUuid == null || !mounted) return;
    await s.parkTask(t, groupUuid);
  }

  // ------------------------------------------------------------- composer

  /// The long form, from the add field. Ctrl+D and the ⤢ both land here.
  ///
  /// Whatever has been typed is carried over as the title - a shortcut that
  /// cost you the line you had already written would not be worth pressing -
  /// and the field is only cleared once the composer actually produced a task,
  /// so cancelling leaves the quick path exactly as it was.
  Future<void> _openComposer() async {
    final draft = await showTaskComposer(
      context,
      initialText: _addController.text.trim(),
    );
    if (draft == null || !mounted) return;
    _addController.clear();
    await s.addTask(
      draft.text,
      notes: draft.notes,
      priority: draft.priority,
      remindAt: draft.remindAt,
      recur: draft.recur,
    );
  }

  /// The same form on a task that already exists, opened from its own text.
  Future<void> _openTask(Task t) async {
    final draft = await showTaskComposer(context, existing: t);
    if (draft == null || !mounted) return;
    await s.saveTaskDetails(
      t,
      text: draft.text,
      notes: draft.notes,
      priority: draft.priority,
      remindAt: draft.remindAt,
      recur: draft.recur,
    );
  }

  Widget _addField(Color ws) {
    final field = TextField(
        controller: _addController,
        focusNode: _addFocus,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Add a task…',
          filled: true,
          fillColor: T.surface,
          // The shortcut, made visible - and the only way in on a phone, which
          // has no Ctrl to hold.
          suffixIcon: Tooltip(
            message: 'More: notes, priority, reminder (Ctrl+D)',
            child: InkWell(
              onTap: _openComposer,
              borderRadius: BorderRadius.circular(6),
              child: const Icon(Icons.open_in_full_rounded,
                  size: 14, color: T.muted),
            ),
          ),
          suffixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 30),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: ws.withValues(alpha: 0.6)),
          ),
        ),
        onSubmitted: (value) async {
          // Ctrl+Enter keeps the field focused for chaining entries; plain
          // Enter drops focus once the task is added.
          final chain = HardwareKeyboard.instance.isControlPressed;
          _addController.clear();
          await s.addTask(value);
          if (!mounted) return;
          if (chain) {
            _addFocus.requestFocus();
          } else {
            _addFocus.unfocus();
          }
        },
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      // The shortcut is bound around the field rather than globally: Ctrl+D is
      // only unambiguous while the caret is in here, and a global binding would
      // fire from inside the journal editor or a note.
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyD, control: true):
              _openComposer,
        },
        child: field,
      ),
    );
  }

  Widget _activeView(Color ws) {
    if (s.tasks.isEmpty) {
      return const Center(
        child: Text(
          'Nothing left. Nice. ✨',
          style: TextStyle(color: T.muted, fontSize: 12.5),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      buildDefaultDragHandles: false,
      itemCount: s.tasks.length,
      // onReorderItem (unlike the deprecated onReorder) already accounts for
      // the removed item, so newIndex needs no adjustment here.
      onReorderItem: (oldIndex, newIndex) async {
        final order = [...s.tasks];
        order.insert(newIndex, order.removeAt(oldIndex));
        await s.reorder(order.map((t) => t.uuid).toList());
      },
      itemBuilder: (context, i) {
        final t = s.tasks[i];
        final key = _rowKeys.putIfAbsent(t.uuid, () => GlobalKey());
        return KeyedSubtree(
          key: ValueKey(t.uuid),
          child: _plannable(
            t,
            ws,
            TaskRow(
            key: key,
            task: t,
            accent: ws,
            onComplete: () => s.completeTask(t),
            onDelete: () => s.deleteTask(t),
            onFocus: () => _startFocus(t),
            onSetReminder: (at) => s.setReminder(t, at),
            onPark: (anchor) => _parkTask(t, anchor),
            // Only ever drawn on a task that *is* planned, where it doubles as
            // the mark saying so - the list is otherwise unchanged by planning.
            onUnplan: () => s.setTaskEvent(t, null),
            onOpenAttachments: () => _openAttachments(t),
            onSetPriority: (high) => s.setPriority(t, high),
            onOpen: () => _openTask(t),
            attachmentCount: s.attachmentCounts[t.uuid] ?? 0,
              dragHandle: ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.drag_indicator, size: 14, color: T.muted),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// A row that can be dragged onto a calendar block, when there is a calendar
  /// beside it to drop onto - otherwise the row itself, untouched.
  ///
  /// `affinity: horizontal` is what keeps this out of the list's way: a
  /// vertical drag still scrolls and the ≡ handle still reorders, while a drag
  /// *towards the calendar* is the one gesture that means "plan this". Nothing
  /// here fires on a phone, where the two are never side by side.
  Widget _plannable(Task t, Color ws, Widget row) {
    if (!s.showCalendar || !_layout.splitsCalendar) return row;
    return Draggable<Task>(
      data: t,
      affinity: Axis.horizontal,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _dragFeedback(t, ws),
      childWhenDragging: Opacity(opacity: 0.35, child: row),
      child: row,
    );
  }

  /// What follows the pointer: the task's own title, small, in the workspace
  /// colour. A ghost of the whole row would be 340px of widget dragged across
  /// a grid it is about to cover.
  Widget _dragFeedback(Task t, Color ws) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        margin: const EdgeInsets.only(left: 10, top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Color.lerp(T.bgSolid, ws, 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ws.withValues(alpha: 0.7)),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 12),
          ],
        ),
        child: Text(
          t.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: T.text),
        ),
      ),
    );
  }

  Widget _historyView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelHeader(title: 'Done recently', onBack: _toggleHistory),
        Expanded(
          child: s.historyTasks.isEmpty
              ? const Center(
                  child: Text(
                    'No completed tasks yet.',
                    style: TextStyle(color: T.muted, fontSize: 12.5),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: s.historyTasks.length,
                  itemBuilder: (context, i) {
                    final t = s.historyTasks[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.text,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: T.muted,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                          Text(
                            _formatWhen(t.completedAt),
                            style: const TextStyle(fontSize: 10.5, color: T.muted),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _formatWhen(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, $hh:$mm';
  }

  // ------------------------------------------------------------ focus view

  Widget _focusOverlay(Color ws) {
    final t = s.focusTask;
    if (t == null) return const SizedBox.shrink();

    // The tile and the controls under it are held to the tile's own width, so
    // the whole thing stays one object in the middle of the window however wide
    // that window is.
    final width = _layout.focusTileWidth;

    return Positioned.fill(
      top: TitleBar.height,
      child: Center(
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Exactly the box the flight lands on, so the tile does not shift
              // sideways when it hands back to normal layout.
              NudgeBob(
                active: s.nudgeEnabled,
                child: _tile(t.text, ws, 20),
              ),
              const SizedBox(height: 22),

              // Parking a thought without leaving focus. Above the buttons, so
              // opening it never covers Done or Back.
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: _focusThoughtOpen
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: _focusThoughtController,
                          focusNode: _focusThoughtFocus,
                          style: const TextStyle(fontSize: 12.5),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Park a thought…',
                            filled: true,
                            fillColor: T.surface,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9),
                              borderSide:
                                  BorderSide(color: ws.withValues(alpha: 0.6)),
                            ),
                          ),
                          onSubmitted: (_) => _submitFocusThought(),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    onPressed: _completeFromFocus,
                    child: const Text('✓ Done'),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Park a side thought without leaving focus',
                    child: TextButton(
                      onPressed: () => _focusThoughtOpen
                          ? _closeFocusThought()
                          : _openFocusThought(),
                      child: Text(
                        s.thoughtCount > 0 ? '💭 ${s.thoughtCount}' : '💭',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _exitFocus,
                    child: const Text('Back to list'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // The nudge keeps the tile bobbing the whole time you are
              // focused, so it stays in the corner of your eye.
              TextButton.icon(
                onPressed: () => s.setNudge(!s.nudgeEnabled),
                icon: Icon(
                  s.nudgeEnabled
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  size: 14,
                  color: s.nudgeEnabled ? ws : T.muted,
                ),
                label: Text(
                  'Nudge',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: s.nudgeEnabled ? ws : T.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The tile mid-flight. Interpolates the box itself rather than applying a
  /// scale transform - a non-uniform scale would stretch the text.
  Widget _flyingTile(Color ws) {
    final t = s.focusTask;
    final text = t?.text ?? '';
    final from = _fromRect;
    final to = _toRect;
    if (from == null || to == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _hero,
      builder: (context, _) {
        final v = T.heroEase.transform(_hero.value);
        final rect = Rect.lerp(from, to, v)!;
        final fontSize = 13 + (20 - 13) * v;
        return Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: _tile(text, ws, fontSize),
        );
      },
    );
  }

  Widget _tile(String text, Color ws, double fontSize) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Color.lerp(T.bgSolid, ws, 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ws.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: ws.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: T.text,
          height: 1.25,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ workspaces

  /// Switching is *not* blocked by pending thoughts, unlike closing.
  ///
  /// It used to be, on the theory that the same guard should cover both. It is
  /// the wrong guard: side thoughts are global, so every workspace shows the
  /// same pile and the same bar, and moving between them neither hides a
  /// thought nor risks losing one. All the block did was make the app feel
  /// stuck during the one activity - looking around your own lists - that is
  /// how you work out where a parked thought actually belongs.
  ///
  /// Closing still blocks: that is the path where the pile leaves the screen.
  Future<void> _switchWorkspace(Workspace w) => s.selectWorkspace(w.uuid);

  Future<void> _editWorkspace(Workspace? existing) async {
    final result = await showWorkspaceForm(
      context,
      existing: existing,
      workspaceCount: s.workspaces.length,
    );
    if (result == null) return;
    if (result.delete && existing != null) {
      await s.deleteWorkspace(existing.uuid);
      return;
    }
    await s.saveWorkspace(
      uuid: existing?.uuid,
      name: result.name,
      color: result.color,
    );
  }
}

/// "Sublist" on the live-block tile: the way to give a block a list when it has
/// none. A labelled button rather than a bare ＋ because it is the one control
/// on that tile whose meaning is not obvious from the tile itself, and it is
/// only ever drawn in the case where the tile has nothing else to offer.
class _SublistButton extends StatelessWidget {
  const _SublistButton({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Give this block a list of its own',
      child: Material(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 4, 8, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.playlist_add_rounded, size: 14, color: color),
                const SizedBox(width: 4),
                const Text(
                  'Sublist',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: T.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
