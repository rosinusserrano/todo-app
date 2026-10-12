// Side thoughts and the pressure meter.
//
// Side thoughts are global: one pile, seen from every workspace, and switching
// workspace does not clear it or hide it. Switching used to be *blocked* while
// thoughts were pending, which is what made the pile impossible to ignore. That
// block is gone - it punished the wrong action, since moving between workspaces
// is not what lets a thought rot - so the control has to carry the whole
// signal, and the escalation is tuned harder than it was. The numbers live in
// thought_pressure.dart, because the phone's [ViewBar] runs the same one.
//
// The alarm colour is the complement of the active workspace colour, so it
// always reads against the window tint rather than blending into it.
//
// The footer is only ever the bar. The thoughts themselves live in
// [ThoughtsPanel], which takes over the content area on demand - a parked
// thought is something you review deliberately, not a list that should be
// eating room above the tasks the whole time.
//
// The bar carries two 💭 controls and they do different jobs: the one on the
// left opens the capture field, the count on the right opens the panel.
//
// On a phone it carries neither, and draws nothing at all. Both were at the
// wrong end of the screen - a strip *below* the view bar, furthest from the
// hand, for the control used in the biggest hurry - and both moved onto
// [ViewBar], where the thumb already is: the pile is its fourth entry, a swipe
// up on it writes a thought, and the whole bar carries the escalation. What is left of this bar
// there is the refusal message, which is a desktop close guard and so never
// fires, and the field itself, which the desktop hotkey can still open.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout.dart';
import '../sync/models.dart';
import '../theme.dart';
import 'list_rule.dart';
import 'thought_pressure.dart';

class ThoughtFooter extends StatefulWidget {
  const ThoughtFooter({
    super.key,
    required this.thoughts,
    required this.accent,
    required this.blockedMessage,
    required this.onAdd,
    this.onCapture,
    this.showCaptureButton = true,
    this.showPressure = true,
    required this.listOpen,
    required this.onToggleList,
  });

  final List<SideThought> thoughts;

  /// [T.thoughts] in the app - the pile is global, see there.
  final Color accent;

  /// Whether [ThoughtsPanel] currently owns the content area, so the count
  /// badge can show itself as the pressed control it is.
  final bool listOpen;
  final VoidCallback onToggleList;

  /// Non-null while a close or workspace switch has just been refused. Drives
  /// the shake and the explanatory text.
  final String? blockedMessage;

  final Future<void> Function(String text) onAdd;

  /// Non-null on touch: capturing takes over the screen instead of expanding
  /// this field in place. See ui/thought_sheet.dart - a phone is held in front
  /// of people, and the inline field leaves the whole task list on show behind
  /// the keyboard at exactly the moment somebody is watching you type.
  final VoidCallback? onCapture;

  /// False while [ViewBar] is on screen: a swipe up on it is then the way in,
  /// and a 💭 down here would be two doors to one field. Deliberately separate from [onCapture], which says *how* capturing
  /// happens rather than whether this bar offers it - a tablet wide enough for
  /// the rail has no view bar and still wants the pane rather than the inline
  /// field.
  final bool showCaptureButton;

  /// Whether the meter and the count belong to this bar. False on a phone,
  /// where the view bar wears them: a strip along the bottom edge saying how many
  /// thoughts are waiting, under a bar that already says which view you are in,
  /// is the third row of chrome on the smallest screen there is - and it says
  /// it inches below a bar that could say it instead.
  ///
  /// With this and [showCaptureButton] both false the bar has nothing of its
  /// own left and takes no height at all.
  final bool showPressure;

  @override
  State<ThoughtFooter> createState() => ThoughtFooterState();
}

