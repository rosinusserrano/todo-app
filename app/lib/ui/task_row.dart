// A single task row, ported from .task in styles.css.
//
// The row animates its own removal. Checking the box does not immediately drop
// the row: it plays the slide-out first, then tells the app to persist and
// reload. That ordering is what made the original feel deliberate rather than
// twitchy, and keeping the animation inside the row means the duration lives in
// one place instead of being mirrored between CSS and a setTimeout.
//
// **The row has two shapes, and the axis is the pointer, not the width.** With
// a mouse the actions are hover-revealed and sit in the row's right-hand end:
// nine controls fit across 340px precisely *because* they are invisible until
// the pointer is on the row, and hovering costs nothing.
//
// A fingertip has no hover. That did not make the icons small on a phone, it
// made them **absent** - `visible: _hovered` is never true there, so setting a
// reminder, parking, focusing and deleting a task had no way in at all, and no
// amount of extra width would have produced one. So on touch the same actions
// are laid out *below* the title as a real bar of finger-sized targets, always
// visible, and the row expands in place to show its notes. See [Layout.touch].
//
// Tapping the title therefore means different things on the two: on desktop it
// opens the composer (unchanged - the hover icons already make everything else
// reachable), on touch it expands the row, and the composer gets an explicit
// pencil in the bar. A tap that opened a modal editor would be a poor use of
// the one gesture a phone has most of.

import 'package:flutter/material.dart';

