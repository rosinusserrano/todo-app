// Where a task - or a selection of them, or side thoughts - can go: the list
// or a shelf of any workspace.
//
// This replaced a picker that offered only this workspace's shelves. Filing
// something under the wrong workspace is the commonest misfiling there is (it
// was typed while the wrong list was on screen), and the only way to fix it was
// to delete it and type it again somewhere else.
//
// One menu for both jobs rather than a "park" menu and a "move" menu, because
// they are one question - *where does this belong*.
//
// **Workspaces first, their destinations beside them** (Marco, 2026-11-24).
// It was one long menu - this workspace's shelves, then every other workspace
// under a header with its list and all its shelves - which grew with every
// shelf anyone made until the workspace you wanted was a scroll away. Now the
// panel lists only workspaces (this one first, projects indented under their
// own), and the one under the mouse - or the one tapped, on a finger -
// opens a second panel beside it with its list, its shelves, and, for this
// workspace, *New group…*. Hover waits [_hoverDelay] so crossing the list on
// the way to the flyout does not open every row on the way; a click or tap
// opens at once, because that is what a finger has instead.
//
// A custom route rather than Material's `MenuAnchor`, which has submenus: a
// `MenuAnchor` is a widget that must already be in the tree where it opens,
// and this is opened from a row, a selection bar and a swipe, none of which
// should carry one. The two panels are placed by delegates for
// task_actions.dart's reason - where they go depends on their size.

import 'dart:async';

import 'package:flutter/material.dart';

import '../layout.dart';
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
/// passes. Not null: a null result is a dismissal.
const _newGroup = MoveTarget('#new');

/// How long the mouse rests on a workspace before its destinations open.
const _hoverDelay = Duration(milliseconds: 140);

/// [position] is read for its top-left: the picker opens below and to the
/// right of that point, in the overlay's space (see `taskActionAnchor`).
Future<MoveTarget?> showMovePicker(
  BuildContext context, {
  required RelativeRect position,
  required String currentWorkspaceUuid,
  required List<Workspace> workspaces,
  required Map<String, List<ParkedGroup>> groups,
  required Future<ParkedGroup?> Function() onCreateGroup,
  bool includeHereList = false,
}) async {
  final layout = Layout.of(context);
  final chosen = await showGeneralDialog<MoveTarget>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // Transparent for the action bar's reason: a menu over a row you can
    // still see, not a modal dialog.
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, _, _) => _MovePicker(
      at: Offset(position.left, position.top),
      layout: layout,
      here: currentWorkspaceUuid,
      workspaces: _hereFirst(workspaces, currentWorkspaceUuid),
      groups: groups,
      includeHereList: includeHereList,
    ),
    transitionBuilder: (context, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );

  if (chosen != _newGroup) return chosen;
  final created = await onCreateGroup();
  return created == null ? null : MoveTarget(currentWorkspaceUuid, created.uuid);
}

/// [AppState.moveTargets]'s order - each workspace followed by its projects -
/// with the block holding this workspace moved to the top, since parking here
/// is still the commonest answer.
List<Workspace> _hereFirst(List<Workspace> all, String here) {
  final at = all.indexWhere((w) => w.uuid == here);
  if (at < 0) return all;
  final home = all[at].isProject ? all[at].parentUuid : all[at].uuid;
  bool inBlock(Workspace w) => w.uuid == home || w.parentUuid == home;
  return [...all.where(inBlock), ...all.where((w) => !inBlock(w))];
}

class _MovePicker extends StatefulWidget {
  const _MovePicker({
    required this.at,
    required this.layout,
    required this.here,
    required this.workspaces,
    required this.groups,
    required this.includeHereList,
  });

  final Offset at;
  final Layout layout;
  final String here;
  final List<Workspace> workspaces;
  final Map<String, List<ParkedGroup>> groups;
  final bool includeHereList;

  @override
  State<_MovePicker> createState() => _MovePickerState();
}

class _MovePickerState extends State<_MovePicker> {
  static const _margin = 8.0;
  static const _gap = 4.0;

  final _stackKey = GlobalKey();
  final _rowKeys = <String, GlobalKey>{};

  /// The workspace whose destinations are showing, and its row's box in the
  /// picker's space - measured when it opens, which is after layout.
  String? _open;
  Rect? _openRow;

  Timer? _hover;
  String? _hoverFor;

  double get _rowHeight => widget.layout.touch ? 40 : 30;

  @override
  void dispose() {
    _hover?.cancel();
    super.dispose();
  }

