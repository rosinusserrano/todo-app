// The active-workspace tab, the switcher dropdown, the per-workspace views menu,
// and the edit form.
//
// Tasks belong to exactly one workspace; side thoughts stay global across all
// of them. Only the active workspace is shown as a tab - clicking its name opens
// it for editing. The ▾ *inside* the tab's right edge lists the other
// workspaces; picking one switches to it. (This replaced a scrolling row of
// every tab, which ate the width on a 340px window once there were more than a
// few.)
//
// That arrow lives inside the pill rather than beside it because the views menu
// further along the bar is a free-standing ▾: two bare arrows sitting loose in
// one 340px row read as two of the same control. Inside the pill, the arrow is
// visibly a part of the workspace tab and the loose one is visibly not.
//
// The second ▾ menu holds the views that are *about the current workspace* -
// Notes, Parked and History. They used to sit in the title bar beside the window
// controls; they live here now because they belong to the workspace, not the
// window, and the grouping reads more clearly. A lapsed parked-group review
// shows as a dot on the menu, since the panel is closed most of the time.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';

/// Which of the per-workspace views currently owns the content area, so the ▾
/// menu can say so. Re-picking the open one closes it - true before this
/// existed too, but nothing on screen admitted it.
///
/// [thoughts] is not in the ▾ menu: the pile is global, and its way in is the
/// count on the footer, which is where the pressure is shown. It is in this
/// enum because [WorkspaceRail] lists every view that can own the content area
/// and would otherwise light up Tasks while the thoughts panel is on screen.
enum WorkspaceView { notes, parked, history, thoughts }

class WorkspaceBar extends StatelessWidget {
  const WorkspaceBar({
    super.key,
    required this.workspaces,
    required this.currentUuid,
    required this.accent,
    required this.onSelect,
    required this.onEdit,
    required this.onCreate,
    required this.onOpenNotes,
    required this.onOpenParked,
    required this.onOpenHistory,
    required this.parkedReviewDue,
    required this.openView,
  });

  final List<Workspace> workspaces;
  final String? currentUuid;
  final Color accent;
  final ValueChanged<Workspace> onSelect;
  final ValueChanged<Workspace> onEdit;
  final VoidCallback onCreate;

  final VoidCallback onOpenNotes;
  final VoidCallback onOpenParked;
  final VoidCallback onOpenHistory;

  /// A parked group in this workspace has gone past its review interval - the
  /// dot on the views menu is the only thing that says so while the panel is
  /// closed.
  final bool parkedReviewDue;

  /// Null when the task list is showing.
  final WorkspaceView? openView;

  @override
  Widget build(BuildContext context) {
    final current = workspaces.firstWhere(
      (ws) => ws.uuid == currentUuid,
      orElse: () => workspaces.first,
    );
    final others = [for (final ws in workspaces) if (ws.uuid != current.uuid) ws];

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Flexible(
            child: _Tab(
              workspace: current,
              others: others,
              onTap: () => onEdit(current),
              onSelect: onSelect,
            ),
          ),
          const Spacer(),
          _ViewsMenu(
            accent: accent,
            parkedReviewDue: parkedReviewDue,
            openView: openView,
            onOpenNotes: onOpenNotes,
            onOpenParked: onOpenParked,
            onOpenHistory: onOpenHistory,
          ),
          Tooltip(
            message: 'New workspace',
            child: InkWell(
              onTap: onCreate,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Icon(Icons.add, size: 15, color: T.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The per-workspace views, gathered under one ▾. A popup rather than three
/// more icons in the row: on a 340px window the tabs need the width, and these
/// are opened occasionally, not constantly.
class _ViewsMenu extends StatelessWidget {
  const _ViewsMenu({
    required this.accent,
    required this.parkedReviewDue,
    required this.openView,
    required this.onOpenNotes,
    required this.onOpenParked,
    required this.onOpenHistory,
  });

  final Color accent;
  final bool parkedReviewDue;
  final WorkspaceView? openView;
  final VoidCallback onOpenNotes;
  final VoidCallback onOpenParked;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final dueTint = T.complementary(accent);
    return PopupMenuButton<int>(
      tooltip: parkedReviewDue ? 'Views — a parked group is due' : 'Views',
      color: T.bgSolid,
      position: PopupMenuPosition.under,
      onSelected: (v) => switch (v) {
        0 => onOpenNotes(),
        1 => onOpenParked(),
        _ => onOpenHistory(),
      },
      itemBuilder: (context) => [
        _item(0, Icons.notes_rounded, 'Notes', WorkspaceView.notes),
        _item(
          1,
          Icons.inbox_rounded,
          'Parked',
          WorkspaceView.parked,
          trailing: parkedReviewDue
              ? Text('review due',
                  style: TextStyle(
                      fontSize: 10.5, color: dueTint, fontWeight: FontWeight.w600))
              : null,
        ),
        _item(2, Icons.history_rounded, 'History', WorkspaceView.history),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // An overdue review outranks the open view: it is news, and the
            // open view is already obvious from the content area.
            Icon(Icons.expand_more_rounded,
                size: 18,
                color: parkedReviewDue
                    ? dueTint
                    : openView != null
                        ? accent
                        : T.muted),
            if (parkedReviewDue)
              Positioned(
                right: -2,
                top: -1,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: dueTint, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The open view is ticked and tinted, and picking it again closes it. That
  /// was always true; without the tick nothing said so, which left these views
  /// looking like one-way doors.
  PopupMenuItem<int> _item(
    int value,
    IconData icon,
    String label,
    WorkspaceView view, {
    Widget? trailing,
  }) {
    final open = openView == view;
    return PopupMenuItem<int>(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 16, color: open ? accent : T.muted),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: open ? accent : T.text,
              fontWeight: open ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing],
          if (open) ...[
            if (trailing == null) const Spacer(),
            const SizedBox(width: 6),
            Icon(Icons.check_rounded, size: 14, color: accent),
          ],
        ],
      ),
    );
  }
}

/// The switcher for the workspaces that aren't active. A popup rather than a row
/// of tabs so the bar stays a fixed width no matter how many workspaces exist.
/// Drawn as the right-hand end of [_Tab], which owns the outline around it.
class _SwitcherMenu extends StatelessWidget {
  const _SwitcherMenu({
    required this.others,
    required this.onSelect,
    required this.radius,
  });

  final List<Workspace> others;
  final ValueChanged<Workspace> onSelect;

  /// The enclosing pill's corner radius, so the tap highlight follows it.
  final Radius radius;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Workspace>(
      tooltip: 'Switch workspace',
      color: T.bgSolid,
      position: PopupMenuPosition.under,
      borderRadius: BorderRadius.only(topRight: radius, bottomRight: radius),
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final ws in others)
          PopupMenuItem<Workspace>(
            value: ws,
            height: 38,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: T.parseHex(ws.color),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(ws.name,
                    style: const TextStyle(fontSize: 12.5, color: T.text)),
              ],
            ),
          ),
      ],
      // Smaller than the free-standing views ▾: this one is a detail on a
      // control that is already there, not a button in its own right.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 5, 5, 5),
        child: Icon(Icons.expand_more_rounded,
            size: 15, color: T.text.withValues(alpha: 0.75)),
      ),
    );
  }
}

