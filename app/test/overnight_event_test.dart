// A block that crosses midnight is a night, not a multi-day event.
//
// The band at the top of the grid is for blocks with a whole calendar day
// inside them: drawn in a column, one of those would be 24 hours of scrolling
// past the same thing. A shift from 22:00 to 04:00 is not that, and in the band
// it loses both the hour it starts and the hour it ends - which is all anybody
// wants to know about it.
//
// So the rule is "a whole day inside it", not "it touches two dates", and the
// grid draws the overnight case as the two segments it actually is. What is
// pinned here is that split: one block, two columns, cut at midnight.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/calendar/time_grid.dart';

void main() {
  final monday = DateTime(2026, 8, 17);
  final week = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];

  CalendarEvent event(String title, DateTime from, DateTime to,
          {bool allDay = false}) =>
      CalendarEvent(
        uuid: title,
        calendarUuid: 'cal',
        title: title,
        startAt: reminderStamp(from),
        endAt: reminderStamp(to),
        allDay: allDay,
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );

  Widget grid(List<CalendarEvent> events) => MaterialApp(
        home: Scaffold(
          body: TimeGridView(
            days: week,
            events: events,
            colorFor: (_) => T.accent,
            hasAttachment: (_) => false,
            taskCountFor: (_) => 0,
            onOpenEvent: (_) {},
            onEventMenu: (_, _) {},
            onCreate: (_, _) {},
          ),
        ),
      );

  /// The blobs drawn in the hour columns. The band above the grid draws its own
  /// chips, so anything counted here is in a column.
  List<EventBlock> blocks(WidgetTester tester) =>
      tester.widgetList<EventBlock>(find.byType(EventBlock)).toList();

  testWidgets('an overnight block is drawn in both of its columns',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(grid([
      event('night', monday.add(const Duration(hours: 22)),
          monday.add(const Duration(days: 1, hours: 4))),
    ]));

    final drawn = blocks(tester);
    expect(drawn.length, 2);
    // Monday's half runs off the bottom, Tuesday's starts above the top, and
    // each says so by being cut square at that end.
    expect(drawn.first.continuesBefore, isFalse);
    expect(drawn.first.continuesAfter, isTrue);
    expect(drawn.last.continuesBefore, isTrue);
    expect(drawn.last.continuesAfter, isFalse);
  });

  testWidgets('a block ending at midnight stays in the day it started',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(grid([
      event('evening', monday.add(const Duration(hours: 22)),
          monday.add(const Duration(days: 1))),
    ]));

    // Midnight is where Tuesday begins, and the block touches it for zero
    // minutes. One column, and nothing hanging off either end of it.
    final drawn = blocks(tester);
    expect(drawn.length, 1);
    expect(drawn.single.continuesAfter, isFalse);
  });

  testWidgets('a block with a whole day inside it goes to the band instead',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(grid([
      // Monday 22:00 to Wednesday 04:00: Tuesday is covered end to end.
      event('conference', monday.add(const Duration(hours: 22)),
          monday.add(const Duration(days: 2, hours: 4))),
    ]));

    expect(blocks(tester), isEmpty);
  });

  testWidgets('a whole-day event still goes to the band', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(grid([
      event('birthday', monday, monday.add(const Duration(days: 1)),
          allDay: true),
    ]));

    expect(blocks(tester), isEmpty);
  });
}
