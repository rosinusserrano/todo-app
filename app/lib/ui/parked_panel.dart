// Parked groups - the shelves a workspace keeps beside its current list.
//
// "Backlog", "Future ideas", "Someday": tasks you are deliberately not doing
// now. They are per-workspace, unlike side thoughts, because a backlog is a
// property of the thing you are working on.
//
// The review interval is what keeps a shelf from being a landfill. Each group
// asks to be looked at every so often (monthly by default); once that lapses
// the group reads as overdue everywhere it appears - here, and as a dot on the
// title bar button, which is the only part visible while this panel is closed.
//
// Groups collapse. On a 340x480 window three shelves of ten items each is a
// scroll with no shape to it, so only the ones you open take up room, and an
// overdue group opens itself.
//
// Tasks move in and out of a shelf both ways round, and the two directions are
// deliberately not symmetrical:
//
//   - **Out** is a button, always: ↗ on a row puts one task back on the list,
//     ↗ on a group header puts the whole shelf back (behind a confirmation -
//     that one can move a dozen rows at once and there is no undo).
//   - **In** by dragging works only when the list is actually beside this panel
//     ([Layout.splitsContent]). Otherwise there is nothing on screen to drag
//     from, and the 📥 on a task row - which opens the same shelves as a menu -
//     is the way in that works at every size. No size takes a feature away; a
//     shortcut that needs two things visible at once needs them visible.
//   - **In** *directly* is the field at the foot of an open shelf. Everything
//     above puts a task here that was first put somewhere else, which is the
//     wrong shape for the commonest thing anybody does with a backlog: think of
//     something that is explicitly not for today and write it down. Going via
//     the main list to do that means adding a task, finding it, and parking it
//     - three steps to record that you are not doing something.
//
// Reviewing a shelf is its own screen ([ParkedReview]) rather than a button
// under a list. See the header of parked_review.dart for why.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sync/models.dart';
import '../theme.dart';
import 'panel_header.dart';
import 'parked_review.dart';
import 'task_drag.dart';

class ParkedPanel extends StatefulWidget {
  const ParkedPanel({
    super.key,
    required this.groups,
    required this.parked,
    required this.accent,
    required this.onUnpark,
    required this.onComplete,
    required this.onDelete,
    required this.onAddTask,
    required this.onReviewed,
    required this.onEditGroup,
    required this.onCreateGroup,
    required this.onBack,
    required this.onActivateGroup,
    this.onPark,
  });

  final List<ParkedGroup> groups;
  final Map<String, List<Task>> parked;
  final Color accent;

  final Future<void> Function(Task) onUnpark;
  final Future<void> Function(Task) onComplete;

  /// Drop a task outright. Only the review offers this - a shelf's own rows do
  /// not, because the whole point of a shelf is that you are not deciding about
  /// its contents right now.
  final Future<void> Function(Task) onDelete;

  /// A new task, straight onto this shelf. The text is whatever was typed into
  /// the shelf's own field; everything else is what a one-line add means.
  final Future<void> Function(ParkedGroup, String) onAddTask;

  final Future<void> Function(ParkedGroup) onReviewed;
  final void Function(ParkedGroup) onEditGroup;
  final VoidCallback onCreateGroup;
  final VoidCallback onBack;

  /// Put every open task on this shelf back onto the list. Already confirmed by
  /// the time this is called.
  final Future<void> Function(ParkedGroup) onActivateGroup;

  /// A task dragged out of the list beside this panel and dropped on a group.
  /// Null when there is no list beside it - see the header.
  final Future<void> Function(ParkedGroup, Task)? onPark;

  @override
  State<ParkedPanel> createState() => _ParkedPanelState();
}

