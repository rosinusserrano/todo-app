// Twelve months at once.
//
// There is no month view, and that is the point: a month view is one of these
// tiles at full size, so building both would mean two layouts of the same
// grid. What a year gives that a month does not is shape - which weeks are
// full, where the empty stretches are - so the tiles carry density rather than
// event text, which would be unreadable at this size anyway.
//
// Tapping a day opens it in the day view, which is the drill-down the year is
// for.

import 'package:flutter/material.dart';

import '../../sync/models.dart';
import '../../theme.dart';

class YearView extends StatelessWidget {
  const YearView({
    super.key,
    required this.year,
    required this.events,
    required this.colorFor,
    required this.onPickDay,
  });

  final int year;
  final List<CalendarEvent> events;
  final Color Function(CalendarEvent) colorFor;
  final void Function(DateTime) onPickDay;

  /// The colours on each day of the year, deduplicated and capped.
  ///
  /// Built once for all twelve tiles rather than per tile: an event is matched
  /// against days by walking the days it covers, and doing that per month would
  /// walk every multi-day event twelve times.
  Map<DateTime, List<Color>> _dotsByDay() {
    final out = <DateTime, List<Color>>{};
    for (final e in events) {
      final color = colorFor(e);
      var day = DateTime(e.start.year, e.start.month, e.start.day);
      final last = DateTime(e.end.year, e.end.month, e.end.day);
      // An event ending exactly at midnight belongs to the day before, not to
      // the one it touches for zero minutes.
      final endsAtMidnight =
          e.end.hour == 0 && e.end.minute == 0 && e.end.isAfter(e.start);

      while (!day.isAfter(last)) {
        if (!(endsAtMidnight && day == last)) {
          final dots = out.putIfAbsent(day, () => []);
          // Three is what fits under a day number; beyond that the count stops
          // meaning anything anyway.
          if (!dots.contains(color) && dots.length < 3) dots.add(color);
        }
        day = day.add(const Duration(days: 1));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final dots = _dotsByDay();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Tiles want ~190px to keep the day numbers legible; below three
        // columns this is a phone, where two is the most that fits.
        final columns = (constraints.maxWidth / 190).floor().clamp(2, 4);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var month = 1; month <= 12; month++)
                SizedBox(
                  width: (constraints.maxWidth - 16 - (columns - 1) * 8) / columns,
                  child: _MonthTile(
                    year: year,
                    month: month,
                    dots: dots,
                    onPickDay: onPickDay,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.year,
    required this.month,
    required this.dots,
    required this.onPickDay,
  });

  final int year;
  final int month;
  final Map<DateTime, List<Color>> dots;
  final void Function(DateTime) onPickDay;

  static const _names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final first = DateTime(year, month);
    // Day 0 of the next month is the last day of this one - avoids a leap-year
    // table.
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leading = first.weekday - 1; // Monday-based, matching the week view.
    final today = DateTime.now();

    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++)
        () {
          final day = DateTime(year, month, d);
          return _DayCell(
            day: day,
            isToday: day.year == today.year &&
                day.month == today.month &&
                day.day == today.day,
            dots: dots[day] ?? const [],
            onTap: () => onPickDay(day),
          );
        }(),
    ];

    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _names[month - 1],
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: T.text,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: const TextStyle(fontSize: 8, color: T.muted),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.92,
            children: cells,
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.dots,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final List<Color> dots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 15,
            height: 15,
            alignment: Alignment.center,
            decoration: isToday
                ? const BoxDecoration(color: T.accent, shape: BoxShape.circle)
                : null,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 9,
                color: isToday ? T.bgSolid : T.text,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          SizedBox(
            height: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final c in dots)
                  Container(
                    width: 3,
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 0.5),
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
