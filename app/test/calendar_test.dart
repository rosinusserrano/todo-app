// The calendar: calendars, events, the range query, scope filtering, the
// notification rules and the grid's overlap packing.
//
// The range query gets the most attention here because it is the one piece
// whose bugs are invisible on screen: an event that fails to overlap the window
// simply is not drawn, and nothing says it was skipped.

import 'dart:io' show Directory;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter/material.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kLongPressTimeout;

import 'package:todo_widget/ui/calendar/time_grid.dart'
    show
        EventBlock,
        kGutter,
        TimeGridView,
        kHourHeight,
        kHourHeightMax,
        kHourHeightMin,
        packOverlaps;
import 'package:todo_widget/ui/calendar/year_view.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<LocalStore> freshStore() => LocalStore.open(
        path: inMemoryDatabasePath,
        singleInstance: false,
      );

  Future<AppState> device() async {
    final state = AppState(await freshStore());
    await state.load();
    return state;
  }

  CalendarEvent event(
    String uuid,
    DateTime start,
    DateTime end, {
    String calendar = 'cal-1',
    String title = 'an event',
    int? notifyMinutes,
  }) =>
      CalendarEvent(
        uuid: uuid,
        calendarUuid: calendar,
        title: title,
        startAt: reminderStamp(start),
        endAt: reminderStamp(end),
        notifyMinutes: notifyMinutes,
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );

  group('provisioning', () {
    test('every workspace gets a calendar, keyed by its own uuid', () async {
      final s = await device();
      await s.refreshCalendars();

      final ws = s.workspaces.single;
      final cal = s.calendars.single;
      expect(cal.workspaceUuid, ws.uuid);
      // The invariant that lets two offline devices provision independently
      // without producing duplicates.
      expect(cal.uuid, ws.uuid);

      await s.store.close();
    });

    test('provisioning twice does not make a second calendar', () async {
      final s = await device();
      await s.refreshCalendars();
      await s.ensureWorkspaceCalendars();
      await s.refreshCalendars();
      expect(s.calendars.length, 1);
      await s.store.close();
    });

    test('a workspace calendar takes its name and colour from the workspace',
        () async {
      final s = await device();
      await s.refreshCalendars();

      await s.saveWorkspace(
        uuid: s.workspaces.single.uuid,
        name: 'Renamed',
        color: '#ff6c6c',
      );
      await s.refreshCalendars();

      final cal = s.calendars.firstWhere((c) => c.isWorkspaceCalendar);
      // The calendar row still holds the old name; the display name does not.
      expect(s.calendarName(cal), 'Renamed');
      expect(s.calendarColor(cal), T.parseHex('#ff6c6c'));

      await s.store.close();
    });
  });

  group('the range query', () {
    test('an event overlapping the window is included, one outside is not',
        () async {
      final store = await freshStore();
      final day = DateTime(2026, 7, 30);

      await store.putEvent(event(
        'inside',
        day.add(const Duration(hours: 10)),
        day.add(const Duration(hours: 11)),
      ));
      await store.putEvent(event(
        'tomorrow',
        day.add(const Duration(days: 1, hours: 10)),
        day.add(const Duration(days: 1, hours: 11)),
      ));

      final found = await store.eventsBetween(day, day.add(const Duration(days: 1)));
      expect(found.map((e) => e.uuid), ['inside']);
      await store.close();
    });

    test('a multi-day event spanning the whole window is included', () async {
      // The case a query keyed only on start_at gets wrong: this event starts
      // before the window and ends after it, so it appears in neither bound
      // unless the query tests for overlap.
      final store = await freshStore();
      final day = DateTime(2026, 7, 30);

      await store.putEvent(event(
        'holiday',
        day.subtract(const Duration(days: 3)),
        day.add(const Duration(days: 3)),
      ));

      final found = await store.eventsBetween(day, day.add(const Duration(days: 1)));
      expect(found.single.uuid, 'holiday');
      await store.close();
    });

    test('the window is half-open at both ends', () async {
      final store = await freshStore();
      final day = DateTime(2026, 7, 30);
      final next = day.add(const Duration(days: 1));

      // Ends exactly when the window opens, starts exactly when it closes.
      await store.putEvent(
          event('ends-at-open', day.subtract(const Duration(hours: 1)), day));
      await store.putEvent(
          event('starts-at-close', next, next.add(const Duration(hours: 1))));

      final found = await store.eventsBetween(day, next);
      expect(found, isEmpty);
      await store.close();
    });

    test('a tombstoned event is gone', () async {
      final store = await freshStore();
      final day = DateTime(2026, 7, 30);
      final e = event('x', day.add(const Duration(hours: 9)),
          day.add(const Duration(hours: 10)));
      await store.putEvent(e);
      await store.putEvent(e.copyWith(deletedAt: nowStamp()));

      expect(await store.eventsBetween(day, day.add(const Duration(days: 1))),
          isEmpty);
      await store.close();
    });

    test('sub-millisecond stamps still compare correctly', () async {
      // reminderStamp truncates to milliseconds so that "…00.000Z" and
      // "…00.000500Z" cannot end up sorting the wrong way round as strings.
      final store = await freshStore();
      final base = DateTime(2026, 7, 30, 10);
      final odd = base.add(const Duration(microseconds: 500));

      await store.putEvent(event('e', odd, odd.add(const Duration(hours: 1))));

      final found = await store.eventsBetween(
        DateTime(2026, 7, 30),
        DateTime(2026, 7, 31),
      );
      expect(found.single.uuid, 'e');
      await store.close();
    });
  });

  group('scope and visibility', () {
    test('the workspace scope hides another workspace\'s calendar', () async {
      final s = await device();
      await s.saveWorkspace(name: 'Second', color: '#7ee3a1');
      await s.refreshCalendars();

      final first = s.workspaces.firstWhere((w) => w.name != 'Second');
      final second = s.workspaces.firstWhere((w) => w.name == 'Second');
      await s.selectWorkspace(first.uuid);
      await s.refreshCalendars();

      expect(s.calendarScope, CalendarScope.workspace);
      final visible = s.visibleCalendars.map((c) => c.uuid);
      expect(visible, contains(first.uuid));
      expect(visible, isNot(contains(second.uuid)));

      await s.setCalendarScope(CalendarScope.all);
      expect(s.visibleCalendars.map((c) => c.uuid), contains(second.uuid));

      await s.store.close();
    });

    test('a standalone calendar is visible in either scope', () async {
      final s = await device();
      await s.refreshCalendars();
      final workout =
          await s.saveCalendar(name: 'Workout', color: '#ffcf6c');

      expect(s.visibleCalendars.map((c) => c.uuid), contains(workout!.uuid));
      await s.setCalendarScope(CalendarScope.all);
      expect(s.visibleCalendars.map((c) => c.uuid), contains(workout.uuid));

      await s.store.close();
    });

    test('unticking a calendar drops its events from the view', () async {
      final s = await device();
      await s.refreshCalendars();
      final workout = (await s.saveCalendar(name: 'Workout', color: '#ffcf6c'))!;

      await s.setCalendarAnchor(DateTime(2026, 7, 30));
      await s.saveEvent(
        calendarUuid: workout.uuid,
        title: 'squats',
        start: DateTime(2026, 7, 30, 18),
        end: DateTime(2026, 7, 30, 19),
      );
      expect(s.events.map((e) => e.title), contains('squats'));

      await s.toggleCalendarHidden(workout.uuid);
      expect(s.events, isEmpty);

      await s.toggleCalendarHidden(workout.uuid);
      expect(s.events.map((e) => e.title), contains('squats'));

      await s.store.close();
    });
  });

  group('time-block mode', () {
    test('the target is remembered, and reads back as a calendar', () async {
      final s = await device();
      await s.refreshCalendars();
      final cal = s.calendars.single;

      expect(s.timeBlocking, isFalse);
      await s.setTimeBlockCalendar(cal.uuid);
      expect(s.timeBlockCalendar!.uuid, cal.uuid);

      // Device-local, like the other calendar prefs, so it has to survive
      // through the settings table rather than in memory.
      final again = AppState(s.store);
      await again.load();
      await again.loadCalendarPrefs();
      await again.refreshCalendars();
      expect(again.timeBlockCalendar!.uuid, cal.uuid);

      await s.store.close();
    });

    test('a target that goes off screen turns the mode off', () async {
      final s = await device();
      await s.refreshCalendars();
      final workout = (await s.saveCalendar(name: 'Workout', color: '#ffcf6c'))!;
      await s.setTimeBlockCalendar(workout.uuid);
      expect(s.timeBlocking, isTrue);

      // Unticked in the filter: its chip is gone from the strip, so a drag must
      // not still be landing on it.
      await s.toggleCalendarHidden(workout.uuid);
      expect(s.timeBlockCalendar, isNull);
      expect(s.timeBlocking, isFalse);

      await s.toggleCalendarHidden(workout.uuid);
      expect(s.timeBlockCalendar!.uuid, workout.uuid);

      await s.store.close();
    });

    test('a target that no longer exists resolves to null', () async {
      final s = await device();
      await s.refreshCalendars();
      await s.setTimeBlockCalendar('a-calendar-from-another-device');
      expect(s.timeBlockCalendar, isNull);
      await s.store.close();
    });
  });

  group('saving', () {
    test('a backwards drag is normalised, not rejected', () async {
      final s = await device();
      await s.refreshCalendars();
      await s.setCalendarAnchor(DateTime(2026, 7, 30));

      final saved = await s.saveEvent(
        calendarUuid: s.calendars.single.uuid,
        title: 'dragged upwards',
        start: DateTime(2026, 7, 30, 15),
        end: DateTime(2026, 7, 30, 13),
      );

      expect(saved!.start, DateTime(2026, 7, 30, 13));
      expect(saved.end, DateTime(2026, 7, 30, 15));
      await s.store.close();
    });

    test('a zero-length drag still produces a grabbable block', () async {
      final s = await device();
      await s.refreshCalendars();
      final at = DateTime(2026, 7, 30, 9);

      final saved = await s.saveEvent(
        calendarUuid: s.calendars.single.uuid,
        title: 'a click',
        start: at,
        end: at,
      );
      expect(saved!.end.isAfter(saved.start), isTrue);
      await s.store.close();
    });

    test('an untitled event is refused', () async {
      final s = await device();
      await s.refreshCalendars();
      final saved = await s.saveEvent(
        calendarUuid: s.calendars.single.uuid,
        title: '   ',
        start: DateTime(2026, 7, 30, 9),
        end: DateTime(2026, 7, 30, 10),
      );
      expect(saved, isNull);
      await s.store.close();
    });
  });

  group('notification rules', () {
    final cal = Calendar(
      uuid: 'cal-1',
      name: 'Workout',
      color: '#ffcf6c',
      notifyMinutes: 10,
      createdAt: nowStamp(),
      updatedAt: nowStamp(),
    );

    final start = DateTime(2026, 7, 30, 18);

    test('an event with no rule of its own inherits the calendar\'s', () {
      final e = event('e', start, start.add(const Duration(hours: 1)));
      expect(e.notifyAt(cal), start.subtract(const Duration(minutes: 10)));
    });

    test('an event rule overrides the calendar', () {
      final e = event('e', start, start.add(const Duration(hours: 1)),
          notifyMinutes: 60);
      expect(e.notifyAt(cal), start.subtract(const Duration(hours: 1)));
    });

    test('the silent sentinel beats a calendar that does notify', () {
      final e = event('e', start, start.add(const Duration(hours: 1)),
          notifyMinutes: CalendarEvent.notifySilent);
      expect(e.notifyAt(cal), isNull);
    });

    test('a calendar that never notifies produces nothing', () {
      final quiet = cal.copyWith(clearNotify: true);
      final e = event('e', start, start.add(const Duration(hours: 1)));
      expect(e.notifyAt(quiet), isNull);
    });

    test('an event can still notify on a silent calendar', () {
      final quiet = cal.copyWith(clearNotify: true);
      final e = event('e', start, start.add(const Duration(hours: 1)),
          notifyMinutes: 30);
      expect(e.notifyAt(quiet), start.subtract(const Duration(minutes: 30)));
    });
  });

  group('cascades', () {
    test('deleting a standalone calendar tombstones its events', () async {
      final s = await device();
      await s.refreshCalendars();
      final workout = (await s.saveCalendar(name: 'Workout', color: '#ffcf6c'))!;
      await s.setCalendarAnchor(DateTime(2026, 7, 30));
      await s.saveEvent(
        calendarUuid: workout.uuid,
        title: 'squats',
        start: DateTime(2026, 7, 30, 18),
        end: DateTime(2026, 7, 30, 19),
      );

      await s.deleteCalendar(workout);

      expect(s.calendars.map((c) => c.uuid), isNot(contains(workout.uuid)));
      expect(await s.store.eventsOnCalendar(workout.uuid), isEmpty);
      await s.store.close();
    });

    test('a workspace calendar refuses to be deleted on its own', () async {
      final s = await device();
      await s.refreshCalendars();
      final cal = s.calendars.single;

      await s.deleteCalendar(cal);

      // Still there: deleting the workspace is the way to do this, and
      // provisioning would recreate it on the next refresh anyway.
      expect(s.calendars.map((c) => c.uuid), contains(cal.uuid));
      await s.store.close();
    });

    test('deleting a workspace takes its calendar and events with it',
        () async {
      final s = await device();
      await s.saveWorkspace(name: 'Second', color: '#7ee3a1');
      await s.refreshCalendars();

      final second = s.workspaces.firstWhere((w) => w.name == 'Second');
      await s.setCalendarAnchor(DateTime(2026, 7, 30));
      await s.saveEvent(
        calendarUuid: second.uuid,
        title: 'standup',
        start: DateTime(2026, 7, 30, 9),
        end: DateTime(2026, 7, 30, 10),
      );

      await s.deleteWorkspace(second.uuid);
      await s.refreshCalendars();

      expect(s.calendars.map((c) => c.uuid), isNot(contains(second.uuid)));
      expect(await s.store.eventsOnCalendar(second.uuid), isEmpty);
      await s.store.close();
    });
  });

  group('multi-day', () {
    test('a night is not a multi-day event', () {
      // The band is for blocks with a whole day inside them. Crossing midnight
      // is not that: 22:00-02:00 drawn as a band would lose both the hour it
      // starts and the hour it ends, which is all there is to know about it.
      final sameDay =
          event('a', DateTime(2026, 7, 30, 9), DateTime(2026, 7, 30, 17));
      final overnight =
          event('b', DateTime(2026, 7, 30, 22), DateTime(2026, 7, 31, 2));
      final toMidnight =
          event('c', DateTime(2026, 7, 30, 22), DateTime(2026, 7, 31));
      expect(sameDay.spansWholeDay, isFalse);
      expect(overnight.spansWholeDay, isFalse);
      expect(toMidnight.spansWholeDay, isFalse);
    });

    test('a whole day inside it is', () {
      // Tuesday is covered end to end, so there is a column that would be
      // nothing but this block from top to bottom.
      final twoNights =
          event('a', DateTime(2026, 7, 30, 22), DateTime(2026, 8, 1, 4));
      // Exactly midnight to midnight - the shortest thing that qualifies.
      final oneDay = event('b', DateTime(2026, 7, 30), DateTime(2026, 7, 31));
      expect(twoNights.spansWholeDay, isTrue);
      expect(oneDay.spansWholeDay, isTrue);
    });
  });

  group('planned todos and the session', () {
    /// A workspace with one calendar, one block and one task in it.
    Future<(AppState, CalendarEvent, Task)> planned({
      required DateTime start,
      required DateTime end,
    }) async {
      final s = await device();
      await s.refreshCalendars();
      await s.setCalendarAnchor(start);
      await s.addTask('write the summary');

      final event = (await s.saveEvent(
        calendarUuid: s.calendars.single.uuid,
        title: 'Deep work',
        start: start,
        end: end,
      ))!;
      await s.setTaskEvent(s.tasks.single, event.uuid);
      return (s, event, s.tasks.single);
    }

    test('a task planned into a block stays on the list', () async {
      final now = DateTime.now();
      final (s, event, task) = await planned(
        start: now.subtract(const Duration(minutes: 10)),
        end: now.add(const Duration(hours: 1)),
      );

      // Parking takes a task off the list; planning deliberately does not - it
      // says when you will do it, not that you have put it away.
      expect(s.tasks.single.uuid, task.uuid);
      expect(s.tasks.single.eventUuid, event.uuid);
      expect(s.tasks.single.isPlanned, isTrue);

      await s.store.close();
    });

    test('the block running now is the session, with its todos', () async {
      final now = DateTime.now();
      final (s, event, task) = await planned(
        start: now.subtract(const Duration(minutes: 10)),
        end: now.add(const Duration(hours: 1)),
      );

      expect(s.hasLiveSession, isTrue);
      expect(s.liveEvents.single.uuid, event.uuid);
      expect(s.sessionTasks[event.uuid]!.single.uuid, task.uuid);

      // Checking it off empties the session without ending it.
      await s.completeTask(task);
      expect(s.hasLiveSession, isTrue);
      expect(s.sessionTaskList, isEmpty);

      await s.store.close();
    });

    test('a block that has not started or is over is not live', () async {
      final now = DateTime.now();

      final (later, _, _) = await planned(
        start: now.add(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 2)),
      );
      expect(later.hasLiveSession, isFalse);
      await later.store.close();

      final (earlier, _, _) = await planned(
        start: now.subtract(const Duration(hours: 2)),
        end: now.subtract(const Duration(hours: 1)),
      );
      expect(earlier.hasLiveSession, isFalse);
      await earlier.store.close();
    });

    test('a block is live at its start and over at its end', () async {
      final s = await device();
      await s.refreshCalendars();
      final start = DateTime(2026, 7, 30, 9);
      final end = DateTime(2026, 7, 30, 10);
      await s.setCalendarAnchor(start);
      await s.saveEvent(
        calendarUuid: s.calendars.single.uuid,
        title: 'standup',
        start: start,
        end: end,
      );

      // Half-open, matching the grid: the block you are in at 09:00 is this
      // one, and at 10:00 you are already out of it.
      await s.refreshSessions(start.subtract(const Duration(seconds: 1)));
      expect(s.hasLiveSession, isFalse);
      await s.refreshSessions(start);
      expect(s.hasLiveSession, isTrue);
      await s.refreshSessions(end.subtract(const Duration(seconds: 1)));
      expect(s.hasLiveSession, isTrue);
      await s.refreshSessions(end);
      expect(s.hasLiveSession, isFalse);

      await s.store.close();
    });

    test('a parked task drops out of its session but keeps its block',
        () async {
      final now = DateTime.now();
      final (s, event, task) = await planned(
        start: now.subtract(const Duration(minutes: 5)),
        end: now.add(const Duration(hours: 1)),
      );

      final group = await s.saveGroup(title: 'Later', reviewEveryDays: 30);
      await s.parkTask(task, group!.uuid);

      // Shelving says "not now", and a session list is the strongest "now"
      // there is - but the plan itself survives, so unparking restores it.
      expect(s.sessionTaskList, isEmpty);
      expect((await s.store.taskByUuid(task.uuid))!.eventUuid, event.uuid);

      await s.unparkTask(task);
      expect(s.sessionTasks[event.uuid]!.single.uuid, task.uuid);

      await s.store.close();
    });

    test('deleting the block releases its todos rather than taking them',
        () async {
      final now = DateTime.now();
      final (s, event, task) = await planned(
        start: now.subtract(const Duration(minutes: 5)),
        end: now.add(const Duration(hours: 1)),
      );

      await s.deleteEvent(event);

      // The task is still a task. It has only lost the time set aside for it -
      // and it must not keep pointing at a block that no longer exists.
      expect(s.tasks.single.uuid, task.uuid);
      expect(s.tasks.single.eventUuid, isNull);
      expect(s.hasLiveSession, isFalse);

      await s.store.close();
    });

    test('deleting a calendar releases the todos on its blocks', () async {
      final s = await device();
      await s.refreshCalendars();
      final workout = (await s.saveCalendar(name: 'Workout', color: '#ffcf6c'))!;
      final start = DateTime.now();
      await s.setCalendarAnchor(start);
      await s.addTask('stretch first');
      final event = (await s.saveEvent(
        calendarUuid: workout.uuid,
        title: 'gym',
        start: start,
        end: start.add(const Duration(hours: 1)),
      ))!;
      await s.setTaskEvent(s.tasks.single, event.uuid);

      await s.deleteCalendar(workout);

      expect(s.tasks.single.eventUuid, isNull);
      await s.store.close();
    });

    test('a task is in at most one block: planning it again moves it',
        () async {
      final now = DateTime.now();
      final (s, first, task) = await planned(
        start: now.subtract(const Duration(minutes: 5)),
        end: now.add(const Duration(minutes: 30)),
      );
      final second = (await s.saveEvent(
        calendarUuid: s.calendars.single.uuid,
        title: 'Second block',
        start: now.add(const Duration(hours: 2)),
        end: now.add(const Duration(hours: 3)),
      ))!;

      await s.setTaskEvent(s.tasks.single, second.uuid);

      expect(await s.tasksForEvent(first.uuid), isEmpty);
      expect((await s.tasksForEvent(second.uuid)).single.uuid, task.uuid);

      // And unplanning puts it back to being an ordinary task.
      await s.setTaskEvent(s.tasks.single, null);
      expect(await s.tasksForEvent(second.uuid), isEmpty);
      expect(s.tasks.single.isPlanned, isFalse);

      await s.store.close();
    });

    test('overlapping blocks are both live, each with its own todos', () async {
      final now = DateTime.now();
      final (s, first, firstTask) = await planned(
        start: now.subtract(const Duration(minutes: 10)),
        end: now.add(const Duration(hours: 1)),
      );
      await s.addTask('and the other thing');
      final second = (await s.saveEvent(
        calendarUuid: s.calendars.single.uuid,
        title: 'Overlapping',
        start: now.subtract(const Duration(minutes: 5)),
        end: now.add(const Duration(minutes: 30)),
      ))!;
      await s.setTaskEvent(
        s.tasks.firstWhere((t) => t.text == 'and the other thing'),
        second.uuid,
      );

      // Two things really can be scheduled at once. Picking one of them would
      // be a guess, so both are live and the view lists them in order.
      expect(s.liveEvents.map((e) => e.uuid), [first.uuid, second.uuid]);
      expect(s.sessionTasks[first.uuid]!.single.uuid, firstTask.uuid);
      expect(s.sessionTasks[second.uuid]!.single.text, 'and the other thing');

      await s.store.close();
    });

    test('the plannable list is the calendar owner\'s workspace', () async {
      final s = await device();
      await s.saveWorkspace(name: 'Second', color: '#7ee3a1');
      await s.refreshCalendars();
      final second = s.workspaces.firstWhere((w) => w.name == 'Second');
      final first = s.workspaces.firstWhere((w) => w.name != 'Second');

      await s.selectWorkspace(second.uuid);
      await s.addTask('belongs to Second');
      await s.selectWorkspace(first.uuid);
      await s.addTask('belongs to the first');

      final start = DateTime(2026, 7, 30, 9);
      await s.setCalendarAnchor(start);
      final event = (await s.saveEvent(
        calendarUuid: second.uuid, // the second workspace's calendar
        title: 'their block',
        start: start,
        end: start.add(const Duration(hours: 1)),
      ))!;

      // The block belongs to Second, so what can be planned into it is
      // Second's list - not the workspace that happens to be on screen.
      final offered = await s.plannableTasks(event);
      expect(offered.map((t) => t.text), ['belongs to Second']);

      await s.store.close();
    });
  });

  group('the year view', () {
    Widget yearAt(int year) => MaterialApp(
          home: Scaffold(
            body: YearView(
              year: year,
              events: const [],
              colorFor: (_) => T.accent,
              onPickDay: (_) {},
            ),
          ),
        );

    testWidgets('every month tile is drawn the same height', (tester) async {
      // Wide enough for several columns, which is the case where unequal tiles
      // showed: a 4-week February beside a 6-week month left the row ragged.
      await tester.binding.setSurfaceSize(const Size(820, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(yearAt(2026));

      final grids = find.byType(GridView);
      expect(grids, findsNWidgets(12));
      final heights = {
        for (var i = 0; i < 12; i++) tester.getSize(grids.at(i)).height,
      };
      expect(heights.length, 1);
    });

    testWidgets('a February that fits in four weeks still gets six rows',
        (tester) async {
      // February 2026 starts on a Sunday: 6 leading blanks + 28 days = 34
      // cells, and February 2027 starts on a Monday and needs only 28. Both
      // are padded to the same 42, which is what makes the heights above equal
      // rather than coincidentally so for one year.
      await tester.binding.setSurfaceSize(const Size(820, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final year in [2026, 2027]) {
        await tester.pumpWidget(yearAt(year));
        final grid = tester.widget<GridView>(find.byType(GridView).at(1));
        expect((grid.childrenDelegate as SliverChildListDelegate).children.length,
            42);
      }
    });
  });

  group('the hour grid', () {
    final day = DateTime(2026, 7, 30);

    testWidgets('clicking an event opens it and does not create another',
        (tester) async {
      // Both gestures live in the same grid, and creating used to sit on an
      // ancestor of the blocks - so opening an event also wrote a new one
      // behind the editor.
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final opened = <String>[];
      final created = <DateTime>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TimeGridView(
            days: [day],
            events: [
              event('e1', day.add(const Duration(hours: 9)),
                  day.add(const Duration(hours: 10))),
            ],
            colorFor: (_) => T.accent,
            hasAttachment: (_) => false,
            taskCountFor: (_) => 0,
            onOpenEvent: (e) => opened.add(e.uuid),
            onEventMenu: (_, _) {},
            onCreate: (start, _) => created.add(start),
          ),
        ),
      ));

      final block = tester.getCenter(find.byType(EventBlock));
      await tester.tapAt(block, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(opened, ['e1']);
      expect(created, isEmpty);

      // The other half of the same guard: empty grid still creates on a click.
      await tester.tapAt(block + const Offset(0, 60),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(created, hasLength(1));
      expect(opened, ['e1']);
    });

    testWidgets('a task dragged onto a block is planned into it',
        (tester) async {
      // The gesture only exists where both halves are on screen at once, so
      // the test builds that arrangement: a list on the left, the grid on the
      // right, and a drag from one to the other.
      await tester.binding.setSurfaceSize(const Size(700, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final planned = <String>[];
      final task = Task(
        uuid: 't1',
        workspaceUuid: 'ws',
        text: 'write the summary',
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 180,
                child: Draggable<Task>(
                  data: task,
                  feedback: const SizedBox(width: 40, height: 20),
                  child: const Text('write the summary'),
                ),
              ),
              Expanded(
                child: TimeGridView(
                  days: [day],
                  events: [
                    event('e1', day.add(const Duration(hours: 9)),
                        day.add(const Duration(hours: 10))),
                  ],
                  colorFor: (_) => T.accent,
                  hasAttachment: (_) => false,
                  taskCountFor: (_) => 0,
                  onOpenEvent: (_) {},
                  onEventMenu: (_, _) {},
                  onCreate: (_, _) {},
                  onPlanTask: (e, t) => planned.add('${e.uuid}:${t.uuid}'),
                ),
              ),
            ],
          ),
        ),
      ));

      final gesture =
          await tester.startGesture(tester.getCenter(find.text('write the summary')));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(tester.getCenter(find.byType(EventBlock)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(planned, ['e1:t1']);
    });

    testWidgets('a block only takes a drop where there is a list to drag from',
        (tester) async {
      // Without onPlanTask there is no DragTarget at all, which is what keeps
      // a phone's grid free of a gesture it can never receive.
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TimeGridView(
            days: [day],
            events: [
              event('e1', day.add(const Duration(hours: 9)),
                  day.add(const Duration(hours: 10))),
            ],
            colorFor: (_) => T.accent,
            hasAttachment: (_) => false,
            taskCountFor: (_) => 0,
            onOpenEvent: (_) {},
            onEventMenu: (_, _) {},
            onCreate: (_, _) {},
          ),
        ),
      ));

      expect(find.byType(EventBlock), findsOneWidget);
      expect(find.byType(DragTarget<Task>), findsNothing);
    });

    testWidgets('a phone-width week is seven real columns', (tester) async {
      // The size an iPhone 15 lays out at, inside the window frame. Every day
      // has to be there, drawn as a column you can drag on - not folded into
      // an agenda, and not seven slivers with the gutter eating a fifth of it.
      const width = 338.0;
      await tester.binding.setSurfaceSize(const Size(width, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final monday = DateTime(2026, 7, 27);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TimeGridView(
            days: [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))],
            events: [
              event('e1', monday.add(const Duration(hours: 9)),
                  monday.add(const Duration(hours: 10)),
                  title: 'standup'),
            ],
            colorFor: (_) => T.accent,
            hasAttachment: (_) => true,
            taskCountFor: (_) => 2,
            onOpenEvent: (_) {},
            onEventMenu: (_, _) {},
            onCreate: (_, _) {},
          ),
        ),
      ));

      // Initials, because 'Mon 27' does not fit in 45px - but all seven days.
      for (final d in ['M 27', 'T 28', 'W 29', 'T 30', 'F 31', 'S 1', 'S 2']) {
        expect(find.text(d), findsOneWidget);
      }

      // The block is drawn in its own column, at a width the compact geometry
      // is what makes usable: (338 - 22) / 7.
      final block = tester.getSize(find.byType(EventBlock));
      expect(block.width, closeTo((width - 22) / 7 - 3, 1.5));
      expect(find.text('standup'), findsOneWidget);
      // ...and the ornament that would have left the title nothing is gone.
      expect(find.byIcon(Icons.attach_file), findsNothing);
    });

    testWidgets('a long press on an event does not create either',
        (tester) async {
      // The touch path starts from a long press rather than a drag, and it
      // needs the same protection as the mouse one.
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final created = <DateTime>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TimeGridView(
            days: [day],
            events: [
              event('e1', day.add(const Duration(hours: 9)),
                  day.add(const Duration(hours: 10))),
            ],
            colorFor: (_) => T.accent,
            hasAttachment: (_) => false,
            taskCountFor: (_) => 0,
            onOpenEvent: (_) {},
            onEventMenu: (_, _) {},
            onCreate: (start, _) => created.add(start),
          ),
        ),
      ));

      await tester.longPressAt(tester.getCenter(find.byType(EventBlock)));
      await tester.pumpAndSettle();

      expect(created, isEmpty);
    });
  });

  group('pressing to create', () {
    final day = DateTime(2026, 7, 30);

    // Aiming is at a box, not a line: a finger put down a few minutes into
    // 10:00-10:15 means that quarter, and rounding to the nearest line used
    // to start the block at 10:15.
    testWidgets('the quarter the finger lands in is the start, and the one '
        'it lets go in is included', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final created = <(DateTime, DateTime)>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TimeGridView(
            days: [day],
            events: const [],
            colorFor: (_) => T.accent,
            hasAttachment: (_) => false,
            taskCountFor: (_) => 0,
            onOpenEvent: (_) {},
            onEventMenu: (_, _) {},
            onCreate: (start, end) => created.add((start, end)),
          ),
        ),
      ));

      final top = tester.getTopLeft(find.byType(SingleChildScrollView));
      final scrolled = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      Offset at(int minutes) => Offset(
            200,
            top.dy + minutes / 60 * kHourHeight - scrolled,
          );

      // Down at 10:11, up at 11:52: 10:00 to 12:00.
      var g = await tester.startGesture(at(10 * 60 + 11));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await g.moveTo(at(11 * 60 + 52));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(created.single, (
        day.add(const Duration(hours: 10)),
        day.add(const Duration(hours: 12)),
      ));

      // Dragged upwards, the pressed quarter is still inside: 9:00 to 10:15.
      created.clear();
      g = await tester.startGesture(at(10 * 60 + 11));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await g.moveTo(at(9 * 60 + 4));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(created.single, (
        day.add(const Duration(hours: 9)),
        day.add(const Duration(hours: 10, minutes: 15)),
      ));
    });
  });

  group('moving a block', () {
    final monday = DateTime(2026, 7, 27);
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final wed10 = days[2].add(const Duration(hours: 10));

    late List<(CalendarEvent, DateTime, DateTime)> moved;
    late List<CalendarEvent> menus;

    // 800 wide is the roomy geometry: a 38px gutter and ~109px days.
    const width = 800.0;
    final col = (width - kGutter) / 7;

    Future<Offset> pump(WidgetTester tester, CalendarEvent e) async {
      await tester.binding.setSurfaceSize(const Size(width, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      moved = [];
      menus = [];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TimeGridView(
            days: days,
            events: [e],
            colorFor: (_) => T.accent,
            hasAttachment: (_) => false,
            taskCountFor: (_) => 0,
            onOpenEvent: (_) {},
            onEventMenu: (e, _) => menus.add(e),
            onCreate: (_, _) {},
            onMoveEvent: (e, from, to) => moved.add((e, from, to)),
          ),
        ),
      ));
      return tester.getCenter(find.byType(EventBlock));
    }

    Future<void> carry(TestGesture g, Offset from, Offset by,
        WidgetTester tester) async {
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(from + by * (i / 8));
        await tester.pump();
      }
    }

    testWidgets('a mouse drags it straight away, to another day and hour',
        (tester) async {
      final e = event('e1', wed10, wed10.add(const Duration(hours: 2)));
      final at = await pump(tester, e);

      final g = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      await carry(g, at, Offset(col, kHourHeight), tester);
      // The outline says where it is going before it gets there.
      expect(find.text('11:00 – 13:00'), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();

      expect(moved.single.$2, wed10);
      expect(moved.single.$3, days[3].add(const Duration(hours: 11)));
      expect(menus, isEmpty);
    });

    testWidgets('a finger has to hold it first; a plain drag is a scroll',
        (tester) async {
      final e = event('e1', wed10, wed10.add(const Duration(hours: 2)));
      final at = await pump(tester, e);

      var g = await tester.startGesture(at);
      await carry(g, at, Offset(0, kHourHeight), tester);
      await g.up();
      await tester.pumpAndSettle();
      expect(moved, isEmpty);

      final now = tester.getCenter(find.byType(EventBlock));
      g = await tester.startGesture(now);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await carry(g, now, Offset(-col, kHourHeight * 2), tester);
      await g.up();
      await tester.pumpAndSettle();
      expect(moved.single.$3, days[1].add(const Duration(hours: 12)));
    });

    testWidgets('held and let go in place, it is the menu', (tester) async {
      final e = event('e1', wed10, wed10.add(const Duration(hours: 2)));
      final at = await pump(tester, e);

      final g = await tester.startGesture(at);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await g.up();
      await tester.pumpAndSettle();
      expect(moved, isEmpty);
      expect(menus.single.uuid, 'e1');
    });

    testWidgets("a subscribed calendar's event stays put", (tester) async {
      final e = CalendarEvent(
        uuid: 'f1',
        calendarUuid: 'cal-1',
        title: 'from a feed',
        startAt: reminderStamp(wed10),
        endAt: reminderStamp(wed10.add(const Duration(hours: 2))),
        feedUuid: 'feed-1',
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );
      final at = await pump(tester, e);

      final g = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      await carry(g, at, Offset(col, kHourHeight), tester);
      await g.up();
      await tester.pumpAndSettle();
      expect(moved, isEmpty);
    });

    test('a move shifts the series by the distance, keeping its length',
        () async {
      final s = await device();
      await s.refreshCalendars();
      final cal = s.calendars.single.uuid;
      final first = DateTime(2026, 7, 6, 9);
      final saved = await s.saveEvent(
        calendarUuid: cal,
        title: 'Stand-up',
        start: first,
        end: first.add(const Duration(minutes: 30)),
        recur: 'weekly',
      );
      // An occurrence three weeks on, dragged from Monday 09:00 to Tuesday
      // 10:15: the series moves a day and an hour and a quarter.
      final occurrence = saved!
          .occurrencesBetween(days.first, days.last)
          .single;
      await s.moveEvent(
        occurrence,
        from: occurrence.start,
        to: DateTime(2026, 7, 28, 10, 15),
      );
      final row = (await s.store.eventByUuid(saved.uuid))!;
      expect(row.start, DateTime(2026, 7, 7, 10, 15));
      expect(row.end, DateTime(2026, 7, 7, 10, 45));
      await s.store.close();
    });
  });

  group('stretching a block', () {
    final monday = DateTime(2026, 7, 27);
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final wed10 = days[2].add(const Duration(hours: 10));

    late List<(bool, DateTime, DateTime)> resized;
    late List<(CalendarEvent, DateTime, DateTime)> moved;

    Future<void> pump(WidgetTester tester, CalendarEvent e,
        {bool editing = true, bool holdOnly = false}) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      resized = [];
      moved = [];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TimeGridView(
            days: days,
            events: [e],
            colorFor: (_) => T.accent,
            hasAttachment: (_) => false,
            taskCountFor: (_) => 0,
            onOpenEvent: (_) {},
            onEventMenu: (_, _) {},
            onCreate: (_, _) {},
            onMoveEvent: editing || holdOnly
                ? (e, from, to) => moved.add((e, from, to))
                : null,
            moveNeedsHold: holdOnly,
            onResizeEvent: editing
                ? (e, start, from, to) => resized.add((start, from, to))
                : null,
          ),
        ),
      ));
    }

    Future<void> drag(WidgetTester tester, Offset from, Offset by,
        {PointerDeviceKind kind = PointerDeviceKind.mouse}) async {
      final g = await tester.startGesture(from, kind: kind);
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(from + by * (i / 8));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    testWidgets('the bottom edge moves the end, the top edge the start',
        (tester) async {
      final e = event('e1', wed10, wed10.add(const Duration(hours: 2)));
      await pump(tester, e);
      final box = tester.getRect(find.byType(EventBlock));

      await drag(tester, box.bottomCenter - const Offset(0, 3),
          const Offset(0, kHourHeight));
      expect(resized.single, (false, e.end, e.end.add(const Duration(hours: 1))));
      expect(moved, isEmpty, reason: 'the edge, not the block');

      resized.clear();
      await drag(tester, box.topCenter + const Offset(0, 3),
          const Offset(0, -kHourHeight / 2));
      expect(resized.single,
          (true, e.start, e.start.subtract(const Duration(minutes: 30))));
    });

    testWidgets('a finger drags the edge without holding it first',
        (tester) async {
      final e = event('e1', wed10, wed10.add(const Duration(hours: 2)));
      await pump(tester, e);
      final box = tester.getRect(find.byType(EventBlock));
      await drag(tester, box.bottomCenter - const Offset(0, 4),
          const Offset(0, kHourHeight), kind: PointerDeviceKind.touch);
      expect(resized.single.$3, e.end.add(const Duration(hours: 1)));
    });

    testWidgets('an end cannot be dragged past the other one', (tester) async {
      final e = event('e1', wed10, wed10.add(const Duration(hours: 2)));
      await pump(tester, e);
      final box = tester.getRect(find.byType(EventBlock));
      await drag(tester, box.bottomCenter - const Offset(0, 3),
          const Offset(0, -kHourHeight * 4));
      expect(resized.single.$3, wed10.add(const Duration(minutes: 15)));
    });

    testWidgets('outside edit mode the block neither moves nor stretches',
        (tester) async {
      final e = event('e1', wed10, wed10.add(const Duration(hours: 2)));
      await pump(tester, e, editing: false);
      final box = tester.getRect(find.byType(EventBlock));
      await drag(tester, box.bottomCenter - const Offset(0, 3),
          const Offset(0, kHourHeight));
      await drag(tester, box.center, const Offset(0, kHourHeight));
      expect(resized, isEmpty);
      expect(moved, isEmpty);
    });

    testWidgets('outside edit mode a held block moves, a mouse\'s too',
        (tester) async {
      final e = event('e1', wed10, wed10.add(const Duration(hours: 2)));
      await pump(tester, e, editing: false, holdOnly: true);
      final box = tester.getRect(find.byType(EventBlock));

      // A plain mouse drag still does nothing, and there are no grips.
      await drag(tester, box.center, const Offset(0, kHourHeight));
      await drag(tester, box.bottomCenter - const Offset(0, 3),
          const Offset(0, kHourHeight));
      expect(moved, isEmpty);
      expect(resized, isEmpty);

      for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
        final g = await tester.startGesture(box.center, kind: kind);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        for (var i = 1; i <= 8; i++) {
          await g.moveTo(box.center + const Offset(0, kHourHeight) * (i / 8));
          await tester.pump();
        }
        await g.up();
        await tester.pumpAndSettle();
      }
      expect(moved, hasLength(2));
      expect(moved.first.$3, e.start.add(const Duration(hours: 1)));
    });

    test('stretching an occurrence stretches the series', () async {
      final s = await device();
      await s.refreshCalendars();
      final cal = s.calendars.single.uuid;
      final first = DateTime(2026, 7, 6, 9);
      final saved = await s.saveEvent(
        calendarUuid: cal,
        title: 'Stand-up',
        start: first,
        end: first.add(const Duration(minutes: 30)),
        recur: 'weekly',
      );
      final occurrence =
          saved!.occurrencesBetween(days.first, days.last).single;
      await s.resizeEvent(
        occurrence,
        start: false,
        from: occurrence.end,
        to: occurrence.end.add(const Duration(minutes: 45)),
      );
      final row = (await s.store.eventByUuid(saved.uuid))!;
      expect(row.start, first);
      expect(row.end, DateTime(2026, 7, 6, 10, 15));
      await s.store.close();
    });
  });

  group('an event block', () {
    final day = DateTime(2026, 7, 30);

    Future<void> block(WidgetTester tester, String title, Size size) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: size,
                child: EventBlock(
                  event: event('e1', day, day.add(const Duration(hours: 2)),
                      title: title),
                  color: const Color(0xFFE8A0A0),
                  hasAttachment: false,
                  onTap: () {},
                  compact: true,
                ),
              ),
            ),
          ),
        ));

    // A phone's week column is ~40px wide: a long title lying down is three
    // letters and an ellipsis, standing up it is most of itself.
    testWidgets('a long title in a tall narrow block stands up',
        (tester) async {
      await block(tester, 'Dentist appointment', const Size(40, 120));
      expect(find.byType(RotatedBox), findsOneWidget);
    });

    testWidgets('a title that fits across stays across', (tester) async {
      await block(tester, 'Gym', const Size(40, 120));
      expect(find.byType(RotatedBox), findsNothing);
    });

    testWidgets('a short block keeps the title across', (tester) async {
      await block(tester, 'Dentist appointment', const Size(40, 30));
      expect(find.byType(RotatedBox), findsNothing);
    });

    testWidgets('the face is the calendar colour, the ink its deep shade',
        (tester) async {
      await block(tester, 'Gym', const Size(80, 60));
      final text = tester.widget<Text>(find.text('Gym'));
      expect(text.style!.color, T.inkOn(const Color(0xFFE8A0A0)));
    });
  });

  group('zooming the grid', () {
    test('the hour height is remembered, clamped, and device-local', () async {
      final s = await device();

      // Default until something says otherwise.
      expect(s.hourHeight, kHourHeight);

      s.setHourHeight(80);
      expect(s.hourHeight, 80);

      // Clamped at both ends: a pinch can be enthusiastic, and an hour drawn
      // at 4px is a grid nobody can hit.
      s.setHourHeight(5000);
      expect(s.hourHeight, kHourHeightMax);
      s.setHourHeight(1);
      expect(s.hourHeight, kHourHeightMin);

      // Persisted like the mode and the scope - and *only* locally: how far
      // you are zoomed in is about the screen in front of you, so it is a
      // setting rather than a synced row.
      s.setHourHeight(64);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final reopened = AppState(s.store);
      await reopened.load();
      await reopened.loadCalendarPrefs();
      expect(reopened.hourHeight, 64);
    });
  });

  group('overlap packing', () {
    CalendarEvent at(String uuid, int fromHour, int toHour) => event(
          uuid,
          DateTime(2026, 7, 30, fromHour),
          DateTime(2026, 7, 30, toHour),
        );

    test('events that do not overlap each get the full width', () {
      final placed = packOverlaps([at('a', 9, 10), at('b', 11, 12)]);
      expect(placed.every((p) => p.columns == 1), isTrue);
      expect(placed.every((p) => p.column == 0), isTrue);
    });

    test('two overlapping events split the column', () {
      final placed = packOverlaps([at('a', 9, 11), at('b', 10, 12)]);
      expect(placed.every((p) => p.columns == 2), isTrue);
      expect(placed.map((p) => p.column).toSet(), {0, 1});
    });

    test('a lane is reused once its occupant has ended', () {
      // a and b overlap; c starts after a ends, so it belongs in a's lane
      // rather than forcing a third.
      final placed = packOverlaps([at('a', 9, 10), at('b', 9, 12), at('c', 10, 11)]);
      expect(placed.every((p) => p.columns == 2), isTrue);
      final byUuid = {for (final p in placed) p.event.uuid: p.column};
      expect(byUuid['c'], byUuid['a']);
    });

    test('a busy morning does not narrow a free afternoon', () {
      // The cluster boundary: nothing is running between 12 and 14, so the
      // afternoon event should not inherit the morning's lane count.
      final placed = packOverlaps([
        at('a', 9, 11),
        at('b', 9, 11),
        at('c', 14, 15),
      ]);
      final byUuid = {for (final p in placed) p.event.uuid: p};
      expect(byUuid['a']!.columns, 2);
      expect(byUuid['c']!.columns, 1);
    });
  });

  test('a v7 database gains the calendar tables and the attachment owner',
      () async {
    final dir = await Directory.systemTemp.createTemp('todo_cal_migrate');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'todo.db');

    final store = await LocalStore.open(path: path, singleInstance: false);
    final ws = (await store.workspaces()).single;
    await store.putTask(Task(
      uuid: 't1',
      workspaceUuid: ws.uuid,
      text: 'survives the calendar',
      createdAt: nowStamp(),
      updatedAt: nowStamp(),
    ));
    // Roll back to v7: no calendar tables, attachments without event_uuid, and
    // no event_uuid on tasks (v10). The index on it goes first - SQLite refuses
    // to drop a column an index is built on.
    await store.raw.execute('DROP INDEX idx_tasks_event');
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN event_uuid');
    // Nor notes/priority, which arrived in v11.
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN notes');
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN priority');
    // ...and none of the four recurrence columns (v15). The index on `recur`
    // has to go first for the same reason idx_tasks_event did above: SQLite
    // refuses to drop a column an index is built on.
    await store.raw.execute('DROP INDEX idx_tasks_recur');
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN recur_from');
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN recur_lead');
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN recur_text');
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN recur_notes');
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN recur');
    // ...and no subscriptions (v16): the feed table, and the column on
    // calendar_events with the index built on it.
    await store.raw.execute('DROP TABLE calendar_feeds');
    // ...and no shopping list (v17).
    await store.raw.execute('DROP TABLE lists');
    await store.raw.execute('DROP TABLE list_items');
    // ...and no collections (v18).
    await store.raw.execute('DROP TABLE collections');
    await store.raw.execute('DROP TABLE collection_fields');
    await store.raw.execute('DROP TABLE collection_entries');
    await store.raw.execute('ALTER TABLE workspaces DROP COLUMN shortcuts');
    await store.raw.execute('ALTER TABLE workspaces DROP COLUMN parent_uuid');
    await store.raw.execute('ALTER TABLE workspaces DROP COLUMN archived_at');
    await store.raw.execute('DROP TABLE blobs');
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN audio');
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN audio_ms');
    await store.raw.execute('ALTER TABLE side_thoughts DROP COLUMN audio');
    await store.raw.execute('ALTER TABLE side_thoughts DROP COLUMN audio_ms');
    await store.raw.execute('ALTER TABLE side_thoughts DROP COLUMN remind_at');
    await store.raw
        .execute('ALTER TABLE calendar_events DROP COLUMN series_uuid');
    await store.raw
        .execute('ALTER TABLE calendar_events DROP COLUMN occurrence_at');
    await store.raw
        .execute('ALTER TABLE calendar_events DROP COLUMN cancelled');
    await store.raw.execute('DROP INDEX idx_events_feed');
    await store.raw
        .execute('ALTER TABLE calendar_events DROP COLUMN feed_uuid');
    await store.raw.execute('DROP TABLE calendars');
    await store.raw.execute('DROP TABLE calendar_events');
    await store.raw.execute('DROP TABLE attachments');
    await store.raw.execute('''
      CREATE TABLE attachments (
        uuid       TEXT PRIMARY KEY,
        task_uuid  TEXT NOT NULL,
        filename   TEXT NOT NULL,
        size       INTEGER NOT NULL DEFAULT 0,
        sha256     TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        dirty      INTEGER NOT NULL DEFAULT 1
      )''');
    await store.raw.setVersion(7);
    await store.close();

    final upgraded = await LocalStore.open(path: path, singleInstance: false);
    expect((await upgraded.activeTasks(ws.uuid)).single.text,
        'survives the calendar');
    expect(await upgraded.calendars(), isEmpty);

    // The new column is really there: writing an event-owned attachment is the
    // thing that would fail if the ALTER had not run.
    await upgraded.putAttachment(Attachment(
      uuid: 'a1',
      eventUuid: 'e1',
      filename: 'plan.pdf',
      size: 10,
      sha256: 'deadbeef',
      createdAt: nowStamp(),
      updatedAt: nowStamp(),
    ));
    expect((await upgraded.eventAttachments('e1')).single.filename, 'plan.pdf');
    await upgraded.close();
  });

  test('an event attachment does not show up on a task', () async {
    final store = await freshStore();
    await store.putAttachment(Attachment(
      uuid: 'a1',
      eventUuid: 'e1',
      filename: 'plan.pdf',
      size: 10,
      sha256: 'deadbeef',
      createdAt: nowStamp(),
      updatedAt: nowStamp(),
    ));
    // The event row carries an empty task_uuid, so a task query that forgot to
    // exclude event rows would hand this back.
    expect(await store.attachmentsFor(''), isEmpty);
    expect(await store.eventsWithAttachments(), {'e1'});
    await store.close();
  });
}
