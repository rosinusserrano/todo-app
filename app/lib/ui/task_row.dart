// A single task row, ported from .task in styles.css.
//
// The row animates its own removal. Checking the box does not immediately drop
// the row: it plays the slide-out first, then tells the app to persist and
// reload. That ordering is what made the original feel deliberate rather than
// twitchy, and keeping the animation inside the row means the duration lives in
// one place instead of being mirrored between CSS and a setTimeout.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';
import 'reminder_menu.dart';

class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.accent,
    required this.onComplete,
    required this.onDelete,
    required this.onFocus,
    this.onSetReminder,
    this.dragHandle,
  });

  final Task task;
  final Color accent;
  final Future<void> Function() onComplete;
  final Future<void> Function() onDelete;
  final VoidCallback onFocus;

  /// Null on the history list, where arming a reminder makes no sense.
  final Future<void> Function(DateTime?)? onSetReminder;
  final Widget? dragHandle;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> with SingleTickerProviderStateMixin {
  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: T.slideOutDur,
  );
  bool _hovered = false;
  final _bellKey = GlobalKey();

  @override
  void dispose() {
    _out.dispose();
    super.dispose();
  }

  /// Play the slide-out, then hand off. Awaiting the animation before the
  /// callback means the row is visually gone by the time the list rebuilds,
  /// so it never flickers back in for a frame.
  Future<void> _leave(Future<void> Function() action) async {
    await _out.forward();
    if (!mounted) return;
    await action();
  }

  /// Anchored to the bell rather than the pointer, so the menu appears in the
  /// same place whether it was opened by mouse or keyboard.
  Future<void> _openReminderMenu() async {
    final onSet = widget.onSetReminder;
    final box = _bellKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (onSet == null || box == null || overlay == null) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    await showReminderMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy + box.size.height,
        overlay.size.width - topLeft.dx,
        0,
      ),
      task: widget.task,
      onChosen: onSet,
    );
  }

  @override
  Widget build(BuildContext context) {
    final due = widget.task.isDue();
    final armed = widget.task.remindAtTime;

    return AnimatedBuilder(
      animation: _out,
      builder: (context, child) {
        final t = Curves.easeIn.transform(_out.value);
        return Opacity(
          // Fully transparent at the end, matching the slide-out keyframe.
          opacity: 1 - t,
          child: Transform.translate(
            offset: Offset(40 * t, 0),
            child: Align(
              heightFactor: 1 - t,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            // A due reminder outranks focus for the row's colour: focus is a
            // state you chose and can see, an overdue reminder is the thing
            // asking for attention.
            color: due
                ? T.danger.withValues(alpha: 0.14)
                : widget.task.inProgress
                    ? widget.accent.withValues(alpha: 0.16)
                    : (_hovered ? T.surfaceHover : T.surface),
            borderRadius: BorderRadius.circular(9),
            border: due
                ? Border.all(color: T.danger.withValues(alpha: 0.55))
                : widget.task.inProgress
                    ? Border.all(color: widget.accent.withValues(alpha: 0.5))
                    : null,
          ),
          child: Row(
            children: [
              if (widget.dragHandle != null) widget.dragHandle!,
              _Checkbox(
                accent: widget.accent,
                onChanged: () => _leave(widget.onComplete),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.task.text,
                  style: const TextStyle(fontSize: 13, color: T.text, height: 1.3),
                ),
              ),
              if (widget.onSetReminder != null)
                _IconAction(
                  key: _bellKey,
                  tooltip: armed == null
                      ? 'Remind me'
                      : 'Reminder ${describeReminder(armed)}',
                  icon: armed == null
                      ? Icons.notifications_none_rounded
                      : Icons.notifications_active_rounded,
                  color: due
                      ? T.danger
                      : (armed != null ? widget.accent : T.muted),
                  // An armed reminder stays visible without hovering: it is
                  // state the row is carrying, not an action offered on demand.
                  visible: _hovered || armed != null,
                  onPressed: _openReminderMenu,
                ),
              _IconAction(
                tooltip: 'Work on this — hides everything else',
                icon: Icons.play_arrow_rounded,
                color: widget.task.inProgress ? widget.accent : T.muted,
                visible: _hovered || widget.task.inProgress,
                onPressed: widget.onFocus,
              ),
              _IconAction(
                tooltip: "Delete (don't log)",
                icon: Icons.close_rounded,
                color: T.danger,
                visible: _hovered,
                onPressed: () => _leave(widget.onDelete),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.accent, required this.onChanged});

  final Color accent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Check off task',
      button: true,
      child: InkWell(
        onTap: onChanged,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Hover-revealed action. Kept in the layout at all times rather than being
/// inserted on hover, so revealing it cannot reflow the row's text.
class _IconAction extends StatelessWidget {
  const _IconAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.visible,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      child: IgnorePointer(
        ignoring: !visible,
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(icon, size: 16, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
