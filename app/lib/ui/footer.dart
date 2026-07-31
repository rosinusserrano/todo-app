// Side thoughts and the pressure meter.
//
// Side thoughts are global: one pile, seen from every workspace, and switching
// workspace does not clear it or hide it. Switching used to be *blocked* while
// thoughts were pending, which is what made the pile impossible to ignore. That
// block is gone - it punished the wrong action, since moving between workspaces
// is not what lets a thought rot - so the bar itself now has to carry the whole
// signal, and the escalation below is tuned harder than it was:
//
//   1  thought   the bar starts tinting at all
//   4           it begins to pulse
//   12          full intensity, fastest pulse, and the count is boxed in the
//               alarm colour rather than merely coloured by it
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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sync/models.dart';
import '../theme.dart';

class ThoughtFooter extends StatefulWidget {
  const ThoughtFooter({
    super.key,
    required this.thoughts,
    required this.workspaceColor,
    required this.blockedMessage,
    required this.onAdd,
    required this.listOpen,
    required this.onToggleList,
  });

  final List<SideThought> thoughts;
  final Color workspaceColor;

  /// Whether [ThoughtsPanel] currently owns the content area, so the count
  /// badge can show itself as the pressed control it is.
  final bool listOpen;
  final VoidCallback onToggleList;

  /// Non-null while a close or workspace switch has just been refused. Drives
  /// the shake and the explanatory text.
  final String? blockedMessage;

  final Future<void> Function(String text) onAdd;

  @override
  State<ThoughtFooter> createState() => ThoughtFooterState();
}

class ThoughtFooterState extends State<ThoughtFooter>
    with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _expanded = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  int get _count => widget.thoughts.length;

  /// Where the escalation tops out, and where it starts to move. Both were
  /// roughly twice this before the workspace-switch block was removed; the bar
  /// is now the only thing saying anything, so it has to say it sooner.
  static const _peak = 12;
  static const _pulseFrom = 4;

  /// 0 at empty, 1 at [_peak] pending thoughts.
  double get _intensity => math.min(_count / _peak, 1);

  bool get _pulsing => _count >= _pulseFrom;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(ThoughtFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
    if (widget.blockedMessage != null && oldWidget.blockedMessage == null) {
      _shake.forward(from: 0);
    }
  }

  /// Pulse speeds up from ~1.8s at [_pulseFrom] thoughts to 0.5s at [_peak].
  void _syncPulse() {
    if (_pulsing) {
      final span = (_peak - _pulseFrom).toDouble();
      final t = math.min((_count - _pulseFrom) / span, 1);
      final next = Duration(milliseconds: (1800 - 1300 * t).round());
      if (_pulse.duration != next) {
        _pulse.duration = next;
        if (_pulse.isAnimating) _pulse.repeat(reverse: true);
      }
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
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

  @override
  Widget build(BuildContext context) {
    final alarm = T.complementary(widget.workspaceColor);

    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _shake]),
      builder: (context, child) {
        final glow = Curves.easeInOut.transform(_pulse.value);
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
          fontSize: 11.5,
          color: alarm,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (_count == 0) return const SizedBox.shrink();

    // The count escalates with the pile rather than staying muted: it is the
    // number that matters, so it should get harder to read past as it grows.
    final hot = _intensity;
    final fill = widget.listOpen
        ? widget.workspaceColor.withValues(alpha: 0.25)
        : alarm.withValues(alpha: hot * 0.28);

    return Tooltip(
      message: widget.listOpen ? 'Back to tasks' : 'Review parked thoughts',
      child: InkWell(
        onTap: widget.onToggleList,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: widget.listOpen
                  ? Colors.transparent
                  : alarm.withValues(alpha: hot * 0.7),
            ),
          ),
          child: Text(
            '💭 $_count',
            style: TextStyle(
              fontSize: 11.5 + hot * 1.5,
              color: widget.listOpen
                  ? T.text
                  : Color.lerp(T.muted, alarm, hot),
              fontWeight: widget.listOpen || hot > 0.5
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(Color alarm) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Row(
        children: [
          Tooltip(
            message: 'Capture a side thought',
            child: InkWell(
              onTap: () {
                setState(() => _expanded = !_expanded);
                if (_expanded) _focus.requestFocus();
              },
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Text('💭', style: TextStyle(fontSize: 15)),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        style: const TextStyle(fontSize: 12.5),
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
  });

  final List<SideThought> thoughts;
  final Future<void> Function(SideThought) onPromote;
  final Future<void> Function(SideThought) onDiscard;

  @override
  State<ThoughtsPanel> createState() => _ThoughtsPanelState();
}

class _ThoughtsPanelState extends State<ThoughtsPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);

    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curve),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 2, 14, 6),
              child: Text(
                'Parked thoughts',
                style: TextStyle(
                  fontSize: 12,
                  color: T.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final t in widget.thoughts)
                    _ThoughtTile(
                      thought: t,
                      onPromote: () => widget.onPromote(t),
                      onDiscard: () => widget.onDiscard(t),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThoughtTile extends StatelessWidget {
  const _ThoughtTile({
    required this.thought,
    required this.onPromote,
    required this.onDiscard,
  });

  final SideThought thought;
  final VoidCallback onPromote;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              thought.text,
              style: const TextStyle(fontSize: 12, color: T.muted),
            ),
          ),
          Tooltip(
            message: 'Turn into a task',
            child: InkWell(
              onTap: onPromote,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_upward_rounded, size: 14, color: T.muted),
              ),
            ),
          ),
          Tooltip(
            message: 'Throw it away',
            child: InkWell(
              onTap: onDiscard,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.close_rounded, size: 14, color: T.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
