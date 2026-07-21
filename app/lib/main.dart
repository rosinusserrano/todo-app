// Todo Widget - Flutter client.
//
// Ported from the Tauri build (src/main.ts + src/styles.css). The window
// behaviour is the part that is not allowed to regress on Windows: frameless,
// transparent, acrylic, and always on top *while unfocused*.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'shortcuts.dart';
import 'sync/local_store.dart';
import 'sync/models.dart';
import 'sync/sync_service.dart';
import 'theme.dart';
import 'ui/footer.dart';
import 'ui/settings_dialog.dart';
import 'ui/task_row.dart';
import 'ui/title_bar.dart';
import 'ui/workspace_bar.dart';

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  final state = AppState(store);
  await state.load();

  // Sync pulls the UI, not the other way round: a merge that brings rows in
  // has to refresh whatever is on screen, or the user sees stale lists until
  // they happen to switch workspace.
  final sync = SyncService(
    store,
    onChangesApplied: () async {
      await state.refreshWorkspaces();
      await state.refreshTasks();
      await state.refreshThoughts();
    },
  );
  state.onMutated = sync.scheduleSync;
  await sync.load();

  runApp(TodoApp(state: state, sync: sync));
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key, required this.state, required this.sync});

  final AppState state;
  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: T.themeData(),
      home: WidgetShell(state: state, sync: sync),
    );
  }
}

/// Which stage of the focus transition we are in. The flight and the resting
/// state are distinct because the tile is absolutely positioned mid-flight and
/// handed back to normal layout once it lands.
enum _Focus { none, flyingIn, resting, flyingOut }

class WidgetShell extends StatefulWidget {
  const WidgetShell({super.key, required this.state, required this.sync});

  final AppState state;
  final SyncService sync;

  @override
  State<WidgetShell> createState() => _WidgetShellState();
}

class _WidgetShellState extends State<WidgetShell>
    with TickerProviderStateMixin, WindowListener {
  AppState get s => widget.state;

  final _addController = TextEditingController();
  final _addFocus = FocusNode();
  final _stackKey = GlobalKey();
  final _footerKey = GlobalKey<ThoughtFooterState>();

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
    if (isDesktop) windowManager.addListener(this);
    // A task left in progress at last close reopens straight into focus, with
    // no flight - there is no row for it to have flown from.
    if (s.focusTask != null) _phase = _Focus.resting;
    _registerShortcuts();
  }

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

  /// Raise the window, leave focus mode, and hand back control to the caller
  /// so it can put the caret where it wants it. Both capture fields sit behind
  /// the focus overlay, so jumping to either has to leave focus first.
  Future<bool> _surfaceForCapture() async {
    if (isDesktop) {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    }
    if (s.focusTask != null) await _exitFocus();
    return mounted;
  }

  Future<void> _jumpToAddTask() async {
    if (!await _surfaceForCapture()) return;
    if (s.showHistory) s.toggleHistory();
    _addFocus.requestFocus();
  }

  Future<void> _jumpToAddThought() async {
    if (!await _surfaceForCapture()) return;
    _footerKey.currentState?.openAndFocus();
  }

  @override
  void dispose() {
    s.removeListener(_onState);
    widget.sync.removeListener(_onState);
    _shortcuts.dispose();
    if (isDesktop) windowManager.removeListener(this);
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
    // The footer and its refusal flash live behind the focus overlay, so leave
    // focus before flashing or the message is invisible.
    if (s.focusTask != null) await _exitFocus();
    _flashBlocked();
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
  Rect _restingTileRect(Size size) {
    const margin = 24.0;
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
          // Esc is the quick way out of focus mode.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              s.focusTask != null) {
            _exitFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
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
            child: Stack(
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

                // Above the overlay, so the window stays draggable and
                // closable during focus mode.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: TitleBar(
                    isDesktop: isDesktop,
                    pinned: _pinned,
                    onTogglePin: _togglePin,
                    onToggleHistory: _toggleHistory,
                    onClose: () =>
                        isDesktop ? windowManager.close() : null,
                    onOpenSettings: _openSettings,
                    syncColor: _syncColor(),
                    syncTooltip: widget.sync.describe(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _togglePin() async {
    await windowManager.setAlwaysOnTop(!_pinned);
    final actual = await windowManager.isAlwaysOnTop();
    setState(() => _pinned = actual);
  }

  /// History sits behind the focus overlay, so the first press just leaves
  /// focus rather than revealing a view the user cannot see.
  void _toggleHistory() {
    if (s.focusTask != null) {
      _exitFocus();
      return;
    }
    s.toggleHistory();
  }

  Future<void> _openSettings() async {
    if (s.focusTask != null) await _exitFocus();
    if (!mounted) return;
    await showSyncSettings(context, widget.sync);
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
    return Column(
      children: [
        const SizedBox(height: TitleBar.height),
        WorkspaceBar(
          workspaces: s.workspaces,
          currentUuid: s.currentWorkspaceUuid,
          onSelect: (w) => _switchWorkspace(w),
          onEdit: (w) => _editWorkspace(w),
          onCreate: () => _editWorkspace(null),
        ),
        _addField(ws),
        Expanded(child: s.showHistory ? _historyView() : _activeView(ws)),
        ThoughtFooter(
          key: _footerKey,
          thoughts: s.thoughts,
          workspaceColor: ws,
          blockedMessage: _blockedMessage,
          onAdd: s.addThought,
          onPromote: s.promoteThought,
          onDiscard: s.resolveThought,
        ),
      ],
    );
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
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 2, 14, 6),
          child: Text(
            'Done recently',
            style: TextStyle(
              fontSize: 12,
              color: T.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
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
              NudgeBob(
                active: s.nudgeEnabled,
                child: _tile(t.text, ws, 20),
              ),
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    onPressed: _completeFromFocus,
                    child: const Text('✓ Done'),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: _exitFocus,
                    child: const Text('Back to list'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
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

  Future<void> _switchWorkspace(Workspace w) async {
    // Switching is blocked by pending thoughts for the same reason closing is.
    if (!await s.canProceedPastThoughts()) {
      _flashBlocked();
      return;
    }
    await s.selectWorkspace(w.uuid);
  }

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
