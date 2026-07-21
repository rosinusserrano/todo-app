// Side thoughts and the pressure meter.
//
// The bar reddens as pending thoughts pile up and starts pulsing at 10, faster
// the closer it gets to 20. The alarm colour is the complement of the active
// workspace colour, so it always reads against the window tint rather than
// blending into it.

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
    required this.onPromote,
    required this.onDiscard,
  });

  final List<SideThought> thoughts;
  final Color workspaceColor;

  /// Non-null while a close or workspace switch has just been refused. Drives
  /// the shake and the explanatory text.
  final String? blockedMessage;

  final Future<void> Function(String text) onAdd;
  final Future<void> Function(SideThought) onPromote;
  final Future<void> Function(SideThought) onDiscard;

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

  /// 0 at empty, 1 at 20 pending thoughts.
  double get _intensity => math.min(_count / 20, 1);

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

  /// Pulse speeds up from ~1.8s at 10 thoughts to 0.5s at 20 or more.
  void _syncPulse() {
    if (_count >= 10) {
      final secs = math.max(0.5, 1.8 - (_count - 10) * 0.13);
      final next = Duration(milliseconds: (secs * 1000).round());
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.thoughts.isNotEmpty)
          Flexible(
            child: ListView(
              shrinkWrap: true,
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
        AnimatedBuilder(
          animation: Listenable.merge([_pulse, _shake]),
          builder: (context, child) {
            final glow = Curves.easeInOut.transform(_pulse.value);
            return Transform.translate(
              offset: Offset(_shakeOffset(), 0),
              child: Container(
                decoration: BoxDecoration(
                  color: alarm.withValues(alpha: _intensity * 0.18),
                  boxShadow: [
                    if (_count >= 10)
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
        ),
      ],
    );
  }

  /// Damped shake, mirroring the thought-shake keyframes.
  double _shakeOffset() {
    if (!_shake.isAnimating) return 0;
    final t = _shake.value;
    if (t > 0.25) return 0;
    return math.sin(t * math.pi * 8) * 4 * (1 - t * 4);
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
          Text(
            widget.blockedMessage ?? (_count > 0 ? '💭 $_count' : ''),
            style: TextStyle(
              fontSize: 11.5,
              color: widget.blockedMessage != null ? alarm : T.muted,
              fontWeight: widget.blockedMessage != null
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
        ],
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