class _ParkedPanelState extends State<ParkedPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  /// Which groups are open. Seeded with everything overdue: the review is the
  /// reason to be in here, so those should not need a click to be read.
  late final Set<String> _open = {
    for (final g in widget.groups)
      if (g.isReviewDue()) g.uuid,
  };

  /// The shelf being reviewed, and the queue as it stood when that started.
  /// Null is the ordinary list of shelves. See parked_review.dart for why the
  /// queue is a snapshot rather than a live read of [widget.parked].
  ParkedGroup? _reviewing;
  List<Task> _queue = const [];

  /// The pane's own node, so Esc can back out of a review before the shell uses
  /// it to close the whole panel - the same rung-by-rung ladder the journal
  /// walks, and for the same reason.
  final _paneFocus = FocusNode(debugLabel: 'parked pane');

  @override
  void dispose() {
    _in.dispose();
    _paneFocus.dispose();
    super.dispose();
  }

  void _startReview(ParkedGroup g) {
    setState(() {
      _reviewing = g;
      _queue = List.of(widget.parked[g.uuid] ?? const <Task>[]);
    });
  }

  void _endReview() => setState(() {
        _reviewing = null;
        _queue = const [];
      });

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);

    return Focus(
      focusNode: _paneFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        if (_reviewing == null) return KeyEventResult.ignored;
        _endReview();
        return KeyEventResult.handled;
      },
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curve),
          child: _reviewing != null ? _review(_reviewing!) : _shelves(),
        ),
      ),
    );
  }

  Widget _review(ParkedGroup g) => ParkedReview(
        // Keyed on the shelf, so starting a second review resets the funnel
        // rather than resuming the first one part way through.
        key: ValueKey('review-${g.uuid}'),
        group: g,
        tasks: _queue,
        accent: widget.accent,
        onDecide: _decide,
        onFinished: () => widget.onReviewed(g),
        onClose: _endReview,
      );

  /// One decision, applied straight to the database. Keep never gets here.
  Future<void> _decide(Task t, ReviewChoice choice) async {
    switch (choice) {
      case ReviewChoice.keep:
        return;
      case ReviewChoice.activate:
        return widget.onUnpark(t);
      case ReviewChoice.complete:
        return widget.onComplete(t);
      case ReviewChoice.drop:
        return widget.onDelete(t);
    }
  }

  Widget _shelves() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeader(
            title: 'Parked',
            onBack: widget.onBack,
            actions: [
              Tooltip(
                message: 'New group',
                child: InkWell(
                  onTap: widget.onCreateGroup,
                  borderRadius: BorderRadius.circular(T.radius),
                  child: const Padding(
                    padding: EdgeInsets.all(T.s1),
                    child: Icon(Icons.add, size: 15, color: T.muted),
                  ),
                ),
              ),
            ],
          ),
          Expanded(child: widget.groups.isEmpty ? _empty() : _list()),
        ],
      );

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: T.s5),
          child: Text(
            'No groups yet.\nMake one for the things you are not doing now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: T.muted, fontSize: T.fsLabel, height: 1.5),
          ),
        ),
      );

  Widget _list() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: T.s2),
      children: [
        for (final g in widget.groups)
          _Group(
            group: g,
            tasks: widget.parked[g.uuid] ?? const [],
            accent: widget.accent,
            open: _open.contains(g.uuid),
            onToggle: () => setState(
              () => _open.contains(g.uuid)
                  ? _open.remove(g.uuid)
                  : _open.add(g.uuid),
            ),
            onUnpark: widget.onUnpark,
            onComplete: widget.onComplete,
            onAdd: (text) => widget.onAddTask(g, text),
            onReview: () => _startReview(g),
            onEdit: () => widget.onEditGroup(g),
            onActivate: () => _activate(g),
            onDrop: widget.onPark == null ? null : (t) => _park(g, t),
          ),
      ],
    );
  }

  /// A dropped task lands on the shelf and the shelf **opens**.
  ///
  /// The highlight under the pointer says where it is going; nothing would say
  /// where it went. On a collapsed group the only other visible change is a
  /// count going up by one, which is exactly the too-quiet ending
  /// [TaskDropTarget] exists to avoid.
  Future<void> _park(ParkedGroup g, Task t) async {
    setState(() => _open.add(g.uuid));
    await widget.onPark!(g, t);
  }

  /// The whole shelf back onto the list, once. Confirmed first: this can move a
  /// dozen rows in one press and there is nothing to undo it with.
  Future<void> _activate(ParkedGroup g) async {
    final tasks = widget.parked[g.uuid] ?? const <Task>[];
    if (tasks.isEmpty) return;
    final yes = await _confirmActivate(context, g, tasks.length);
    if (!yes) return;
    await widget.onActivateGroup(g);
  }
}

