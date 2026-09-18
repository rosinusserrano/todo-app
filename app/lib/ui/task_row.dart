// A single task row, ported from .task in styles.css.
//
// The row animates its own removal. Checking the box does not immediately drop
// the row: it plays the slide-out first, then tells the app to persist and
// reload. That ordering is what made the original feel deliberate rather than
// twitchy, and keeping the animation inside the row means the duration lives in
// one place instead of being mirrored between CSS and a setTimeout.
//
// **The row is a tick box, a title and its marks, and nothing else.** The
// actions are not here at all any more - they live in an overlay bar
// (task_actions.dart), asked for by the one gesture each pointer has spare:
// right-click with a mouse, a short tap on the text with a finger. What that
// bought, at both sizes:
//
//   - The nine hover icons were invisible at rest but **still in the layout**,
//     which was the right call while they were on the row (revealing an icon
//     must not reflow the text) and the wrong shape overall: in a narrow
//     window most of a row's width belonged to controls that were not on
//     screen, and the title got the remainder.
//   - The touch bar was a second line under every row - on the screen with the
//     least height of any - and wrapped to a third on a task that carried
//     everything.
//
// What is left inline is **state, not actions**: an armed bell, a paperclip, a
// planned-into mark, the flagged task's red bar. Those say what the task is
// carrying and are not pressable; pressing anything means opening the bar.
//
// The two pointers therefore differ only in which gesture opens what:
//
//   | | mouse | finger |
//   | tap / left-click on the text | expand the row in place | open the actions |
//   | double-click on the text | edit it | - |
//   | right-click | open the actions | - |
//   | long press | - | pick the row up to reorder it (the list's) |
//
// **The double-click is hand-rolled, and that is the point.** Registering
// Flutter's own `onDoubleTap` beside a tap puts both recognisers in one arena,
// and the tap then cannot fire until the double-tap window has expired - which
// buys a second way into the composer at the price of 300ms of lag on *every*
// expansion, the commonest click there is. So the first click expands
// immediately and arms a timer; a second click while that timer is live undoes
// the expansion and opens the composer instead. A double-click is one gesture,
// not a click plus an edit, so the row is left exactly as it was found.
//
// **Selecting several** is Ctrl+click with a mouse and *Select* in the bar
// with a finger. Once anything is selected a plain click or tap on a row toggles
// it too, because a selection you have to hold a modifier to extend is one that
// ends the moment your hand moves. What a selection is *for* lives in the shell.
//
// Editing is the pencil inside that bar on both, and expanding is an action in
// it on both - a phone has no left-click to spare and a mouse has no reason to
// give up a cheap way into the read view. The double-click is a *shortcut* to
// that pencil, not a replacement for it: it is the one thing on this row a
// finger cannot do, so the bar stays the way both pointers can always get
// there.