class ThoughtFooterState extends State<ThoughtFooter>
    with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _expanded = false;

  late final ThoughtPulse _pulse = ThoughtPulse(this);
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// The pile as this bar shows it: nothing at all while the meter belongs to
  /// the view bar, so the tint, the pulse and the count are drawn once.
  int get _count => widget.showPressure ? widget.thoughts.length : 0;

  double get _intensity => ThoughtPulse.intensityOf(_count);

  bool get _pulsing => ThoughtPulse.pulsingAt(_count);

  @override
  void initState() {
    super.initState();
    _pulse.sync(_count);
  }

  @override
  void didUpdateWidget(ThoughtFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pulse.sync(_count);
    if (widget.blockedMessage != null && oldWidget.blockedMessage == null) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _pulse.dispose();
    _shake.dispose();
    super.dispose();
  }

  /// Opens the field and puts the caret in it. Used by the global shortcut.
  void openAndFocus() {
    setState(() => _expanded = true);
    _focus.requestFocus();
  }

  Future<void> _submit({required bool chain}) async {
    final text = _controller.text.trim();
    _controller.clear();
    if (text.isEmpty) {
      setState(() => _expanded = false);
      return;
    }
    await widget.onAdd(text);
    if (!mounted) return;
    // Ctrl+Enter keeps the field open for chaining; plain Enter collapses it.
    if (chain) {
      _focus.requestFocus();
    } else {
      setState(() => _expanded = false);
    }
  }

  /// Nothing to draw: the view bar owns both the way in and the pile, and no
  /// refusal is being explained. Returning early rather than drawing a 36px
  /// strip of nothing above the home indicator.
  /// [_expanded] is in there because the field can be opened from outside
  /// ([openAndFocus], the global shortcut): a bar that hid the field it was
  /// just told to focus would swallow the keystroke.
  bool get _silent =>
      !widget.showCaptureButton &&
      !widget.showPressure &&
      !_expanded &&
      widget.blockedMessage == null;

  @override
  Widget build(BuildContext context) {
    if (_silent) return const SizedBox.shrink();

    final alarm = T.complementary(widget.accent);

    return AnimatedBuilder(
      animation: Listenable.merge([_pulse.controller, _shake]),
      builder: (context, child) {
        final glow = Curves.easeInOut.transform(_pulse.controller.value);
        return Transform.translate(
          offset: Offset(_shakeOffset(), 0),
          child: Container(
            decoration: BoxDecoration(
              color: alarm.withValues(alpha: _intensity * 0.22),
              // A hairline along the top edge as well as the glow. The glow
              // alone reads as a soft shadow against an acrylic background;
              // the line is what makes the bar a distinct object sitting
              // under the list.
              border: Border(
                top: BorderSide(
                  color: alarm.withValues(alpha: _intensity * 0.55),
                  width: _count == 0 ? 0 : 1,
                ),
              ),
              boxShadow: [
                if (_pulsing)
                  BoxShadow(
                    color: alarm.withValues(alpha: glow * _intensity * 0.95),
                    blurRadius: 18,
                    offset: const Offset(0, -3),
                  ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: _bar(alarm),
    );
  }

  /// Damped shake, mirroring the thought-shake keyframes.
  double _shakeOffset() {
    if (!_shake.isAnimating) return 0;
    final t = _shake.value;
    if (t > 0.25) return 0;
    return math.sin(t * math.pi * 8) * 4 * (1 - t * 4);
  }

  /// The count on the right, and the way into the panel. A refusal message
  /// takes the same slot but is deliberately not a button: the bar is shaking
  /// and red at that moment, and offering something to press there would read
  /// as "click here to fix it".
  Widget _countBadge(Color alarm) {
    if (widget.blockedMessage != null) {
      return Text(
        widget.blockedMessage!,
        style: TextStyle(
          fontSize: T.fsMeta,
          color: alarm,
          fontWeight: T.wMedium,
        ),
      );
    }
    if (_count == 0) return const SizedBox.shrink();

    // The count escalates with the pile rather than staying muted: it is the
    // number that matters, so it should get harder to read past as it grows.
    final hot = _intensity;
    final fill = widget.listOpen
        ? widget.accent.withValues(alpha: 0.25)
        : alarm.withValues(alpha: hot * 0.28);

    return Tooltip(
      message: widget.listOpen ? 'Back to tasks' : 'Review parked thoughts',
      child: InkWell(
        onTap: widget.onToggleList,
        borderRadius: BorderRadius.circular(T.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: 3),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(T.radius),
            border: Border.all(
              color: widget.listOpen
                  ? Colors.transparent
                  : alarm.withValues(alpha: hot * 0.7),
            ),
          ),
          child: Text(
            '💭 $_count',
            style: TextStyle(
              fontSize: T.fsMeta + hot * 1.5,
              color: widget.listOpen ? T.text : Color.lerp(T.muted, alarm, hot),
              fontWeight: widget.listOpen || hot > 0.5 ? T.wMedium : T.wNormal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(Color alarm) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s2, T.s2, T.s2, T.s2),
      child: Row(
        children: [
          if (widget.showCaptureButton)
            Tooltip(
              message: 'Capture a side thought',
              child: InkWell(
                onTap: () {
                  final capture = widget.onCapture;
                  if (capture != null) {
                    capture();
                    return;
                  }
                  setState(() => _expanded = !_expanded);
                  if (_expanded) _focus.requestFocus();
                },
                borderRadius: BorderRadius.circular(T.radius),
                child: const Padding(
                  padding: EdgeInsets.all(T.s1),
                  child: Text('💭', style: TextStyle(fontSize: T.fsMenu)),
                ),
              ),
            ),
          Expanded(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: T.s2),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        style: const TextStyle(fontSize: T.fsLabel),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Side thought…',
                          border: InputBorder.none,
                        ),
                        // Ctrl+Enter chains another entry, plain Enter
                        // collapses the field - same as the original.
                        onSubmitted: (_) => _submit(
                          chain: HardwareKeyboard.instance.isControlPressed,
                        ),
                        onTapOutside: (_) {
                          if (_controller.text.trim().isEmpty) {
                            setState(() => _expanded = false);
                          }
                        },
                      ),
                    )
                  : const SizedBox(height: 22),
            ),
          ),
          _countBadge(alarm),
        ],
      ),
    );
  }
}

/// The parked thoughts, taking over the content area in place of the tasks.
///
/// It slides up from the footer it was opened from rather than simply
/// appearing, so it reads as the bar expanding upwards - the thoughts come from
/// down there, and the movement says so.
class ThoughtsPanel extends StatefulWidget {
  const ThoughtsPanel({
    super.key,
    required this.thoughts,
    required this.onPromote,
    required this.onDiscard,
    this.onMove,
  });

  final List<SideThought> thoughts;
  final Future<void> Function(SideThought) onPromote;
  final Future<void> Function(SideThought) onDiscard;

  /// Send one or several thoughts to any workspace's list or shelf, picked
  /// from a menu anchored at the given rect. Null hides the move controls.
  final Future<void> Function(List<SideThought>, RelativeRect anchor)? onMove;

  @override
  State<ThoughtsPanel> createState() => _ThoughtsPanelState();
}

/// Selecting works the way it does on the task list: Ctrl+click toggles a
/// thought (a long press, on touch), and once anything is selected a plain
/// click toggles too. The header then becomes the bar that acts on the
/// selection. Held as uuids and read through [ThoughtsPanel.thoughts], so a
/// thought resolved elsewhere simply drops out of it.
class _ThoughtsPanelState extends State<ThoughtsPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  final _selected = <String>{};

  List<SideThought> get _selection => [
    for (final t in widget.thoughts)
      if (_selected.contains(t.uuid)) t,
  ];

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  void _toggle(SideThought t) {
    setState(() {
      if (!_selected.remove(t.uuid)) _selected.add(t.uuid);
    });
  }

  void _clear() => setState(_selected.clear);

  static RelativeRect _anchor(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return RelativeRect.fill;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    return RelativeRect.fromRect(
      Rect.fromLTWH(rect.left, rect.bottom, rect.width, 0),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _moveSelection(BuildContext anchorContext) async {
    final move = widget.onMove;
    final picked = _selection;
    if (move == null || picked.isEmpty) return;
    await move(picked, _anchor(anchorContext));
    if (mounted) _clear();
  }

  Future<void> _discardSelection() async {
    final picked = _selection;
    if (picked.isEmpty) return;
    _clear();
    for (final t in picked) {
      await widget.onDiscard(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
    final layout = Layout.of(context);
    final selection = _selection;

    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curve),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selection.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(T.s3, 2, T.s3, T.s2),
                child: Text(
                  'Parked thoughts',
                  style: TextStyle(
                    fontSize: T.fsLabel,
                    color: T.muted,
                    fontWeight: T.wMedium,
                  ),
                ),
              )
            else
              _selectionBar(selection.length, layout),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: T.s2),
                children: [
                  for (final (i, t) in widget.thoughts.indexed) ...[
                    if (i > 0) const ListRule(),
                    _ThoughtTile(
                      thought: t,
                      selected: _selected.contains(t.uuid),
                      selecting: _selected.isNotEmpty,
                      onToggleSelect: () => _toggle(t),
                      onPromote: () => widget.onPromote(t),
                      onMove: widget.onMove == null
                          ? null
                          : (anchor) => widget.onMove!([t], anchor),
                      onDiscard: () => widget.onDiscard(t),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionBar(int count, Layout layout) {
    final size = layout.actionIcon;
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s3, 0, T.s2, T.s1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count selected',
              style: const TextStyle(
                fontSize: T.fsBody,
                color: T.text,
                fontWeight: T.wMedium,
              ),
            ),
          ),
          if (widget.onMove != null)
            Builder(
              builder: (context) => _ThoughtButton(
                icon: Icons.drive_file_move_outline,
                tooltip: 'Move to a list or shelf',
                size: size,
                side: layout.tapTarget,
                onTap: () => _moveSelection(context),
              ),
            ),
          _ThoughtButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Throw them away',
            size: size,
            side: layout.tapTarget,
            color: T.danger,
            onTap: _discardSelection,
          ),
          _ThoughtButton(
            icon: Icons.close_rounded,
            tooltip: 'Clear the selection',
            size: size,
            side: layout.tapTarget,
            onTap: _clear,
          ),
        ],
      ),
    );
  }
}

