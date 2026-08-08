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
    this.onPark,
    this.onUnplan,
    this.onOpenAttachments,
    this.onSetPriority,
    this.onOpen,
    this.attachmentCount = 0,
    this.dragHandle,
  });

  final Task task;
  final Color accent;
  final Future<void> Function() onComplete;
  final Future<void> Function() onDelete;
  final VoidCallback onFocus;

  /// Null on the history list, where arming a reminder makes no sense.
  final Future<void> Function(DateTime?)? onSetReminder;

  /// Shelve this task in a parked group. Takes the anchor of the button that
  /// opened it so the picker lands under the icon rather than at the pointer.
  final Future<void> Function(RelativeRect anchor)? onPark;

  /// Take this task back out of the calendar block it is planned into. The
  /// icon it drives appears **only** on a task that is planned - it is a mark
  /// saying so first and an action second, which is why it does not fade in on
  /// hover like the rest of them.
  final Future<void> Function()? onUnplan;

  /// Opens the attachment list. Null on history, where attaching a document to
  /// something already finished is not a thing worth offering.
  final VoidCallback? onOpenAttachments;

  /// Flag or unflag. Null on history, where "urgent" no longer means anything.
  final Future<void> Function(bool high)? onSetPriority;

  /// Open the task's long form - the composer, with its notes. The way in is
  /// the text itself: the row's icons are all *actions*, and the one thing a
  /// title is obviously a handle for is the task it names.
  final VoidCallback? onOpen;

  /// Drives the paperclip. Like the armed bell, a task carrying documents shows
  /// it without hovering - it is state, not an action offered on demand.
  final int attachmentCount;

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
  final _parkKey = GlobalKey();

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

  /// Where a menu opened from [key] should appear. Anchored to the button
  /// rather than the pointer, so it lands in the same place whether it was
  /// opened by mouse or keyboard.
  RelativeRect? _anchor(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return null;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    return RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + box.size.height,
      overlay.size.width - topLeft.dx,
      0,
    );
  }

  Future<void> _openReminderMenu() async {
    final onSet = widget.onSetReminder;
    final at = _anchor(_bellKey);
    if (onSet == null || at == null) return;

    await showReminderMenu(
      context: context,
      position: at,
      task: widget.task,
      onChosen: onSet,
    );
  }

  Future<void> _openParkMenu() async {
    final onPark = widget.onPark;
    final at = _anchor(_parkKey);
    if (onPark == null || at == null) return;
    await onPark(at);
  }

  @override
  Widget build(BuildContext context) {
    final due = widget.task.isDue();
    final armed = widget.task.remindAtTime;
    final high = widget.task.isHighPriority;

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
                    : high
                        ? T.danger.withValues(alpha: 0.09)
                        : (_hovered ? T.surfaceHover : T.surface),
            borderRadius: BorderRadius.circular(9),
            // Three states want this border and only one can have it. Due
            // outranks focus for the reason above; priority comes last because
            // it is the one of the three that also has a mark of its own - the
            // bar below - so it is still legible when it loses the border.
            border: due
                ? Border.all(color: T.danger.withValues(alpha: 0.55))
                : widget.task.inProgress
                    ? Border.all(color: widget.accent.withValues(alpha: 0.5))
                    : high
                        ? Border.all(color: T.danger.withValues(alpha: 0.45))
                        : null,
          ),
          child: Row(
            children: [
              if (widget.dragHandle != null) widget.dragHandle!,
              // The invariant mark of a flagged task: a bar down the leading
              // edge, which is the one channel neither the overdue nor the
              // focus state uses. A row can therefore say "urgent, overdue and
              // being worked on" without any of the three overwriting another.
              if (high) ...[
                Container(
                  width: 3,
                  height: 17,
                  decoration: BoxDecoration(
                    color: T.danger,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 7),
              ],
              _Checkbox(
                accent: widget.accent,
                onChanged: () => _leave(widget.onComplete),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TaskText(
                  task: widget.task,
                  onOpen: widget.onOpen,
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
              if (widget.onOpenAttachments != null)
                _IconAction(
                  tooltip: widget.attachmentCount == 0
                      ? 'Attach a document'
                      : '${widget.attachmentCount} attached',
                  icon: Icons.attach_file_rounded,
                  color: widget.attachmentCount > 0
                      ? widget.accent
                      : T.muted,
                  visible: _hovered || widget.attachmentCount > 0,
                  onPressed: widget.onOpenAttachments!,
                ),
              if (widget.onUnplan != null && widget.task.isPlanned)
                _IconAction(
                  tooltip: 'Planned into a calendar block — click to take it out',
                  icon: Icons.event_available_rounded,
                  color: widget.accent,
                  visible: true,
                  onPressed: () => widget.onUnplan!(),
                ),
              if (widget.onSetPriority != null)
                _IconAction(
                  tooltip: high
                      ? 'High priority — click to clear'
                      : 'Flag as high priority',
                  icon: high
                      ? Icons.flag_rounded
                      : Icons.outlined_flag_rounded,
                  color: high ? T.danger : T.muted,
                  // Lit without hovering once set, like the armed bell: it is
                  // state the row is carrying.
                  visible: _hovered || high,
                  onPressed: () => widget.onSetPriority!(!high),
                ),
              if (widget.onPark != null)
                _IconAction(
                  key: _parkKey,
                  tooltip: 'Park it in a group — off the list, not gone',
                  icon: Icons.inbox_rounded,
                  color: T.muted,
                  visible: _hovered,
                  onPressed: _openParkMenu,
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

/// The title, and the first line of its notes when it has any.
///
/// The preview is how notes stay *readable* without a second icon on a row that
/// is already nine controls wide at 340px: it costs no horizontal space, and it
/// answers the question the icon would only have offered to answer. Tapping
/// either opens the long form.
class _TaskText extends StatelessWidget {
  const _TaskText({required this.task, required this.onOpen});

  final Task task;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          task.text,
          style: const TextStyle(fontSize: 13, color: T.text, height: 1.3),
        ),
        if (task.hasNotes)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              // One line of it, whitespace flattened - a note written as a
              // paragraph would otherwise preview as its first six words and a
              // ragged newline.
              task.notes.replaceAll(RegExp(r'\s+'), ' ').trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: T.muted, height: 1.25),
            ),
          ),
      ],
    );

    if (onOpen == null) return body;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: body,
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
