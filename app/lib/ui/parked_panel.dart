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
import '../layout.dart';
import '../theme.dart';
import 'list_rule.dart';
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
    this.onEditTask,
  });

  /// The task's long form, the composer - opened by a tap on a shelved
  /// task's text, as on the list (Marco, 2026-10-21: a shelf's tasks could be
  /// moved and ticked but not changed). Null leaves the text inert.
  final Future<void> Function(Task)? onEditTask;

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

  /// Shelves whose add line is showing while they are closed - the ＋ on a
  /// group's line. Adding to a shelf is not reading it, so it does not open
  /// the contents; the line goes again when it is left empty.
  final Set<String> _adding = {};

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
        count: widget.groups.isEmpty ? null : widget.groups.length,
        actions: [
          Tooltip(
            message: 'New group',
            child: _ShelfButton(
              icon: Icons.add_rounded,
              onTap: widget.onCreateGroup,
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
      children: [
        for (final (i, g) in widget.groups.indexed) ...[
          if (i > 0) const ListRule(),
          _Group(
            group: g,
            tasks: widget.parked[g.uuid] ?? const [],
            accent: widget.accent,
            open: _open.contains(g.uuid),
            adding: _adding.contains(g.uuid),
            onStartAdd: () => setState(() => _adding.add(g.uuid)),
            onStopAdd: () => setState(() => _adding.remove(g.uuid)),
            onToggle: () => setState(
              () => _open.contains(g.uuid)
                  ? _open.remove(g.uuid)
                  : _open.add(g.uuid),
            ),
            onUnpark: widget.onUnpark,
            onComplete: widget.onComplete,
            onEditTask: widget.onEditTask,
            onAdd: (text) => widget.onAddTask(g, text),
            onReview: () => _startReview(g),
            onEdit: () => widget.onEditGroup(g),
            onActivate: () => _activate(g),
            onDrop: widget.onPark == null ? null : (t) => _park(g, t),
          ),
        ],
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
      title: const Text(
        'Activate this group?',
        style: TextStyle(fontSize: T.fsMenu),
      ),
      content: Text(
        count == 1
            ? 'The one todo in "${group.title}" will be put onto the active '
                  'todo list.'
            : 'All $count todos in "${group.title}" will be put onto the '
                  'active todo list.',
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
    required this.adding,
    required this.onStartAdd,
    required this.onStopAdd,
    required this.onToggle,
    required this.onUnpark,
    required this.onComplete,
    required this.onAdd,
    required this.onReview,
    required this.onEdit,
    required this.onActivate,
    required this.onDrop,
    this.onEditTask,
  });

  final Future<void> Function(Task)? onEditTask;
  final ParkedGroup group;
  final List<Task> tasks;
  final Color accent;
  final bool open;

  /// The add line is wanted (its ＋ was pressed): shown even while closed, and
  /// given the caret.
  final bool adding;
  final VoidCallback onStartAdd;
  final VoidCallback onStopAdd;
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

    // The whole group, collapsed or not, is the target. Aiming at a group's
    // *contents* would mean an empty or closed shelf had nothing to hit, and
    // those are the ones a task is most likely being put away into.
    return TaskDropTarget(
      onDrop: onDrop,
      color: accent,
      radius: T.radius,
      child: _section(context, due, tint),
    );
  }

  /// A group is a section of the page, not a card on it: a title with the
  /// whole width to itself, a line of facts and controls under it, and a rule
  /// to the next group.
  ///
  /// The controls used to share one row with the title, which did two things
  /// wrong. The title lost - "Todo Wi…", "Journal A…" - to four controls that
  /// say nothing about which group this is. And the row's right-hand end was
  /// wherever the controls happened to finish: an empty group has no ↗, so its
  /// ⋯ sat one slot further left than every other group's. Now the ↗ keeps its
  /// slot even when it is not drawn, so the ⋯ - and the chevron above it - are
  /// one column down the whole page.
  Widget _section(BuildContext context, bool due, Color tint) {
    final layout = Layout.of(context);
    final review = _reviewLabel(group);
    final facts = [
      tasks.isEmpty
          ? 'Empty'
          : tasks.length == 1
          ? '1 todo'
          : '${tasks.length} todos',
      if (review.isNotEmpty) review,
    ].join('  ·  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(T.s4, T.s3, T.s2, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    group.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: T.fsMenu,
                      fontFamily: T.fontDisplay,
                      height: 1.25,
                      color: due ? tint : T.text,
                      fontWeight: T.wMedium,
                    ),
                  ),
                ),
                SizedBox(
                  width: layout.tapTarget,
                  height: T.fsMenu * 1.25,
                  child: Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: layout.actionIcon,
                    color: T.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(T.s4, 0, T.s2, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  facts,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: T.fsMeta,
                    color: due ? tint : T.muted,
                    fontWeight: due ? T.wMedium : T.wNormal,
                  ),
                ),
              ),
              Tooltip(
                message: 'Add to this shelf',
                child: _ShelfButton(icon: Icons.add, onTap: onStartAdd),
              ),
              _ReviewButton(
                empty: tasks.isEmpty,
                due: due,
                tint: tint,
                onPressed: onReview,
              ),
              // The same ↗ a single parked row carries, meaning the same
              // thing one level up. Offered only when there is something to
              // move - on an empty shelf it would be a control that opens a
              // dialog to do nothing - but its slot is kept either way.
              if (tasks.isNotEmpty)
                Tooltip(
                  message: tasks.length == 1
                      ? 'Put it back onto the list'
                      : 'Put all ${tasks.length} back onto the list',
                  child: _ShelfButton(
                    icon: Icons.north_east_rounded,
                    color: accent,
                    onTap: onActivate,
                  ),
                )
              else
                SizedBox(width: layout.tapTarget),
              Tooltip(
                message: 'Edit the group',
                child: _ShelfButton(icon: Icons.more_horiz, onTap: onEdit),
              ),
            ],
          ),
        ),
        if (open)
          for (final t in tasks) ...[
            const Padding(
              padding: EdgeInsets.only(left: _indent - T.s4),
              child: ListRule(),
            ),
            _ParkedRow(
              task: t,
              accent: accent,
              onUnpark: () => onUnpark(t),
              onComplete: () => onComplete(t),
              onEdit: onEditTask == null ? null : () => onEditTask!(t),
            ),
          ],
        if (open || adding) ...[
          // The way in that needs nothing else on screen. Under the shelf's
          // own contents rather than above them, so it reads as the end of
          // this list and not as a second add field competing with the one at
          // the top of the window.
          const Padding(
            padding: EdgeInsets.only(left: _indent - T.s4),
            child: ListRule(),
          ),
          _AddToShelf(
            group: group,
            accent: accent,
            onAdd: onAdd,
            focus: adding,
            onLeave: onStopAdd,
          ),
        ],
        const SizedBox(height: T.s1),
      ],
    );
  }

  /// Where a shelf's own todos start: in from the group's title, which is the
  /// only thing saying they belong to it now that there is no card around
  /// them.
  static const _indent = T.s4 + T.s4;

  /// "review in 12d" / "review due" - the second fact on the group's line.
  static String _reviewLabel(ParkedGroup g) {
    if (g.reviewEveryDays <= 0) return '';
    if (g.isReviewDue()) return 'review due';
    final at = g.reviewDueAt;
    if (at == null) return '';
    final days = at.difference(DateTime.now()).inDays;
    return days < 1 ? 'review today' : 'review in ${days}d';
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
    required this.focus,
    required this.onLeave,
  });

  final ParkedGroup group;
  final Color accent;
  final Future<void> Function(String) onAdd;

  /// Take the caret - on being built, or on turning true (the ＋ pressed on a
  /// shelf whose line was already showing).
  final bool focus;

  /// Called when the caret leaves an empty line, so a line the ＋ brought up
  /// on a closed shelf goes away again.
  final VoidCallback onLeave;

  @override
  State<_AddToShelf> createState() => _AddToShelfState();
}

