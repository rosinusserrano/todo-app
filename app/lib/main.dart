// Todo Widget - Flutter client.
//
// Ported from the Tauri build (src/main.ts + src/styles.css). The window
// behaviour is the part that is not allowed to regress on Windows: frameless,
// transparent, acrylic, and always on top *while unfocused*.

import 'dart:async' show unawaited;
import 'dart:convert' show utf8;
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:media_kit/media_kit.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'journal_crypto.dart';
import 'layout.dart';
import 'link_titles.dart';
import 'voice_notes.dart';
import 'notifications.dart';
import 'platform.dart';
import 'quick_actions.dart';
import 'reminders.dart';
import 'shortcuts.dart';
import 'sound/sound_service.dart';
import 'sound/taskbar_transport.dart';
import 'startup.dart';
import 'sync/attachment_store.dart';
import 'sync/feeds.dart';
import 'sync/legacy_import.dart';
import 'sync/ics.dart';
import 'sync/local_store.dart';
import 'sync/models.dart';
import 'sync/protocol.dart';
import 'sync/sync_service.dart';
import 'theme.dart';
import 'tray.dart';
import 'web_keyboard.dart';
import 'whats_new.dart';
import 'window_spots.dart';
import 'ui/archived_projects.dart';
import 'ui/attachment_sheet.dart';
import 'ui/calendar/calendar_form.dart';
import 'ui/calendar/calendar_view.dart';
import 'ui/calendar/ics_import.dart';
import 'ui/calendar/subscribe_form.dart';
import 'ui/calendar/event_details.dart';
import 'ui/calendar/event_editor.dart';
import 'ui/calendar/time_grid.dart' show hhmm, kGutter;
import 'ui/collections.dart';
import 'ui/content_slot.dart';
import 'ui/dock.dart';
import 'ui/footer.dart';
import 'ui/journal_panel.dart';
import 'ui/list_rule.dart';
import 'ui/panel_header.dart';
import 'ui/parked_panel.dart';
import 'ui/project_row.dart';
import 'ui/session_view.dart';
import 'ui/move_picker.dart';
import 'ui/selection_bar.dart';
import 'ui/settings_sheet.dart';
import 'ui/shopping_list.dart';
import 'ui/sheet_transition.dart';
import 'ui/sound_sheet.dart';
import 'ui/split_pane.dart';
import 'ui/task_capture.dart';
import 'ui/task_composer.dart';
import 'ui/task_detail.dart';
import 'ui/task_drag.dart';
import 'ui/task_row.dart';
import 'ui/title_bar.dart';
import 'ui/thought_sheet.dart';
import 'ui/update_sheet.dart';
import 'ui/workspace_form.dart';
import 'ui/workspace_view.dart';
import 'web_safe_area.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Must run before any Player is constructed. The browser build has no
  // concentration sound at all (see `_toggleSound` below), so no Player is
  // ever constructed there and libmpv is never looked for.
  if (!isWeb) MediaKit.ensureInitialized();

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
  // A browser has no Tauri-era database to find.
  if (!isWeb) debugPrint((await LegacyImport.run(store)).toString());

  // Before AppState, which hands it the armed reminders on every task refresh -
  // including the one inside load() below, so the schedule is correct from the
  // first frame rather than from the first edit.
  final notifications = NotificationService();
  await notifications.init();

  // Attachment bytes live in a directory beside todo.db, and a browser has no
  // such directory. Null is the state AppState already handles - rows still
  // sync and show, as "not on this device" - and it is the honest one: the web
  // build is a second device that has never been handed the bytes.
  final blobs = isWeb ? null : await AttachmentStore.open();

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
  await state.checkWhatsNew();

  // Bytes whose row was tombstoned on another device arrive here as a merge,
  // never as a local delete, so this is the only thing that ever collects them.
  // Not awaited: it is a directory listing, and nothing on screen depends on it.
  if (blobs != null) state.sweepAttachments();

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
      // A subscription made on another device, and the events its refreshes
      // wrote. Subscriptions sync so that every device keeps them fresh.
      await state.loadFeeds();
      if (state.showCalendar) await state.refreshCalendars();
      // A list started or ticked on another device - the point of syncing it.
      await state.loadList();
    },
  );
  state.onMutated = sync.scheduleSync;
  // Natively a calendar address is simply asked; a browser is refused the
  // answer (calendar services send no CORS headers), so the web build has the
  // sync server fetch it instead.
  state.fetchFeed = isWeb ? sync.fetchFeedViaServer : fetchFeedDirect;
  await sync.load();

  // Links in task titles are drawn as their pages' titles - asked of the page
  // natively, of the sync server in a browser, for the feeds' reason.
  final linkTitles = LinkTitles(
    fetch: isWeb ? sync.linkTitleViaServer : fetchLinkTitleDirect,
    read: () => store.setting('link-titles'),
    write: (json) => store.setSetting('link-titles', json),
  );
  await linkTitles.load();

  // Voice notes play from this device's copy, else the server's - see
  // voice_notes.dart.
  final voiceNotes = VoiceNotes(store: store, fetch: sync.fetchBlob);

  final sound = SoundService(store);
  if (!isWeb) await sound.load();

  runApp(
    TodoApp(
      state: state,
      sync: sync,
      sound: sound,
      notifications: notifications,
      linkTitles: linkTitles,
      voiceNotes: voiceNotes,
    ),
  );
}

class TodoApp extends StatelessWidget {
  const TodoApp({
    super.key,
    required this.state,
    required this.sync,
    required this.sound,
    required this.notifications,
    this.linkTitles,
    this.voiceNotes,
  });

  final AppState state;
  final SyncService sync;
  final SoundService sound;
  final NotificationService notifications;
  final LinkTitles? linkTitles;
  final VoiceNotes? voiceNotes;

