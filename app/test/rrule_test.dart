// Expanding RRULEs for subscribed calendars.
//
// The cases are the ones real calendars are full of and that the import could
// only ever bring in once: an interval, an nth weekday, the last working day,
// a day the month does not have, an end by count or by date. And the one that
// is easy to get wrong without noticing - a series counted in its own
// timezone stays at the same time of day across a clock change.

import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/sync/ics.dart';
import 'package:todo_widget/sync/rrule.dart';

void main() {
  /// Readings as UTC instants, which is all a test of the date arithmetic
  /// needs.
  List<DateTime> expand(String rule, DateTime start, {DateTime? before}) =>
      expandRrule(
        rule,
        start,
        instantOf: (w) => w,
        before: before ?? DateTime.utc(2030),
      )!;

  List<String> days(List<DateTime> ds) => [
        for (final d in ds)
          '${d.year}-${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}',
      ];

  test('daily with a count', () {
    final out = expand('FREQ=DAILY;COUNT=3', DateTime.utc(2026, 8, 30, 9));
    expect(days(out), ['2026-08-30', '2026-08-31', '2026-09-01']);
    expect(out.every((d) => d.hour == 9), isTrue);
  });

  test('every second week on Tuesday and Thursday', () {
    final out = expand(
      'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;COUNT=6',
      DateTime.utc(2026, 9, 1, 10), // a Tuesday
    );
    expect(days(out), [
      '2026-09-01', '2026-09-03',
      '2026-09-15', '2026-09-17',
      '2026-09-29', '2026-10-01',
    ]);
  });

  test('the second Tuesday and the last Friday of the month', () {
    expect(
      days(expand('FREQ=MONTHLY;BYDAY=2TU;COUNT=3', DateTime.utc(2026, 9, 8))),
      ['2026-09-08', '2026-10-13', '2026-11-10'],
    );
    expect(
      days(expand('FREQ=MONTHLY;BYDAY=-1FR;COUNT=3', DateTime.utc(2026, 9, 25))),
      ['2026-09-25', '2026-10-30', '2026-11-27'],
    );
  });

  test('the last working day of the month (BYSETPOS)', () {
    final out = expand(
      'FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3',
      DateTime.utc(2026, 10, 30),
    );
    // 31 October 2026 is a Saturday.
    expect(days(out), ['2026-10-30', '2026-11-30', '2026-12-31']);
  });

  test('monthly on the 31st skips the months that do not have one', () {
    // Not clamped to the 30th - and, unlike walking one month at a time, it
    // does not drift to the 30th for ever after the first short month.
    final out = expand('FREQ=MONTHLY;COUNT=4', DateTime.utc(2026, 8, 31));
    expect(days(out), ['2026-08-31', '2026-10-31', '2026-12-31', '2027-01-31']);
  });

  test('the last day of every month (BYMONTHDAY=-1)', () {
    final out =
        expand('FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3', DateTime.utc(2027, 1, 31));
    expect(days(out), ['2027-01-31', '2027-02-28', '2027-03-31']);
  });

  test('yearly on a date, and on the fourth Thursday of November', () {
    expect(
      days(expand('FREQ=YEARLY;COUNT=2', DateTime.utc(2026, 3, 14))),
      ['2026-03-14', '2027-03-14'],
    );
    expect(
      days(expand('FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=2',
          DateTime.utc(2026, 11, 26))),
      ['2026-11-26', '2027-11-25'],
    );
  });

  test('UNTIL includes its own day and nothing after', () {
    final out = expand(
      'FREQ=WEEKLY;UNTIL=20260922T235959Z',
      DateTime.utc(2026, 9, 1, 18),
    );
    expect(days(out), ['2026-09-01', '2026-09-08', '2026-09-15', '2026-09-22']);
  });

  test('stops at the window, so a rule with no end is still finite', () {
    final out = expand('FREQ=DAILY', DateTime.utc(2026, 1, 1),
        before: DateTime.utc(2026, 1, 11));
    expect(out, hasLength(10));
  });

  test('DTSTART counts even when the rule would not produce it', () {
    // Starts on a Wednesday, repeats Mondays: Google shows the Wednesday too.
    final out = expand(
      'FREQ=WEEKLY;BYDAY=MO;COUNT=3',
      DateTime.utc(2026, 9, 2),
    );
    expect(days(out), ['2026-09-02', '2026-09-07', '2026-09-14']);
  });

  test('what it cannot expand it says so, rather than guessing', () {
    expect(
      expandRrule('FREQ=YEARLY;BYWEEKNO=20', DateTime.utc(2026),
          instantOf: (w) => w, before: DateTime.utc(2030)),
      isNull,
    );
    expect(
      expandRrule('FREQ=HOURLY', DateTime.utc(2026),
          instantOf: (w) => w, before: DateTime.utc(2030)),
      isNull,
    );
  });

  test('a series in its own zone keeps its time across the clock change', () {
    // 09:00 Berlin, weekly across the end of summer time on 25 October 2026:
    // 07:00 UTC before it, 08:00 UTC after - the same 09:00 on the wall.
    final time = IcsTime(DateTime.utc(2026, 10, 18, 9), zone: 'Europe/Berlin');
    final walls = expandRrule(
      'FREQ=WEEKLY;COUNT=3',
      time.wall,
      instantOf: (w) => time.at(w).toLocal(),
      before: DateTime.utc(2030),
    )!;
    final utc = [for (final w in walls) time.at(w).toLocal().toUtc()];
    expect(utc, [
      DateTime.utc(2026, 10, 18, 7),
      DateTime.utc(2026, 10, 25, 8),
      DateTime.utc(2026, 11, 1, 8),
    ]);
  });
}