import '../layout.dart';
import '../sync/models.dart';
import '../theme.dart';
import 'markdown_text.dart';
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

  /// Showing its notes in place. Touch only, and deliberately per-row state
  /// rather than something the list owns: several open at once is the normal
  /// way to read a checklist, and nothing outside the row needs to know.
  bool _expanded = false;

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
    final layout = Layout.of(context);
    final touch = layout.touch;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
                  // The notes preview is what the expansion replaces, so it
                  // only earns its line while the row is closed.
                  showPreview: !(touch && _expanded),
                  onOpen: touch && widget.task.hasNotes
                      ? () => setState(() => _expanded = !_expanded)
                      : widget.onOpen,
                ),
              ),
              if (!touch) ...[
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
            ],
          ),

              // The notes, in place. Reachable only on touch, where tapping
              // the title is what opened it - on desktop the same text is one
              // click away in the composer and the row stays one line tall.
              if (touch && _expanded && widget.task.hasNotes)
                Padding(
                  padding: EdgeInsets.only(
                    left: _textInset(high),
                    right: 4,
                    top: 4,
                    bottom: 2,
                  ),
                  child: MarkdownText(
                    widget.task.notes,
                    style: const TextStyle(
                      fontSize: 12,
                      color: T.muted,
                      height: 1.35,
                    ),
                  ),
                ),

              if (touch)
                Padding(
                  padding: EdgeInsets.only(left: _textInset(high) - 6, top: 2),
                  child: _TouchActions(
                    task: widget.task,
                    accent: widget.accent,
                    layout: layout,
                    due: due,
                    armed: armed,
                    high: high,
                    expanded: _expanded,
                    attachmentCount: widget.attachmentCount,
                    bellKey: _bellKey,
                    parkKey: _parkKey,
                    onToggleExpanded: widget.task.hasNotes
                        ? () => setState(() => _expanded = !_expanded)
                        : null,
                    onEdit: widget.onOpen,
                    onReminder:
                        widget.onSetReminder == null ? null : _openReminderMenu,
                    onPark: widget.onPark == null ? null : _openParkMenu,
                    onSetPriority: widget.onSetPriority,
                    onOpenAttachments: widget.onOpenAttachments,
                    onUnplan: widget.onUnplan,
                    onFocus: widget.onFocus,
                    onDelete: () => _leave(widget.onDelete),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Where the title starts, so the notes and the action bar line up under it
  /// rather than under the tick box.
  double _textInset(bool high) {
    var inset = 18.0 + 8; // the checkbox and its gap
    if (widget.dragHandle != null) inset += 18;
    if (high) inset += 10; // the priority bar and its gap
    return inset;
  }
}

/// The actions, as a bar under the title.
///
/// Everything here is also in the row's hover icons on desktop; what differs is
/// that these are always visible and [Layout.tapTarget] across. The order is
/// the order they are reached for: the two that change what the task *is*
/// (reminder, priority), then the ones that move it somewhere (park, focus),
/// then editing, then the destructive one last and set apart.
class _TouchActions extends StatelessWidget {
  const _TouchActions({
    required this.task,
    required this.accent,
    required this.layout,
    required this.due,
    required this.armed,
    required this.high,
    required this.expanded,
    required this.attachmentCount,
    required this.bellKey,
    required this.parkKey,
    required this.onToggleExpanded,
    required this.onEdit,
    required this.onReminder,
    required this.onPark,
    required this.onSetPriority,
    required this.onOpenAttachments,
    required this.onUnplan,
    required this.onFocus,
    required this.onDelete,
  });

  final Task task;
  final Color accent;
  final Layout layout;
  final bool due;
  final DateTime? armed;
  final bool high;
  final bool expanded;
  final int attachmentCount;
  final GlobalKey bellKey;
  final GlobalKey parkKey;
  final VoidCallback? onToggleExpanded;
  final VoidCallback? onEdit;
  final VoidCallback? onReminder;
  final VoidCallback? onPark;
  final Future<void> Function(bool high)? onSetPriority;
  final VoidCallback? onOpenAttachments;
  final Future<void> Function()? onUnplan;
  final VoidCallback onFocus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onReminder != null)
          _TouchAction(
            key: bellKey,
            layout: layout,
            semantics: armed == null
                ? 'Remind me'
                : 'Reminder ${describeReminder(armed!)}',
            icon: armed == null
                ? Icons.notifications_none_rounded
                : Icons.notifications_active_rounded,
            color: due ? T.danger : (armed != null ? accent : T.muted),
            onPressed: onReminder!,
          ),
        if (onSetPriority != null)
          _TouchAction(
            layout: layout,
            semantics: high ? 'Clear high priority' : 'Flag as high priority',
            icon: high ? Icons.flag_rounded : Icons.outlined_flag_rounded,
            color: high ? T.danger : T.muted,
            onPressed: () => onSetPriority!(!high),
          ),
        if (onOpenAttachments != null)
          _TouchAction(
            layout: layout,
            semantics: attachmentCount == 0
                ? 'Attach a document'
                : '$attachmentCount attached',
            icon: Icons.attach_file_rounded,
            color: attachmentCount > 0 ? accent : T.muted,
            onPressed: onOpenAttachments!,
          ),
        if (onUnplan != null && task.isPlanned)
          _TouchAction(
            layout: layout,
            semantics: 'Take it out of its calendar block',
            icon: Icons.event_available_rounded,
            color: accent,
            onPressed: () => onUnplan!(),
          ),
        if (onPark != null)
          _TouchAction(
            key: parkKey,
            layout: layout,
            semantics: 'Park it in a group',
            icon: Icons.inbox_rounded,
            color: T.muted,
            onPressed: onPark!,
          ),
        _TouchAction(
          layout: layout,
          semantics: 'Work on this',
          icon: Icons.play_arrow_rounded,
          color: task.inProgress ? accent : T.muted,
          onPressed: onFocus,
        ),
        if (onEdit != null)
          _TouchAction(
            layout: layout,
            semantics: 'Edit task and notes',
            icon: Icons.edit_outlined,
            color: T.muted,
            onPressed: onEdit!,
          ),

        // Pushed to the far end rather than sitting next to the others: it is
        // the one press here with nothing behind it, and a fingertip is wide.
        const Spacer(),
        if (onToggleExpanded != null)
          _TouchAction(
            layout: layout,
            semantics: expanded ? 'Hide notes' : 'Show notes',
            icon: expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            color: T.muted,
            onPressed: onToggleExpanded!,
          ),
        _TouchAction(
          layout: layout,
          semantics: "Delete (don't log)",
          icon: Icons.close_rounded,
          color: T.danger,
          onPressed: onDelete,
        ),
      ],
    );
  }
}

/// One always-visible, finger-sized action.
class _TouchAction extends StatelessWidget {
  const _TouchAction({
    super.key,
    required this.layout,
    required this.semantics,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final Layout layout;
  final String semantics;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Semantics rather than a Tooltip: a tooltip needs a hover or a long press,
    // and the long press here belongs to dragging the row.
    return Semantics(
      label: semantics,
      button: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: layout.tapTarget,
          height: layout.tapTarget,
          child: Icon(icon, size: layout.actionIcon, color: color),
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
  const _TaskText({
    required this.task,
    required this.onOpen,
    this.showPreview = true,
  });

  final Task task;
  final VoidCallback? onOpen;

  /// False while the row is expanded, where the full notes are directly below
  /// and a one-line preview of them would be the same sentence twice.
  final bool showPreview;

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
        if (task.hasNotes && showPreview)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              // One line of it, whitespace flattened - a note written as a
              // paragraph would otherwise preview as its first six words and a
              // ragged newline. Rendered down from Markdown rather than shown
              // raw: a note that opens with a heading previewed as "## Trip",
              // which spends the one line on punctuation.
              markdownPlainText(task.notes),
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
