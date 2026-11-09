// The home screen: every workspace as a big square of its own colour, its
// projects listed inside it. What the app opens on at launch when there is no
// checklist to open - so it does not open on the tasks of a workspace you are
// not working in (Marco, 2026-11-09).
//
// It is a launch screen, not a place: there is no button back to it, since
// the dock's workspace menu already lists them. Picking a square switches to
// that workspace; picking a project line opens the project. Anything else
// picked in the dock leaves it too (AppState._closeOtherViews clears it).
//
// Flat blocks in the workspace colour with `T.inkOn` text, no border - the
// look the dock's workspace segment already has, at the size of a tile.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';

/// How wide a square wants to be before another column is worth adding.
const kHomeTile = 168.0;

/// How many project lines a square draws before "+n more".
const kHomeProjectLines = 3;

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.workspaces,
    required this.projectsOf,
    required this.openCounts,
    required this.onOpen,
    required this.onOpenProject,
  });

  final List<Workspace> workspaces;
  final List<Workspace> Function(String uuid) projectsOf;

  /// Open tasks per workspace and project uuid.
  final Map<String, int> openCounts;

  final ValueChanged<Workspace> onOpen;
  final ValueChanged<Workspace> onOpenProject;

  /// Columns for [width]: at least two, so a phone gets squares and not a
  /// stack of banners.
  static int columnsFor(double width) =>
      (width / kHomeTile).floor().clamp(2, 6);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 6 * kHomeTile + 2 * T.s3),
        child: LayoutBuilder(
          builder: (context, box) {
            final columns = columnsFor(box.maxWidth - 2 * T.s3);
            return GridView.count(
              padding: const EdgeInsets.fromLTRB(T.s3, T.s3, T.s3, T.s4),
              crossAxisCount: columns,
              mainAxisSpacing: T.s2,
              crossAxisSpacing: T.s2,
              children: [
                for (final w in workspaces)
                  _Square(
                    workspace: w,
                    projects: projectsOf(w.uuid),
                    openCounts: openCounts,
                    onOpen: () => onOpen(w),
                    onOpenProject: onOpenProject,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Square extends StatefulWidget {
  const _Square({
    required this.workspace,
    required this.projects,
    required this.openCounts,
    required this.onOpen,
    required this.onOpenProject,
  });

  final Workspace workspace;
  final List<Workspace> projects;
  final Map<String, int> openCounts;
  final VoidCallback onOpen;
  final ValueChanged<Workspace> onOpenProject;

  @override
  State<_Square> createState() => _SquareState();
}

class _SquareState extends State<_Square> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.workspace;
    final base = T.parseHex(w.color);
    final fill = _hovered ? Color.lerp(base, Colors.white, 0.08)! : base;
    final ink = T.inkOn(base);
    final open = widget.openCounts[w.uuid] ?? 0;
    final shown = widget.projects.take(kHomeProjectLines).toList();
    final more = widget.projects.length - shown.length;

    return Semantics(
      button: true,
      label: '${w.name}, $open open',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(T.radius),
            ),
            padding: const EdgeInsets.fromLTRB(T.s3, T.s3, T.s2, T.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: T.s1),
                  child: Text(
                    w.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: T.fontDisplay,
                      fontSize: T.fsTitle,
                      fontWeight: T.wMedium,
                      color: ink,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  open == 0 ? 'Nothing open' : '$open open',
                  style: TextStyle(
                    fontSize: T.fsMeta,
                    color: ink.withValues(alpha: 0.75),
                  ),
                ),
                const Spacer(),
                // Clipped rather than overflowing: a small square with three
                // projects keeps its name and loses lines from the bottom.
                ClipRect(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final p in shown)
                        _ProjectLine(
                          name: p.name,
                          open: widget.openCounts[p.uuid] ?? 0,
                          ink: ink,
                          onTap: () => widget.onOpenProject(p),
                        ),
                      if (more > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: T.s1),
                          child: Text(
                            '+$more more',
                            style: TextStyle(
                              fontSize: T.fsMeta,
                              color: ink.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                    ],
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

class _ProjectLine extends StatelessWidget {
  const _ProjectLine({
    required this.name,
    required this.open,
    required this.ink,
    required this.onTap,
  });

  final String name;
  final int open;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Project $name, $open open',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.radius / 2),
        hoverColor: ink.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.s1, vertical: 3),
          child: Row(
            children: [
              Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 12,
                color: ink,
              ),
              const SizedBox(width: T.s1),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: T.fsLabel, color: ink),
                ),
              ),
              if (open > 0)
                Text(
                  '$open',
                  style: TextStyle(
                    fontFamily: T.fontDisplay,
                    fontSize: T.fsLabel,
                    color: ink.withValues(alpha: 0.75),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