  void _openFor(String uuid) {
    _hover?.cancel();
    _hoverFor = null;
    final row = _rowKeys[uuid]?.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (row == null || stack == null) return;
    setState(() {
      _open = uuid;
      _openRow = row.localToGlobal(Offset.zero, ancestor: stack) & row.size;
    });
  }

  void _enter(String uuid) {
    if (_open == uuid) return;
    _hover?.cancel();
    _hoverFor = uuid;
    _hover = Timer(_hoverDelay, () {
      if (mounted && _hoverFor == uuid) _openFor(uuid);
    });
  }

  /// Only the timer this row started: enter and exit of neighbouring rows do
  /// not arrive in a promised order.
  void _exit(String uuid) {
    if (_hoverFor != uuid) return;
    _hover?.cancel();
    _hoverFor = null;
  }

  /// The mouse reached the flyout: whatever row it crossed on the way there
  /// was only being crossed.
  void _enterFlyout() {
    _hover?.cancel();
    _hoverFor = null;
  }

  /// Two panels side by side when they fit; narrower ones on a narrow window
  /// rather than a flyout that lands on top of the list it came from.
  double _panelWidth(double available) =>
      ((available - _margin * 2 - _gap) / 2).clamp(140.0, 220.0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = _panelWidth(box.maxWidth);
        final open = _open;
        final openRow = _openRow;
        return Stack(
          key: _stackKey,
          children: [
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: _MainPlace(widget.at, width, _gap, _margin),
                child: _panel(_workspaceList(width)),
              ),
            ),
            if (open != null && openRow != null)
              Positioned.fill(
                child: CustomSingleChildLayout(
                  delegate: _FlyoutPlace(openRow, width, _gap, _margin),
                  child: MouseRegion(
                    onEnter: (_) => _enterFlyout(),
                    child: _panel(_destinations(open, width)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _panel(Widget child) => Material(
    color: T.bgSolid,
    elevation: 10,
    shadowColor: const Color(0x88000000),
    borderRadius: BorderRadius.circular(T.radius),
    clipBehavior: Clip.antiAlias,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(T.radius),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      padding: const EdgeInsets.all(T.s1),
      child: child,
    ),
  );

  Widget _workspaceList(double width) {
    return SizedBox(
      width: width,
      // A long list scrolls; the flyout is placed from a row measured when
      // it opened, so scrolling closes it rather than leaving it pointing at
      // where the row used to be.
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (_) {
          if (_open != null) setState(() => _open = null);
          return false;
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Caption('Move to'),
              for (final w in widget.workspaces) _workspaceRow(w),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workspaceRow(Workspace w) {
    final open = _open == w.uuid;
    final here = w.uuid == widget.here;
    return MouseRegion(
      onEnter: (_) => _enter(w.uuid),
      onExit: (_) => _exit(w.uuid),
      child: InkWell(
        key: _rowKeys.putIfAbsent(w.uuid, GlobalKey.new),
        onTap: () => _openFor(w.uuid),
        borderRadius: BorderRadius.circular(T.radius),
        child: Container(
          height: _rowHeight,
          decoration: BoxDecoration(
            color: open ? T.surfaceHover : null,
            borderRadius: BorderRadius.circular(T.radius),
          ),
          padding: EdgeInsets.only(
            left: w.isProject ? T.s4 + T.s1 : T.s2,
            right: T.s1,
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: T.parseHex(_colorOf(w)),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: T.s2),
              Expanded(
                child: Text(
                  here && w.isProject ? _name(w, widget.workspaces) : w.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: T.fsLabel,
                    fontWeight: here ? T.wMedium : null,
                  ),
                ),
              ),
              if (here)
                const Padding(
                  padding: EdgeInsets.only(left: T.s1),
                  child: Text(
                    'here',
                    style: TextStyle(fontSize: T.fsMeta, color: T.muted),
                  ),
                ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: open ? T.text : T.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A project draws its parent's colour, as everywhere else.
  String _colorOf(Workspace w) {
    if (!w.isProject) return w.color;
    return widget.workspaces
            .where((p) => p.uuid == w.parentUuid)
            .firstOrNull
            ?.color ??
        w.color;
  }

  Widget _destinations(String uuid, double width) {
    final here = uuid == widget.here;
    final shelves = widget.groups[uuid] ?? const <ParkedGroup>[];
    return SizedBox(
      width: width,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A task is already on this list, so it is not offered here; a
            // side thought is on no list at all, and this is its commonest
            // destination.
            if (!here || widget.includeHereList)
              _destination(
                MoveTarget(uuid),
                here ? 'This list' : 'List',
                Icons.checklist_rounded,
              ),
            for (final g in shelves)
              _destination(MoveTarget(uuid, g.uuid), g.title, Icons.inbox_rounded),
            if (here)
              _destination(_newGroup, 'New group…', Icons.add_rounded),
          ],
        ),
      ),
    );
  }

  Widget _destination(MoveTarget target, String label, IconData icon) =>
      InkWell(
        onTap: () => Navigator.of(context).pop(target),
        borderRadius: BorderRadius.circular(T.radius),
        child: Container(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: T.s2),
          child: Row(
            children: [
              Icon(icon, size: 14, color: T.muted),
              const SizedBox(width: T.s2),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: T.fsLabel),
                ),
              ),
            ],
          ),
        ),
      );
}

/// The workspace panel: below [at], moved left far enough that the flyout
/// still fits to its right, and never off an edge.
class _MainPlace extends SingleChildLayoutDelegate {
  const _MainPlace(this.at, this.width, this.gap, this.margin);

  final Offset at;
  final double width;
  final double gap;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(constraints.maxWidth, constraints.maxHeight - margin * 2),
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = at.dx;
    final both = child.width * 2 + gap;
    if (x + both > size.width - margin) x = size.width - margin - both;
    if (x + child.width > size.width - margin) {
      x = size.width - margin - child.width;
    }
    if (x < margin) x = margin;
    var y = at.dy + gap;
    if (y + child.height > size.height - margin) {
      y = size.height - margin - child.height;
    }
    if (y < margin) y = margin;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MainPlace old) =>
      old.at != at || old.width != width;
}

/// The destinations: level with their workspace's row, to its right if there
/// is room, else to its left, else as far right as the window allows.
class _FlyoutPlace extends SingleChildLayoutDelegate {
  const _FlyoutPlace(this.row, this.width, this.gap, this.margin);

  /// The workspace row, in the picker's space. The panel's padding is
  /// outside it, hence the [T.s1]s.
  final Rect row;
  final double width;
  final double gap;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(constraints.maxWidth, constraints.maxHeight - margin * 2),
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = row.right + T.s1 + gap;
    if (x + child.width > size.width - margin) {
      final left = row.left - T.s1 - gap - child.width;
      x = left >= margin ? left : size.width - margin - child.width;
    }
    var y = row.top - T.s1;
    if (y + child.height > size.height - margin) {
      y = size.height - margin - child.height;
    }
    if (y < margin) y = margin;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_FlyoutPlace old) =>
      old.row != row || old.width != width;
}

/// The picker's title line. Not a row: nothing happens on it.
class _Caption extends StatelessWidget {
  const _Caption(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(T.s2, T.s1, T.s2, T.s1),
    child: Text(
      label,
      style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
    ),
  );
}

/// A project is named under its workspace - "Work › Launch" - since two
/// workspaces can each have a project of the same name.
String _name(Workspace w, List<Workspace> all) {
  if (!w.isProject) return w.name;
  final parent = all.where((p) => p.uuid == w.parentUuid).firstOrNull;
  return parent == null ? w.name : '${parent.name} › ${w.name}';
}

/// Where a whole thing - a collection - goes: any workspace or project but
/// the one it is in. Resolves to the chosen one's uuid, or null.
///
/// [targets] is `AppState.moveTargets`, each workspace followed by its
/// projects, which is the order this lists them in; a project is drawn
/// indented under its workspace and named on its own.
Future<String?> showWorkspacePicker(
  BuildContext context, {
  required RelativeRect position,
  required String currentWorkspaceUuid,
  required List<Workspace> targets,
  String title = 'Move to',
}) {
  return showMenu<String>(
    context: context,
    position: position,
    color: T.bgSolid,
    items: [
      _WorkspaceHeader(title),
      for (final w in targets)
        if (w.uuid != currentWorkspaceUuid)
          PopupMenuItem(
            value: w.uuid,
            height: 34,
            child: Padding(
              padding: EdgeInsets.only(left: w.isProject ? T.s4 : 0),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: T.parseHex(
                        w.isProject
                            ? targets
                                      .where((p) => p.uuid == w.parentUuid)
                                      .firstOrNull
                                      ?.color ??
                                  w.color
                            : w.color,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: T.s2),
                  Flexible(
                    child: Text(
                      w.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: T.fsLabel),
                    ),
                  ),
                ],
              ),
            ),
          ),
    ],
  );
}

class _WorkspaceHeader extends PopupMenuEntry<String> {
  const _WorkspaceHeader(this.label);

  final String label;

  @override
  double get height => 26;

  @override
  bool represents(String? value) => false;

  @override
  State<_WorkspaceHeader> createState() => _WorkspaceHeaderState();
}

class _WorkspaceHeaderState extends State<_WorkspaceHeader> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s3, 2),
    child: Text(
      widget.label,
      style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
    ),
  );
}
