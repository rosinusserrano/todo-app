// The week, as a list, for when the grid does not fit.
//
// This is *not* the mobile week - a phone gets the real grid, drawn with the
// compact geometry in `time_grid.dart`. This is what the widget dragged down
// towards its 260px floor gets, where seven columns are under 40px and a title
// has nowhere to go. Growing the window instead was the old answer, and it took
// the widget off the corner of the screen it was pinned to.
//
// The same seven days, stacked, with each event on a line of its own - a title
// gets the whole width instead of a sliver. What it gives up is shape: you can
// no longer see at a glance that Tuesday afternoon is free. That trade is why
// the grid comes back the moment there is room for it ([Layout.weekGridFits]).
//
// Creating still has to work here, so each day header carries a +, which opens
// the editor on a 09:00 block for that day. Dragging a span out is the grid's
// gesture and stays there - tapping into the day view is one press away.

import 'package:flutter/material.dart';

import '../../sync/models.dart';
import '../../theme.dart';
import 'time_grid.dart' show hhmm;

class AgendaView extends StatelessWidget {
  const AgendaView({
    super.key,
    required this.days,
    required this.events,
    required this.colorFor,
    required this.hasAttachment,
    required this.taskCountFor,
    required this.onOpenEvent,
    required this.onCreate,
    required this.onPickDay,
  });

  /// The days on screen, each at local midnight.
  final List<DateTime> days;

  final List<CalendarEvent> events;
  final Color Function(CalendarEvent) colorFor;
  final bool Function(CalendarEvent) hasAttachment;

  /// Open todos planned into an event, shown as a count on its row.
  final int Function(CalendarEvent) taskCountFor;
  final void Function(CalendarEvent) onOpenEvent;
  final void Function(DateTime start, DateTime end) onCreate;

  /// Drilling into one day's grid, which is where dragging a span out lives.
  final void Function(DateTime) onPickDay;

  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Everything overlapping [day], earliest first.
  ///
  /// Overlap rather than "starts on": a block running Tuesday 22:00 to
  /// Wednesday 02:00 is part of Wednesday too, and a list keyed on the start
  /// time would drop it from the day you are looking at.
  List<CalendarEvent> _on(DateTime day) {
    final next = day.add(const Duration(days: 1));
    final out = [
      for (final e in events)
        // An event ending exactly at midnight belongs to the day before, not
        // to the one it touches for zero minutes.
        if (e.start.isBefore(next) && e.end.isAfter(day)) e,
    ];
    out.sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.end.compareTo(b.end);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 14),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final rows = _on(day);
        final isToday = day.year == today.year &&
            day.month == today.month &&
            day.day == today.day;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DayHeader(
                label: '${_names[day.weekday - 1]} ${day.day}',
                isToday: isToday,
                empty: rows.isEmpty,
                onOpen: () => onPickDay(day),
                // 09:00 rather than now: the point of the + is a placeholder to
                // edit, and "now" on a day three days out means nothing.
                onCreate: () => onCreate(
                  day.add(const Duration(hours: 9)),
                  day.add(const Duration(hours: 10)),
                ),
              ),
              for (final e in rows)
                _AgendaRow(
                  event: e,
                  day: day,
                  color: colorFor(e),
                  hasAttachment: hasAttachment(e),
                  taskCount: taskCountFor(e),
                  onTap: () => onOpenEvent(e),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.label,
    required this.isToday,
    required this.empty,
    required this.onOpen,
    required this.onCreate,
  });

  final String label;
  final bool isToday;

  /// An empty day still gets a header. Skipping it would leave the week's shape
  /// unreadable - which days are free is half of what you came to find out.
  final bool empty;

  final VoidCallback onOpen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isToday ? T.accent : T.text,
                    ),
                  ),
                  if (empty) ...[
                    const SizedBox(width: 8),
                    const Text(
                      'free',
                      style: TextStyle(fontSize: 10.5, color: T.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Tooltip(
          message: 'New event on this day',
          child: InkWell(
            onTap: onCreate,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.add, size: 14, color: T.muted),
            ),
          ),
        ),
      ],
    );
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.event,
    required this.day,
    required this.color,
    required this.hasAttachment,
    required this.taskCount,
    required this.onTap,
  });

  final CalendarEvent event;
  final DateTime day;
  final Color color;
  final bool hasAttachment;
  final int taskCount;
  final VoidCallback onTap;

  /// What to print in the time column.
  ///
  /// An event that runs past either edge of this day says so rather than
  /// printing a time from a different day, which would be a lie about when it
  /// starts here.
  String get _when {
    final next = day.add(const Duration(days: 1));
    final startsEarlier = event.start.isBefore(day);
    // Strictly after: an event ending *at* midnight ends today, and printing
    // "→" on it would send you looking for a continuation that is not there.
    final endsLater = event.end.isAfter(next);
    if (startsEarlier && endsLater) return 'all day';
    if (startsEarlier) return 'til ${hhmm(event.end)}';
    if (endsLater) return '${hhmm(event.start)} →';
    return '${hhmm(event.start)}\n${hhmm(event.end)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: Color.lerp(T.bgSolid, color, 0.22),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: color, width: 2.5)),
            ),
            padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    _when,
                    style: const TextStyle(
                      fontSize: 9.5,
                      height: 1.25,
                      color: T.muted,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: T.text,
                        ),
                      ),
                      if (event.description.isNotEmpty)
                        Text(
                          event.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            color: T.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (taskCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline,
                            size: 10, color: T.muted),
                        Text('$taskCount',
                            style:
                                const TextStyle(fontSize: 9.5, color: T.muted)),
                      ],
                    ),
                  ),
                if (hasAttachment)
                  const Padding(
                    padding: EdgeInsets.only(left: 4, top: 1),
                    child: Icon(Icons.attach_file, size: 10, color: T.muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
