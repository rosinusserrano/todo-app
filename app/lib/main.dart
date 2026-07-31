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
import 'ui/calendar/event_editor.dart';
import 'ui/footer.dart';
import 'ui/journal_panel.dart';
import 'ui/panel_header.dart';
import 'ui/parked_panel.dart';
import 'ui/settings_dialog.dart';
import 'ui/sound_sheet.dart';
import 'ui/task_row.dart';
import 'ui/title_bar.dart';
import 'ui/workspace_bar.dart';

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
  );

  _Focus _phase = _Focus.none;
  Rect? _fromRect;
  Rect? _toRect;
  String? _blockedMessage;
  bool _pinned = true;

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

  /// The window size to restore when the calendar closes. Captured rather than
  /// assumed: the widget is resizable, and putting 340x480 back would quietly
  /// undo whatever size the user had actually chosen.
  Size? _sizeBeforeCalendar;

  /// A week grid needs room. At 340px each day column is 43 pixels wide, which
  /// is not enough to read a title in, and dragging out a span in one is
  /// hopeless - so on desktop opening the calendar grows the window, and
  /// closing it puts back exactly what was there before.
  static const _calendarSize = Size(920, 640);

  Future<void> _toggleCalendar() async {
    // The calendar covers the add field and the footer, so anything focused
    // behind it has to let go first - the same reason the other views do this.
    if (s.focusTask != null) _exitFocus();
    _closeSound();

    final opening = !s.showCalendar;
    if (isDesktop) {
      if (opening) {
        _sizeBeforeCalendar = await windowManager.getSize();
        await windowManager.setSize(_calendarSize);
        await windowManager.center();
      } else {
        final previous = _sizeBeforeCalendar;
        if (previous != null) await windowManager.setSize(previous);
        _sizeBeforeCalendar = null;
      }
    }
    await s.toggleCalendar();
  }

  Future<void> _createEvent(DateTime start, DateTime end) async {
    final calendars = s.visibleCalendars;
    if (calendars.isEmpty) return;

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

  Future<void> _openEvent(CalendarEvent event) async {
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

  void _toggleSound() => setState(() => _soundOpen = !_soundOpen);

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
    if (await s.canProceedPastThoughts()) {
      await windowManager.destroy();
      return;
    }
    // The refusal has to be visible, or a quit from the tray while the window
    // is hidden looks like the app simply ignoring the click. Surface first,
    // then leave focus - the footer flash sits behind the focus overlay too.
    await _surfaceWindow();
    if (!mounted) return;
    _closeSound();
    if (s.focusTask != null) await _exitFocus();
    if (!mounted) return;
    _flashBlocked();
  }

  void _flashBlocked() {
    setState(() => _blockedMessage = 'Clear side thoughts first');
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _blockedMessage = null);
    });
  }

  // ----------------------------------------------------------- focus flight

  /// How far the focus tile stays clear of the window edges. Used both by the
  /// resting layout and by the flight's landing rect — if the two disagree, the
  /// tile visibly jumps sideways the instant the flight ends.
  static const _tileMargin = 28.0;

  /// Geometry of the tile at rest. Computed rather than measured: the layout is
  /// fully determined here, and measuring would need an extra frame with the
  /// tile already mounted, which is what the CSS version had to work around.
  Rect _restingTileRect(Size size) {
    const margin = _tileMargin;
    const tileHeight = 110.0;
    final areaTop = TitleBar.height;
    final areaHeight = size.height - areaTop;
    return Rect.fromLTWH(
      margin,
      areaTop + (areaHeight - tileHeight) / 2 - 30,
      size.width - margin * 2,
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

    final size = (context.findRenderObject() as RenderBox).size;
    setState(() {
      _fromRect = from;
      _toRect = _restingTileRect(size);
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

    final size = (context.findRenderObject() as RenderBox).size;
    final tileRect = _restingTileRect(size);

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
          if (_soundOpen) {
            _closeSound();
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
            child: _inset(Stack(
              key: _stackKey,
              children: [
                // Panels keep their layout and only fade, which is what lets
                // the tile fly back to the exact row it came from.
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

                // Above the focus overlay, since picking something to listen
                // to is exactly what you do *after* picking a task.
                if (_soundOpen)
                  SoundSheet(
                    sound: widget.sound,
                    accent: ws,
                    onClose: _closeSound,
                  ),

                // Above everything, so the window stays draggable and
                // closable during focus mode and with the sheet open.
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
                    onClose: () =>
                        isDesktop ? windowManager.close() : null,
                    onOpenSettings: _openSettings,
                    onToggleCalendar: _toggleCalendar,
                    calendarOpen: s.showCalendar,
                    syncColor: _syncColor(),
                    syncTooltip: widget.sync.describe(),
                  ),
                ),
              ],
            )),
          ),
        ),
      ),
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

  /// Dismisses whatever is covering the content area. Returns true if it did,
  /// meaning the press was spent on getting out of the way rather than on the
  /// view the caller wanted.
  bool _clearOverlays() {
    if (_soundOpen) {
      _closeSound();
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
    if (s.focusTask != null) await _exitFocus();
    if (!mounted) return;
    await showSyncSettings(
      context,
      widget.sync,
      startup: isDesktop && StartupSetting.supported ? _startup : null,
    );
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
    if (s.showCalendar) {
      return Column(
        children: [
          const SizedBox(height: TitleBar.height),
          Expanded(
            child: CalendarView(
              state: s,
              onClose: _toggleCalendar,
              onOpenEvent: _openEvent,
              onCreate: _createEvent,
              onNewCalendar: () => _editCalendar(null),
              onEditCalendar: (c) => _editCalendar(c),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        const SizedBox(height: TitleBar.height),
        WorkspaceBar(
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
          openView: s.showJournal
              ? WorkspaceView.notes
              : s.showParked
                  ? WorkspaceView.parked
                  : s.showHistory
                      ? WorkspaceView.history
                      : null,
        ),
        _addField(ws),
        Expanded(child: _contentView(ws)),
        ThoughtFooter(
          key: _footerKey,
          thoughts: s.thoughts,
          workspaceColor: ws,
          blockedMessage: _blockedMessage,
          onAdd: s.addThought,
          listOpen: s.showThoughts,
          onToggleList: s.toggleThoughts,
        ),
      ],
    );
  }

  /// The content area holds exactly one of three views. Thoughts and history
  /// both take it over rather than stacking on top of the tasks, which is what
  /// keeps a 340x480 window legible.
  Widget _contentView(Color ws) {
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
    return _activeView(ws);
  }

  // ----------------------------------------------------------- attachments

  Future<void> _openAttachments(Task t) async {
    final blobs = s.blobs;
    if (blobs == null) return;
    _closeSound();
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

  Widget _addField(Color ws) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: TextField(
        controller: _addController,
        focusNode: _addFocus,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Add a task…',
          filled: true,
          fillColor: T.surface,
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
          child: TaskRow(
            key: key,
            task: t,
            accent: ws,
            onComplete: () => s.completeTask(t),
            onDelete: () => s.deleteTask(t),
            onFocus: () => _startFocus(t),
            onSetReminder: (at) => s.setReminder(t, at),
            onPark: (anchor) => _parkTask(t, anchor),
            onOpenAttachments: () => _openAttachments(t),
            attachmentCount: s.attachmentCounts[t.uuid] ?? 0,
            dragHandle: ReorderableDragStartListener(
              index: i,
              child: const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.drag_indicator, size: 14, color: T.muted),
              ),
            ),
          ),
        );
      },
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

    return Positioned.fill(
      top: TitleBar.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The same inset the flight lands on, so the tile does not shift
              // sideways when it hands back to normal layout.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _tileMargin),
                child: NudgeBob(
                  active: s.nudgeEnabled,
                  child: _tile(t.text, ws, 20),
                ),
              ),
              const SizedBox(height: 22),

              // Parking a thought without leaving focus. Above the buttons, so
              // opening it never covers Done or Back.
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: _focusThoughtOpen
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(
                            _tileMargin, 0, _tileMargin, 12),
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
          );
        },
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
