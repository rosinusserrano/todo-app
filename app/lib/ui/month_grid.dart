// One month as a seven-by-six grid of days.
//
// Shared by the year view's month tiles and the reminder date picker, and
// shared for the *arithmetic* rather than the styling. Where a month starts
// (Monday-based, so the leading blanks match the week view) and how many week
// rows it gets are the parts that must not differ between two calendars in the
// same app - a picker that disagreed with the year view about which column the
// 1st falls in is a bug nobody would think to look for. The cell itself is the
// caller's: the year view draws twelve of these at 9pt with event dots, the
// picker draws one at a size you can hit with a finger, and forcing those
// through one set of paddings would make both worse.

import 'package:flutter/material.dart';

import '../theme.dart';

/// Week rows every month is drawn with.
///
/// Six is the worst case - a 31-day month beginning on a Sunday needs 6 leading
/// blanks + 31 days = 37 cells - and every month uses it so that two side by
/// side are the same height. Sizing each to its own month leaves a `Wrap` run
/// ragged; don't make it adaptive to save a row of pixels.
const int kMonthWeekRows = 6;

const List<String> kMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// True when [a] and [b] are the same calendar day, ignoring the time.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.dayBuilder,
    this.weekdayFontSize = 8,
    this.childAspectRatio = 0.92,
  });

  final int year;
  final int month;

  /// Draws one day. Called only for days in this month; the blanks either side
  /// are this widget's business.
  final Widget Function(DateTime day) dayBuilder;

  final double weekdayFontSize;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    // Day 0 of the next month is the last day of this one - avoids a leap-year
    // table.
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leading = DateTime(year, month).weekday - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: TextStyle(fontSize: weekdayFontSize, color: T.muted),
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
          childAspectRatio: childAspectRatio,
          children: [
            for (var i = 0; i < leading; i++) const SizedBox.shrink(),
            for (var d = 1; d <= daysInMonth; d++)
              dayBuilder(DateTime(year, month, d)),
            // Padded out to the full six weeks. Empty cells rather than the
            // next month's days: a tile is one month, and greyed-out neighbours
            // at this size are just noise.
            for (var i = leading + daysInMonth; i < kMonthWeekRows * 7; i++)
              const SizedBox.shrink(),
          ],
        ),
      ],
    );
  }
}