/// "All of these, now" - said before it happens rather than reported after.
///
/// A dialog, not a sheet: modal by nature and gone in seconds, which is the
/// case the sheet rule in main.dart carves out.
Future<bool> _confirmActivate(
  BuildContext context,
  ParkedGroup group,
  int count,
) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: T.bgSolid,
      title: const Text('Activate this group?', style: TextStyle(fontSize: T.fsMenu)),
      content: Text(
        count == 1
            ? 'The one todo in "${group.title}" will be put onto the active '
                'todo list.'
            : 'All $count todos in "${group.title}" will be put onto the '
                'active todo list.',
        style: const TextStyle(fontSize: T.fsLabel, color: T.muted, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Activate'),
        ),
      ],
    ),
  );
  return answer ?? false;
}

class _Group extends StatelessWidget {
  const _Group({
    required this.group,
    required this.tasks,
    required this.accent,
    required this.open,
    required this.onToggle,
    required this.onUnpark,
    required this.onComplete,
    required this.onAdd,
    required this.onReview,
    required this.onEdit,
    required this.onActivate,
    required this.onDrop,
  });

  final ParkedGroup group;
  final List<Task> tasks;
  final Color accent;
  final bool open;
  final VoidCallback onToggle;
  final Future<void> Function(Task) onUnpark;
  final Future<void> Function(Task) onComplete;
  final Future<void> Function(String) onAdd;
  final VoidCallback onReview;
  final VoidCallback onEdit;
  final VoidCallback onActivate;

  /// Null where nothing can be dragged onto it.
  final void Function(Task)? onDrop;

  @override
  Widget build(BuildContext context) {
    final due = group.isReviewDue();
    final tint = due ? T.complementary(accent) : accent;

    // The whole card, collapsed or not, is the target. Aiming at a group's
    // *contents* would mean an empty or closed shelf had nothing to hit, and
    // those are the ones a task is most likely being put away into.
    //
    // The gap between cards is a Padding out here rather than a margin on the
    // Container, so the highlight is drawn around the card and not around the
    // card plus six pixels of nothing.
    return Padding(
      padding: const EdgeInsets.only(bottom: T.s2),
      child: TaskDropTarget(
        onDrop: onDrop,
        color: accent,
        radius: 9,
        child: _card(due, tint),
      ),
    );
  }

