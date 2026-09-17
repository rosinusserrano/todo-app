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
//
// **Collapsed** it is a strip of [Layout.railCollapsedWidth]: one coloured dot
// per workspace and one icon per view, each with its name in a tooltip. Still
// the same navigation - every destination the full rail offers is on the strip
// - and the choice is remembered, because somebody who folds the rail away to
// give a note the width wants it folded the next time too.

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
    this.collapsed = false,
    this.onToggleCollapsed,
    this.onAddTask,
  });

  /// Opens the add field. First under Views, since adding is to the list the
  /// Tasks entry below it shows.
  final VoidCallback? onAddTask;

  /// Drawn as the narrow strip. See the header.
  final bool collapsed;

  /// Null hides the toggle, which is how a test pumps the rail without one.
  final VoidCallback? onToggleCollapsed;

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
    if (collapsed) return _strip();
    final dueTint = T.complementary(accent);

    return Container(
      width: Layout.railWidth,
      padding: const EdgeInsets.fromLTRB(T.s2, 2, T.s2, T.s2),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RailLabel(
            'Workspaces',
            trailing: onToggleCollapsed == null
                ? null
                : _StripButton(
                    icon: Icons.keyboard_double_arrow_left_rounded,
                    tooltip: 'Collapse the sidebar',
                    onTap: onToggleCollapsed!,
                    size: 24,
                  ),
          ),
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
          if (onAddTask != null)
            _RailItem(
              icon: Icons.add_rounded,
              label: 'Add task',
              accent: accent,
              onTap: onAddTask!,
            ),
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
                  fontSize: T.fsMeta,
                  fontWeight: T.wMedium,
                  color: dueTint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension on WorkspaceRail {
  /// The rail folded down to its marks. Same destinations, same order.
  Widget _strip() {
    final dueTint = T.complementary(accent);
    Widget view(
      IconData icon,
      String label,
      WorkspaceView? view,
      VoidCallback onTap, {
      Widget? badge,
    }) =>
        _StripButton(
          icon: icon,
          tooltip: label,
          onTap: onTap,
          selected: openView == view,
          accent: accent,
          badge: badge,
        );

    return Container(
      width: Layout.railCollapsedWidth,
      padding: const EdgeInsets.symmetric(vertical: T.s1),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Column(
        children: [
          if (onToggleCollapsed != null)
            _StripButton(
              icon: Icons.keyboard_double_arrow_right_rounded,
              tooltip: 'Expand the sidebar',
              onTap: onToggleCollapsed!,
            ),
          const SizedBox(height: T.s1),
          Flexible(
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final ws in workspaces)
                  _WorkspaceDot(
                    workspace: ws,
                    current: ws.uuid == currentUuid,
                    onTap: () =>
                        ws.uuid == currentUuid ? onEdit(ws) : onSelect(ws),
                  ),
              ],
            ),
          ),
          _StripButton(icon: Icons.add, tooltip: 'New workspace', onTap: onCreate),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: T.s2, vertical: T.s1),
            child: Divider(height: 1, thickness: 1, color: Color(0x14FFFFFF)),
          ),
          if (onAddTask != null)
            _StripButton(
              icon: Icons.add_rounded,
              tooltip: 'Add task (N)',
              onTap: onAddTask!,
            ),
          view(Icons.check_circle_outline, 'Tasks', null, onShowTasks),
          view(Icons.notes_rounded, 'Notes', WorkspaceView.notes, onOpenNotes),
          view(
            Icons.inbox_rounded,
            'Parked',
            WorkspaceView.parked,
            onOpenParked,
            badge: parkedReviewDue ? _Dot(color: dueTint) : null,
          ),
          view(Icons.history_rounded, 'History', WorkspaceView.history,
              onOpenHistory),
          if (thoughtCount > 0)
            view(
              Icons.cloud_outlined,
              'Thoughts ($thoughtCount)',
              WorkspaceView.thoughts,
              onOpenThoughts,
              badge: _Dot(color: dueTint),
            ),
        ],
      ),
    );
  }
}

class _RailLabel extends StatelessWidget {
  const _RailLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(T.s2, trailing == null ? T.s2 : 0, 0, T.s1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: T.fsMeta,
                letterSpacing: 0.8,
                fontWeight: T.wMedium,
                color: T.muted,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// One square icon on the collapsed strip, with its name as the tooltip.
class _StripButton extends StatelessWidget {
  const _StripButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.accent = T.accent,
    this.badge,
    this.size = 32,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;
  final Color accent;
  final Widget? badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(T.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(T.radius),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  size: size < 30 ? 13 : 15,
                  color: selected ? accent : T.muted,
                ),
                if (badge != null) Positioned(top: 5, right: 5, child: badge!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A workspace on the collapsed strip: its colour, ringed when it is current.
/// The click model is the full rail's - another workspace switches, the
/// current one opens for editing.
class _WorkspaceDot extends StatelessWidget {
  const _WorkspaceDot({
    required this.workspace,
    required this.current,
    required this.onTap,
  });

  final Workspace workspace;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = T.parseHex(workspace.color);
    return Tooltip(
      message: current ? '${workspace.name} (click to edit)' : workspace.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.radius),
        child: SizedBox(
          width: 32,
          height: 28,
          child: Center(
            child: Container(
              width: current ? 16 : 10,
              height: current ? 16 : 10,
              decoration: BoxDecoration(
                color: current ? color.withValues(alpha: 0.25) : color,
                shape: BoxShape.circle,
                border: current ? Border.all(color: color, width: 2) : null,
              ),
            ),
          ),
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
        borderRadius: BorderRadius.circular(T.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(T.radius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(T.radius),
              border: Border.all(
                color: current ? color.withValues(alpha: 0.5) : Colors.transparent,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(T.s2, T.s2, T.s1, T.s2),
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
                      fontSize: T.fsLabel,
                      color: T.text,
                      fontWeight: current ? T.wMedium : FontWeight.w400,
                    ),
                  ),
                ),
                if (current)
                  Tooltip(
                    message: 'Edit workspace',
                    child: InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(T.radius),
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
      borderRadius: BorderRadius.circular(T.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.radius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(T.s2, T.s2, T.s2, T.s2),
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
                    fontSize: T.fsLabel,
                    color: color,
                    fontWeight: selected ? T.wMedium : FontWeight.w400,
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
