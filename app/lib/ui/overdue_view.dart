// Every overdue task in one place (Marco, 2026-11-28), reached from home: the
// strip above the squares, or the Overdue row in the submenu of the dock's
// Home row. Overdue is what overdue.dart counts - a reminder gone off and
// still open, or a task left on its list past its workspace's automatic
// overdue - and the counts tell you *where*; this is where you go to get rid
// of them in one sitting rather than a tour of workspaces.
//
// Grouped by list, the list holding the longest-overdue task first, each
// group under its workspace's name in its colour (a project as
// "Workspace › Project"); the heading goes to that list. The rows are the
// list's own [TaskRow], built by the shell, so ticking, the reminder menu,
// moving and the swipe all work here exactly as they do there - and a row
// leaves this list the moment it stops being overdue.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';
import 'panel_header.dart';

/// How a list is named and coloured in a group heading.
typedef OverdueList = ({String name, Color color});

class OverdueView extends StatelessWidget {
  const OverdueView({
    super.key,
    required this.tasks,
    required this.listOf,
    required this.onOpenList,
    required this.buildRow,
    this.onBack,
  });

  /// Longest overdue first ([AppState.overdueTasks]).
  final List<Task> tasks;

  /// The heading for a list uuid, or null for one that is gone - its tasks
  /// are then under "Elsewhere".
  final OverdueList? Function(String listUuid) listOf;

  final ValueChanged<String> onOpenList;

  /// The row for [task], drawn in [accent]; [divider] as on the list.
  final Widget Function(Task task, Color accent, bool divider) buildRow;

  /// Back to home.
  final VoidCallback? onBack;

  /// [tasks] by list, in order of each list's first (longest-overdue) task.
  static List<(String, List<Task>)> grouped(List<Task> tasks) {
    final by = <String, List<Task>>{};
    for (final t in tasks) {
      by.putIfAbsent(t.workspaceUuid, () => []).add(t);
    }
    return [for (final e in by.entries) (e.key, e.value)];
  }

  @override
  Widget build(BuildContext context) {
    final groups = grouped(tasks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          title: 'Overdue',
          count: tasks.isEmpty ? null : tasks.length,
          onBack: onBack,
          backTooltip: 'Back to home (Esc)',
        ),
        Expanded(
          child: tasks.isEmpty
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(T.s4, T.s2, T.s4, T.s4),
                  child: Text(
                    'Nothing overdue. A task lands here when its reminder '
                    'has gone off, or when it has sat on a list longer than '
                    "that workspace's automatic overdue.",
                    style: TextStyle(
                      fontSize: T.fsLabel,
                      color: T.muted,
                      height: 1.4,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(T.s2, 0, T.s2, T.s4),
                  children: [
                    for (final (i, (uuid, rows)) in groups.indexed) ...[
                      _Heading(
                        list: listOf(uuid),
                        count: rows.length,
                        first: i == 0,
                        onOpen: listOf(uuid) == null
                            ? null
                            : () => onOpenList(uuid),
                      ),
                      for (final (j, t) in rows.indexed)
                        buildRow(
                          t,
                          listOf(uuid)?.color ?? T.muted,
                          j < rows.length - 1,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.list,
    required this.count,
    required this.first,
    required this.onOpen,
  });

  final OverdueList? list;
  final int count;
  final bool first;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final color = list?.color ?? T.muted;
    final name = list?.name ?? 'Elsewhere';
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : T.s3, bottom: T.s1),
      child: Tooltip(
        message: onOpen == null ? '' : 'Go to $name',
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(T.radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: T.s2),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: T.fontDisplay,
                      fontSize: T.fsBody,
                      fontWeight: T.wMedium,
                      color: T.text,
                    ),
                  ),
                ),
                const SizedBox(width: T.s2),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontFamily: T.fontDisplay,
                    fontSize: T.fsBody,
                    color: T.muted,
                  ),
                ),
                const Spacer(),
                if (onOpen != null)
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: T.muted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The way into [OverdueView] from home: a strip above the squares, warn
/// while anything is overdue, quiet when nothing is - always there, so the
/// list is somewhere you can find before you need it.
class OverdueStrip extends StatelessWidget {
  const OverdueStrip({super.key, required this.count, required this.onOpen});

  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final any = count > 0;
    return Semantics(
      button: true,
      label: any ? '$count overdue' : 'Nothing overdue',
      child: Material(
        color: any ? T.warn.withValues(alpha: 0.16) : T.surface,
        borderRadius: BorderRadius.circular(T.radius),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(T.radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: T.s3,
              vertical: T.s2,
            ),
            child: Row(
              children: [
                Icon(
                  any ? Icons.warning_amber_rounded : Icons.check_rounded,
                  size: 18,
                  color: any ? T.warn : T.muted,
                ),
                const SizedBox(width: T.s2),
                Expanded(
                  child: Text(
                    any
                        ? '$count overdue ${count == 1 ? 'task' : 'tasks'}'
                        : 'Nothing overdue',
                    style: TextStyle(
                      fontSize: T.fsBody,
                      fontWeight: any ? T.wMedium : T.wNormal,
                      color: any ? T.text : T.muted,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: any ? T.text : T.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