  Widget _card(bool due, Color tint) {
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.radius),
        border: Border.all(
          color: due ? tint.withValues(alpha: 0.55) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(T.radius),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(T.s2, T.s2, T.s2, T.s2),
              child: Row(
                children: [
                  Icon(
                    open
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 16,
                    color: T.muted,
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      group.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: T.fsLabel,
                        color: due ? tint : T.text,
                        fontWeight: T.wMedium,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${tasks.length}',
                    style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
                  ),
                  const Spacer(),
                  Text(
                    _reviewLabel(group),
                    style: TextStyle(
                      fontSize: T.fsMeta,
                      color: due ? tint : T.muted,
                      fontWeight: due ? T.wMedium : T.wNormal,
                    ),
                  ),
                  const SizedBox(width: T.s1),
                  _ReviewButton(
                    empty: tasks.isEmpty,
                    due: due,
                    tint: tint,
                    onPressed: onReview,
                  ),
                  // The same ↗ a single parked row carries, meaning the same
                  // thing one level up. Offered only when there is something to
                  // move: on an empty shelf it would be a control that opens a
                  // dialog to do nothing.
                  if (tasks.isNotEmpty)
                    Tooltip(
                      message: tasks.length == 1
                          ? 'Put it back onto the list'
                          : 'Put all ${tasks.length} back onto the list',
                      child: InkWell(
                        onTap: onActivate,
                        borderRadius: BorderRadius.circular(T.radius),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: T.s1, vertical: 2),
                          child: Icon(
                            Icons.north_east_rounded,
                            size: 15,
                            color: accent,
                          ),
                        ),
                      ),
                    ),
                  InkWell(
                    onTap: onEdit,
                    borderRadius: BorderRadius.circular(T.radius),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: T.s1, vertical: 2),
                      child: Icon(Icons.more_horiz, size: 15, color: T.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            for (final t in tasks)
              _ParkedRow(
                task: t,
                accent: accent,
                onUnpark: () => onUnpark(t),
                onComplete: () => onComplete(t),
              ),
            // The way in that needs nothing else on screen. Under the shelf's
            // own contents rather than above them, so it reads as the end of
            // this list and not as a second add field competing with the one at
            // the top of the window.
            _AddToShelf(group: group, accent: accent, onAdd: onAdd),
            const SizedBox(height: T.s1),
          ],
        ],
      ),
    );
  }

  /// "in 12d" / "review due" - short enough to sit on the header row of a
  /// 340px window without pushing the title out.
  static String _reviewLabel(ParkedGroup g) {
    if (g.reviewEveryDays <= 0) return '';
    if (g.isReviewDue()) return 'review due';
    final at = g.reviewDueAt;
    if (at == null) return '';
    final days = at.difference(DateTime.now()).inDays;
    return days < 1 ? 'today' : 'in ${days}d';
  }
}

/// The one-line field at the foot of an open shelf.
///
/// It keeps the caret after a submit, because the reason to be typing here at
/// all is that several things have just occurred to you and none of them are
/// for today. Clearing the field and keeping the focus is what makes that a
/// list rather than a form filled in once.
///
/// Deliberately quiet - no border until it is focused, [T.fsLabel] like the
/// rows above it - so a collapsed-looking shelf does not grow a second input
/// box shouting for attention beside the real one at the top of the window.
class _AddToShelf extends StatefulWidget {
  const _AddToShelf({
    required this.group,
    required this.accent,
    required this.onAdd,
  });

  final ParkedGroup group;
  final Color accent;
  final Future<void> Function(String) onAdd;

  @override
  State<_AddToShelf> createState() => _AddToShelfState();
}