  @override
  Widget build(BuildContext context) {
    final titles = linkTitles;
    final voice = voiceNotes;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: T.themeData(),
      // Above the Navigator, so dialogs and menus are scaled with everything
      // else rather than staying desktop-sized on top of a zoomed widget.
      // The zoom setting is applied here too, for the same reason.
      builder: (context, child) => _withWebSafeArea(
        context,
        ValueListenableBuilder<double>(
          valueListenable: state.zoom,
          builder: (context, zoom, _) => UiScale(
            scale: isDesktop ? 1.0 : T.mobileScale,
            zoom: zoom,
            child: _scoped(
              child ?? const SizedBox.shrink(),
              titles: titles,
              voice: voice,
            ),
          ),
        ),
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

/// The app-wide services a widget anywhere may draw from, above the
/// Navigator so routes see them too.
Widget _scoped(Widget child, {LinkTitles? titles, VoiceNotes? voice}) {
  var out = child;
  if (voice != null) out = VoiceNotesScope(notes: voice, child: out);
  if (titles != null) out = LinkTitlesScope(titles: titles, child: out);
  return out;
}

/// Hands a browser build the safe area its engine leaves out (see
/// `web_safe_area.dart`), so the shell's SafeArea keeps the view bar off the
/// home indicator and the title bar out from under the clock, the way it does
/// in the native app. The bottom is left out while the keyboard is up: the
/// keyboard covers the indicator, and the gap would sit above it.
Widget _withWebSafeArea(BuildContext context, Widget child) {
  if (!isWeb) return child;
  final mq = MediaQuery.of(context);
  final safeTop = webSafeTop();
  final top = safeTop > mq.padding.top ? safeTop : mq.padding.top;
  var bottom = webSafeBottom();
  if (bottom <= mq.padding.bottom || mq.viewInsets.bottom > 0) {
    bottom = mq.padding.bottom;
  }
  if (top == mq.padding.top && bottom == mq.padding.bottom) return child;
  return MediaQuery(
    data: mq.copyWith(
      padding: mq.padding.copyWith(top: top, bottom: bottom),
      viewPadding: mq.viewPadding.copyWith(top: top, bottom: bottom),
    ),
    child: child,
  );
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

  final _addController = KeywordController();
  final _addFocus = FocusNode();

  /// The add card is open (ui/task_capture.dart).
  ///
  /// The field used to open in place at the head of the list; now the folded
  /// line there is where the card lifts off from and lands back on. Closing
  /// keeps whatever was typed - the folded line shows it - so a tap on the
  /// dimmed list costs nothing.
  bool _adding = false;

  /// The card is on screen, flying home included. The folded line stays
  /// hidden until it has landed, or there would be two of it.
  bool _addCardShown = false;

  final _addPromptKey = GlobalKey();

  /// Open the card. The caret is the card's to place, once it is built.
  void _openAdd() {
    // Inside the tap, when there is one: iOS raises the keyboard only for a
    // focus moved during the touch's own handler (see web_keyboard.dart).
    if (isWeb && _layout.touch) primeWebKeyboard();
    if (_adding) return;
    setState(() {
      _adding = true;
      _addCardShown = true;
    });
  }

  /// Fly it home. What was typed stays as the draft.
  void _closeAdd() {
    if (!_adding) return;
    setState(() => _adding = false);
  }

  /// The folded line, in the shell Stack's coordinates - where the card
  /// leaves from and lands on. Null when another view has the content area.
  Rect? _addPromptRect() {
    final box = _addPromptKey.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.attached || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
  }

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

  /// The full-screen side-thought capture pane. Touch only - see
  /// ui/thought_sheet.dart for why a phone does not get the inline field.
  bool _thoughtCapture = false;

  /// The task a line is being added to, from the home-screen quick action.
  /// Null the rest of the time, which is nearly always: this is one field
  /// opened from outside the app and closed again.
  Task? _noteOn;

  /// An open note is in focus: its ⛶ was pressed, and the shell hands it the
  /// whole screen - see [_noteTakesScreen].
  bool _noteFocused = false;

  /// A note is being written, not read. A bottom dock steps aside for it
  /// (Marco, 2026-10-18) - see [_dockShows].
  bool _noteEditing = false;

  /// The next journal pane opens on a blank entry ([_addNote]). Cleared after
  /// the frame that built it, since the pane reads it only once.
  bool _startNewNote = false;

  /// An on-screen keyboard is up, as of the last build. See [_dockShows].
  bool _keyboardUp = false;

  /// The task whose read-only long form has the content area, by uuid.
  ///
  /// The uuid rather than the row, because the list is reloaded under this
  /// constantly - a sync merge, a completion elsewhere, a reminder firing -
  /// and a held [Task] would be a copy that quietly went stale. It resolves
  /// through [_expandedTask], which is also how a task that was completed or
  /// deleted on another device simply stops being expanded.
  ///
  /// Only ever set where the shell is the one that can give a view the screen
  /// (see [_expandsToScreen]); under a pointer the row expands inside itself
  /// and the shell is not involved at all.
  String? _expandedTaskUuid;

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

  /// The phone's equivalent of the global shortcuts: the same capture paths,
  /// reached by long-pressing the app icon. The third one names whichever task
  /// is in focus, so the menu is rebuilt whenever that changes - see
  /// [_onState].
  ///
  /// Every entry waits for the first layout ([_afterLayout]): a cold start hands
  /// the shortcut over before anything is built.
  late final AppQuickActions _quickActions = AppQuickActions(
    onAddTask: _afterLayout(_jumpToAddTask),
    onAddThought: _afterLayout(_jumpToAddThought),
    onNoteOnActive: _afterLayout(_noteOnActiveTask),
    onOpenCalendar: _afterLayout(_openCalendarFromOutside),
  );

  /// Whether [_layout] has been measured yet, rather than being its default.
  bool _laidOut = false;

  /// [action], deferred until the shell has been laid out once.
  ///
  /// iOS delivers the shortcut that launched the app as soon as the handler is
  /// installed, which is during [initState] - before the first build. Until
  /// then [_layout] is the desktop default, so "Park a thought" asked a
  /// footer field that a phone does not draw to take the caret, and nothing
  /// happened. Both quick actions were dead from a cold start for that reason.
  Future<void> Function() _afterLayout(Future<void> Function() action) {
    return () async {
      if (!_laidOut) await WidgetsBinding.instance.endOfFrame;
      if (mounted) await action();
    };
  }

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
    onTick: _onTick,
  );

  /// The one poll. Three things need a clock and none of them writes anything
  /// a listener could hang off:
  ///
  ///   - a time block *starting*, which is why [AppState.refreshSessions] is
  ///     driven from here rather than from a write path;
  ///   - a repeating task **falling due**, which for a rule-based repeat has
  ///     nothing to do with anything being ticked - a monthly report appears on
  ///     the last day of the month whether or not last month's was ever sent,
  ///     and only a clock notices that;
  ///   - the window quietly losing always-on-top, which nothing reports at all.
  ///
  /// One timer rather than three to keep in step, for the same reason `onTick`
  /// exists at all.
  Future<void> _onTick() async {
    // Before the sessions: a task laid down here can be planned into the block
    // the same tick is about to describe.
    await s.sweepRecurrences();
    await s.refreshSessions();
    await _ensurePinned();
    // Last, and not awaited: a fetch can take seconds, and nothing else on
    // this tick should wait on somebody else's calendar server. Due-ness is
    // checked inside, so a tick with nothing due costs a comparison per feed.
    unawaited(s.refreshFeeds());
  }

  /// Put the window back on top if Windows has taken it off.
  ///
  /// Always-on-top is a *style bit* (`WS_EX_TOPMOST`), and it is not ours alone
  /// to hold: another application going full screen makes Windows strip it from
  /// everyone else, and nothing puts it back when that application exits. The
  /// widget was set topmost once, in `main()`, so from then on it was simply an
  /// ordinary window that happened to still say "pinned" - the symptom being a
  /// widget that falls behind everything after something like Photo Viewer has
  /// been open, and stays there.
  ///
  /// So the pin is re-asserted rather than set: [_pinned] is the *intent*, and
  /// this is what makes the intent survive. It reads the bit first and only
  /// writes when the two disagree - `setAlwaysOnTop` maps to a `SetWindowPos`
  /// that also activates, so calling it unconditionally on a 20-second timer
  /// would raise the window every time round.
  Future<void> _ensurePinned() async {
    if (!isDesktop || !_pinned) return;
    try {
      if (await windowManager.isAlwaysOnTop()) return;
      await windowManager.setAlwaysOnTop(true);
    } catch (_) {
      // Losing the pin is a nuisance; a throw from a timer would be worse.
    }
  }

  /// Clicking back onto the widget repairs the pin immediately rather than at
  /// the next tick. Free of the activation concern above: the window is already
  /// the active one by the time this runs.
  @override
  void onWindowFocus() => _ensurePinned();

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
    // Launching is opening the app, so it opens on the list - after the first
    // layout, and after any quick action that launched it, which wins. The
    // notes for an update go over whatever that opened.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _openListOnReturn();
      await _showWhatsNew();
    });
  }

  /// The box after an update (whats_new.dart), once. Marked as seen when it
  /// opens rather than when it closes: a box that came back because the page
  /// was reloaded with it up would be the box nagging.
  Future<void> _showWhatsNew() async {
    final notes = s.whatsNew;
    if (!mounted || notes.isEmpty) return;
    await s.markWhatsNewSeen();
    if (!mounted) return;
    await showWhatsNew(context, notes: notes, accent: T.accent);
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
    if (lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.paused) {
      _wentAway = true;
    }
    if (lifecycle != AppLifecycleState.resumed) return;
    widget.sync.resume();
    _reminders.tick();
    // Every return opens on the list - but a return, not a blink: `inactive`
    // alone is a notification shade pulled down or a browser losing focus to
    // its own address bar, and the app never went anywhere. The desktop widget
    // is always open and gains and loses focus constantly; its returns are
    // the tray and un-minimising (see _surfaceWindow, onWindowRestore).
    if (_wentAway && !isDesktop) {
      _wentAway = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openListOnReturn());
    }
  }

  /// The app went to the background (hidden or paused) since it last came
  /// back. See [didChangeAppLifecycleState].
  bool _wentAway = false;

  // ---------------------------------------------------------- shopping list

  Future<void> _toggleList() async {
    // Same clearing as the calendar: the list owns the content area.
    if (s.focusTask != null) _exitFocus();
    _closeSound();
    _closeSettings();
    _collapseTask();
    await s.toggleList();
  }

  /// The app was opened - launched, or back from the background - so it opens
  /// on the list, if there is one. Moving around inside the app never calls
  /// this: go to Tasks and come back when you like.
  ///
  /// It does not take the screen from anything being written. A form or dialog
  /// on top, the add field open, a thought or a note being captured - those
  /// are someone in the middle of something, and in the case of a quick action
  /// they are what this opening was *for*. Focus mode is left alone too: it
  /// is already "the app opens on this one thing", and leaving it is an edit.
  Future<void> _openListOnReturn() async {
    if (!mounted || s.showList || s.currentList == null) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (_adding || _thoughtCapture || _noteOn != null || _focusThoughtOpen) {
      return;
    }
    if (s.focusTask != null) return;
    _closeSound();
    _closeSettings();
    _collapseTask();
    await s.setListOpen(true);
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
    // Leaving the calendar ends quick-add too, so anything placed and not yet
    // written goes in now. Same rule as the bolt and the mode switch: a block
    // you laid down is never lost by leaving in a way you did not think of.
    if (s.showCalendar) await s.commitPendingBlocks();
    await s.toggleCalendar();
  }

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
      recur: edit.recur,
      allDay: edit.allDay,
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
      offerWorkspace: s.workspaceForEvent(event) != null,
      feedName: _feedNameFor(event),
    );
    if (action == null || !mounted) return;
    await _runEventAction(event, action);
  }

  /// The subscription a block came from, by name, or null for one made here.
  /// A feed that has since been removed on another device still makes the
  /// block read-only; it just has no name to give.
  String? _feedNameFor(CalendarEvent event) {
    if (!event.fromFeed) return null;
    return s.feedByUuid(event.feedUuid)?.name ?? 'a subscribed calendar';
  }

  /// Right-click, or long-press on a phone. The same things the details card
  /// offers, without having to open it first - which is the whole point of a
  /// context menu: it is for when you already know what you want to do.
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
              const SizedBox(width: T.s2),
              Text(
                event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: T.fsLabel, color: T.muted),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (s.workspaceForEvent(event) != null)
          _menuItem(
            EventAction.openWorkspace,
            Icons.checklist_rounded,
            'Go to workspace',
          ),
        // A subscribed block is the feed's to change, so the menu offers
        // only what does not write to it - the details card's rule.
        if (!event.fromFeed) ...[
          _menuItem(EventAction.edit, Icons.edit_outlined, 'Edit'),
          _menuItem(
            EventAction.delete,
            Icons.delete_outline,
            'Delete',
            color: T.danger,
          ),
        ],
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
          const SizedBox(width: T.s2),
          Text(
            label,
            style: TextStyle(fontSize: T.fsLabel, color: color),
          ),
        ],
      ),
    );
  }

  Future<void> _runEventAction(CalendarEvent event, EventAction action) async {
    // Neither surface offers these on a subscribed block; this is the
    // backstop for any path that one day does.
    if (event.fromFeed && action != EventAction.openWorkspace) return;
    switch (action) {
      case EventAction.edit:
        await _editEvent(event);
      case EventAction.delete:
        await _deleteEvent(event);
      case EventAction.openWorkspace:
        await _goToEventWorkspace(event);
    }
  }

  /// From a block to the list it belongs to.
  ///
  /// Beside the list (the split) the calendar stays open and only the pane on
  /// the left changes - both halves of the question are then on screen. Where
  /// the calendar has the whole window it closes, because a workspace switch
  /// behind a calendar you are still looking at would change nothing visible.
  Future<void> _goToEventWorkspace(CalendarEvent event) async {
    final ws = s.workspaceForEvent(event);
    if (ws == null) return;
    if (s.showCalendar && !_layout.splitsCalendar) await _toggleCalendar();
    if (!mounted) return;
    await s.selectWorkspace(ws);
  }

  /// Deleting a repeating block deletes **the series**, so it says so first.
  ///
  /// The same rule as activating a parked group: one press that removes a row
  /// you can see is its own confirmation, but one press that removes fifty-two
  /// Tuesdays you cannot see is not, and there is no undo behind either.
  Future<void> _deleteEvent(CalendarEvent event) async {
    if (event.repeats) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: T.bgSolid,
          title: const Text(
            'Delete every occurrence?',
            style: TextStyle(fontSize: T.fsMenu),
          ),
          content: Text(
            '"${event.title}" repeats ${Recur.label(event.recur!).toLowerCase()}. '
            'Deleting it removes the whole series, not just this one.',
            style: const TextStyle(
              fontSize: T.fsLabel,
              color: T.muted,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete series'),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    await s.deleteEvent(event);
  }

  Future<void> _editEvent(CalendarEvent occurrence) async {
    final calendars = s.calendars;
    if (calendars.isEmpty) return;

    // The form always edits the **series**, times included. Opening the third
    // Tuesday of a weekly block and changing its title would otherwise save
    // that Tuesday's start as the series start, quietly moving every
    // occurrence; there is nowhere yet to record "this one is different". The
    // form says so, and for a one-off `stored` is the row itself.
    final event = occurrence.stored;

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
      onAddAttachment: s.blobs == null
          ? null
          : (file) => s.attachFileToEvent(event, file),
      onRemoveAttachment: s.removeEventAttachment,
      loadTasks: () => s.plannableTasks(event),
      onPlanTask: (task, on) => s.setTaskEvent(task, on ? event.uuid : null),
    );
    if (edit == null) return;

    if (edit.delete) {
      await _deleteEvent(event);
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
      // so the form's null has to be passed as an explicit clear. Same for the
      // repeat rule, where null means "stop repeating".
      clearNotify: edit.notifyMinutes == null,
      recur: edit.recur,
      clearRecur: edit.recur == null,
      allDay: edit.allDay,
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
    await _openListOnReturn();
  }

  /// The taskbar toolbar cannot be set while the window is hidden - Windows
  /// drops the call - and this app spends much of its life in the tray. Both
  /// ways back have to re-apply it: this one covers an OS-driven restore
  /// (clicking the taskbar button), [_surfaceWindow] covers ours.
  @override
  void onWindowRestore() {
    _taskbar.refresh();
    _openListOnReturn();
  }

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
    _closeNoteOn();
    if (leaveFocus && s.focusTask != null) await _exitFocus();
    return mounted;
  }

  /// The add field sits behind the focus overlay, so this one has to leave it.
  ///
  /// It also has to leave everything else that can stand where the field is
  /// drawn, or it opens out of sight - which from the outside is a shortcut
  /// that does nothing. The calendar replaces the whole window unless it is
  /// split beside the list; a task read on a phone takes the content area; a
  /// selection puts its own bar in the field's slot.
  Future<void> _jumpToAddTask() async {
    if (!await _surfaceForCapture(leaveFocus: true)) return;
    if (s.showCalendar && !_layout.splitsCalendar) await _toggleCalendar();
    if (s.showList) await s.setListOpen(false);
    if (!mounted) return;
    // Land on the task list, not on whichever view was covering it. Not
    // [_showTasks]: that stops after closing one overlay, which is right for a
    // tap and wrong here. The capture pane is one of those overlays, and the
    // top-most - a phone left on it covers the field entirely.
    if (_thoughtCapture) _closeThoughtCapture();
    if (s.showHistory) s.toggleHistory();
    if (s.showThoughts) s.toggleThoughts();
    if (s.showParked) s.toggleParked();
    if (s.showJournal) s.toggleJournal();
    if (s.showCollections) s.toggleCollections();
    if (s.showSession) s.toggleSession();
    if (_expandedTaskUuid != null) _collapseTask();
    _clearSelection();
    _openAdd();
  }

  /// Ctrl+Alt+H, the quick action, the dock's ＋. Focus mode keeps its own
  /// field, so capturing does not end it; everywhere else it is the capture
  /// pane, on every device. On a desktop that used to be the footer's field
  /// expanding in place - except on the full-window calendar and the list,
  /// which draw no footer - and one shortcut opening two different things
  /// depending on the view was the complaint. Closing the pane lands back on
  /// whatever was under it.
  Future<void> _jumpToAddThought() async {
    if (!await _surfaceForCapture(leaveFocus: false)) return;
    if (s.focusTask != null) {
      _openFocusThought();
      return;
    }
    _openThoughtCapture();
  }

  /// The quick action for the task in focus was picked.
  ///
  /// Reads the task *now* rather than trusting the menu: the entry is stored by
  /// the OS and survives the app being killed, so it can name a task that has
  /// since been finished or deleted. With nothing in focus this falls back to
  /// the add field - the user asked to write something down, and the honest
  /// answer to "that task is gone" is a place to put it, not a dead press.
  Future<void> _noteOnActiveTask() async {
    final task = s.focusTask;
    if (task == null) {
      await _jumpToAddTask();
      return;
    }
    // leaveFocus: false - the whole point is the task you are on, and dropping
    // out of focus mode to write a line about it would be backwards.
    if (!await _surfaceForCapture(leaveFocus: false)) return;
    setState(() => _noteOn = task);
  }

  /// The calendar quick action. Opens it rather than toggling: pressed while it
  /// is already showing - the app was left on it - the answer is to stay there,
  /// not to close the thing that was asked for.
  Future<void> _openCalendarFromOutside() async {
    if (!await _surfaceForCapture(leaveFocus: true)) return;
    if (!s.showCalendar) await _toggleCalendar();
  }

  void _closeNoteOn() {
    if (_noteOn != null) setState(() => _noteOn = null);
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

  void _toggleSound() {
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

  void _onState() {
    _noteCompatibility();
    // The quick-action menu names the task in focus. Cheap to call on every
    // notify - it compares the title it would print and does nothing unless it
    // has moved - and there is no single write to hang it off instead, since a
    // task can leave focus by being completed, deleted, parked or merged away.
    _quickActions.setActiveTask(s.focusTask?.text);
    setState(() {});
  }

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
      await widget.sound.stop().timeout(
        const Duration(milliseconds: 600),
        onTimeout: () {},
      );
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
              const SizedBox(width: T.s2),
              const Text(
                'Closing…',
                style: TextStyle(fontSize: T.fsLabel, color: T.muted),
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

  /// The window drops the workspace tint for the calendar's neutral chrome.
  ///
  /// The tint says which workspace you are looking at, and the calendar is the
  /// one view that is not looking at one. **Whenever it is open**, including
  /// beside the task list: this was `&& !splitsCalendar` at first, on the
  /// theory that half a split window really is that workspace's list and the
  /// tint was telling the truth there. What that actually bought was a change
  /// nobody could see - the widget is run at about 1140x670, the split starts
  /// at 813x400, so the exception was the only case that ever ran. A rule with
  /// an exception covering the normal size is not a rule.
  ///
  /// Nothing is lost in the split, either. Which workspace you are in is on the
  /// workspace bar's coloured pill, two inches from the tint that was repeating
  /// it, and the blocks on the grid keep their own calendars' colours - which
  /// is the distinction the neutral exists to stop competing with.
  ///
  /// The thought pile follows the same rule for the same reason: it is global,
  /// so a window tinted with one workspace's colour around it was claiming the
  /// pile belonged to that workspace. Including in the split, where the tint is
  /// no more needed than it is beside the calendar - the pill on the workspace
  /// bar is still saying which list is on the left.
  bool get _neutralChrome => s.showCalendar || s.showThoughts || s.showList;

  @override
  Widget build(BuildContext context) {
    final ws = s.workspaceColor;
    _bottomInset = isDesktop ? 0 : MediaQuery.paddingOf(context).bottom;
    // Read here, above the Scaffold: its body is handed a MediaQuery with
    // the keyboard taken out.
    _keyboardUp = !isDesktop && MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          // N opens the add field, from anywhere a key is not being typed
          // into something - the keyboard's way to the ＋. Checked through
          // the focused node's ancestry because a text field's own key events
          // bubble up through here too, and "n" typed into a note must stay
          // an "n".
          if (event is KeyDownEvent &&
              isDesktop &&
              event.logicalKey == LogicalKeyboardKey.keyN &&
              !HardwareKeyboard.instance.isControlPressed &&
              !HardwareKeyboard.instance.isAltPressed &&
              !HardwareKeyboard.instance.isMetaPressed &&
              FocusManager.instance.primaryFocus?.context
                      ?.findAncestorStateOfType<EditableTextState>() ==
                  null &&
              !s.showCalendar &&
              !s.showList &&
              s.focusTask == null &&
              !_soundOpen &&
              !_settingsOpen) {
            _openAdd();
            return KeyEventResult.handled;
          }
          // Ctrl+E: the calendar's edit mode, on and off. In a browser too -
          // there it would otherwise be the address bar's search.
          if (event is KeyDownEvent &&
              (isDesktop || isWeb) &&
              s.showCalendar &&
              event.logicalKey == LogicalKeyboardKey.keyE &&
              HardwareKeyboard.instance.isControlPressed &&
              !HardwareKeyboard.instance.isAltPressed &&
              !HardwareKeyboard.instance.isShiftPressed &&
              FocusManager.instance.primaryFocus?.context
                      ?.findAncestorStateOfType<EditableTextState>() ==
                  null) {
            s.toggleCalendarEditing();
            return KeyEventResult.handled;
          }
          // Ctrl + / Ctrl - / Ctrl 0, as in a browser. Not in one: the
          // browser takes those keys for its own zoom, and both at once would
          // be two zooms multiplied.
          if (event is KeyDownEvent &&
              isDesktop &&
              HardwareKeyboard.instance.isControlPressed) {
            final step = switch (event.logicalKey) {
              LogicalKeyboardKey.equal ||
              LogicalKeyboardKey.add ||
              LogicalKeyboardKey.numpadAdd => 1,
              LogicalKeyboardKey.minus ||
              LogicalKeyboardKey.numpadSubtract => -1,
              LogicalKeyboardKey.digit0 || LogicalKeyboardKey.numpad0 => 0,
              _ => null,
            };
            if (step != null) {
              step == 0 ? s.setZoom(1.0) : s.stepZoom(step);
              return KeyEventResult.handled;
            }
          }
          // Esc unwinds one layer at a time: the sound sheet, then the
          // focus-mode thought field, then focus mode itself.
          if (event is! KeyDownEvent ||
              event.logicalKey != LogicalKeyboardKey.escape) {
            return KeyEventResult.ignored;
          }
          if (_updateOpen) {
            _closeUpdateSheet();
          } else if (_thoughtCapture) {
            // What was typed stays unsaved, as with the ✕: Esc is "never
            // mind", and Enter is right there for "keep it".
            _closeThoughtCapture();
          } else if (_noteOn != null) {
            _closeNoteOn();
          } else if (_settingsOpen) {
            _closeSettings();
          } else if (_soundOpen) {
            _closeSound();
          } else if (_focusThoughtOpen) {
            _closeFocusThought();
          } else if (_adding) {
            _closeAdd();
          } else if (s.focusTask != null) {
            _exitFocus();
          } else if (_taskTakesScreen) {
            _collapseTask();
          } else if (_selectedTasks.isNotEmpty) {
            _clearSelection();
          } else if (s.showList) {
            _toggleList();
          } else if (s.showCalendar) {
            _toggleCalendar();
          } else if (s.showThoughts) {
            s.toggleThoughts();
          } else if (s.showParked) {
            s.toggleParked();
          } else if (s.showJournal) {
            s.toggleJournal();
          } else if (s.showCollections) {
            s.toggleCollections();
          } else if (s.showSession) {
            s.toggleSession();
          } else if (s.showHistory) {
            s.toggleHistory();
          } else if (s.currentProject != null) {
            // The project's list is one rung above its workspace's.
            _leaveProject();
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          // The rounded, bordered frame is a desktop window's: it is what
          // tells this widget apart from whatever is behind it. A phone has
          // nothing behind it - the app *is* the screen - and there the frame
          // was a hairline box drawn round the whole app, the one tile left
          // after every other one was taken away.
          decoration: BoxDecoration(
            color: _neutralChrome
                ? T.calendarBackground
                : T.tintedBackground(ws),
            borderRadius: isDesktop
                ? BorderRadius.circular(T.radius)
                : BorderRadius.zero,
            border: isDesktop
                ? Border.all(
                    color: _neutralChrome
                        ? T.calendarBorder
                        : T.tintedBorder(ws),
                  )
                : null,
          ),
          child: ClipRRect(
            borderRadius: isDesktop
                ? BorderRadius.circular(T.radius)
                : BorderRadius.zero,
            child: _inset(
              LayoutBuilder(
                builder: (context, constraints) {
                  _layout = Layout(constraints.biggest, touch: !isDesktop);
                  _laidOut = true;
                  return LayoutScope(layout: _layout, child: _shell(ws));
                },
              ),
            ),
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
      // Not clipped: the dock paints its colours down into the home
      // indicator's strip, which is outside this box (the SafeArea above
      // keeps it out). The window's own ClipRRect is still the edge.
      clipBehavior: Clip.none,
      children: [
        // Panels keep their layout and only fade, which is what lets the tile
        // fly back to the exact row it came from.
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _focusVisible ? 0 : 1,
            duration: T.heroDur,
            child: IgnorePointer(ignoring: _focusVisible, child: _body(ws)),
          ),
        ),

        if (_phase == _Focus.resting) _focusOverlay(ws),
        if (_phase == _Focus.flyingIn || _phase == _Focus.flyingOut)
          _flyingTile(ws),

        // The add card, over the list it lifts off from and under every sheet:
        // a capture hotkey or a thought pane opened on top of it closes back
        // onto it, draft intact.
        Positioned.fill(
          child: TaskCapture(
            open: _adding,
            controller: _addController,
            focusNode: _addFocus,
            workspaces: s.moveTargets,
            hereUuid: s.currentWorkspaceUuid,
            layout: _layout,
            originOf: _addPromptRect,
            onSubmit: (r) async {
              if (r.project) {
                await s.addProject(r.title, parentUuid: r.workspaceUuid);
                return;
              }
              await s.addTask(
                r.title,
                workspaceUuid: r.workspaceUuid,
                priority: r.priority,
                remindAt: r.remindAt,
              );
            },
            onExpand: _openComposer,
            onClose: _closeAdd,
            onClosed: () {
              if (mounted) setState(() => _addCardShown = false);
            },
            onAddShortcut: s.addWorkspaceShortcut,
          ),
        ),

        // Above the focus overlay, since picking something to listen to is
        // exactly what you do *after* picking a task.
        SheetTransition(
          open: _soundOpen,
          builder: (_) =>
              SoundSheet(sound: widget.sound, accent: ws, onClose: _closeSound),
        ),

        // Above every other sheet: it is opened to hide what is behind it, so
        // anything drawn over it would defeat the point.
        SheetTransition(
          open: _thoughtCapture,
          builder: (_) => ThoughtSheet(
            accent: T.thoughts,
            onAdd: (text, clip) => s.addThought(text, clip: clip),
            onClose: _closeThoughtCapture,
            enterSaves: !_layout.touch,
            canRecord: true,
          ),
        ),

        // The same pane, pointed at a task's notes instead of the pile. The
        // task is captured here rather than read from the field inside the
        // callbacks: the pane is animating out by the time the last write
        // lands, and by then the field is null.
        SheetTransition(
          open: _noteOn != null,
          builder: (_) {
            final task = _noteOn!;
            return ThoughtSheet(
              accent: ws,
              glyph: '📝',
              title: task.text,
              hint: 'Add a line to its notes…',
              onAdd: (text, _) async => s.appendToNotes(task, text),
              onClose: _closeNoteOn,
              enterSaves: !_layout.touch,
            );
          },
        ),

        SheetTransition(
          open: _settingsOpen,
          builder: (_) => SettingsSheet(
            sync: widget.sync,
            accent: ws,
            onClose: _closeSettings,
            zoom: s.zoom.value,
            onZoom: s.setZoom,
            startup: isDesktop && StartupSetting.supported ? _startup : null,
            dockEdge: s.wideDock,
            onDockEdge: s.setWideDock,
            archivedCount: s.archivedProjects.length,
            archive: (key) => ArchivedProjectsView(key: key, state: s),
          ),
        ),

        // Above everything, so the window stays draggable and closable during
        // focus mode and with the sheet open. A note in focus fades it on a
        // phone, where it holds nothing a note needs; a desktop window keeps
        // it, since it is how the window is moved and closed.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _fadeForNote(
            TitleBar(
              isDesktop: isDesktop,
              pinned: _pinned,
              onTogglePin: _togglePin,
              onToggleSound: isWeb ? null : _toggleSound,
              soundPlaying: widget.sound.isPlaying,
              soundPaused: widget.sound.isPaused,
              onTogglePause: widget.sound.togglePause,
              volume: widget.sound.volume,
              onVolumeChanged: widget.sound.setVolume,
              // The bar's lit controls follow the window they sit on. With the
              // calendar's neutral chrome underneath, the workspace colour would
              // be the only thing left on screen belonging to a workspace you
              // cannot see - and the neutral itself is no use as a tint, being
              // within a few points of T.muted, so "lit" would stop reading as
              // lit. The app's own accent is neither workspace's, and it is what
              // the calendar's own toolbar already uses for an active control.
              accent: _neutralChrome ? T.accent : ws,
              onClose: () => isDesktop ? windowManager.close() : null,
              // No settings, calendar or list buttons: the dock holds all three,
              // at every size, and a second door to each is one too many.
              calendarOpen: s.showCalendar,
              listOpen: s.showList,
              syncColor: _syncColor(),
              syncTooltip: widget.sync.describe(),
              windowModes: isDesktop ? s.windowModes : null,
              onWindowMode: _placeWindow,
              onFullScreen: _fullScreen,
              onSaveWindowMode: _saveWindowMode,
              onRemoveWindowMode: s.removeWindowMode,
              // Along the top the dock is in this bar, beside the name, rather
              // than a second bar under it. It fades with the body in focus
              // mode, which this bar otherwise stays visible through.
              dock: _dockShows && _dockEdge == DockEdge.top
                  ? AnimatedOpacity(
                      opacity: _focusVisible ? 0 : 1,
                      duration: T.heroDur,
                      child: IgnorePointer(
                        ignoring: _focusVisible,
                        child: _dock(ws, DockEdge.top),
                      ),
                    )
                  : null,
            ),
          ),
        ),

        // Above every other sheet and below the title bar: it is the one
        // panel that is *about* the app rather than part of using it, and it
        // is opened by the app rather than asked for - so it must not arrive
        // underneath whatever happened to be open.
        SheetTransition(
          open: _updateOpen,
          builder: (_) => UpdateSheet(
            compatibility: widget.sync.compatibility,
            server: widget.sync.serverProtocol ?? ServerProtocol.legacy,
            accent: ws,
            onClose: _closeUpdateSheet,
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

  /// The bottom inset that [_inset] keeps the content out of - recorded so
  /// the dock can paint down into it. Read in [build], outside the SafeArea,
  /// which is the only place it is still in the MediaQuery.
  double _bottomInset = 0;

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

  void _toggleCollections() {
    if (_clearOverlays()) return;
    s.toggleCollections();
  }

  void _toggleSession() {
    if (_clearOverlays()) return;
    s.toggleSession();
  }

  /// The first time, straight to subscribing; after that, the list, which is
  /// where subscribing another one is too.
  Future<void> _subscriptions() async {
    if (s.feeds.isEmpty) {
      await showSubscribeForm(context, s);
    } else {
      await showSubscriptions(context, s);
    }
  }

  /// Bring in events from an .ics file another application produced.
  ///
  /// A file picker rather than the share sheet, and for now that is the whole
  /// feature: picking works identically on every platform today, whereas
  /// receiving a share needs native glue per platform (see ROADMAP). The parse,
  /// the confirmation and the write are the same either way, so the share sheet
  /// becomes a second way in rather than a second implementation.
  Future<void> _importIcs() async {
    // lockParentWindow for the same reason attachment_sheet.dart passes it:
    // this window is always-on-top, so without it the picker opens behind the
    // thing that asked for it.
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Import a calendar file',
      type: FileType.custom,
      allowedExtensions: const ['ics', 'ical', 'ifb'],
      withData: true,
      lockParentWindow: true,
    );
    if (picked == null || !mounted) return;

    final file = picked.files.single;
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;

    // allowMalformed rather than a strict decode: an .ics is meant to be UTF-8,
    // and a stray Windows-1252 one should import with a single odd character
    // rather than failing outright.
    final events = parseIcs(utf8.decode(bytes, allowMalformed: true));

    if (!mounted) return;
    if (events.isEmpty) {
      await _notice('Nothing to import', 'No events were found in that file.');
      return;
    }

    final target = await showImportIcs(context, events, state: s);
    if (target == null || !mounted) return;

    await s.importIcsEvents(events, calendarUuid: target);
  }

  /// A one-line dialog for something that has already happened.
  ///
  /// A dialog rather than a sheet, per the rule in this file: it is transient
  /// and modal by nature. There is no toast mechanism in this app and adding
  /// one for a single message would be a second way of saying things.
  Future<void> _notice(String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: T.bgSolid,
        title: Text(title, style: const TextStyle(fontSize: T.fsMenu)),
        content: Text(body, style: const TextStyle(fontSize: T.fsLabel)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(fontSize: T.fsLabel)),
          ),
        ],
      ),
    );
  }

  /// The tile above the list was pressed.
  ///
  /// One thing happens that a plain toggle would not do: it **switches to the
  /// block's workspace** first, because the tile is the one control in the app
  /// that talks about a workspace other than the one on screen - showing its
  /// todos beside a different workspace's list is how you read the wrong one.
  Future<void> _openSession() async {
    if (_clearOverlays()) return;
    final first = s.liveEvents.isEmpty ? null : s.liveEvents.first;
    if (first == null) return;

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

  /// Back to the task list - the dock's Tasks row, a panel header's title.
  /// Every branch is a toggle and at most one view is open, so at most one
  /// fires.
  void _showTasks() {
    if (_clearOverlays()) return;
    if (s.showHistory) s.toggleHistory();
    if (s.showThoughts) s.toggleThoughts();
    if (s.showParked) s.toggleParked();
    if (s.showJournal) s.toggleJournal();
    if (s.showCollections) s.toggleCollections();
    if (s.showSession) s.toggleSession();
  }

  /// Go to one view directly, rather than toggling towards it.
  ///
  /// The dock's rows and the swipe are *destinations*: picking Notes must
  /// land on Notes whatever was showing, and a swipe that toggled would go
  /// backwards half the time.
  void _selectView(WorkspaceView? view) {
    if (_clearOverlays()) return;
    _showTasks();
    switch (view) {
      case null:
        break;
      case WorkspaceView.notes:
        s.toggleJournal();
      case WorkspaceView.parked:
        s.toggleParked();
      case WorkspaceView.collections:
        s.toggleCollections();
      case WorkspaceView.history:
        s.toggleHistory();
      case WorkspaceView.thoughts:
        s.toggleThoughts();
    }
  }

  /// One step along [kViewOrder]. Returns false at either end, so a swipe
  /// there does nothing rather than wrapping around - a list with a first and
  /// last entry that silently loops is one you cannot tell your position in.
  bool _swipeView(int direction) {
    final at = kViewOrder.indexOf(_openView);
    // The thought pile is not one of the workspace's views, so a swipe from
    // it has no defined neighbour. Going back to the list is the honest
    // answer.
    if (at < 0) {
      _showTasks();
      return true;
    }
    final next = at + direction;
    if (next < 0 || next >= kViewOrder.length) return false;
    _selectView(kViewOrder[next]);
    return true;
  }

  /// Dismisses whatever is covering the content area. Returns true if it did,
  /// meaning the press was spent on getting out of the way rather than on the
  /// view the caller wanted.
  bool _clearOverlays() {
    if (_updateOpen) {
      _closeUpdateSheet();
      return true;
    }
    // First of the rest, because it is the top-most sheet and the one whose
    // whole job is to be covering the others.
    if (_thoughtCapture) {
      _closeThoughtCapture();
      return true;
    }
    if (_noteOn != null) {
      _closeNoteOn();
      return true;
    }
    if (_settingsOpen) {
      _closeSettings();
      return true;
    }
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

  /// The capture pane. Focus mode goes first: it is an overlay of its own, and
  /// leaving it up behind an opaque sheet means closing this one lands back
  /// somewhere the user did not ask to be.
  /// Which mismatch the alert has already been shown for.
  ///
  /// Once per mismatch, not once per sync: the check re-runs on every cycle
  /// while it is failing (that is what makes syncing resume by itself when the
  /// server is deployed), and a screen that reappeared every minute would be
  /// something you learn to dismiss without reading. Null again the moment the
  /// two agree, so a *later* mismatch is announced properly.
  Compatibility? _updateShownFor;
  bool _updateOpen = false;

  void _noteCompatibility() {
    final now = widget.sync.compatibility;
    if (now.isOk) {
      _updateShownFor = null;
      if (_updateOpen) _updateOpen = false;
      return;
    }
    if (_updateShownFor == now) return;
    _updateShownFor = now;
    // Focus mode first, for the same reason the capture pane does it: leaving
    // an overlay up behind this one means closing it lands somewhere the user
    // did not ask to be.
    _exitFocus();
    _updateOpen = true;
  }

  void _closeUpdateSheet() {
    if (_updateOpen) setState(() => _updateOpen = false);
  }

  /// A saved window mode from the title bar: the bounds it was saved with,
  /// or the same place in proportion when its screen is gone. See
  /// window_spots.dart.
  Future<void> _placeWindow(WindowMode mode) async {
    if (await windowManager.isMaximized()) await windowManager.unmaximize();
    final (_, area, areas) = await _windowAndAreas();
    await windowManager.setBounds(mode.placeIn(areas, area));
  }

  /// The title bar's one built-in mode. Maximised rather than a saved
  /// rectangle: it means the whole screen on every screen.
  Future<void> _fullScreen() => windowManager.maximize();

  /// The window as it is now, kept under a name asked for here.
  Future<void> _saveWindowMode() async {
    final (bounds, area, _) = await _windowAndAreas();
    if (!mounted) return;
    final name = await askWindowModeName(
      context,
      taken: [for (final m in s.windowModes) m.name],
    );
    if (name == null) return;
    await s.addWindowMode(WindowMode(name: name, bounds: bounds, area: area));
  }

  /// The window's bounds, the work area of the screen it is on, and the
  /// work areas of every screen.
  Future<(Rect, Rect, List<Rect>)> _windowAndAreas() async {
    final bounds = await windowManager.getBounds();
    Rect areaOf(Display d) =>
        (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size);
    final areas = [
      for (final d in await screenRetriever.getAllDisplays()) areaOf(d),
    ];
    final area = areaFor(
      bounds,
      areas,
      areaOf(await screenRetriever.getPrimaryDisplay()),
    );
    return (bounds, area, areas);
  }

  void _openThoughtCapture() {
    _exitFocus();
    // Still inside the tap that asked for it, which is the only moment iOS
    // will bring a keyboard up for a web page. A browser with a mouse has no
    // on-screen keyboard to bring, and a focus moved out from under it there
    // would only blink.
    if (isWeb && _layout.touch) primeWebKeyboard();
    setState(() => _thoughtCapture = true);
  }

  void _closeThoughtCapture() => setState(() => _thoughtCapture = false);

  Future<void> _openSettings() async {
    _closeSound();
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
    SyncStatus.ok => T.ok,
    SyncStatus.error => T.warn,
    SyncStatus.blocked => T.danger,
    // Red like blocked: both are states that will not recover on their own.
    // What differs is the sentence, which the settings sheet and the alert
    // carry - the icon has one colour to spend and "needs you" is the message.
    SyncStatus.outdated => T.danger,
  };

  /// Everything under the title bar, with the dock along whichever edge it
  /// is on.
  ///
  /// The column and the row inside it are built whether or not the dock is
  /// in them, and the body is keyed in both, so the dock coming and going (a
  /// note taking the screen) or changing edge never changes the body's
  /// parent - see content_slot.dart for what that costs when it does.
  Widget _body(Color ws) {
    final edge = _dockShows ? _dockEdge : null;
    return Column(
      children: [
        // A top dock is drawn in the title bar (see `TitleBar.dock`).
        const SizedBox(height: TitleBar.height),
        Expanded(
          key: const ValueKey('body'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (edge == DockEdge.left) _dock(ws, edge!),
              Expanded(key: const ValueKey('content'), child: _bodyAbove(ws)),
            ],
          ),
        ),
        if (edge == DockEdge.bottom) _dock(ws, edge!),
      ],
    );
  }

  Widget _bodyAbove(Color ws) {
    // The calendar replaces the whole body, workspace bar and footer included:
    // it spans workspaces, so a workspace tab above it would be saying
    // something the grid underneath does not agree with.
    //
    // Given room for both (Layout.splitsCalendar) it stops replacing anything
    // and opens beside the list instead - which is the one arrangement in which
    // a task can be dragged onto a block, because both ends of that gesture
    // have to be on screen at once.
    // The shopping list replaces the whole body the same way: it belongs to no
    // workspace, and it is meant to be the only thing on screen.
    if (s.showList) return ShoppingListView(state: s);

    if (s.showCalendar) {
      if (_layout.splitsCalendar) return _splitCalendar(ws);
      return _calendar();
    }

    // The dock and the swipe are the same navigation, offered twice: the
    // dock says which views exist, the swipe is the cheap way between them.
    // Both walk kViewOrder, so they cannot disagree about what is next to
    // what.
    //
    // A horizontal drag is safe to claim here. The one other horizontal gesture
    // in the list is the task Draggable, and that only exists when there is
    // something beside the list to drop onto (see _plannable) - which needs a
    // window far wider than any phone, so the two can never both be live.
    final content = _layout.touch && !_layout.isWide
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              // Flung, not merely dragged a little sideways while scrolling.
              if (v.abs() < 220) return;
              _swipeView(v < 0 ? 1 : -1);
            },
            child: _contentArea(ws),
          )
        : _contentArea(ws);

    return Column(
      children: [
        if (s.hasLiveSession && !s.showSession && !_takesScreen)
          _sessionBanner(),
        // The content keeps its element through every one of those `if`s
        // resolving differently - see content_slot.dart, which is the whole
        // reason opening a note on a phone no longer closes it again.
        contentSlot(child: content),
        // Spanning the whole width: the pile is global, not the business of
        // the view above it. With the dock carrying the pile's count and the
        // way in, this draws nothing unless the desktop shortcut opens its
        // field - see [_footer].
        if (!_takesScreen) _footer(ws),
      ],
    );
  }

  /// A note in focus gets the screen to itself, at every size: the dock, the
  /// footer and the session banner go, and on a phone the title bar fades.
  ///
  /// It used to be every open note on a phone, which took the dock away from
  /// anyone who had only opened a note to glance at it (Marco, 2026-10-18).
  /// Now it is asked for, with the note's own ⛶, and the same button (or Esc)
  /// is the way back.
  bool get _noteTakesScreen => s.showJournal && _noteFocused;

  Widget _fadeForNote(Widget titleBar) {
    final hide = _noteTakesScreen && !isDesktop;
    return AnimatedOpacity(
      opacity: hide ? 0 : 1,
      duration: T.heroDur,
      child: IgnorePointer(ignoring: hide, child: titleBar),
    );
  }

  /// Where expanding a task is the *shell's* job rather than the row's.
  ///
  /// The same condition the note follows, for the same reason: on a phone a
  /// task's notes and details want the height the workspace pill, the view bar
  /// and the footer are using, and a row inside a scrolling list cannot take
  /// them. Anywhere else the row grows in place, which keeps the list around
  /// it - scroll past an expanded task on a desktop and the next one is there.
  bool get _expandsToScreen => _layout.touch && !_layout.isWide;

  /// The expanded task, or null if nothing is expanded or the row it named has
  /// since left the list (completed here, or merged away by sync).
  Task? get _expandedTask {
    final uuid = _expandedTaskUuid;
    if (uuid == null) return null;
    for (final t in s.tasks) {
      if (t.uuid == uuid) return t;
    }
    return null;
  }

  /// Whether that expanded task is what the content area is showing.
  ///
  /// Guarded **structurally** rather than by every path that opens something
  /// else: a view, the calendar and focus mode all own the content area, and a
  /// rule each of them had to remember to apply is the rule that gets missed
  /// (see the quick-add commit rule for how that goes). Opening any of them
  /// simply stops this being true; coming back to the tasks lands where you
  /// were reading, which is what the calendar's remembered date does too.
  bool get _taskTakesScreen =>
      _expandsToScreen &&
      _openView == null &&
      !s.showSession &&
      !s.showCalendar &&
      !s.showList &&
      s.focusTask == null &&
      _expandedTask != null;

  /// Anything that has taken the whole screen off the workspace's chrome.
  bool get _takesScreen => _noteTakesScreen || _taskTakesScreen;

  void _expandTask(Task t) => setState(() => _expandedTaskUuid = t.uuid);

  void _collapseTask() => setState(() => _expandedTaskUuid = null);

  /// The dock is the whole navigation at every size - workspace, view, and
  /// everything global - and replaced the workspace bar, the rail, the view
  /// bar and the title bar's calendar, list and settings buttons. Only a note
  /// or a task that has taken a phone's screen hides it.
  ///
  /// It also steps aside for an on-screen keyboard - it was a row of the
  /// little space left above one, and nothing in it is for typing - and,
  /// along the bottom, for a note being written; reading one keeps it
  /// (Marco, 2026-10-18).
  bool get _dockShows =>
      !_takesScreen &&
      !_keyboardUp &&
      !(s.showJournal && _noteEditing && _dockEdge == DockEdge.bottom);

  /// Along the bottom while the window is narrow - a phone, the desktop
  /// widget at its own size - where a thumb is and where the eye ends up.
  /// Past [Layout.isWide] it goes where Settings says: across the top or
  /// down the side.
  DockEdge get _dockEdge => _layout.isWide ? s.wideDock : DockEdge.bottom;

  /// Outside the split, spanning the whole width: the
  /// pressure meter is about the pile, not about the workspace - or the view -
  /// you happen to be in.
  Widget _footer(Color ws) => ThoughtFooter(
    key: _footerKey,
    onCapture: _openThoughtCapture,
    // Wherever the dock is drawn it is the whole control - the way in, the
    // count and the escalation - and this bar has nothing of its own left to
    // say. It stays in the tree rather than being dropped from it because the
    // field is still what [openAndFocus] focuses (the desktop shortcut) and
    // the refusal is still what the close guard flashes; it simply takes no
    // height until one of those happens.
    // Not `_dockShows`: a keyboard hiding the dock for a moment is no
    // reason for this bar to grow a second way in.
    showCaptureButton: _takesScreen,
    showPressure: _takesScreen,
    thoughts: s.thoughts,
    accent: T.thoughts,
    blockedMessage: _blockedMessage,
    onAdd: s.addThought,
    listOpen: s.showThoughts,
    onToggleList: s.toggleThoughts,
  );

  /// The bar: workspace, view, everything else. See ui/dock.dart.
  ///
  /// Every row is a *destination*, not a toggle - picking Notes lands on Notes
  /// whatever was showing, and picking the open one again changes nothing -
  /// for the same reason [_selectView] is.
  Widget _dock(Color ws, DockEdge edge) {
    final view = _openView;
    final global =
        s.showCalendar || s.showList || view == WorkspaceView.thoughts;
    const views = {
      null: (Icons.check_circle_outline_rounded, 'Tasks'),
      WorkspaceView.notes: (Icons.notes_rounded, 'Notes'),
      WorkspaceView.parked: (Icons.inbox_rounded, 'Parked'),
      WorkspaceView.collections: (Icons.table_rows_outlined, 'Collections'),
      WorkspaceView.history: (Icons.history_rounded, 'History'),
    };
    final here = views[view == WorkspaceView.thoughts ? null : view]!;
    // Inside a project the dock still names its workspace: the project is a
    // place in it, and its own name heads the list.
    final current = s.homeWorkspace;
    final syncNeedsYou = switch (widget.sync.status) {
      SyncStatus.blocked || SyncStatus.outdated => true,
      _ => false,
    };

    DockItem viewItem(WorkspaceView? v) => DockItem(
      icon: views[v]!.$1,
      label: views[v]!.$2,
      current: !global && view == v,
      dot: v == WorkspaceView.parked && s.groupsDueForReview.isNotEmpty,
      onChoose: () => _dockToView(v),
    );

    final (moreIcon, moreLabel) = s.showCalendar
        ? (Icons.calendar_month_outlined, 'Calendar')
        : s.showList
        ? (Icons.shopping_basket_outlined, 'List')
        : view == WorkspaceView.thoughts
        ? (Icons.cloud_outlined, 'Thoughts')
        : (Icons.more_horiz_rounded, 'More');

    return Dock(
      edge: edge,
      // Slimmer away from the bottom: up there and down the side it is aimed
      // at, not landed on by a thumb. Along the top it is the title bar's own
      // height, since it sits in that bar.
      thickness: switch (edge) {
        DockEdge.bottom => 52,
        DockEdge.top => TitleBar.height,
        DockEdge.left => 48,
      },
      underhang: edge == DockEdge.bottom ? _bottomInset : 0,
      segments: [
        DockSegment(
          label: current?.name ?? 'Workspace',
          fill: ws,
          ink: T.inkOn(ws),
          dimmed: s.showCalendar || s.showList,
          semanticLabel: 'Workspace: ${current?.name ?? ''}',
          // A tap or a click on the workspace itself goes to its task list:
          // "this one's tasks" is the commonest thing to want of it. It used
          // to open the add field, which put a caret in front of someone who
          // had only come to look (Marco, 2026-10-16), and on touch it
          // opened the menu, which stood in the way (2026-10-17).
          // Inside a project it is the workspace's list, the one it names.
          onClick: () => s.currentProject != null && current != null
              ? _dockToWorkspace(current)
              : _dockToView(null),
          items: [
            DockItem(
              icon: Icons.add_rounded,
              label: 'New workspace',
              onChoose: () => _editWorkspace(null),
            ),
            for (final w in s.workspaces)
              DockItem(
                label: w.name,
                fill: T.parseHex(w.color),
                current: w.uuid == current?.uuid,
                onChoose: () => _dockToWorkspace(w),
                secondaryIcon: Icons.edit_outlined,
                secondaryLabel: 'Edit ${w.name}',
                onSecondary: () => _editWorkspace(w),
                // Straight to one of its views, from anywhere.
                children: [
                  for (final v in kViewOrder)
                    DockItem(
                      icon: views[v]!.$1,
                      label: views[v]!.$2,
                      current:
                          !global &&
                          w.uuid == s.currentWorkspaceUuid &&
                          view == v,
                      onChoose: () => _dockToWorkspaceView(w, v),
                      // Notes carries a ＋ at its end: a new note in this
                      // workspace, straight from the menu.
                      secondaryIcon: v == WorkspaceView.notes
                          ? Icons.add_rounded
                          : null,
                      secondaryLabel: v == WorkspaceView.notes
                          ? 'New note'
                          : null,
                      onSecondary: v == WorkspaceView.notes
                          ? () => _addNote(w)
                          : null,
                    ),
                ],
              ),
          ],
        ),
        DockSegment(
          icon: here.$1,
          label: here.$2,
          fill: Color.lerp(T.bgSolid, ws, 0.30)!,
          ink: T.text,
          dimmed: global,
          dot: s.groupsDueForReview.isNotEmpty,
          // A tap goes to the top of the view it names: out of a collection
          // to the collections, out of a note to the notes (Marco,
          // 2026-10-18).
          onClick: () =>
              _dockToViewRoot(view == WorkspaceView.thoughts ? null : view),
          // Nearest the thumb at the bottom: Tasks is the one you go back to.
          items: [for (final v in kViewOrder.reversed) viewItem(v)],
        ),
        DockSegment(
          icon: moreIcon,
          label: moreLabel,
          fill: Color.lerp(T.bgSolid, T.text, 0.07)!,
          ink: T.text,
          count: s.thoughtCount,
          pressure: s.thoughtCount,
          dot: syncNeedsYou,
          items: [
            DockItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              dot: syncNeedsYou,
              onChoose: () {
                if (!_settingsOpen) _openSettings();
              },
            ),
            DockItem(
              icon: Icons.shopping_basket_outlined,
              label: 'List',
              current: s.showList,
              onChoose: _dockToList,
            ),
            DockItem(
              icon: Icons.calendar_month_outlined,
              label: 'Calendar',
              current: s.showCalendar,
              onChoose: _dockToCalendar,
            ),
            DockItem(
              icon: Icons.cloud_outlined,
              label: 'Thoughts',
              count: s.thoughtCount,
              current:
                  !s.showCalendar &&
                  !s.showList &&
                  view == WorkspaceView.thoughts,
              onChoose: () => _dockToView(WorkspaceView.thoughts),
            ),
          ],
        ),
        // The fourth kind of thing: not a place but an act. Writing something
        // down is the commonest reason to open the app at all, so it is a
        // door of its own rather than a second action hidden on a row - the
        // same as the home-screen quick actions, minus "Note on <task>": that
        // one names the focused task, and focus mode hides this bar.
        DockSegment(
          icon: Icons.add_rounded,
          label: '',
          semanticLabel: 'Quick add',
          extent: 56,
          fill: Color.lerp(T.bgSolid, T.text, 0.16)!,
          ink: T.text,
          onClick: _jumpToAddTask,
          items: [
            DockItem(
              icon: Icons.check_circle_outline_rounded,
              label: 'Add a task',
              onChoose: _jumpToAddTask,
            ),
            // Nearest the thumb: a thought is the thing that has to be down
            // before it is gone.
            DockItem(
              icon: Icons.cloud_outlined,
              label: 'Add a thought',
              onChoose: _openThoughtCapture,
            ),
          ],
        ),
      ],
    );
  }

  /// Clears what stands in front of the workspace - every overlay, the
  /// calendar, the list - before a dock destination is shown. All of them,
  /// unlike [_clearOverlays]: a row picked in the dock is a decision, not a
  /// tap that might have been aimed at the thing in the way.
  Future<void> _dockClear({
    bool keepCalendar = false,
    bool keepList = false,
  }) async {
    for (var i = 0; i < 6 && _clearOverlays(); i++) {}
    // Through _toggleCalendar, not the flag: leaving the calendar is one of the
    // places quick-add's pending blocks are committed.
    if (!keepCalendar && s.showCalendar) await _toggleCalendar();
    if (!keepList && s.showList) await s.setListOpen(false);
    if (_expandedTaskUuid != null) _collapseTask();
  }

  Future<void> _dockToView(WorkspaceView? view) async {
    await _dockClear();
    if (!mounted) return;
    _selectView(view);
  }

  /// [view] from its top: whatever was open inside it - a note, a
  /// collection, a shelf's review - is left. A fresh key on the view is a
  /// fresh State, which is each view's top rung; the journal still saves an
  /// open draft as it goes.
  Future<void> _dockToViewRoot(WorkspaceView? view) async {
    await _dockClear();
    if (!mounted) return;
    if (_openView == view) {
      setState(() {
        _secondaryKey = GlobalKey(debugLabel: 'secondary view');
        _noteFocused = false;
        _noteEditing = false;
      });
    }
    _selectView(view);
  }

  /// The ＋ on a workspace's Notes row in the dock: that workspace's Notes,
  /// on a blank entry, from wherever you were. A fresh State, as
  /// [_dockToViewRoot] makes, so it lands on the editor whatever rung Notes
  /// was on; a draft that was open saves on its way out.
  Future<void> _addNote(Workspace w) async {
    // Inside the tap, as for a thought: iOS raises a web page's keyboard
    // only then, and the title field is built frames later.
    if (isWeb && _layout.touch) primeWebKeyboard();
    await _dockClear();
    if (!mounted) return;
    if (w.uuid != s.currentWorkspaceUuid) await _switchWorkspace(w);
    if (!mounted) return;
    setState(() {
      _secondaryKey = GlobalKey(debugLabel: 'secondary view');
      _noteFocused = false;
      _noteEditing = false;
      _startNewNote = true;
    });
    if (_openView != WorkspaceView.notes) _selectView(WorkspaceView.notes);
  }

  Future<void> _dockToWorkspace(Workspace w) async {
    await _dockClear();
    if (!mounted) return;
    // selectWorkspace closes every view, so this lands on its task list.
    await _switchWorkspace(w);
  }

  /// A workspace's view from the workspace menu's submenu: switch (which
  /// lands on its list), then go to the view.
  Future<void> _dockToWorkspaceView(Workspace w, WorkspaceView? view) async {
    await _dockClear();
    if (!mounted) return;
    if (w.uuid != s.currentWorkspaceUuid) await _switchWorkspace(w);
    if (!mounted) return;
    _selectView(view);
  }

  Future<void> _dockToCalendar() async {
    await _dockClear(keepCalendar: true);
    if (!mounted || s.showCalendar) return;
    await _toggleCalendar();
  }

  Future<void> _dockToList() async {
    await _dockClear(keepList: true);
    if (!mounted || s.showList) return;
    await _toggleList();
  }

  /// The calendar, wherever it is drawn.
  ///
  /// It publishes its **own** [LayoutScope]: beside the list it gets a fraction
  /// of the window, and every question the views ask about whether they fit -
  /// the week grid's fallback to the agenda, the year's column count - has to
  /// be about the box the calendar actually got, not about the window.
  Widget _calendar() {
    return LayoutBuilder(
      builder: (context, constraints) => LayoutScope(
        layout: Layout(constraints.biggest, touch: !isDesktop),
        child: CalendarView(
          state: s,
          onClose: _toggleCalendar,
          onOpenEvent: _openEvent,
          onEventMenu: _eventMenu,
          onCreate: _createEvent,
          onNewCalendar: () => _editCalendar(null),
          onImportIcs: _importIcs,
          onSubscriptions: _subscriptions,
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
  /// The left pane opens under its workspace's name (the list's own
  /// [PanelHeader]), which is the honest place for it here: the calendar
  /// beside it can be showing every workspace at once.
  ///
  /// The footer still spans both, because the pile of side thoughts is neither
  /// half's business.
  Widget _splitCalendar(Color ws) {
    return Column(
      children: [
        Expanded(
          // Same boundary as the views' split, with its own remembered
          // position: the grid wants every pixel a notes pane would not. The
          // fold is shared - "not the list, thanks" is one preference.
          child: SplitPane(
            fraction: s.calendarSplitFraction,
            defaultLeft: (_) => Layout.calendarTaskPaneWidth,
            collapsed: s.tasksPaneCollapsed,
            onFraction: (f) => s.setSplitFraction(f, calendar: true),
            onCollapsed: s.setTasksPaneCollapsed,
            minRight: kGutter + 7 * Layout.minDayColumn,
            left: LayoutBuilder(
              builder: (context, constraints) => LayoutScope(
                layout: Layout(constraints.biggest, touch: !isDesktop),
                child: Column(
                  children: [
                    if (s.hasLiveSession && !s.showSession) _sessionBanner(),
                    Expanded(child: _stackedContent(ws)),
                  ],
                ),
              ),
            ),
            right: _calendar(),
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
      padding: const EdgeInsets.fromLTRB(T.s2, T.s2, T.s2, T.s1),
      child: Material(
        color: Color.lerp(T.bgSolid, color, 0.22),
        borderRadius: BorderRadius.circular(T.radius),
        child: InkWell(
          onTap: _openSession,
          borderRadius: BorderRadius.circular(T.radius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(T.radius),
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
            padding: const EdgeInsets.all(T.s2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        more > 0 ? '${first.title}  +$more more' : first.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: T.fsLabel,
                          fontWeight: T.wMedium,
                          color: T.text,
                        ),
                      ),
                      Text(
                        'until ${hhmm(first.end)} · '
                        '${left == 0 ? 'nothing planned' : '$left to do'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: T.fsMeta,
                          color: T.muted,
                        ),
                      ),
                    ],
                  ),
                ),
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
      : s.showCollections
      ? WorkspaceView.collections
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
    // An expanded task owns the area outright wherever it is drawn at all -
    // not even the add field, which is a second thing to read on a screen
    // being used to read one.
    final expanded = _taskTakesScreen ? _expandedTask : null;
    if (expanded != null) {
      return TaskDetailScreen(
        task: expanded,
        accent: ws,
        attachmentCount: s.attachmentCounts[expanded.uuid] ?? 0,
        onCollapse: _collapseTask,
      );
    }

    final secondary = _secondaryView(ws);
    if (secondary == null) return _taskColumn(ws);

    if (!_layout.splitsContent) return _stackedContent(ws);

    // The boundary moves, and the list folds away entirely for a view that
    // wants the whole width - see split_pane.dart. The default is the 5:4 this
    // used to be fixed at.
    return SplitPane(
      left: _taskColumn(ws),
      right: secondary,
      fraction: s.splitFraction,
      defaultLeft: (width) => width * 5 / 9,
      // A note in focus folds the list away too, without touching the
      // stored preference.
      collapsed: s.tasksPaneCollapsed || _noteTakesScreen,
      onFraction: (f) => s.setSplitFraction(f),
      onCollapsed: s.setTasksPaneCollapsed,
    );
  }

  /// One view at a time, with the add field above whatever is showing: a task
  /// can be captured without first closing the panel you are reading. This is
  /// what a narrow window gets, and what the left pane of the split calendar
  /// gets - it is 340px wide by construction, so it is the narrow case.
  Widget _stackedContent(Color ws) {
    return _secondaryView(ws) ?? _taskColumn(ws);
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
            // The workspace's name is otherwise only in the dock, which on
            // a phone is at the far end of the screen from the list it
            // names. Every other view opens under its own title, so the list
            // does too - in the workspace's colour, which is the one thing
            // that makes "Work" mean that workspace. Kept while selecting, so
            // the list below it keeps its place in this Column (and its
            // scroll).
            _listHeader(ws),
            if (_selectedTasks.isNotEmpty)
              SelectionBar(
                count: _selectedTasks.length,
                accent: ws,
                onComplete: () => _finishSelected(complete: true),
                onMove: (anchor) => _moveTasks(_selectedTasks, anchor),
                onDelete: () => _finishSelected(complete: false),
                onClear: _clearSelection,
              )
            else
              _addPrompt(ws),
            Expanded(child: _activeView(ws)),
          ],
        ),
      ),
    );
  }

  /// Identity for whichever view has the content area, across every place the
  /// shell can put it.
  ///
  /// The same view is a child of the stacked column in a narrow window, of the
  /// split row past [Layout.splitMinWidth], and of a different subtree again
  /// once the rail appears - so resizing the window across any of those
  /// breakpoints reparented it, and an unkeyed widget that changes parent is
  /// built from scratch. For the journal that meant the editor and everything
  /// typed into it: widen the window until the task list appeared beside a note
  /// and the note was gone. A GlobalKey is what lets an element move between
  /// parents with its State intact. [contentSlot] solves the sibling half of
  /// the same problem; this is the parent half.
  var _secondaryKey = GlobalKey(debugLabel: 'secondary view');

  /// Whatever has taken the content area over, or null while the tasks have it.
  Widget? _secondaryView(Color ws) {
    final view = _secondaryViewUnkeyed(ws);
    return view == null ? null : KeyedSubtree(key: _secondaryKey, child: view);
  }

  Widget? _secondaryViewUnkeyed(Color ws) {
    if (s.showHistory) return _historyView();
    if (s.showThoughts) {
      return ThoughtsPanel(
        thoughts: s.thoughts,
        onPromote: s.promoteThought,
        onDiscard: s.resolveThought,
        onMove: _moveThoughts,
      );
    }
    if (s.showParked) {
      return ParkedPanel(
        groups: s.groups,
        parked: s.parked,
        accent: ws,
        onUnpark: s.unparkTask,
        onComplete: s.completeTask,
        onDelete: s.deleteTask,
        onAddTask: (g, text) => s.addTask(text, groupUuid: g.uuid),
        onReviewed: s.markGroupReviewed,
        onEditGroup: _editGroup,
        onCreateGroup: () => _editGroup(null),
        onBack: _toggleParked,
        onActivateGroup: s.unparkGroup,
        // Only where there is a list beside it to drag out of - the same rule
        // the calendar's onPlanTask follows, for the same reason.
        onPark: _layout.splitsContent ? _parkDropped : null,
      );
    }
    if (s.showCollections) {
      return CollectionsView(
        collections: s.collections,
        fields: s.collectionFields,
        entries: s.collectionEntries,
        accent: ws,
        onSaveCollection: (existing, name, fields) =>
            s.saveCollection(existing: existing, name: name, fields: fields),
        onDeleteCollection: s.deleteCollection,
        onSaveEntry: (c, values, existing) =>
            s.saveEntry(c, values, existing: existing),
        onDeleteEntry: s.deleteEntry,
        onSetChecked: s.setEntryChecked,
        onBack: _toggleCollections,
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
        onBack: _toggleSession,
      );
    }
    if (s.showJournal) {
      // Captured now, not read inside the callback: the panel's last save can
      // run from its dispose, after a workspace switch has already moved
      // currentWorkspaceUuid on. See JournalView._saveDraftOnTheWayOut.
      final journalWorkspace = s.currentWorkspaceUuid;
      if (_startNewNote) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _startNewNote = false,
        );
      }
      return JournalView(
        startNew: _startNewNote,
        onFocusChanged: (focus) {
          if (_noteFocused == focus) return;
          setState(() => _noteFocused = focus);
        },
        onEditingChanged: (editing) {
          if (_noteEditing == editing) return;
          setState(() => _noteEditing = editing);
        },
        configured: s.journalConfigured,
        locked: s.journalLocked,
        items: s.journal,
        onSetup: s.setupJournalPassword,
        onUnlock: s.unlockJournal,
        onLock: s.lockJournal,
        onRemovePassword: s.removeJournalPassword,
        onSave: (title, body, existing) => existing == null
            ? s.addJournalEntry(title, body, workspaceUuid: journalWorkspace)
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
    await showAttachments(
      context,
      task: t,
      accent: s.workspaceColor,
      blobs: blobs,
      load: () => s.attachmentsFor(t),
      onAdd: (file) => s.attachFile(t, file),
      onRemove: s.removeAttachment,
      onLocate: s.locateAttachment,
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

  /// Park a task from its row - or move it to another workspace, which the
  /// same picker offers (see move_picker.dart). Creating a group from inside
  /// the picker parks straight into it, so the first park does not take two
  /// passes.
  Future<void> _parkTask(Task t, RelativeRect anchor) =>
      _moveTasks([t], anchor);

  /// The picker, for one task or a selection.
  Future<void> _moveTasks(List<Task> tasks, RelativeRect anchor) async {
    final here = s.currentWorkspaceUuid;
    if (tasks.isEmpty || here == null) return;
    final groups = await s.groupsByWorkspace();
    if (!mounted) return;
    final target = await showMovePicker(
      context,
      position: anchor,
      currentWorkspaceUuid: here,
      workspaces: s.moveTargets,
      groups: groups,
      onCreateGroup: () => _editGroup(null),
    );
    if (target == null || !mounted) return;
    _clearSelection();
    if (tasks.length == 1 && target.workspaceUuid == here) {
      // The one-row park path, which the shelf's own tests and the focus
      // bookkeeping already know.
      await s.parkTask(tasks.single, target.groupUuid!);
      return;
    }
    await s.moveTasks(
      tasks,
      workspaceUuid: target.workspaceUuid,
      groupUuid: target.groupUuid,
    );
  }

  /// Thoughts to any workspace's list or shelf, through the same picker a
  /// task is moved with. "New group…" in it creates a shelf in this workspace.
  Future<void> _moveThoughts(
    List<SideThought> thoughts,
    RelativeRect anchor,
  ) async {
    final here = s.currentWorkspaceUuid;
    if (thoughts.isEmpty || here == null) return;
    final groups = await s.groupsByWorkspace();
    if (!mounted) return;
    final target = await showMovePicker(
      context,
      position: anchor,
      currentWorkspaceUuid: here,
      workspaces: s.moveTargets,
      groups: groups,
      onCreateGroup: () => _editGroup(null),
      includeHereList: true,
    );
    if (target == null || !mounted) return;
    await s.moveThoughts(
      thoughts,
      workspaceUuid: target.workspaceUuid,
      groupUuid: target.groupUuid,
    );
  }

  // ------------------------------------------------------------ selection

  /// The tasks selected with Ctrl+click (or *Select* on touch), by uuid.
  ///
  /// Uuids for the same reason [_expandedTaskUuid] is one: the list is reloaded
  /// under this constantly. Anything no longer on the list simply drops out of
  /// [_selectedTasks], so a task completed on another device mid-selection is
  /// not acted on.
  final _selected = <String>{};

  /// The workspace the selection was made in. A selection is a set of rows on
  /// one list; switching lists ends it rather than carrying invisible rows
  /// along into the next.
  String? _selectedIn;

  List<Task> get _selectedTasks => _selectedIn != s.currentWorkspaceUuid
      ? const []
      : [
          for (final t in s.tasks)
            if (_selected.contains(t.uuid)) t,
        ];

  void _toggleSelected(Task t) {
    setState(() {
      if (_selectedIn != s.currentWorkspaceUuid) _selected.clear();
      _selectedIn = s.currentWorkspaceUuid;
      if (!_selected.remove(t.uuid)) _selected.add(t.uuid);
    });
  }

  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(_selected.clear);
  }

  Future<void> _finishSelected({required bool complete}) async {
    final tasks = _selectedTasks;
    if (tasks.isEmpty) return;
    if (!complete) {
      final what = tasks.length == 1 ? 'this task' : '${tasks.length} tasks';
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: T.bgSolid,
          title: Text(
            'Delete $what?',
            style: const TextStyle(fontSize: T.fsMenu),
          ),
          content: const Text(
            'Removed without being logged to history.',
            style: TextStyle(fontSize: T.fsLabel, color: T.muted, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    _clearSelection();
    await s.finishTasks(tasks, complete: complete);
  }

  /// A task dropped on a shelf beside the list. If it was part of a selection
  /// the whole selection goes with it - dragging one of five selected rows and
  /// having only that one move would be a surprise every time.
  Future<void> _parkDropped(ParkedGroup g, Task t) async {
    final batch = _selected.contains(t.uuid) ? _selectedTasks : [t];
    _clearSelection();
    if (batch.length <= 1) {
      await s.parkTask(t, g.uuid);
    } else {
      await s.moveTasks(
        batch,
        workspaceUuid: g.workspaceUuid,
        groupUuid: g.uuid,
      );
    }
  }

  // ------------------------------------------------------------- composer

  /// The long form, from the add card. Ctrl+D and the ⤢ both land here.
  ///
  /// The card's title (keywords taken out) and settings are carried over - a
  /// shortcut that cost you what you had already set would not be worth
  /// pressing - and the card is only emptied once the composer actually
  /// produced a task, so cancelling leaves it exactly as it was.
  Future<bool> _openComposer(CaptureResult r) async {
    final target = r.workspaceUuid == null
        ? null
        : s.workspaces.where((w) => w.uuid == r.workspaceUuid).firstOrNull;
    final draft = await showTaskComposer(
      context,
      initialText: r.title,
      initialPriority: r.priority,
      initialRemindAt: r.remindAt,
      accent: target == null ? s.workspaceColor : T.parseHex(target.color),
    );
    if (draft == null || !mounted) return false;
    _closeAdd();
    await s.addTask(
      draft.text,
      workspaceUuid: target?.uuid,
      notes: draft.notes,
      priority: draft.priority,
      remindAt: draft.remindAt,
      recur: draft.repeat.recur,
      recurFrom: draft.repeat.from,
      recurLead: draft.repeat.lead,
    );
    return true;
  }

  /// The same form on a task that already exists, opened from its own text.
  Future<void> _openTask(Task t) async {
    final draft = await showTaskComposer(
      context,
      existing: t,
      accent: s.workspaceColor,
    );
    if (draft == null || !mounted) return;
    await s.saveTaskDetails(
      t,
      text: draft.text,
      notes: draft.notes,
      priority: draft.priority,
      remindAt: draft.remindAt,
      recur: draft.repeat.recur,
      recurFrom: draft.repeat.from,
      recurLead: draft.repeat.lead,
    );
  }

  /// The add card, folded: one line at the head of the list saying a task can
  /// be added here. Pressed, the card lifts off from it (ui/task_capture.dart)
  /// and lands back on it when it closes.
  ///
  /// The dock's ＋, a click on its workspace and N are ways in too, but they
  /// are not where the task will appear, and a shortcut is only a way in
  /// once you know it. Adding a task is the commonest thing done in this app,
  /// so the way to do it is on the list itself. A closed card keeps its
  /// draft, and this line shows it, so nothing half-typed is out of sight.
  Widget _addPrompt(Color ws) {
    final draft = _addController.text.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s2, T.s1, T.s2, T.s1),
      child: Opacity(
        // The card is this line, lifted off; drawing both would be two.
        opacity: _addCardShown ? 0 : 1,
        child: Semantics(
          button: true,
          label: draft.isEmpty ? 'Add a task' : 'Continue: $draft',
          child: InkWell(
            key: _addPromptKey,
            onTap: _openAdd,
            borderRadius: BorderRadius.circular(T.radius),
            child: Padding(
              padding: const EdgeInsets.all(T.s2),
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 16, color: ws),
                  const SizedBox(width: T.s2),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        draft.isEmpty ? 'Add a task' : draft,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: T.fsBody,
                          color: draft.isEmpty ? T.muted : T.text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The list's title: the workspace's name, or inside a project the
  /// project's, with the way back to its workspace and its menu.
  Widget _listHeader(Color ws) {
    final p = s.currentProject;
    final count = s.tasks.isEmpty ? null : s.tasks.length;
    if (p == null) {
      return PanelHeader(
        title: s.currentWorkspace?.name ?? 'Tasks',
        color: ws,
        count: count,
      );
    }
    final parent = s.homeWorkspace;
    return PanelHeader(
      title: p.name,
      color: ws,
      count: count,
      onBack: _leaveProject,
      backTooltip: 'Back to ${parent?.name ?? 'the workspace'} (Esc)',
      actions: [
        // The journal's header buttons' size, so the list starts where a
        // workspace's does.
        Tooltip(
          message: 'Project',
          child: InkWell(
            key: _projectMenuKey,
            borderRadius: BorderRadius.circular(T.radius),
            onTap: () async {
              final a = await showProjectMenu(context, anchor: _projectMenuKey);
              if (a != null) await _projectAction(p, a);
            },
            child: const Padding(
              padding: EdgeInsets.all(T.s1),
              child: Icon(Icons.more_horiz_rounded, size: 16, color: T.muted),
            ),
          ),
        ),
      ],
    );
  }

  final _projectMenuKey = GlobalKey();

  Widget _projectRow(Workspace p, int i, Color ws) {
    return KeyedSubtree(
      key: ValueKey(p.uuid),
      child: _layout.touch
          ? ReorderableDelayedDragStartListener(
              index: i,
              child: _projectTile(p, ws, null),
            )
          : _projectTile(
              p,
              ws,
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.drag_indicator, size: 14, color: T.muted),
                ),
              ),
            ),
    );
  }

  Widget _projectTile(Workspace p, Color ws, Widget? handle) => ProjectRow(
    project: p,
    accent: ws,
    openCount: s.projectOpenCounts[p.uuid] ?? 0,
    onOpen: () => _openProject(p),
    onAction: (a) => _projectAction(p, a),
    dragHandle: handle,
  );

  Future<void> _openProject(Workspace p) async {
    _clearSelection();
    await s.selectWorkspace(p.uuid);
  }

  Future<void> _leaveProject() async {
    final parent = s.currentProject?.parentUuid;
    if (parent == null) return;
    _clearSelection();
    await s.selectWorkspace(parent);
  }

  Future<void> _projectAction(Workspace p, ProjectAction a) async {
    switch (a) {
      case ProjectAction.open:
        await _openProject(p);
      case ProjectAction.rename:
        final name = await askProjectName(
          context,
          accent: s.colorOf(p),
          initial: p.name,
        );
        if (name != null) await s.renameProject(p, name);
      case ProjectAction.archive:
        // Not confirmed: Settings' archive gives it back as it was.
        await s.archiveProject(p);
      case ProjectAction.delete:
        if (!await confirmDeleteProject(context, p)) return;
        await s.deleteWorkspace(p.uuid);
    }
  }

  Widget _activeView(Color ws) {
    final rows = s.listRows;
    if (rows.isEmpty) {
      return Center(
        child: Text(
          s.currentProject != null
              ? 'Nothing in it yet.'
              : 'Nothing left. Nice. ✨',
          style: const TextStyle(color: T.muted, fontSize: T.fsLabel),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: T.s2),
      buildDefaultDragHandles: false,
      itemCount: rows.length,
      // onReorderItem (unlike the deprecated onReorder) already accounts for
      // the removed item, so newIndex needs no adjustment here. Projects and
      // tasks share one order (see AppState.listRows).
      onReorderItem: (oldIndex, newIndex) async {
        final order = [...rows];
        order.insert(newIndex, order.removeAt(oldIndex));
        await s.reorder([
          for (final r in order) r is Task ? r.uuid : (r as Workspace).uuid,
        ]);
      },
      itemBuilder: (context, i) {
        final r = rows[i];
        if (r is Workspace) return _projectRow(r, i, ws);
        final t = r as Task;
        final key = _rowKeys.putIfAbsent(t.uuid, () => GlobalKey());
        final row = _plannable(
          t,
          ws,
          TaskRow(
            key: key,
            task: t,
            accent: ws,
            // No rule against a project's block: the block is its own edge.
            divider: i < rows.length - 1 && rows[i + 1] is Task,
            onComplete: () => s.completeTask(t),
            onDelete: () => s.deleteTask(t),
            onFocus: () => _startFocus(t),
            onSetReminder: (at) => s.setReminder(t, at),
            onPark: (anchor) => _parkTask(t, anchor),
            // One level only: a project's tasks cannot become projects.
            onMakeProject: s.currentProject != null
                ? null
                : () => s.taskToProject(t),
            // Only ever offered on a task that *is* planned, where the row also
            // draws the mark saying so - the list is otherwise unchanged by
            // planning.
            onUnplan: () => s.setTaskEvent(t, null),
            // No blob store means nowhere to put the bytes (the browser
            // build), so no paperclip rather than a sheet that cannot add.
            onOpenAttachments: s.blobs == null
                ? null
                : () => _openAttachments(t),
            onSetPriority: (high) => s.setPriority(t, high),
            onOpen: () => _openTask(t),
            // Null under a pointer, which is how the row knows to expand
            // inside itself instead - see [_expandsToScreen].
            onExpand: _expandsToScreen ? () => _expandTask(t) : null,
            attachmentCount: s.attachmentCounts[t.uuid] ?? 0,
            selected:
                _selected.contains(t.uuid) &&
                _selectedIn == s.currentWorkspaceUuid,
            selecting: _selectedTasks.isNotEmpty,
            onToggleSelect: () => _toggleSelected(t),
            // On the right, and only where there is a pointer to aim it with.
            // A finger picks the row up by pressing and holding it, so the
            // six-dot glyph would be a permanent mark for a gesture that needs
            // no target - and it was sitting where it pushed the title of every
            // row in the list inwards.
            dragHandle: _layout.touch
                ? null
                : ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 14,
                        color: T.muted,
                      ),
                    ),
                  ),
          ),
        );

        return KeyedSubtree(
          key: ValueKey(t.uuid),
          // The whole row is the grip on touch. Safe to take the long press
          // here: the row's own gestures are a tap (which opens the action
          // bar) and, where there is something beside the list, a *horizontal*
          // drag - and that one never happens on a screen this narrow.
          child: _layout.touch
              ? ReorderableDelayedDragStartListener(index: i, child: row)
              : row,
        );
      },
    );
  }

  /// A row that can be dragged onto whatever is open beside the list - a
  /// calendar block ("do this then") or a parked group ("not now") - or the row
  /// itself, untouched, when there is nothing beside it.
  ///
  /// One `Draggable` for both, because the drag is one gesture: what it means
  /// is decided by where it is let go, and the two targets can never be on
  /// screen at once (the calendar replaces the content area the parked panel
  /// lives in). Whether it is offered at all is a question about *layout*,
  /// which is why it is answered here rather than in either panel.
  ///
  /// `affinity: horizontal` is what keeps this out of the list's way: a
  /// vertical drag still scrolls and the ≡ handle still reorders, while a drag
  /// *sideways* is the one gesture that means "put this over there". Nothing
  /// here fires on a phone, where nothing is ever side by side.
  Widget _plannable(Task t, Color ws, Widget row) {
    final toCalendar = s.showCalendar && _layout.splitsCalendar;
    final toGroup = s.showParked && _layout.splitsContent;
    if (!toCalendar && !toGroup) return row;
    return Draggable<Task>(
      data: t,
      affinity: Axis.horizontal,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: TaskDragFeedback(task: t, accent: ws),
      childWhenDragging: Opacity(opacity: 0.35, child: row),
      child: row,
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
                    style: TextStyle(color: T.muted, fontSize: T.fsLabel),
                  ),
                )
              : ListView.builder(
                  itemCount: s.historyTasks.length,
                  itemBuilder: (context, i) {
                    final t = s.historyTasks[i];
                    // The same row shape as the list it came from - content
                    // at T.s4, a rule between - minus the strike-through:
                    // everything in History is done, so crossing each one out
                    // said the one thing the title already says, on every row.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (i > 0) const ListRule(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            T.s4,
                            T.s3,
                            T.s4,
                            T.s3,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  t.text,
                                  style: const TextStyle(
                                    fontSize: T.fsBody,
                                    color: T.muted,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              // The only place a repeat with no open
                              // occurrence can be reached. A
                              // completion-anchored task is invisible between
                              // being ticked and coming back, and a scheduled
                              // one is invisible until its lead - so without
                              // this the way to stop a repeat would be to wait
                              // for it to come round again.
                              if (t.recur != null) _stopRepeatingButton(t),
                              const SizedBox(width: T.s2),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  _formatWhen(t.completedAt),
                                  style: const TextStyle(
                                    fontSize: T.fsMeta,
                                    color: T.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// The ↻ on a completed repeating task, and what it offers.
  ///
  /// It says the rule as well as being the way out of it - a row in History
  /// that is going to produce another one should say so, and "Every month" is
  /// the whole explanation of why this task keeps coming back.
  Widget _stopRepeatingButton(Task t) {
    return Tooltip(
      message: '${Recur.label(t.recur!)} - stop repeating',
      child: InkWell(
        onTap: () => _confirmStopRepeating(t),
        borderRadius: BorderRadius.circular(T.radius),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: T.s1, vertical: 2),
          child: Icon(Icons.repeat_rounded, size: 13, color: T.muted),
        ),
      ),
    );
  }

  Future<void> _confirmStopRepeating(Task t) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: T.bgSolid,
        title: const Text(
          'Stop repeating?',
          style: TextStyle(fontSize: T.fsMenu),
        ),
        content: Text(
          '"${t.text}" repeats ${Recur.label(t.recur!).toLowerCase()}. '
          'Stopping it leaves this one in history exactly as it is; no more '
          'will be created.',
          style: const TextStyle(
            fontSize: T.fsLabel,
            color: T.muted,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (yes == true) await s.stopRepeating(t);
  }

  static String _formatWhen(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
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
              NudgeBob(active: s.nudgeEnabled, child: _tile(t.text, ws, 20)),
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
                          style: const TextStyle(fontSize: T.fsLabel),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Park a thought…',
                            filled: true,
                            fillColor: T.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(T.radius),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(T.radius),
                              borderSide: BorderSide(
                                color: ws.withValues(alpha: 0.6),
                              ),
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
                        style: const TextStyle(fontSize: T.fsLabel),
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
                    fontSize: T.fsMeta,
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
        // Grows out of the row's own body size into the one display size in
        // the app - focus mode is one task and a whole window, so it is the
        // one place a fifth size earns itself.
        const focused = 20.0;
        final fontSize = T.fsBody + (focused - T.fsBody) * v;
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
      padding: const EdgeInsets.all(T.s4),
      decoration: BoxDecoration(
        color: Color.lerp(T.bgSolid, ws, 0.22),
        borderRadius: BorderRadius.circular(T.radius),
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
          fontWeight: T.wMedium,
          color: T.text,
          height: 1.3,
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
      shortcuts: result.shortcuts,
    );
  }
}