class _AddToShelfState extends State<_AddToShelf> {
  final _controller = TextEditingController();
  late final _focus = FocusNode(onKeyEvent: _onKey)
    ..addListener(_focusChanged);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.focus) _takeCaret();
  }

  @override
  void didUpdateWidget(_AddToShelf old) {
    super.didUpdateWidget(old);
    if (widget.focus && !old.focus) _takeCaret();
  }

  void _takeCaret() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _focus.requestFocus();
  });

  void _focusChanged() {
    if (!_focus.hasFocus && !_busy && _controller.text.trim().isEmpty) {
      widget.onLeave();
    }
  }

  /// Esc lets go of the line rather than going on up to close the pane; an
  /// empty one then goes (see [_focusChanged]).
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    _focus.unfocus();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
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
      padding: const EdgeInsets.fromLTRB(_Group._indent, T.s1, T.s2, 0),
      child: Row(
        children: [
          Icon(Icons.add, size: 16, color: widget.accent),
          const SizedBox(width: T.s2),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: !_busy,
              style: const TextStyle(fontSize: T.fsBody, color: T.text),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: T.s2),
                hintText: 'Add to ${widget.group.title}',
                hintStyle: const TextStyle(fontSize: T.fsBody, color: T.muted),
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
    this.onEdit,
  });

  final Task task;
  final Color accent;
  final VoidCallback onUnpark;
  final VoidCallback onComplete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_Group._indent, 2, T.s2, 2),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: onEdit == null ? '' : 'Edit',
              waitDuration: const Duration(milliseconds: 600),
              child: InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(T.radius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: T.s1),
                  child: Text(
                    task.text,
                    style: const TextStyle(
                      fontSize: T.fsBody,
                      color: T.text,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Back onto the list',
            child: _ShelfButton(
              icon: Icons.north_east_rounded,
              color: accent,
              onTap: onUnpark,
            ),
          ),
          Tooltip(
            message: 'Check it off from here',
            child: _ShelfButton(icon: Icons.check_rounded, onTap: onComplete),
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

Future<GroupEdit?> showGroupForm(
  BuildContext context, {
  ParkedGroup? existing,
}) {
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
            style: TextStyle(fontSize: T.fsLabel, color: T.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _options.entries)
                ChoiceChip(
                  label: Text(
                    e.value,
                    style: const TextStyle(fontSize: T.fsLabel),
                  ),
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
        // A word, not a chip: the rest of the line is plain text and icons,
        // and a filled pill was the last box left on the shelf.
        child: Container(
          height: Layout.of(context).tapTarget,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: T.s2),
          child: Text(
            'Review',
            style: TextStyle(
              fontSize: T.fsLabel,
              color: color,
              fontWeight: due ? T.wMedium : T.wNormal,
            ),
          ),
        ),
      ),
    );
  }
}

/// A shelf's icon control: a square the size the layout says a target is.
///
/// These were 14-15px glyphs with two or three pixels of padding - a control
/// you aim at twice on a phone - and the shelf is a view used mostly there.
class _ShelfButton extends StatelessWidget {
  const _ShelfButton({
    required this.icon,
    required this.onTap,
    this.color = T.muted,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(T.radius),
      child: SizedBox(
        width: layout.tapTarget,
        height: layout.tapTarget,
        child: Icon(icon, size: layout.actionIcon, color: color),
      ),
    );
  }
}