class _AddToShelfState extends State<_AddToShelf> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    await widget.onAdd(text);
    if (!mounted) return;
    _controller.clear();
    setState(() => _busy = false);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s4, 0, T.s2, T.s1),
      child: Row(
        children: [
          Icon(Icons.add, size: 14, color: widget.accent),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: !_busy,
              style: const TextStyle(fontSize: T.fsLabel, color: T.text),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                hintText: 'Add to ${widget.group.title}',
                hintStyle: const TextStyle(
                  fontSize: T.fsLabel,
                  color: T.muted,
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParkedRow extends StatelessWidget {
  const _ParkedRow({
    required this.task,
    required this.accent,
    required this.onUnpark,
    required this.onComplete,
  });

  final Task task;
  final Color accent;
  final VoidCallback onUnpark;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s5, 1, T.s2, 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              task.text,
              style: const TextStyle(fontSize: T.fsLabel, color: T.muted, height: 1.35),
            ),
          ),
          Tooltip(
            message: 'Back onto the list',
            child: InkWell(
              onTap: onUnpark,
              borderRadius: BorderRadius.circular(T.radius),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: T.s1, vertical: 3),
                child: Icon(Icons.north_east_rounded, size: 14, color: accent),
              ),
            ),
          ),
          Tooltip(
            message: 'Check it off from here',
            child: InkWell(
              onTap: onComplete,
              borderRadius: BorderRadius.circular(T.radius),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: T.s1, vertical: 3),
                child: Icon(Icons.check_rounded, size: 14, color: T.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Create/edit sheet for a group. Returns null on cancel, a [GroupEdit] on
/// save, and [GroupEdit.deleted] to remove the group (its tasks come back to
/// the list - see AppState.deleteGroup).
class GroupEdit {
  const GroupEdit(this.title, this.reviewEveryDays, {this.delete = false});

  final String title;
  final int reviewEveryDays;
  final bool delete;

  static const deleted = GroupEdit('', 0, delete: true);
}

Future<GroupEdit?> showGroupForm(BuildContext context, {ParkedGroup? existing}) {
  return showDialog<GroupEdit>(
    context: context,
    builder: (context) => _GroupDialog(existing: existing),
  );
}

class _GroupDialog extends StatefulWidget {
  const _GroupDialog({required this.existing});

  final ParkedGroup? existing;

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late int _days =
      widget.existing?.reviewEveryDays ?? ParkedGroup.defaultReviewEveryDays;

  /// Weekly through yearly, plus "never". Presets rather than a number field:
  /// the choice being made is how seriously to take the shelf, not an integer.
  static const _options = <int, String>{
    7: 'Weekly',
    30: 'Monthly',
    90: 'Quarterly',
    365: 'Yearly',
    0: 'Never',
  };

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(context, GroupEdit(title, _days));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: T.bgSolid,
      title: Text(
        widget.existing == null ? 'New group' : 'Edit group',
        style: const TextStyle(fontSize: T.fsMenu),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            maxLength: 28,
            style: const TextStyle(fontSize: T.fsBody),
            decoration: const InputDecoration(
              hintText: 'Backlog, Future ideas…',
              counterText: '',
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          const Text(
            'Review this group',
            style: TextStyle(fontSize: T.fsMeta, color: T.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _options.entries)
                ChoiceChip(
                  label: Text(e.value, style: const TextStyle(fontSize: T.fsMeta)),
                  selected: _days == e.key,
                  onSelected: (_) => setState(() => _days = e.key),
                ),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: () => Navigator.pop(context, GroupEdit.deleted),
            child: const Text('Delete', style: TextStyle(color: T.danger)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// The way into the funnel, on the shelf's header rather than inside it.
///
/// It used to sit at the foot of the *expanded* card, under the contents - so
/// starting a review meant opening the shelf and scrolling past everything on
/// it first, which is the reading the funnel exists to do one task at a time.
/// On the header it is one press from the list of shelves, and the card's own
/// expand is left for what it is for: glancing at what is on there.
///
/// One label whether or not the clock has run out: this opens the funnel either
/// way, and "mark reviewed" was a promise the old button did not keep. The
/// shelf's colour lights it when the review is due. An empty shelf keeps the
/// button - the funnel finishes such a shelf by being looked at - and says so
/// in the tooltip rather than the label, which has no room to.
class _ReviewButton extends StatelessWidget {
  const _ReviewButton({
    required this.empty,
    required this.due,
    required this.tint,
    required this.onPressed,
  });

  final bool empty;
  final bool due;
  final Color tint;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = due ? tint : T.muted;
    return Tooltip(
      message: empty
          ? 'Nothing on it - reviewing marks it reviewed'
          : 'Go through it one todo at a time',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(T.radius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: 2),
          decoration: BoxDecoration(
            color: due ? tint.withValues(alpha: 0.16) : T.surface,
            borderRadius: BorderRadius.circular(T.radius),
          ),
          child: Text(
            'Review',
            style: TextStyle(
              fontSize: T.fsMeta,
              color: color,
              fontWeight: due ? T.wMedium : T.wNormal,
            ),
          ),
        ),
      ),
    );
  }
}
