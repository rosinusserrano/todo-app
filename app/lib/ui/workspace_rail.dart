// The workspace bar, unrolled down the left edge of a wide window.
//
// This is not a second navigation model - it is the *same* one with the popups
// taken off. In a 340px window the workspace list and the views have to hide
// behind two ▾ menus because there is no width for them; given [Layout.railMinWidth]
// there is, and a permanent list saves a press on every switch and, more to the
// point, tells you what exists. Same callbacks as [WorkspaceBar], so the shell
// swaps one for the other and nothing else changes.
//
// The click model is carried over exactly: tapping another workspace switches
// to it, tapping the one you are on opens it for editing. The pencil is only
// there because on a tab that behaviour was discoverable from the ▾ beside it
// and here there is no ▾.

import 'package:flutter/material.dart';

import '../layout.dart';
import '../sync/models.dart';
import '../theme.dart';
import 'workspace_bar.dart' show WorkspaceView;

class WorkspaceRail extends StatelessWidget {
  const WorkspaceRail({
    super.key,
    required this.workspaces,
    required this.currentUuid,
    required this.accent,
    required this.onSelect,
    required this.onEdit,
    required this.onCreate,
    required this.onShowTasks,
    required this.onOpenNotes,
    required this.onOpenParked,
    required this.onOpenHistory,
    required this.onOpenThoughts,
    required this.thoughtCount,
    required this.parkedReviewDue,
    required this.openView,
  });

  final List<Workspace> workspaces;
  final String? currentUuid;
  final Color accent;
  final ValueChanged<Workspace> onSelect;
  final ValueChanged<Workspace> onEdit;
  final VoidCallback onCreate;

  /// Closes whatever view is open. The ▾ menu gets this by re-picking the open
  /// entry; a list of destinations needs the destination to be in the list.
  final VoidCallback onShowTasks;

  final VoidCallback onOpenNotes;
  final VoidCallback onOpenParked;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenThoughts;

  /// Shown against Thoughts. The footer's meter is still the thing that
  /// escalates - this is just the count, so the rail is not lying by omission.
  final int thoughtCount;

  final bool parkedReviewDue;

  /// Null while the task list is showing.
  final WorkspaceView? openView;

  @override
  Widget build(BuildContext context) {
    final dueTint = T.complementary(accent);

    return Container(
      width: Layout.railWidth,
      padding: const EdgeInsets.fromLTRB(8, 2, 6, 8),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _RailLabel('Workspaces'),
          // The list scrolls and the views below it do not: with thirty
          // workspaces it is the list that should give, not the navigation.
          Flexible(
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final ws in workspaces)
                  _WorkspaceRow(
                    workspace: ws,
                    current: ws.uuid == currentUuid,
                    onTap: () =>
                        ws.uuid == currentUuid ? onEdit(ws) : onSelect(ws),
                    onEdit: () => onEdit(ws),
                  ),
              ],
            ),
          ),
          _RailItem(
            icon: Icons.add,
            label: 'New workspace',
            muted: true,
            onTap: onCreate,
          ),
          const SizedBox(height: 8),
          const _RailLabel('Views'),
          _RailItem(
            icon: Icons.check_circle_outline,
            label: 'Tasks',
            selected: openView == null,
            accent: accent,
            onTap: onShowTasks,
          ),
          _RailItem(
            icon: Icons.notes_rounded,
            label: 'Notes',
            selected: openView == WorkspaceView.notes,
            accent: accent,
            onTap: onOpenNotes,
          ),
          _RailItem(
            icon: Icons.inbox_rounded,
            label: 'Parked',
            selected: openView == WorkspaceView.parked,
            accent: accent,
            onTap: onOpenParked,
            trailing: parkedReviewDue
                ? Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: dueTint, shape: BoxShape.circle),
                  )
                : null,
          ),
          _RailItem(
            icon: Icons.history_rounded,
            label: 'History',
            selected: openView == WorkspaceView.history,
            accent: accent,
            onTap: onOpenHistory,
          ),
          if (thoughtCount > 0)
            _RailItem(
              icon: Icons.cloud_outlined,
              label: 'Thoughts',
              selected: openView == WorkspaceView.thoughts,
              accent: accent,
              onTap: onOpenThoughts,
              trailing: Text(
                '$thoughtCount',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: dueTint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailLabel extends StatelessWidget {
  const _RailLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: T.muted,
        ),
      ),
    );
  }
}

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    required this.workspace,
    required this.current,
    required this.onTap,
    required this.onEdit,
  });

  final Workspace workspace;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = T.parseHex(workspace.color);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: current ? color.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: current ? color.withValues(alpha: 0.5) : Colors.transparent,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    workspace.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: T.text,
                      fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (current)
                  Tooltip(
                    message: 'Edit workspace',
                    child: InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(5),
                      child: const Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(Icons.edit, size: 11, color: T.muted),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.muted = false,
    this.accent = T.accent,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool muted;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? accent
        : muted
            ? T.muted
            : T.text;

    return Material(
      color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
          child: Row(
            children: [
              Icon(icon, size: 14, color: selected ? accent : T.muted),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
