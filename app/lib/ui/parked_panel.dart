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

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';
import 'panel_header.dart';
import 'task_drag.dart';

class ParkedPanel extends StatefulWidget {
  const ParkedPanel({
    super.key,
    required this.groups,
    required this.parked,
    required this.accent,
    required this.onUnpark,
    required this.onComplete,
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
            PanelHeader(
              title: 'Parked',
              onBack: widget.onBack,
              actions: [
                Tooltip(
                  message: 'New group',
                  child: InkWell(
                    onTap: widget.onCreateGroup,
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.add, size: 15, color: T.muted),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: widget.groups.isEmpty ? _empty() : _list(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 26),
          child: Text(
            'No groups yet.\nMake one for the things you are not doing now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: T.muted, fontSize: 12.5, height: 1.5),
          ),
        ),
      );

  Widget _list() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
            onReviewed: () => widget.onReviewed(g),
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
      title: const Text('Activate this group?', style: TextStyle(fontSize: 15)),
      content: Text(
        count == 1
            ? 'The one todo in "${group.title}" will be put onto the active '
                'todo list.'
            : 'All $count todos in "${group.title}" will be put onto the '
                'active todo list.',
        style: const TextStyle(fontSize: 12.5, color: T.muted, height: 1.4),
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
    required this.onReviewed,
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
  final VoidCallback onReviewed;
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
      padding: const EdgeInsets.only(bottom: 6),
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
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: due ? tint.withValues(alpha: 0.55) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 7, 6, 7),
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
                        fontSize: 12.5,
                        color: due ? tint : T.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${tasks.length}',
                    style: const TextStyle(fontSize: 11, color: T.muted),
                  ),
                  const Spacer(),
                  Text(
                    _reviewLabel(group),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: due ? tint : T.muted,
                      fontWeight: due ? FontWeight.w600 : FontWeight.normal,
                    ),
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
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
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
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
            if (tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 10, 8),
                child: Text(
                  'Empty.',
                  style: TextStyle(fontSize: 11.5, color: T.muted),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onReviewed,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    due ? 'Mark reviewed' : 'Reviewed now',
                    style: TextStyle(fontSize: 11, color: due ? tint : T.muted),
                  ),
                ),
              ),
            ),
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
      padding: const EdgeInsets.fromLTRB(22, 1, 6, 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              task.text,
              style: const TextStyle(fontSize: 12, color: T.muted, height: 1.35),
            ),
          ),
          Tooltip(
            message: 'Back onto the list',
            child: InkWell(
              onTap: onUnpark,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Icon(Icons.north_east_rounded, size: 14, color: accent),
              ),
            ),
          ),
          Tooltip(
            message: 'Check it off from here',
            child: InkWell(
              onTap: onComplete,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
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
        style: const TextStyle(fontSize: 15),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            maxLength: 28,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Backlog, Future ideas…',
              counterText: '',
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          const Text(
            'Review this group',
            style: TextStyle(fontSize: 11.5, color: T.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _options.entries)
                ChoiceChip(
                  label: Text(e.value, style: const TextStyle(fontSize: 11.5)),
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

/// Picker shown when parking a task from its row. "New group…" is in the same
/// list rather than behind a separate button: the first time you park anything
/// there are no groups at all, and a menu with one disabled entry would be a
/// dead end.
Future<String?> showParkPicker(
  BuildContext context, {
  required RelativeRect position,
  required List<ParkedGroup> groups,
  required Future<ParkedGroup?> Function() onCreate,
}) async {
  const newGroup = '#new';

  final chosen = await showMenu<String>(
    context: context,
    position: position,
    color: T.bgSolid,
    items: [
      for (final g in groups)
        PopupMenuItem(
          value: g.uuid,
          height: 34,
          child: Text(g.title, style: const TextStyle(fontSize: 12.5)),
        ),
      if (groups.isNotEmpty) const PopupMenuDivider(),
      const PopupMenuItem(
        value: newGroup,
        height: 34,
        child: Text('New group…', style: TextStyle(fontSize: 12.5)),
      ),
    ],
  );

  if (chosen != newGroup) return chosen;
  return (await onCreate())?.uuid;
}
