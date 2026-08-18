// Whole days.
//
// The flag says how to *draw* an event and how to notify for it; the instants
// still say when it is, and they are stored the way .ics stores them - midnight
// on the first day to midnight on the day after the last. That exclusive end is
// what lets the window query, the spanning band and the session go on working
// untouched, and it is also the one thing everybody gets wrong by a day, so
// most of what is pinned here is the off-by-one.

import 'dart:io' show Directory;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/ics.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';

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
    await state.refreshCalendars();
    await state.ensureWorkspaceCalendars();
    await state.refreshCalendars();
    return state;
  }

  group('storing one', () {
    test('a single day runs midnight to midnight', () async {
      final state = await device();
      final saved = await state.saveEvent(
        calendarUuid: state.calendars.first.uuid,
        title: 'day off',
        start: DateTime(2026, 8, 18, 14, 20),
        end: DateTime(2026, 8, 18, 15),
        allDay: true,
      );

      expect(saved!.allDay, true);
      expect(saved.start, DateTime(2026, 8, 18));
      expect(saved.end, DateTime(2026, 8, 19),
          reason: 'the end is exclusive, so one day ends at the next midnight');
    });

    test('a run of days keeps the days it was given', () async {
      final state = await device();
      final saved = await state.saveEvent(
        calendarUuid: state.calendars.first.uuid,
        title: 'holiday',
        start: DateTime(2026, 8, 17),
        // Exclusive: the editor converts what the user picked before it gets
        // here, and parseIcs already produces this form.
        end: DateTime(2026, 8, 22),
        allDay: true,
      );

      expect(saved!.start, DateTime(2026, 8, 17));
      expect(saved.end, DateTime(2026, 8, 22));
      expect(saved.duration, const Duration(days: 5));
    });

    test('the flag survives a round trip through the database', () async {
      final store = await freshStore();
      final e = CalendarEvent(
        uuid: 'e-1',
        calendarUuid: 'cal-1',
        title: 'birthday',
        startAt: reminderStamp(DateTime(2026, 8, 18)),
        endAt: reminderStamp(DateTime(2026, 8, 19)),
        allDay: true,
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );
      await store.putEvent(e);

      expect((await store.eventByUuid('e-1'))!.allDay, true);
      await store.close();
    });

    test('an ordinary block is not one', () async {
      final state = await device();
      final saved = await state.saveEvent(
        calendarUuid: state.calendars.first.uuid,
        title: 'standup',
        start: DateTime(2026, 8, 18, 9),
        end: DateTime(2026, 8, 18, 9, 15),
      );
      expect(saved!.allDay, false);
      expect(saved.start, DateTime(2026, 8, 18, 9));
    });
  });

  group('drawing it', () {
    final oneDay = CalendarEvent(
      uuid: 'e-1',
      calendarUuid: 'cal-1',
      title: 'day off',
      startAt: reminderStamp(DateTime(2026, 8, 18)),
      endAt: reminderStamp(DateTime(2026, 8, 19)),
      allDay: true,
      createdAt: nowStamp(),
      updatedAt: nowStamp(),
    );

    test('one whole day already counts as spanning', () {
      // Which is what puts it in the band rather than in an hour column - the
      // grid needs no separate rule for the one-day case.
      expect(oneDay.spansDays, true);
    });

    test('it is still found by the window query for its own day', () async {
      final store = await freshStore();
      await store.putEvent(oneDay);

      expect(
        (await store.eventsBetween(
          DateTime(2026, 8, 18),
          DateTime(2026, 8, 19),
        ))
            .length,
        1,
      );
      // And not by the next day's, because the end is exclusive.
      expect(
        await store.eventsBetween(DateTime(2026, 8, 19), DateTime(2026, 8, 20)),
        isEmpty,
      );
      await store.close();
    });
  });

  group('notifying for it', () {
    final calendar = Calendar(
      uuid: 'cal-1',
      name: 'Work',
      color: '#6c8cff',
      notifyMinutes: 60,
      createdAt: nowStamp(),
      updatedAt: nowStamp(),
    );

    CalendarEvent dayOff({int? notify}) => CalendarEvent(
          uuid: 'e-1',
          calendarUuid: 'cal-1',
          title: 'day off',
          startAt: reminderStamp(DateTime(2026, 8, 18)),
          endAt: reminderStamp(DateTime(2026, 8, 19)),
          allDay: true,
          notifyMinutes: notify,
          createdAt: nowStamp(),
          updatedAt: nowStamp(),
        );

    test('a whole day does not inherit the calendar rule', () {
      // "An hour before" means an hour before a meeting. Inherited, it would
      // fire at 23:00 the night before for every birthday and every day off.
      expect(dayOff().notifyAt(calendar), isNull);
    });

    test('a lead set on the event itself is honoured', () {
      expect(
        dayOff(notify: 30).notifyAt(calendar),
        DateTime(2026, 8, 17, 23, 30),
      );
    });

    test('a timed event on the same calendar still inherits', () {
      final meeting = CalendarEvent(
        uuid: 'e-2',
        calendarUuid: 'cal-1',
        title: 'review',
        startAt: reminderStamp(DateTime(2026, 8, 18, 15)),
        endAt: reminderStamp(DateTime(2026, 8, 18, 16)),
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );
      expect(meeting.notifyAt(calendar), DateTime(2026, 8, 18, 14));
    });
  });

  group('importing one', () {
    test('an all-day .ics event stops being flattened to an hour', () async {
      final state = await device();
      final events = parseIcs('''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:a
SUMMARY:public holiday
DTSTART;VALUE=DATE:20260818
DTEND;VALUE=DATE:20260819
END:VEVENT
END:VCALENDAR
''');

      expect(events.single.allDay, true);
      await state.importIcsEvents(events,
          calendarUuid: state.calendars.first.uuid);

      final row = (await state.store
              .eventsOnCalendar(state.calendars.first.uuid))
          .single;
      expect(row.allDay, true);
      expect(row.start, DateTime(2026, 8, 18));
      expect(row.end, DateTime(2026, 8, 19));
    });

    test('a timed .ics event is unaffected', () async {
      final state = await device();
      final events = parseIcs('''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:b
SUMMARY:train
DTSTART:20260818T093000
DTEND:20260818T114500
END:VEVENT
END:VCALENDAR
''');

      await state.importIcsEvents(events,
          calendarUuid: state.calendars.first.uuid);

      final row = (await state.store
              .eventsOnCalendar(state.calendars.first.uuid))
          .single;
      expect(row.allDay, false);
      expect(row.start, DateTime(2026, 8, 18, 9, 30));
    });
  });

  group('repeating whole days', () {
    test('a yearly birthday keeps its flag on every occurrence', () {
      final birthday = CalendarEvent(
        uuid: 'e-1',
        calendarUuid: 'cal-1',
        title: 'a birthday',
        startAt: reminderStamp(DateTime(2024, 3, 9)),
        endAt: reminderStamp(DateTime(2024, 3, 10)),
        allDay: true,
        recur: Recur.yearly,
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );

      final out = birthday.occurrencesBetween(
        DateTime(2026, 1, 1),
        DateTime(2027, 1, 1),
      );

      expect(out.length, 1);
      expect(out.single.allDay, true);
      expect(out.single.start, DateTime(2026, 3, 9));
      expect(out.single.end, DateTime(2026, 3, 10));
    });
  });

  group('migration', () {
    test('a pre-v14 database gains the column and keeps its events', () async {
      final dir = await Directory.systemTemp.createTemp('todo_all_day');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      final path = p.join(dir.path, 'todo.db');

      final store = await LocalStore.open(path: path, singleInstance: false);
      await store.raw.insert('calendar_events', {
        'uuid': 'old-block',
        'calendar_uuid': 'cal-1',
        'title': 'from before whole days',
        'start_at': reminderStamp(DateTime(2026, 8, 3, 9)),
        'end_at': reminderStamp(DateTime(2026, 8, 3, 10)),
        'created_at': nowStamp(),
        'updated_at': nowStamp(),
      });
      await store.raw
          .execute('ALTER TABLE calendar_events DROP COLUMN all_day');
      await store.raw.setVersion(13);
      await store.close();

      final upgraded = await LocalStore.open(path: path, singleInstance: false);
      final row = (await upgraded.eventByUuid('old-block'))!;

      expect(row.allDay, false, reason: 'every existing block is a timed one');
      expect(row.title, 'from before whole days');
      await upgraded.close();
    });
  });
}