/// The active workspace's pill. Since only the active one is ever drawn there
/// is no inactive styling left - the tab is always the current workspace.
///
/// It is split into two hit areas sharing one outline: the name opens the edit
/// form, the ▾ on the right opens the switcher. [others] empty means this is
/// the only workspace, and the pill carries no arrow at all.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.workspace,
    required this.others,
    required this.onTap,
    required this.onSelect,
  });

  final Workspace workspace;
  final List<Workspace> others;
  final VoidCallback onTap;
  final ValueChanged<Workspace> onSelect;

  @override
  Widget build(BuildContext context) {
    final color = T.parseHex(workspace.color);
    final hasSwitcher = others.isNotEmpty;
    const radius = Radius.circular(7);

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: const BorderRadius.all(radius),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InkWell(
                onTap: onTap,
                // Square off the inner corners so the tap highlight cannot
                // round away from the outline it sits inside.
                borderRadius: BorderRadius.only(
                  topLeft: radius,
                  bottomLeft: radius,
                  topRight: hasSwitcher ? Radius.zero : radius,
                  bottomRight: hasSwitcher ? Radius.zero : radius,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(9, 5, hasSwitcher ? 7 : 9, 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration:
                            BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          workspace.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: T.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (hasSwitcher) ...[
              // Fixed height rather than a Border on the arrow: a stretched
              // divider would need the Row to size on the cross axis, and this
              // Row is deliberately unbounded there.
              Container(
                width: 1,
                height: 16,
                color: color.withValues(alpha: 0.4),
              ),
              _SwitcherMenu(
                others: others,
                onSelect: onSelect,
                radius: radius,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Create/edit sheet. Returns null on cancel, a [WorkspaceEdit] on save, and
/// [WorkspaceEdit.deleted] when the workspace should be removed.
class WorkspaceEdit {
  const WorkspaceEdit(this.name, this.color, {this.delete = false});

  final String name;
  final String color;
  final bool delete;

  static const deleted = WorkspaceEdit('', '', delete: true);
}

Future<WorkspaceEdit?> showWorkspaceForm(
  BuildContext context, {
  Workspace? existing,
  required int workspaceCount,
}) {
  return showDialog<WorkspaceEdit>(
    context: context,
    builder: (context) => _WorkspaceDialog(
      existing: existing,
      canDelete: existing != null && workspaceCount > 1,
      initialColor: existing != null
          ? T.parseHex(existing.color)
          : T.workspaceColors[workspaceCount % T.workspaceColors.length],
    ),
  );
}

class _WorkspaceDialog extends StatefulWidget {
  const _WorkspaceDialog({
    required this.existing,
    required this.canDelete,
    required this.initialColor,
  });

  final Workspace? existing;
  final bool canDelete;
  final Color initialColor;

  @override
  State<_WorkspaceDialog> createState() => _WorkspaceDialogState();
}

class _WorkspaceDialogState extends State<_WorkspaceDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late Color _color = widget.initialColor;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, WorkspaceEdit(name, T.toHex(_color)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: T.bgSolid,
      title: Text(
        widget.existing == null ? 'New workspace' : 'Edit workspace',
        style: const TextStyle(fontSize: 15),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 24,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Workspace name…',
              counterText: '',
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in T.workspaceColors)
                InkWell(
                  onTap: () => setState(() => _color = c),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == _color ? T.text : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.canDelete)
          TextButton(
            onPressed: () => Navigator.pop(context, WorkspaceEdit.deleted),
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
