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

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/calendar/time_grid.dart' show packOverlaps;

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
    test('spansDays is false within one day and true across midnight', () {
      final sameDay = event('a', DateTime(2026, 7, 30, 9), DateTime(2026, 7, 30, 17));
      final overnight =
          event('b', DateTime(2026, 7, 30, 22), DateTime(2026, 7, 31, 2));
      expect(sameDay.spansDays, isFalse);
      expect(overnight.spansDays, isTrue);
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
    // Roll back to v7: no calendar tables, and attachments without event_uuid.
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
