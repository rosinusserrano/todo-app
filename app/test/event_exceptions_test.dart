// One occurrence of a repeating block, changed or deleted on its own.
//
// The occurrence becomes a row of its own (an exception) pointing back at its
// series, and the series leaves that occurrence out. What is pinned here is
// that every read agrees about it - the grid, the session and the
// notification schedule - that the exception's id is derived, and that moving
// the series lets go of its exceptions rather than leaving a moved Tuesday
// beside a series that no longer has one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/ui/calendar/series_scope.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> device() async {
    final state = AppState(await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    ));
    await state.load();
    await state.refreshCalendars();
    await state.ensureWorkspaceCalendars();
    await state.refreshCalendars();
    return state;
  }

  /// The blocks on screen - [AppState.events] also holds the neighbours.
  List<CalendarEvent> onScreen(AppState state) {
    final (from, to) = state.calendarRange;
    return [
      for (final e in state.events)
        if (e.start.isBefore(to) && e.end.isAfter(from)) e,
    ];
  }

  /// A weekly stand-up on Mondays at 09:00 from 3 August, shown on the week
  /// of the 17th (its third occurrence).
  Future<(AppState, CalendarEvent)> standUp() async {
    final state = await device();
    await state.saveEvent(
      calendarUuid: state.calendars.first.uuid,
      title: 'stand-up',
      start: DateTime(2026, 8, 3, 9),
      end: DateTime(2026, 8, 3, 9, 15),
      recur: Recur.weekly,
    );
    await state.setCalendarAnchor(DateTime(2026, 8, 19));
    return (state, onScreen(state).single);
  }

  group('the exception row', () {
    test('is derived from the series and the occurrence, with no rule', () {
      final s = CalendarEvent(
        uuid: 'series-1',
        calendarUuid: 'cal-1',
        title: 'stand-up',
        startAt: reminderStamp(DateTime(2026, 8, 3, 9)),
        endAt: reminderStamp(DateTime(2026, 8, 3, 9, 15)),
        recur: Recur.weekly,
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );
      final third = s
          .occurrencesBetween(DateTime(2026, 8, 17), DateTime(2026, 8, 18))
          .single;

      final a = third.detached();
      final b = third.detached();
      expect(a.uuid, b.uuid, reason: 'two devices must write the same row');
      expect(a.uuid, isNot(s.uuid));
      expect(a.seriesUuid, 'series-1');
      expect(a.occurrenceAt, third.startAt);
      expect(a.recur, isNull);
      expect(a.isException && a.inSeries, true);
      // The first occurrence is the stored row itself, and detaches too.
      expect(s.detached().occurrenceAt, s.startAt);
      // An exception already is the one occurrence.
      expect(identical(a.detached(), a), true);
    });

    test('round-trips through a map', () {
      final row = CalendarEvent(
        uuid: 'series-1',
        calendarUuid: 'cal-1',
        title: 'x',
        startAt: reminderStamp(DateTime(2026, 8, 3, 9)),
        endAt: reminderStamp(DateTime(2026, 8, 3, 10)),
        recur: Recur.daily,
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      ).detached().copyWith(cancelled: true);
      final back = CalendarEvent.fromMap(row.toMap());
      expect(back.seriesUuid, 'series-1');
      expect(back.occurrenceAt, row.occurrenceAt);
      expect(back.cancelled, true);
      // A null from an older peer reads as not cancelled.
      expect(
        CalendarEvent.fromMap({...row.toMap(), 'cancelled': null}).cancelled,
        false,
      );
    });
  });

  group('deleting only this one', () {
    test('leaves that week empty and every other week alone', () async {
      final (state, third) = await standUp();

      await state.deleteEvent(third, onlyThis: true);

      expect(onScreen(state), isEmpty);
      await state.setCalendarAnchor(DateTime(2026, 8, 12));
      expect(onScreen(state).single.start, DateTime(2026, 8, 10, 9));
      await state.setCalendarAnchor(DateTime(2026, 8, 26));
      expect(onScreen(state).single.start, DateTime(2026, 8, 24, 9));

      // Kept as a skipped row, not tombstoned: a tombstone would bring the
      // occurrence back.
      final rows =
          await state.store.eventsOnCalendar(state.calendars.first.uuid);
      expect(rows.length, 2);
      expect(rows.where((r) => r.cancelled).single.uuid,
          third.detached().uuid);
    });

    test('is not notified, and the next occurrence is', () async {
      final (state, third) = await standUp();
      await state.deleteEvent(third, onlyThis: true);

      final next =
          await state.store.upcomingEvents(DateTime(2026, 8, 16, 12));
      expect(next.single.start, DateTime(2026, 8, 24, 9));
    });

    test('is not live while it would have run', () async {
      final (state, third) = await standUp();
      await state.deleteEvent(third, onlyThis: true);

      expect(await state.store.liveEvents(DateTime(2026, 8, 17, 9, 5)),
          isEmpty);
      expect(
        (await state.store.liveEvents(DateTime(2026, 8, 24, 9, 5))).length,
        1,
      );
    });
  });

  group('changing only this one', () {
    test('draws it where it was put and the series everywhere else', () async {
      final (state, third) = await standUp();

      await state.saveEvent(
        existing: third.detached(),
        calendarUuid: third.calendarUuid,
        title: 'stand-up (late)',
        start: DateTime(2026, 8, 17, 14),
        end: DateTime(2026, 8, 17, 14, 30),
        // A rule handed to an exception is ignored, not a second series.
        recur: Recur.daily,
      );

      final shown = onScreen(state).single;
      expect(shown.title, 'stand-up (late)');
      expect(shown.start, DateTime(2026, 8, 17, 14));
      expect(shown.isException, true);
      expect(shown.repeats, false);

      await state.setCalendarAnchor(DateTime(2026, 8, 26));
      expect(onScreen(state).single.title, 'stand-up');
      expect(onScreen(state).single.start, DateTime(2026, 8, 24, 9));

      expect(
        (await state.store.liveEvents(DateTime(2026, 8, 17, 14, 10)))
            .single
            .title,
        'stand-up (late)',
      );
      expect(await state.store.liveEvents(DateTime(2026, 8, 17, 9, 5)),
          isEmpty);
    });

    test('dragging it moves that one alone', () async {
      final (state, third) = await standUp();

      await state.moveEvent(
        third,
        from: DateTime(2026, 8, 17, 9),
        to: DateTime(2026, 8, 18, 11),
        onlyThis: true,
      );

      expect(onScreen(state).single.start, DateTime(2026, 8, 18, 11));
      await state.setCalendarAnchor(DateTime(2026, 8, 26));
      expect(onScreen(state).single.start, DateTime(2026, 8, 24, 9));
    });

    test('stretching it stretches that one alone', () async {
      final (state, third) = await standUp();

      await state.resizeEvent(
        third,
        start: false,
        from: DateTime(2026, 8, 17, 9, 15),
        to: DateTime(2026, 8, 17, 10),
        onlyThis: true,
      );

      expect(onScreen(state).single.end, DateTime(2026, 8, 17, 10));
      await state.setCalendarAnchor(DateTime(2026, 8, 26));
      expect(onScreen(state).single.end, DateTime(2026, 8, 24, 9, 15));
    });

    test('keeps what was planned into the series', () async {
      final (state, third) = await standUp();
      await state.addTask('agenda');
      final task = state.tasks.single;
      await state.setTaskEvent(task, third.uuid);

      await state.moveEvent(
        third,
        from: DateTime(2026, 8, 17, 9),
        to: DateTime(2026, 8, 17, 15),
        onlyThis: true,
      );
      final moved = onScreen(state).single;

      expect((await state.tasksForBlock(moved)).single.uuid, task.uuid);
      expect(state.taskCountFor(moved), 1);
    });

    test('deleting it afterwards skips the occurrence', () async {
      final (state, third) = await standUp();
      await state.moveEvent(
        third,
        from: DateTime(2026, 8, 17, 9),
        to: DateTime(2026, 8, 17, 15),
        onlyThis: true,
      );

      await state.deleteEvent(onScreen(state).single, onlyThis: true);

      expect(onScreen(state), isEmpty,
          reason: 'neither the moved block nor the original comes back');
    });
  });

  group('the series', () {
    test('moving it lets go of its exceptions', () async {
      final (state, third) = await standUp();
      await state.deleteEvent(third, onlyThis: true);
      expect(onScreen(state), isEmpty);

      // Every occurrence an hour later: the skipped one was the 09:00 on the
      // 17th, which no longer exists, so the 10:00 is drawn.
      await state.moveEvent(
        third,
        from: DateTime(2026, 8, 17, 9),
        to: DateTime(2026, 8, 17, 10),
      );
      expect(onScreen(state).single.start, DateTime(2026, 8, 17, 10));
    });

    test('renaming it keeps them', () async {
      final (state, third) = await standUp();
      await state.deleteEvent(third, onlyThis: true);
      final series = third.stored;

      await state.saveEvent(
        existing: series,
        calendarUuid: series.calendarUuid,
        title: 'daily sync',
        start: series.start,
        end: series.end,
        recur: Recur.weekly,
      );

      expect(onScreen(state), isEmpty);
      await state.setCalendarAnchor(DateTime(2026, 8, 26));
      expect(onScreen(state).single.title, 'daily sync');
    });

    test('deleting it through an exception takes the series and them',
        () async {
      final (state, third) = await standUp();
      await state.moveEvent(
        third,
        from: DateTime(2026, 8, 17, 9),
        to: DateTime(2026, 8, 17, 15),
        onlyThis: true,
      );

      await state.deleteEvent(onScreen(state).single);

      expect(state.events, isEmpty);
      expect(
        await state.store.eventsOnCalendar(state.calendars.first.uuid),
        isEmpty,
      );
    });
  });

  group('the question', () {
    Future<SeriesScope?> answer(WidgetTester tester, String button) async {
      final series = CalendarEvent(
        uuid: 'series-1',
        calendarUuid: 'cal-1',
        title: 'stand-up',
        startAt: reminderStamp(DateTime(2026, 8, 3, 9)),
        endAt: reminderStamp(DateTime(2026, 8, 3, 9, 15)),
        recur: Recur.weekly,
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );
      late Future<SeriesScope?> asked;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => asked =
                askSeriesScope(context, event: series, deleting: true),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"stand-up" repeats'), findsOneWidget);
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      return asked;
    }

    testWidgets('names both answers, and Cancel is neither', (tester) async {
      expect(await answer(tester, 'Only this one'), SeriesScope.one);
      expect(await answer(tester, 'Whole series'), SeriesScope.all);
      expect(await answer(tester, 'Cancel'), isNull);
    });
  });
}