import 'dart:async';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout.dart';
import '../sync/models.dart';
import '../theme.dart';
import 'markdown_text.dart';
import 'reminder_menu.dart';
import 'task_actions.dart';
import 'task_detail.dart';

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
    this.onExpand,
    this.attachmentCount = 0,
    this.dragHandle,
    this.selected = false,
    this.selecting = false,
    this.onToggleSelect,
  });

  /// This row is in the multi-selection.
  final bool selected;

  /// *Something* is selected, so a plain click extends the selection rather
  /// than doing what a click normally does.
  final bool selecting;

  /// Null where selecting is not offered (the session view).
  final VoidCallback? onToggleSelect;

  final Task task;
  final Color accent;
  final Future<void> Function() onComplete;
  final Future<void> Function() onDelete;
  final VoidCallback onFocus;

  /// Null on the history list, where arming a reminder makes no sense.
  final Future<void> Function(DateTime?)? onSetReminder;

  /// Shelve this task in a parked group. Takes the anchor of the row that
  /// opened it so the picker lands under the task rather than at the pointer.
  final Future<void> Function(RelativeRect anchor)? onPark;

  /// Take this task back out of the calendar block it is planned into. Offered
  /// only on a task that *is* planned, which is also the only case where the
  /// row draws the mark saying so.
  final Future<void> Function()? onUnplan;

  /// Opens the attachment list. Null on history, where attaching a document to
  /// something already finished is not a thing worth offering.
  final VoidCallback? onOpenAttachments;

  /// Flag or unflag. Null on history, where "urgent" no longer means anything.
  final Future<void> Function(bool high)? onSetPriority;

  /// Open the task's long form - the composer, with its fields. Reached from
  /// the pencil in the action bar; the row's own text is the *read* view now.
  final VoidCallback? onOpen;

  /// Show the task's read-only long form somewhere the row cannot reach.
  ///
  /// Non-null only where the **shell** owns that view: on a phone the expanded
  /// task takes the whole content area, which a row inside a scrolling list
  /// cannot do for itself. Null means the row expands in place, which is what
  /// a pointer gets - the tasks above and below stay where they were and the
  /// list scrolls past them.
  final VoidCallback? onExpand;

  /// Drives the paperclip mark. A task carrying documents says so without being
  /// asked - it is state, not an action offered on demand.
  final int attachmentCount;

  /// The reorder grip, on the **right**. It was on the left, where it sat
  /// between the edge of the row and the tick box and pushed both the title and
  /// the notes in by its own width on every row in the list. Nothing else is
  /// over there any more, and a grip is the one control that does not need to
  /// be near the text it moves.
  ///
  /// Null on touch, where a long press anywhere on the row picks it up and a
  /// permanent six-dot glyph would be a mark for a gesture that does not need
  /// one.
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

  /// Showing its details in place. Deliberately per-row state rather than
  /// something the list owns: several open at once is a normal way to read a
  /// checklist, and nothing outside the row needs to know.
  bool _expanded = false;

  /// The row's own box - what the action bar, the reminder menu and the park
  /// picker are anchored to now that none of them has an icon to hang off.
  final _rowKey = GlobalKey();

  /// Live between the two halves of a double-click. A click arriving while it
  /// is still running is the second half; it clears itself after
  /// [kDoubleTapTimeout], which is what makes two deliberate clicks a minute
  /// apart two separate clicks.
  Timer? _secondClick;

  @override
  void dispose() {
    _secondClick?.cancel();
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

  /// Where a menu opened from the row should appear.
  RelativeRect? _menuAnchor() {
    final rect = taskActionAnchor(context, key: _rowKey);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (rect == null || overlay == null) return null;

    return RelativeRect.fromLTRB(
      rect.left,
      rect.bottom,
      overlay.size.width - rect.left,
      0,
    );
  }

  Future<void> _openReminderMenu() async {
    final onSet = widget.onSetReminder;
    final at = _menuAnchor();
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
    final at = _menuAnchor();
    if (onPark == null || at == null) return;
    await onPark(at);
  }

  /// A click that belongs to the selection rather than to the row: Ctrl held,
  /// or a selection already under way. Returns whether it was taken.
  bool _selectInstead() {
    final toggle = widget.onToggleSelect;
    if (toggle == null) return false;
    if (!widget.selecting && !HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    toggle();
    return true;
  }

  /// Read the task. In place under a pointer, whole-screen where the shell has
  /// said it will take it ([TaskRow.onExpand]).
  void _toggleExpanded() {
    final elsewhere = widget.onExpand;
    if (elsewhere != null) {
      elsewhere();
      return;
    }
    setState(() => _expanded = !_expanded);
  }

  /// A left-click on the text, under a pointer.
  ///
  /// The first one expands the row and arms [_secondClick]; one that arrives
  /// while that is live is a double-click, which puts the expansion back and
  /// opens the composer. See the note in the file header for why this is not
  /// `GestureDetector.onDoubleTap`.
  void _clickText() {
    final open = widget.onOpen;

    if (_secondClick != null && open != null) {
      _secondClick!.cancel();
      _secondClick = null;
      // Undo the first click of the pair - but only the in-place expansion.
      // Where the shell takes the read view ([TaskRow.onExpand]) there is
      // nothing to put back, and calling it again would open it twice.
      if (widget.onExpand == null) setState(() => _expanded = !_expanded);
      open();
      return;
    }

    _toggleExpanded();
    _secondClick?.cancel();
    _secondClick = Timer(kDoubleTapTimeout, () => _secondClick = null);
  }

  /// What the bar offers for this row. An action whose callback is null is not
  /// in the list at all, which is how the session view's rows come out with
  /// four buttons and the task list's with nine.
  List<TaskActionItem> _actions() {
    final task = widget.task;
    final armed = task.remindAtTime;
    final due = task.isDue();
    final high = task.isHighPriority;

    return [
      // The order the old bar had, and it is the order they are reached for:
      // the two that change what the task *is*, then its documents, then the
      // ones that move it somewhere, then reading and writing it, then the
      // destructive one last.
      if (widget.onSetReminder != null)
        TaskActionItem(
          action: TaskAction.remind,
          icon: armed == null
              ? Icons.notifications_none_rounded
              : Icons.notifications_active_rounded,
          label: armed == null
              ? 'Remind me'
              : 'Reminder ${describeReminder(armed)}',
          color: due ? T.warn : (armed != null ? widget.accent : T.muted),
        ),
      if (widget.onSetPriority != null)
        TaskActionItem(
          action: TaskAction.priority,
          icon: high ? Icons.flag_rounded : Icons.outlined_flag_rounded,
          label: high ? 'Clear high priority' : 'Flag as high priority',
          color: high ? T.flagged : T.muted,
        ),
      if (widget.onOpenAttachments != null)
        TaskActionItem(
          action: TaskAction.attach,
          icon: Icons.attach_file_rounded,
          label: widget.attachmentCount == 0
              ? 'Attach a document'
              : '${widget.attachmentCount} attached',
          color: widget.attachmentCount > 0 ? widget.accent : T.muted,
        ),
      if (widget.onUnplan != null && task.isPlanned)
        TaskActionItem(
          action: TaskAction.unplan,
          icon: Icons.event_busy_rounded,
          label: 'Take it out of its calendar block',
          color: widget.accent,
        ),
      if (widget.onPark != null)
        const TaskActionItem(
          action: TaskAction.park,
          icon: Icons.inbox_rounded,
          label: 'Park it in a group — off the list, not gone',
        ),
      TaskActionItem(
        action: TaskAction.focus,
        icon: Icons.play_arrow_rounded,
        label: 'Work on this — hides everything else',
        color: task.inProgress ? widget.accent : T.muted,
      ),
      TaskActionItem(
        action: TaskAction.expand,
        icon: _expanded
            ? Icons.close_fullscreen_rounded
            : Icons.open_in_full_rounded,
        label: _expanded ? 'Collapse' : 'Expand — notes and details',
      ),
      if (widget.onOpen != null)
        const TaskActionItem(
          action: TaskAction.edit,
          icon: Icons.edit_outlined,
          label: 'Edit task and notes',
        ),
      if (widget.onToggleSelect != null)
        TaskActionItem(
          action: TaskAction.select,
          icon: widget.selected
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          label: widget.selected
              ? 'Unselect'
              : 'Select - then pick others to move them together (Ctrl+click)',
          color: widget.selected ? widget.accent : T.muted,
        ),
      const TaskActionItem(
        action: TaskAction.delete,
        icon: Icons.close_rounded,
        label: "Delete (don't log)",
        color: T.danger,
      ),
    ];
  }

  /// Open the bar, then run whatever was pressed.
  ///
  /// The bar itself knows nothing about tasks - it resolves to an enum and the
  /// row is what turns that back into a callback, which is what keeps a park
  /// picker and a reminder menu (both of which want an anchor of their own)
  /// out of it.
  Future<void> _openActions({Offset? at}) async {
    final layout = Layout.of(context);
    final anchor = taskActionAnchor(context, key: _rowKey, at: at);
    if (anchor == null) return;

    final chosen = await showTaskActions(
      context,
      anchor: anchor,
      items: _actions(),
      layout: layout,
    );
    if (chosen == null || !mounted) return;

    switch (chosen) {
      case TaskAction.remind:
        await _openReminderMenu();
      case TaskAction.priority:
        await widget.onSetPriority?.call(!widget.task.isHighPriority);
      case TaskAction.attach:
        widget.onOpenAttachments?.call();
      case TaskAction.unplan:
        await widget.onUnplan?.call();
      case TaskAction.park:
        await _openParkMenu();
      case TaskAction.focus:
        widget.onFocus();
      case TaskAction.expand:
        _toggleExpanded();
      case TaskAction.edit:
        widget.onOpen?.call();
      case TaskAction.select:
        widget.onToggleSelect?.call();
      case TaskAction.delete:
        await _leave(widget.onDelete);
    }
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
        child: GestureDetector(
          // Anywhere on the row, not only on the text: a right-click is aimed
          // at the row, and the text is a fraction of it on a short title.
          // Opaque so the blank space to the right of a title is part of the
          // target rather than a hole in it.
          behavior: HitTestBehavior.opaque,
          // Only while it means something: an onTap here would otherwise sit
          // in the arena against the text's own tap on every click.
          onTap: widget.onToggleSelect != null &&
                  (widget.selecting || !touch)
              ? _selectInstead
              : null,
          onSecondaryTapUp:
              touch ? null : (d) => _openActions(at: d.globalPosition),
          child: Container(
            key: _rowKey,
            // Half a step, so the gap between two rows is one whole one.
            margin: const EdgeInsets.symmetric(vertical: T.s1 / 2),
            padding: const EdgeInsets.all(T.s2),
            decoration: BoxDecoration(
              // A due reminder outranks focus for the row's colour: focus is a
              // state you chose and can see, an overdue reminder is the thing
              // asking for attention.
              // Selected outranks everything: it is the state you are about to
              // act on, and a row that is both overdue and selected has to be
              // unmistakably part of the batch.
              color: widget.selected
                  ? widget.accent.withValues(alpha: 0.24)
                  : due
                  ? T.warn.withValues(alpha: 0.14)
                  : widget.task.inProgress
                      ? widget.accent.withValues(alpha: 0.16)
                      : high
                          ? T.flagged.withValues(alpha: 0.09)
                          : (_hovered ? T.surfaceHover : T.surface),
              borderRadius: BorderRadius.circular(T.radius),
              // Three states want this border and only one can have it. Due
              // outranks focus for the reason above; priority comes last
              // because it is the one of the three that also has a mark of its
              // own - the bar below - so it is still legible when it loses the
              // border.
              border: widget.selected
                  ? Border.all(color: widget.accent.withValues(alpha: 0.9))
                  : due
                  ? Border.all(color: T.warn.withValues(alpha: 0.55))
                  : widget.task.inProgress
                      ? Border.all(color: widget.accent.withValues(alpha: 0.5))
                      : high
                          ? Border.all(color: T.flagged.withValues(alpha: 0.45))
                          : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // The invariant mark of a flagged task: a bar down the
                    // leading edge, which is the one channel neither the
                    // overdue nor the focus state uses. A row can therefore say
                    // "urgent, overdue and being worked on" without any of the
                    // three overwriting another.
                    if (high) ...[
                      Container(
                        width: 3,
                        height: 17,
                        decoration: BoxDecoration(
                          color: T.flagged,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: T.s1),
                    ],
                    _Checkbox(
                      accent: widget.accent,
                      onChanged: () => _leave(widget.onComplete),
                    ),
                    const SizedBox(width: T.s2),
                    Expanded(
                      child: _TaskText(
                        task: widget.task,
                        // The preview is what the expansion replaces, so it
                        // only earns its line while the row is closed.
                        showPreview: !_expanded,
                        // A finger asks for the actions, a mouse reads the
                        // task - see the table in the file header.
                        onTap: () {
                          if (_selectInstead()) return;
                          touch ? _openActions() : _clickText();
                        },
                      ),
                    ),
                    _StateMarks(
                      accent: widget.accent,
                      size: touch ? 15 : 13,
                      due: due,
                      armed: armed != null,
                      attached: widget.attachmentCount > 0,
                      planned: widget.task.isPlanned,
                    ),
                    if (widget.dragHandle != null) widget.dragHandle!,
                  ],
                ),

                // The read view, in place. Only ever reached under a pointer:
                // on touch [TaskRow.onExpand] hands this to the shell, which
                // gives it the screen.
                if (_expanded)
                  Padding(
                    padding: EdgeInsets.only(
                      left: _textInset(high),
                      right: T.s1,
                      top: T.s2,
                      bottom: T.s1 / 2,
                    ),
                    child: TaskDetail(
                      task: widget.task,
                      accent: widget.accent,
                      attachmentCount: widget.attachmentCount,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Where the title starts, so the expanded detail lines up under it rather
  /// than under the tick box.
  double _textInset(bool high) {
    var inset = 18.0 + T.s2; // the checkbox and its gap
    if (high) inset += 3 + T.s1; // the priority bar and its gap
    return inset;
  }
}

/// What the task is carrying, drawn small and **not pressable**.
///
/// These were actions once - the bell, the paperclip and the planned mark were
/// all lit-up buttons that stayed visible without a hover because they were
/// state as much as controls. With the actions gone into the bar, only the
/// state half is left: it answers "does this have a reminder / documents / a
/// slot" at a glance, and pressing anything on the row opens the bar, which is
/// where the matching action is.
class _StateMarks extends StatelessWidget {
  const _StateMarks({
    required this.accent,
    required this.size,
    required this.due,
    required this.armed,
    required this.attached,
    required this.planned,
  });

  final Color accent;
  final double size;
  final bool due;
  final bool armed;
  final bool attached;
  final bool planned;

  @override
  Widget build(BuildContext context) {
    final marks = <Widget>[
      if (armed)
        Icon(
          due
              ? Icons.notification_important_rounded
              : Icons.notifications_active_rounded,
          size: size,
          color: due ? T.warn : accent,
        ),
      if (attached)
        Icon(Icons.attach_file_rounded, size: size, color: accent),
      if (planned)
        Icon(Icons.event_available_rounded, size: size, color: accent),
    ];
    if (marks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: T.s1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in marks)
            Padding(padding: const EdgeInsets.only(left: T.s1 / 2), child: m),
        ],
      ),
    );
  }
}

/// The title, and the first line of its notes when it has any.
///
/// The preview is how notes stay *readable* without opening anything: it costs
/// no horizontal space, and it answers the question an icon would only have
/// offered to answer. Tapping it does whatever this pointer's tap does - see
/// the table in the file header.
class _TaskText extends StatelessWidget {
  const _TaskText({
    required this.task,
    required this.onTap,
    this.showPreview = true,
  });

  final Task task;
  final VoidCallback? onTap;

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
          style: const TextStyle(fontSize: T.fsBody, color: T.text, height: 1.4),
        ),
        if (task.hasNotes && showPreview)
          Padding(
            padding: const EdgeInsets.only(top: T.s1 / 2),
            child: Text(
              // One line of it, whitespace flattened - a note written as a
              // paragraph would otherwise preview as its first six words and a
              // ragged newline. Rendered down from Markdown rather than shown
              // raw: a note that opens with a heading previewed as "## Trip",
              // which spends the one line on punctuation.
              markdownPlainText(task.notes),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.35),
            ),
          ),
      ],
    );

    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(T.radius),
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
