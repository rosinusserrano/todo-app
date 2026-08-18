// A block of time that repeats.
//
// The thing under test is that a series is **one row**: its occurrences are
// produced on the way out of the store and never written. That makes two
// classes of bug possible which no screenshot would show - an occurrence that
// is not drawn because the window query filtered its series out, and a write
// made through an occurrence landing on the series with the *occurrence's*
// times, quietly moving every other one. Both are pinned here.

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

  CalendarEvent series(
    DateTime start,
    DateTime end, {
    String uuid = 'series-1',
    String? recur = Recur.weekly,
    String title = 'stand-up',
  }) =>
      CalendarEvent(
        uuid: uuid,
        calendarUuid: 'cal-1',
        title: title,
        startAt: reminderStamp(start),
        endAt: reminderStamp(end),
        recur: recur,
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );

  group('expanding a series', () {
    test('a one-off yields itself only when it overlaps', () {
      final e = series(
        DateTime(2026, 8, 18, 9),
        DateTime(2026, 8, 18, 10),
        recur: null,
      );

      expect(
        e.occurrencesBetween(DateTime(2026, 8, 18), DateTime(2026, 8, 19)),
        [e],
      );
      expect(
        e.occurrencesBetween(DateTime(2026, 8, 19), DateTime(2026, 8, 20)),
        isEmpty,
      );
    });

    test('a weekly block appears once in every week of the window', () {
      final e = series(DateTime(2026, 8, 3, 9), DateTime(2026, 8, 3, 9, 30));

      final out =
          e.occurrencesBetween(DateTime(2026, 8, 1), DateTime(2026, 9, 1));

      expect(out.map((o) => o.start.day), [3, 10, 17, 24, 31]);
      // The length travels with the rule; only the day moves.
      expect(out.every((o) => o.duration == const Duration(minutes: 30)), true);
      expect(out.every((o) => o.start.hour == 9), true);
    });

    test('a window that starts long after the series still finds it', () {
      final e = series(DateTime(2020, 1, 6, 9), DateTime(2020, 1, 6, 10));

      final out =
          e.occurrencesBetween(DateTime(2026, 8, 17), DateTime(2026, 8, 24));

      expect(out.length, 1);
      expect(out.single.start, DateTime(2026, 8, 17, 9));
    });

    test('an occurrence overlapping the window edge is included', () {
      // 23:30 on Sunday to 00:30 on Monday: it belongs on both days' grids.
      final e = series(DateTime(2026, 8, 2, 23, 30), DateTime(2026, 8, 3, 0, 30),
          recur: Recur.daily);

      final out =
          e.occurrencesBetween(DateTime(2026, 8, 5), DateTime(2026, 8, 6));

      expect(out.length, 2);
      expect(out.first.end, DateTime(2026, 8, 5, 0, 30));
      expect(out.last.start, DateTime(2026, 8, 5, 23, 30));
    });

    test('monthly clamps rather than skipping a short month', () {
      final e = series(DateTime(2026, 1, 31, 9), DateTime(2026, 1, 31, 10),
          recur: Recur.monthly);

      final out =
          e.occurrencesBetween(DateTime(2026, 1, 1), DateTime(2026, 4, 1));

      // Counted from the anchor, so February borrows nothing from March: a
      // walk from occurrence to occurrence would stick on the 28th for ever.
      expect(out.map((o) => '${o.start.month}-${o.start.day}'),
          ['1-31', '2-28', '3-31']);
    });

    test('every weekday skips the weekend', () {
      final e = series(DateTime(2026, 8, 17, 9), DateTime(2026, 8, 17, 9, 15),
          recur: Recur.weekdays);

      final out =
          e.occurrencesBetween(DateTime(2026, 8, 17), DateTime(2026, 8, 24));

      expect(out.map((o) => o.start.weekday),
          [1, 2, 3, 4, 5]); // Monday to Friday, nothing at the weekend
    });

    test('a rule this version does not know yields the first occurrence only',
        () {
      final e = series(DateTime(2026, 8, 18, 9), DateTime(2026, 8, 18, 10),
          recur: 'every-fortnight-from-a-newer-build');

      final out =
          e.occurrencesBetween(DateTime(2026, 8, 1), DateTime(2026, 12, 1));

      // Not an error and not an infinite loop: a row from the future reads as
      // a one-off here.
      expect(out.length, 1);
      expect(out.single.start, DateTime(2026, 8, 18, 9));
    });

    test('the wall-clock reading survives a DST boundary', () {
      // Europe/Madrid puts the clocks back on 25 October 2026. A daily 09:00
      // block has to still read 09:00 on the far side of it, which is what
      // calendar arithmetic buys over adding 24 hours.
      final e = series(DateTime(2026, 10, 23, 9), DateTime(2026, 10, 23, 10),
          recur: Recur.daily);

      final out =
          e.occurrencesBetween(DateTime(2026, 10, 23), DateTime(2026, 10, 29));

      expect(out.every((o) => o.start.hour == 9), true,
          reason: 'every occurrence should read 09:00 local');
    });
  });

  group('an occurrence knows what it is', () {
    final first = DateTime(2026, 8, 3, 9);
    final e = series(first, first.add(const Duration(hours: 1)));
    final out = e.occurrencesBetween(DateTime(2026, 8, 1), DateTime(2026, 9, 1));

    test('the first occurrence is the stored row itself', () {
      expect(identical(out.first, e), true);
      expect(out.first.isOccurrence, false);
    });

    test('a later occurrence carries the series and shares its uuid', () {
      final third = out[2];
      expect(third.isOccurrence, true);
      expect(third.uuid, e.uuid);
      expect(third.stored.startAt, e.startAt);
      // Anything keyed on the uuid - attachments, planned todos - therefore
      // needs no special handling at all.
      expect(third.instanceKey == out[1].instanceKey, false);
    });

    test('a write through an occurrence keeps the series times', () {
      final edited = out[2].copyWith(title: 'renamed');

      expect(edited.title, 'renamed');
      expect(edited.startAt, e.startAt,
          reason: 'editing the third Monday must not move the series to it');
      expect(edited.recur, Recur.weekly);
    });

    test('toMap never writes an occurrence start', () {
      expect(out[2].toMap()['start_at'], e.startAt);
    });
  });

  group('the store', () {
    test('the window query returns occurrences, not just the stored row',
        () async {
      final store = await freshStore();
      await store.putEvent(
        series(DateTime(2026, 8, 3, 9), DateTime(2026, 8, 3, 10)),
      );

      final out = await store.eventsBetween(
        DateTime(2026, 9, 1),
        DateTime(2026, 10, 1),
      );

      // The whole window is after the stored end_at, which is exactly the case
      // an end-based filter would drop. Four Mondays in September 2026.
      expect(out.length, 4);
      expect(out.first.start, DateTime(2026, 9, 7, 9));
      await store.close();
    });

    test('a series and a one-off come back in start order', () async {
      final store = await freshStore();
      await store.putEvent(
        series(DateTime(2026, 8, 3, 9), DateTime(2026, 8, 3, 10)),
      );
      await store.putEvent(series(
        DateTime(2026, 8, 10, 8),
        DateTime(2026, 8, 10, 8, 30),
        uuid: 'one-off',
        recur: null,
        title: 'dentist',
      ));

      final out = await store.eventsBetween(
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 11),
      );

      expect(out.map((e) => e.title), ['dentist', 'stand-up']);
      await store.close();
    });

    test('a deleted series stops expanding', () async {
      final store = await freshStore();
      final s = series(DateTime(2026, 8, 3, 9), DateTime(2026, 8, 3, 10));
      await store.putEvent(s);
      await store.putEvent(s.copyWith(deletedAt: nowStamp()));

      expect(
        await store.eventsBetween(DateTime(2026, 8, 1), DateTime(2026, 9, 1)),
        isEmpty,
      );
      await store.close();
    });

    test('liveEvents finds the occurrence covering an instant', () async {
      final store = await freshStore();
      await store.putEvent(
        series(DateTime(2026, 8, 3, 9), DateTime(2026, 8, 3, 10)),
      );

      // The fourth Monday, half way through the block.
      expect(
        (await store.liveEvents(DateTime(2026, 8, 24, 9, 30))).length,
        1,
      );
      // The same Monday, after it has finished.
      expect(
        await store.liveEvents(DateTime(2026, 8, 24, 10, 1)),
        isEmpty,
      );
      // A Tuesday.
      expect(
        await store.liveEvents(DateTime(2026, 8, 25, 9, 30)),
        isEmpty,
      );
      await store.close();
    });

    test('the notification schedule arms one instant per series', () async {
      final store = await freshStore();
      await store.putEvent(
        series(DateTime(2026, 8, 3, 9), DateTime(2026, 8, 3, 10),
            recur: Recur.daily),
      );

      final out = await store.upcomingEvents(DateTime(2026, 8, 20, 12));

      expect(out.length, 1);
      expect(out.single.start, DateTime(2026, 8, 21, 9));
      await store.close();
    });

    test('a finished one-off is not armed', () async {
      final store = await freshStore();
      await store.putEvent(series(
        DateTime(2026, 8, 3, 9),
        DateTime(2026, 8, 3, 10),
        recur: null,
      ));

      expect(await store.upcomingEvents(DateTime(2026, 8, 20, 12)), isEmpty);
      await store.close();
    });
  });

  group('through AppState', () {
    /// A loaded state with its calendars provisioned - the workspace calendar
    /// is created lazily on the first calendar refresh, not by [AppState.load].
    Future<AppState> device() async {
      final state = AppState(await freshStore());
      await state.load();
      await state.refreshCalendars();
      await state.ensureWorkspaceCalendars();
      await state.refreshCalendars();
      return state;
    }

    test('saving a rule keeps one row and shows many blocks', () async {
      final state = await device();
      final cal = state.calendars.first;

      await state.saveEvent(
        calendarUuid: cal.uuid,
        title: 'stand-up',
        start: DateTime(2026, 8, 3, 9),
        end: DateTime(2026, 8, 3, 9, 15),
        recur: Recur.weekly,
      );

      final stored = await state.store.eventsOnCalendar(cal.uuid);
      expect(stored.length, 1, reason: 'a series is one row');

      // A week the series does not start in: what is on screen there can only
      // have come from expanding it.
      await state.setCalendarAnchor(DateTime(2026, 8, 19));
      expect(state.events.length, 1);
      expect(state.events.single.start, DateTime(2026, 8, 17, 9));
      expect(state.events.single.isOccurrence, true);
    });

    test('deleting through an occurrence tombstones the series', () async {
      final state = await device();
      final cal = state.calendars.first;
      await state.saveEvent(
        calendarUuid: cal.uuid,
        title: 'stand-up',
        start: DateTime(2026, 8, 3, 9),
        end: DateTime(2026, 8, 3, 9, 15),
        recur: Recur.weekly,
      );
      await state.setCalendarAnchor(DateTime(2026, 8, 19));

      // The occurrence on screen is the fourth Monday, not the stored row.
      await state.deleteEvent(state.events.single);

      expect(state.events, isEmpty);
      expect(await state.store.eventsOnCalendar(cal.uuid), isEmpty);
    });

    test('clearing the rule leaves the first occurrence behind', () async {
      final state = await device();
      final cal = state.calendars.first;
      final saved = await state.saveEvent(
        calendarUuid: cal.uuid,
        title: 'stand-up',
        start: DateTime(2026, 8, 3, 9),
        end: DateTime(2026, 8, 3, 9, 15),
        recur: Recur.weekly,
      );

      await state.saveEvent(
        existing: saved,
        calendarUuid: cal.uuid,
        title: 'stand-up',
        start: saved!.start,
        end: saved.end,
        clearRecur: true,
      );

      await state.setCalendarAnchor(DateTime(2026, 8, 19));
      expect(state.events, isEmpty,
          reason: 'no rule, so nothing beyond the first block');

      await state.setCalendarAnchor(DateTime(2026, 8, 3));
      expect(state.events.length, 1);
      expect(state.events.single.repeats, false);
    });
  });

  group('reading a rule out of an .ics', () {
    final monday = DateTime(2026, 8, 17, 9);

    test('the plain frequencies come across', () {
      expect(icsRecurRule('FREQ=DAILY', monday), Recur.daily);
      expect(icsRecurRule('FREQ=WEEKLY', monday), Recur.weekly);
      expect(icsRecurRule('FREQ=MONTHLY', monday), Recur.monthly);
      expect(icsRecurRule('FREQ=YEARLY', monday), Recur.yearly);
      expect(icsRecurRule('FREQ=WEEKLY;INTERVAL=1', monday), Recur.weekly);
    });

    test('every working day is a rule this app has', () {
      expect(icsRecurRule('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', monday),
          Recur.weekdays);
      expect(icsRecurRule('FREQ=WEEKLY;BYDAY=FR,TH,WE,TU,MO', monday),
          Recur.weekdays);
    });

    test('a BYDAY that merely restates the start day is still weekly', () {
      expect(icsRecurRule('FREQ=WEEKLY;BYDAY=MO', monday), Recur.weekly);
      expect(icsRecurRule('FREQ=WEEKLY;BYDAY=TU', monday), isNull);
    });

    test('anything with an end or an interval is rejected', () {
      // The important half: these come in as one block plus a note, rather
      // than as "for ever", which would be wrong every week after the sixth.
      expect(icsRecurRule('FREQ=WEEKLY;COUNT=6', monday), isNull);
      expect(icsRecurRule('FREQ=WEEKLY;UNTIL=20261001T090000Z', monday), isNull);
      expect(icsRecurRule('FREQ=WEEKLY;INTERVAL=2', monday), isNull);
      expect(icsRecurRule('FREQ=MONTHLY;BYDAY=2MO', monday), isNull);
      expect(icsRecurRule('FREQ=MONTHLY;BYMONTHDAY=15', monday), isNull);
      expect(icsRecurRule('FREQ=HOURLY', monday), isNull);
      expect(icsRecurRule(null, monday), isNull);
    });

    test('an imported series is a real series, and one that is not says so',
        () async {
      final state = AppState(await freshStore());
      await state.load();
      await state.refreshCalendars();
      await state.ensureWorkspaceCalendars();
      await state.refreshCalendars();
      final cal = state.calendars.first;

      final events = parseIcs('''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:a
SUMMARY:weekly sync
DTSTART:20260817T090000
DTEND:20260817T093000
RRULE:FREQ=WEEKLY
END:VEVENT
BEGIN:VEVENT
UID:b
SUMMARY:six week course
DTSTART:20260818T180000
DTEND:20260818T200000
RRULE:FREQ=WEEKLY;COUNT=6
END:VEVENT
END:VCALENDAR
''');

      await state.importIcsEvents(events, calendarUuid: cal.uuid);

      final rows = await state.store.eventsOnCalendar(cal.uuid);
      final sync = rows.firstWhere((e) => e.title == 'weekly sync');
      final course = rows.firstWhere((e) => e.title == 'six week course');

      expect(sync.recur, Recur.weekly);
      expect(sync.description, isEmpty);
      expect(course.recur, isNull);
      expect(course.description, contains('only this occurrence'));
    });
  });

  group('migration', () {
    test('a pre-v13 database gains the column and keeps its events', () async {
      final dir = await Directory.systemTemp.createTemp('todo_event_recur');
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
        'title': 'from before repeating blocks',
        'start_at': reminderStamp(DateTime(2026, 8, 3, 9)),
        'end_at': reminderStamp(DateTime(2026, 8, 3, 10)),
        'created_at': nowStamp(),
        'updated_at': nowStamp(),
      });
      // Roll the database back past v13 - the column has to go with it, or the
      // migration on the way up finds it already there.
      await store.raw
          .execute('ALTER TABLE calendar_events DROP COLUMN recur');
      await store.raw
          .execute('ALTER TABLE calendar_events DROP COLUMN all_day');
      await store.raw.setVersion(12);
      await store.close();

      final upgraded = await LocalStore.open(path: path, singleInstance: false);
      final row = (await upgraded.raw.query('calendar_events',
              where: 'uuid = ?', whereArgs: ['old-block']))
          .single;

      expect(row['recur'], isNull, reason: 'an existing block is a one-off');
      expect(row['title'], 'from before repeating blocks');
      await upgraded.close();
    });
  });
}