/// One square, finger-sized where fingers are: the thought tile's controls
/// used to be 14px glyphs with a few pixels of padding, which on a phone is a
/// control you aim at twice.
class _ThoughtButton extends StatelessWidget {
  const _ThoughtButton({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.side,
    required this.onTap,
    this.color = T.muted,
  });

  final IconData icon;
  final String tooltip;
  final double size;
  final double side;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.radius),
        child: SizedBox(
          width: side,
          height: side,
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

class _ThoughtTile extends StatelessWidget {
  const _ThoughtTile({
    required this.thought,
    required this.selected,
    required this.selecting,
    required this.onToggleSelect,
    required this.onPromote,
    required this.onMove,
    required this.onDiscard,
  });

  final SideThought thought;
  final bool selected;

  /// Something is selected, so a plain click toggles rather than doing nothing.
  final bool selecting;
  final VoidCallback onToggleSelect;
  final VoidCallback onPromote;
  final ValueChanged<RelativeRect>? onMove;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.actionIcon;

    // Filled only when selected - see list_rule.dart.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? T.thoughts.withValues(alpha: 0.18)
            : Colors.transparent,
        child: InkWell(
          onTap: () {
            if (selecting || HardwareKeyboard.instance.isControlPressed) {
              onToggleSelect();
            }
          },
          onLongPress: onToggleSelect,
          child: Padding(
            padding: const EdgeInsets.only(left: T.s2),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: T.s2),
                    child: Text(
                      thought.text,
                      style: const TextStyle(fontSize: T.fsBody, color: T.text),
                    ),
                  ),
                ),
                if (!selecting) ...[
                  _ThoughtButton(
                    icon: Icons.arrow_upward_rounded,
                    tooltip: 'Turn into a task here',
                    size: size,
                    side: layout.tapTarget,
                    onTap: onPromote,
                  ),
                  if (onMove != null)
                    Builder(
                      builder: (context) => _ThoughtButton(
                        icon: Icons.drive_file_move_outline,
                        tooltip: 'Move to a list or shelf',
                        size: size,
                        side: layout.tapTarget,
                        onTap: () =>
                            onMove!(_ThoughtsPanelState._anchor(context)),
                      ),
                    ),
                  _ThoughtButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Throw it away',
                    size: size,
                    side: layout.tapTarget,
                    color: T.danger,
                    onTap: onDiscard,
                  ),
                ] else
                  SizedBox(
                    width: layout.tapTarget,
                    height: layout.tapTarget,
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: size,
                      color: selected ? T.thoughts : T.muted,
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
