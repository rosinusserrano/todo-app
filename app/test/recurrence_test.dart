// Recurring tasks.
//
// Two things here are load-bearing and neither is obvious from the schema: the
// next occurrence is computed in *local wall-clock* terms rather than by adding
// a Duration, and its uuid is derived rather than generated. The first is what
// keeps a 09:00 alarm at 09:00 across a DST boundary; the second is what stops
// two devices that both saw a completion from creating two rows sync can only
// keep as siblings.

import 'dart:io' show Directory;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> freshState() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final state = AppState(store);
    await state.load();
    return state;
  }

  group('Recur.next', () {
    test('daily and weekly keep the time of day', () {
      final from = DateTime(2026, 8, 8, 9, 30);
      expect(Recur.next(from, Recur.daily), DateTime(2026, 8, 9, 9, 30));
      expect(Recur.next(from, Recur.weekly), DateTime(2026, 8, 15, 9, 30));
    });

    test('weekdays skips the weekend', () {
      // 2026-08-07 is a Friday.
      final friday = DateTime(2026, 8, 7, 9);
      expect(friday.weekday, DateTime.friday);
      expect(Recur.next(friday, Recur.weekdays), DateTime(2026, 8, 10, 9));

      final saturday = DateTime(2026, 8, 8, 9);
      expect(Recur.next(saturday, Recur.weekdays), DateTime(2026, 8, 10, 9));

      final monday = DateTime(2026, 8, 10, 9);
      expect(Recur.next(monday, Recur.weekdays), DateTime(2026, 8, 11, 9));
    });

    test('monthly clamps rather than spilling into the next month', () {
      // The 31st has no counterpart in a 30-day month, and DateTime would
      // normalise 31 September to 1 October - a "monthly" task that quietly
      // moved to the 1st.
      expect(
        Recur.next(DateTime(2026, 8, 31, 9), Recur.monthly),
        DateTime(2026, 9, 30, 9),
      );
      expect(
        Recur.next(DateTime(2026, 1, 31, 9), Recur.monthly),
        DateTime(2026, 2, 28, 9),
      );
    });

    test('yearly pulls 29 February back to the 28th', () {
      expect(
        Recur.next(DateTime(2028, 2, 29, 9), Recur.yearly),
        DateTime(2029, 2, 28, 9),
      );
    });

    test('a rule this build does not know produces nothing', () {
      // Arrives from a newer device by sync; the task just stops repeating here
      // rather than throwing.
      expect(Recur.next(DateTime(2026, 8, 8, 9), 'fortnightly'), isNull);
    });

    test('crossing a month and a year boundary normalises', () {
      expect(
        Recur.next(DateTime(2026, 12, 31, 23, 45), Recur.daily),
        DateTime(2027, 1, 1, 23, 45),
      );
    });
  });

  group('Task.nextOccurrence', () {
    Task recurring({String rule = Recur.daily, DateTime? at}) => Task(
          uuid: 'parent-uuid',
          workspaceUuid: 'ws',
          text: 'stand-up',
          createdAt: nowStamp(),
          remindAt: reminderStamp(at ?? DateTime(2026, 8, 8, 9)),
          recur: rule,
          notes: 'the agenda',
          priority: Task.priorityHigh,
          updatedAt: nowStamp(),
        );

    test('is null for a one-off, and for a rule with no reminder', () {
      final once = recurring().copyWith(clearRecur: true);
      expect(once.nextOccurrence(), isNull);

      final unarmed = recurring().copyWith(clearReminder: true);
      expect(unarmed.nextOccurrence(), isNull);
    });

    test('carries the rule, the text and the fields forward', () {
      final next = recurring().nextOccurrence()!;

      expect(next.text, 'stand-up');
      expect(next.recur, Recur.daily);
      expect(next.notes, 'the agenda');
      expect(next.priority, Task.priorityHigh);
      expect(next.remindAtTime, DateTime(2026, 8, 9, 9));

      // A fresh occurrence, not a copy of a finished one.
      expect(next.completedAt, isNull);
      expect(next.isActive, isTrue);
    });

    test('does not inherit the block of time the last one was planned into',
        () {
      // A block is a specific afternoon; inheriting it would plan next week's
      // task into last week's.
      final planned = recurring().copyWith(eventUuid: 'some-block');
      expect(planned.nextOccurrence()!.eventUuid, isNull);
    });

    test('derives the same uuid on two devices', () {
      // The whole point: completion is a write, it syncs, and both devices
      // spawn. Generated ids would make those siblings.
      final a = recurring().nextOccurrence()!;
      final b = recurring().nextOccurrence()!;

      expect(a.uuid, b.uuid);
      expect(a.uuid, isNot('parent-uuid'));
    });

    test('a different occurrence is a different row', () {
      final first = recurring().nextOccurrence()!;
      final second = first.nextOccurrence()!;

      expect(second.uuid, isNot(first.uuid));
      expect(second.remindAtTime, DateTime(2026, 8, 10, 9));
    });
  });

  group('completing a recurring task', () {
    test('logs the one done and lays down the next', () async {
      final s = await freshState();
      await s.addTask(
        'stand-up',
        remindAt: DateTime.now().add(const Duration(hours: 1)),
        recur: Recur.daily,
      );

      final today = s.tasks.single;
      await s.completeTask(today);

      // The finished one is in History, like any other completed task - which
      // is the reason recurrence needed no changes there.
      await s.toggleHistory();
      expect(s.historyTasks.single.uuid, today.uuid);

      // And the next one is on the list, armed a day later.
      await s.toggleHistory();
      final next = s.tasks.single;
      expect(next.uuid, isNot(today.uuid));
      expect(next.text, 'stand-up');
      expect(next.recur, Recur.daily);

      // Compared as wall-clock rather than as a 24-hour duration: "the next day
      // at the same time" is the promise, and it is deliberately not the same
      // thing across a DST boundary, where that day is 23 or 25 hours long.
      final was = today.remindAtTime!;
      final now = next.remindAtTime!;
      expect(now.hour, was.hour);
      expect(now.minute, was.minute);
      expect(
        DateTime(now.year, now.month, now.day)
            .difference(DateTime(was.year, was.month, was.day))
            .inDays,
        1,
      );
    });

    test('a one-off leaves nothing behind', () async {
      final s = await freshState();
      await s.addTask('ship it');
      await s.completeTask(s.tasks.single);
      expect(s.tasks, isEmpty);
    });

    test('completing it twice does not make two successors', () async {
      // Two devices both see the completion and both spawn; the derived uuid is
      // what makes the second an update of the first rather than a sibling.
      final s = await freshState();
      await s.addTask(
        'stand-up',
        remindAt: DateTime.now().add(const Duration(hours: 1)),
        recur: Recur.daily,
      );
      final today = s.tasks.single;

      await s.completeTask(today);
      await s.completeTask(today);

      expect(s.tasks.length, 1);
    });

    test('clearing the reminder clears the rule with it', () async {
      // A recurrence with nothing to count from would never produce a second
      // occurrence, so it must not be left set and silently inert.
      final s = await freshState();
      await s.addTask(
        'stand-up',
        remindAt: DateTime.now().add(const Duration(hours: 1)),
        recur: Recur.daily,
      );

      await s.saveTaskDetails(
        s.tasks.single,
        text: 'stand-up',
        notes: '',
        priority: 0,
        remindAt: null,
        recur: Recur.daily,
      );

      expect(s.tasks.single.recur, isNull);
    });
  });

  test('a pre-v12 database gains the column and keeps its tasks', () async {
    // A temp file, not inMemoryDatabasePath: closing an in-memory database
    // discards it, so the reopen below would find an empty one and the
    // migration would never be exercised.
    //
    // Rolled back rather than hand-built: dropping the column is what proves
    // the migration adds it, and the row has to survive.
    final dir = await Directory.systemTemp.createTemp('todo_recur_migrate');
    // Best-effort: Windows refuses to unlink a file the sqlite handle still
    // holds, and a temp directory left behind must not fail the test.
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    final path = p.join(dir.path, 'todo.db');

    final store = await LocalStore.open(path: path, singleInstance: false);
    await store.raw.insert('tasks', {
      'uuid': 'old-row',
      'workspace_uuid': LocalStore.defaultWorkspaceUuid,
      'text': 'from before recurrence',
      'created_at': nowStamp(),
      'updated_at': nowStamp(),
    });
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN recur');
    // v13 put the same column on calendar_events; rolling back past v12 means
    // rolling back past that too, or its migration collides on the way up.
    await store.raw.execute('ALTER TABLE calendar_events DROP COLUMN recur');
    await store.raw.setVersion(11);
    await store.close();

    final upgraded = await LocalStore.open(path: path, singleInstance: false);
    final rows = await upgraded.raw.query(
      'tasks',
      where: 'uuid = ?',
      whereArgs: ['old-row'],
    );
    expect(rows.single['recur'], isNull);
    expect(rows.single['text'], 'from before recurrence');

    // The column is really usable, not merely present: writing a rule through
    // it is what would fail if the ALTER had not run.
    await upgraded.putTask(
      Task.fromMap(rows.single).copyWith(recur: Recur.weekly),
    );
    final back = await upgraded.raw
        .query('tasks', where: 'uuid = ?', whereArgs: ['old-row']);
    expect(back.single['recur'], Recur.weekly);

    await upgraded.close();
  });
}
