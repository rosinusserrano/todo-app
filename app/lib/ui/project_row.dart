// A project's row in its workspace's list, and the few prompts it needs.
//
// A project is a workspace with a parent (`Workspace.parentUuid`): opening it
// makes it the current workspace, and its list, notes, shelves, collections
// and history are its own. In the parent's list it is one row among the
// tasks, in their shared order, and it is drawn as the one thing on the list
// that is **not** a task:
//
//   - **A block, not a line.** Tasks sit on the window's own colour with a
//     rule between them; a project is a flat fill of the workspace's colour,
//     the dock's view-segment mix (30%), so it reads as part of the same
//     family as the bar that names the workspace. No border, for the reason
//     list_rule.dart gives.
//   - **No tick box.** A project is not done, it is put away, so the box's
//     column holds a folder in the workspace's colour - the title still starts
//     where every task's does.
//   - **The display face**, a size up from a task, because it names a place
//     the way a view's title does.
//   - **What is in it**, "4 open", where a task's marks would be.
//
// Its actions are a menu (the ⋯, or a right-click): Open, Rename, Archive,
// Delete. Archive is not confirmed - Settings' archive gives it back - and
// Delete is, because nothing does.

import 'package:flutter/material.dart';

import '../layout.dart';
import '../sync/models.dart';
import '../theme.dart';
import 'form_sheet.dart';

enum ProjectAction { open, rename, archive, delete }

class ProjectRow extends StatefulWidget {
  const ProjectRow({
    super.key,
    required this.project,
    required this.accent,
    required this.openCount,
    required this.onOpen,
    required this.onAction,
    this.dragHandle,
  });

  final Workspace project;

  /// The workspace's colour (a project has no colour of its own).
  final Color accent;

  /// Open tasks on its list.
  final int openCount;

  final VoidCallback onOpen;
  final void Function(ProjectAction action) onAction;

  /// The list's reorder grip, under a pointer; null on touch, where the whole
  /// row is picked up by a long press (the list's, as for a task).
  final Widget? dragHandle;

  @override
  State<ProjectRow> createState() => _ProjectRowState();
}

class _ProjectRowState extends State<ProjectRow> {
  final _moreKey = GlobalKey();
  bool _hovered = false;

