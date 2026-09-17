// Where a task - or a selection of them - can go: a shelf in this workspace, or
// the list or a shelf of any other.
//
// This replaced a picker that offered only this workspace's shelves. Filing
// something under the wrong workspace is the commonest misfiling there is (it
// was typed while the wrong list was on screen), and the only way to fix it was
// to delete it and type it again somewhere else.
//
// One menu for both jobs rather than a "park" menu and a "move" menu, because
// they are one question - *where does this belong* - and the answers sit
// naturally in one list: this workspace's shelves first (the common case, and
// what the old picker was), then each other workspace under its own name with
// its list at the top and its shelves beneath.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';

/// Where the picker was asked to send things. [groupUuid] null is the
/// workspace's list.
@immutable
class MoveTarget {
  const MoveTarget(this.workspaceUuid, [this.groupUuid]);

  final String workspaceUuid;
  final String? groupUuid;

  @override
  bool operator ==(Object other) =>
      other is MoveTarget &&
      other.workspaceUuid == workspaceUuid &&
      other.groupUuid == groupUuid;

  @override
  int get hashCode => Object.hash(workspaceUuid, groupUuid);
}

/// Sentinel for "New group…", which creates a shelf in the *current*
/// workspace and parks straight into it - the first park should not take two
/// passes. Not null: `showMenu` treats a null result as a dismissal.
const _newGroup = MoveTarget('#new');

Future<MoveTarget?> showMovePicker(
  BuildContext context, {
  required RelativeRect position,
  required String currentWorkspaceUuid,
  required List<Workspace> workspaces,
  required Map<String, List<ParkedGroup>> groups,
  required Future<ParkedGroup?> Function() onCreateGroup,
}) async {
  final here = groups[currentWorkspaceUuid] ?? const <ParkedGroup>[];
  final others = [
    for (final w in workspaces)
      if (w.uuid != currentWorkspaceUuid) w,
  ];

  final chosen = await showMenu<MoveTarget>(
    context: context,
    position: position,
    color: T.bgSolid,
    items: [
      if (here.isNotEmpty) const _Header('Park it here'),
      for (final g in here) _item(MoveTarget(currentWorkspaceUuid, g.uuid), g.title),
      const PopupMenuItem(
        value: _newGroup,
        height: 34,
        child: Text('New group…', style: TextStyle(fontSize: T.fsLabel)),
      ),
      for (final w in others) ...[
        const PopupMenuDivider(),
        _Header(w.name, color: T.parseHex(w.color)),
        _item(MoveTarget(w.uuid), 'Its list', icon: Icons.checklist_rounded),
        for (final g in groups[w.uuid] ?? const <ParkedGroup>[])
          _item(MoveTarget(w.uuid, g.uuid), g.title),
      ],
    ],
  );

  if (chosen != _newGroup) return chosen;
  final created = await onCreateGroup();
  return created == null ? null : MoveTarget(currentWorkspaceUuid, created.uuid);
}

PopupMenuItem<MoveTarget> _item(
  MoveTarget target,
  String label, {
  IconData icon = Icons.inbox_rounded,
}) =>
    PopupMenuItem(
      value: target,
      height: 34,
      child: Row(
        children: [
          Icon(icon, size: 14, color: T.muted),
          const SizedBox(width: T.s2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: T.fsLabel),
            ),
          ),
        ],
      ),
    );

/// A workspace's name over its destinations. Not selectable.
class _Header extends PopupMenuEntry<MoveTarget> {
  const _Header(this.label, {this.color});

  final String label;
  final Color? color;

  @override
  double get height => 26;

  @override
  bool represents(MoveTarget? value) => false;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s1, T.s3, 0),
      child: SizedBox(
        height: widget.height - T.s1,
        child: Row(
          children: [
            if (color != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: T.s2),
            ],
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: T.fsMeta,
                  fontWeight: T.wMedium,
                  color: T.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
