// What you are meant to be doing right now.
//
// A calendar says *when*; a task list says *what*. This is the one view where
// they meet: the block of time you are currently inside, and only the todos
// planned into it. Everything else - the rest of the workspace's list, the
// other blocks of the day - is deliberately not here, because a session view
// that showed the whole list again would be the task list with a heading.
//
// It only exists while a block is running (see AppState.refreshSessions), which
// is why there is no permanent button for it: the way in is the banner that
// appears above the list when a session starts, and when the last block ends
// the view hands the content area back on its own rather than sitting there
// showing a session that is over.
//
// Overlapping blocks are all shown, in order, each with its own todos. Two
// things really can be scheduled at once, and choosing one of them for the user
// would be a guess dressed up as an answer.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';
import 'calendar/time_grid.dart' show hhmm;
import 'panel_header.dart';
import 'task_row.dart';

class SessionView extends StatelessWidget {
  const SessionView({
    super.key,
    required this.events,
    required this.tasks,
    required this.accent,
    required this.colorFor,
    required this.nameFor,
    required this.onComplete,
    required this.onDelete,
    required this.onFocus,
    required this.onUnplan,
    required this.onCreateSublist,
    required this.onBack,
  });

  /// The blocks covering now, earliest first.
  final List<CalendarEvent> events;

  /// Their open todos, keyed by event uuid.
  final Map<String, List<Task>> tasks;

  final Color accent;
  final Color Function(CalendarEvent) colorFor;

  /// The calendar's display name, which for a workspace calendar is the
  /// workspace - so a block from a workspace you are not currently in says
  /// which one it belongs to rather than looking like one of yours. Empty when
  /// the calendar cannot be resolved, in which case the line simply omits it.
  final String Function(CalendarEvent) nameFor;

  final Future<void> Function(Task) onComplete;
  final Future<void> Function(Task) onDelete;
  final void Function(Task) onFocus;

  /// Take a task back out of the block. The way in is the event editor; this is
  /// the way out from where you actually notice it does not belong.
  final Future<void> Function(Task) onUnplan;

  /// Start (or add to) the block's own list. Offered on a block with nothing in
  /// it, where the alternative is a paragraph telling the user to go and find
  /// the event in the calendar.
  final void Function(CalendarEvent) onCreateSublist;

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(title: 'Now', onBack: onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            children: [
              for (final e in events)
                _Block(
                  event: e,
                  tasks: tasks[e.uuid] ?? const [],
                  accent: accent,
                  color: colorFor(e),
                  calendarName: nameFor(e),
                  onComplete: onComplete,
                  onDelete: onDelete,
                  onFocus: onFocus,
                  onUnplan: onUnplan,
                  onCreateSublist: () => onCreateSublist(e),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.event,
    required this.tasks,
    required this.accent,
    required this.color,
    required this.calendarName,
    required this.onComplete,
    required this.onDelete,
    required this.onFocus,
    required this.onUnplan,
    required this.onCreateSublist,
  });

  final CalendarEvent event;
  final List<Task> tasks;
  final Color accent;
  final Color color;
  final String calendarName;
  final Future<void> Function(Task) onComplete;
  final Future<void> Function(Task) onDelete;
  final void Function(Task) onFocus;
  final Future<void> Function(Task) onUnplan;
  final VoidCallback onCreateSublist;

  /// "38 min left", or "1 h 12 min left".
  ///
  /// Rounded up, so a block with forty seconds to run says "1 min left" rather
  /// than "0 min left" - the point of the line is the sense that time is going,
  /// and a zero reads as a bug.
  String get _remaining {
    final left = event.end.difference(DateTime.now());
    if (left.isNegative) return 'over';
    final minutes = (left.inSeconds / 60).ceil();
    if (minutes < 60) return '$minutes min left';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours h left' : '$hours h $rest min left';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Color.lerp(T.bgSolid, color, 0.2),
              borderRadius: BorderRadius.circular(9),
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
            padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: T.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (calendarName.isNotEmpty) calendarName,
                    '${hhmm(event.start)}–${hhmm(event.end)}',
                    _remaining,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: T.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nothing planned into this block.',
                    style: TextStyle(fontSize: 11, color: T.muted, height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  // The way to fix that, right where the problem is stated.
                  // Sending the user off to find the event in the calendar was
                  // three navigations away from the thing they are looking at.
                  TextButton.icon(
                    onPressed: onCreateSublist,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(Icons.playlist_add_rounded,
                        size: 15, color: color),
                    label: Text(
                      'Create a sublist',
                      style: TextStyle(fontSize: 11.5, color: color),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final t in tasks)
              TaskRow(
                key: ValueKey(t.uuid),
                task: t,
                accent: accent,
                onComplete: () => onComplete(t),
                onDelete: () => onDelete(t),
                onFocus: () => onFocus(t),
                // Reminders, parking and attachments stay on the list. This
                // view is a short list you are working through right now, and
                // the shelf and the bell are both ways of saying "later".
                onUnplan: () => onUnplan(t),
              ),
        ],
      ),
    );
  }
}