  Future<void> _menu({Offset? at}) async {
    final chosen = await showProjectMenu(context, at: at, anchor: _moreKey);
    if (chosen != null) widget.onAction(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final touch = layout.touch;
    final fill = Color.lerp(T.bgSolid, widget.accent, _hovered ? 0.38 : 0.30)!;
    final n = widget.openCount;

    return Padding(
      // A block between rules: a little air above and below so it does not
      // sit on the hairline of the task before it.
      padding: const EdgeInsets.symmetric(vertical: T.s1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          button: true,
          label: 'Project ${widget.project.name}, $n open',
          child: Material(
            color: fill,
            borderRadius: BorderRadius.circular(T.radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(T.radius),
              onTap: widget.onOpen,
              onSecondaryTapUp: touch
                  ? null
                  : (d) => _menu(at: d.globalPosition),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: T.s2,
                  vertical: T.s3,
                ),
                child: Row(
                  children: [
                    // In the tick box's column, the tick box's width.
                    SizedBox(
                      width: 18,
                      child: Icon(
                        Icons.folder_rounded,
                        size: 18,
                        color: widget.accent,
                      ),
                    ),
                    const SizedBox(width: T.s2),
                    Expanded(
                      child: Text(
                        widget.project.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: T.fontDisplay,
                          fontSize: T.fsMenu,
                          fontWeight: T.wMedium,
                          color: T.text,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: T.s2),
                    Text(
                      n == 0 ? 'empty' : '$n open',
                      style: const TextStyle(
                        fontFamily: T.fontDisplay,
                        fontSize: T.fsMeta,
                        color: T.muted,
                      ),
                    ),
                    InkResponse(
                      key: _moreKey,
                      onTap: _menu,
                      radius: 16,
                      child: Padding(
                        padding: EdgeInsets.all(touch ? T.s2 : T.s1),
                        child: Icon(
                          Icons.more_horiz_rounded,
                          size: touch ? 18 : 16,
                          color: T.muted,
                        ),
                      ),
                    ),
                    if (widget.dragHandle != null) widget.dragHandle!,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A project's actions, at a right-click's [at] or under [anchor]. The list's
/// row and the open project's header both use it, so the two cannot offer
/// different things.
Future<ProjectAction?> showProjectMenu(
  BuildContext context, {
  Offset? at,
  required GlobalKey anchor,
}) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final Rect rect;
  if (at != null) {
    rect = overlay.globalToLocal(at) & Size.zero;
  } else {
    final box = anchor.currentContext!.findRenderObject()! as RenderBox;
    final r = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    rect = Rect.fromLTWH(r.left, r.bottom, r.width, 0);
  }
  PopupMenuItem<ProjectAction> item(
    ProjectAction value,
    IconData icon,
    String label, {
    Color color = T.text,
  }) => PopupMenuItem(
    value: value,
    height: 38,
    child: Row(
      children: [
        Icon(icon, size: 16, color: color == T.text ? T.muted : color),
        const SizedBox(width: T.s2),
        Text(
          label,
          style: TextStyle(fontSize: T.fsLabel, color: color),
        ),
      ],
    ),
  );
  return showMenu<ProjectAction>(
    context: context,
    color: T.bgSolid,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    items: [
      item(ProjectAction.open, Icons.folder_open_outlined, 'Open'),
      item(ProjectAction.rename, Icons.edit_outlined, 'Rename'),
      item(ProjectAction.archive, Icons.archive_outlined, 'Archive'),
      item(
        ProjectAction.delete,
        Icons.delete_outline_rounded,
        'Delete',
        color: T.danger,
      ),
    ],
  );
}

/// Asks for a project's name - a new one, or [initial] to rename. Null when
/// cancelled or left empty.
Future<String?> askProjectName(
  BuildContext context, {
  required Color accent,
  String initial = '',
}) {
  return showFormSheet<String>(
    context,
    builder: (context, layout) =>
        _ProjectNameSheet(layout: layout, accent: accent, initial: initial),
  );
}

class _ProjectNameSheet extends StatefulWidget {
  const _ProjectNameSheet({
    required this.layout,
    required this.accent,
    required this.initial,
  });

  final Layout layout;
  final Color accent;
  final String initial;

  @override
  State<_ProjectNameSheet> createState() => _ProjectNameSheetState();
}

class _ProjectNameSheetState extends State<_ProjectNameSheet> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final touch = widget.layout.touch;
    return FormSheet(
      accent: widget.accent,
      layout: widget.layout,
      title: widget.initial.isEmpty ? 'New project' : 'Rename project',
      maxWidth: 360,
      onClose: () => Navigator.of(context).pop(),
      actions: [
        FormSheet.cancelButton(
          touch: touch,
          onTap: () => Navigator.of(context).pop(),
        ),
        FormSheet.saveButton(touch: touch, accent: widget.accent, onTap: _save),
      ],
      child: TextField(
        controller: _name,
        autofocus: true,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _save(),
        style: const TextStyle(fontSize: T.fsBody, color: T.text),
        decoration: const InputDecoration(hintText: 'Name', isDense: true),
      ),
    );
  }
}

/// Deleting a project deletes everything in it, and unlike archiving there is
/// no way back - so it asks.
Future<bool> confirmDeleteProject(BuildContext context, Workspace p) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: T.bgSolid,
      title: Text(
        'Delete "${p.name}"?',
        style: const TextStyle(fontSize: T.fsMenu),
      ),
      content: const Text(
        'Its tasks, notes, shelves and collections are deleted with it, on '
        'every device. Archive keeps them instead.',
        style: TextStyle(fontSize: T.fsLabel, color: T.muted, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: T.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return yes ?? false;
}
