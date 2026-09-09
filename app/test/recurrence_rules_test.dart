// The half of recurrence that arrived in 0.28.0: rules a due date cannot say,
// an interval counted from the completion, todos that are created because time
// passed rather than because something was ticked, and variables in the title.
//
// `recurrence_test.dart` still covers the original shape - the plain rules, the
// derived uuid, spawn-on-completion - and none of that changes here.

import 'dart:io' show Directory;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/task_variables.dart';

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

  // ------------------------------------------------------------ the rules

  group('rules a due date cannot say', () {
    test('the last day of every month, and never the 28th for ever', () {
      // The trap this rule exists for: "monthly" from 31 January clamps to 28
      // February, and walking on from *there* gives 28 March and the 28th of
      // every month after it. One short February silently rewrites the rule.
      expect(
        Recur.next(DateTime(2026, 1, 31, 9), Recur.monthly),
        DateTime(2026, 2, 28, 9),
      );
      expect(
        Recur.next(DateTime(2026, 2, 28, 9), Recur.monthly),
        DateTime(2026, 3, 28, 9),
      );

      // month-last does not walk, it asks what the end of the month is.
      var at = DateTime(2026, 1, 31, 9);
      final ends = <DateTime>[];
      for (var i = 0; i < 4; i++) {
        at = Recur.next(at, Recur.monthLast)!;
        ends.add(at);
      }
      expect(ends, [
        DateTime(2026, 2, 28, 9),
        DateTime(2026, 3, 31, 9),
        DateTime(2026, 4, 30, 9),
        DateTime(2026, 5, 31, 9),
      ]);
    });

    test('a rule set mid-month lands on the end of that same month', () {
      // "The first occurrence strictly after this instant", not "one period
      // later" - otherwise setting the rule on the 9th would skip September.
      expect(
        Recur.next(DateTime(2026, 9, 9, 17), Recur.monthLast),
        DateTime(2026, 9, 30, 17),
      );
    });

    test('the first Monday of the month', () {
      final rule = Recur.nthWeekday(1, DateTime.monday);
      expect(rule, 'month-1-mon');

      // 7 September 2026 is a Monday, and the first one that month.
      expect(
        Recur.next(DateTime(2026, 8, 20, 9), rule),
        DateTime(2026, 9, 7, 9),
      );
      expect(
        Recur.next(DateTime(2026, 9, 7, 9), rule),
        DateTime(2026, 10, 5, 9),
      );
    });

    test('the last Friday of the month', () {
      final rule = Recur.nthWeekday(Recur.ordLast, DateTime.friday);
      expect(rule, 'month-last-fri');
      expect(
        Recur.next(DateTime(2026, 9, 1, 16), rule),
        DateTime(2026, 9, 25, 16),
      );
      // October 2026 ends on a Saturday, so the last Friday is the 30th.
      expect(
        Recur.next(DateTime(2026, 9, 25, 16), rule),
        DateTime(2026, 10, 30, 16),
      );
    });

    test('every n days, weeks, months and years', () {
      expect(
        Recur.next(DateTime(2026, 9, 9, 9), Recur.every(3, Recur.unitDay)),
        DateTime(2026, 9, 12, 9),
      );
      expect(
        Recur.next(DateTime(2026, 9, 9, 9), Recur.every(2, Recur.unitWeek)),
        DateTime(2026, 9, 23, 9),
      );
      // Month-length overflow clamps rather than spilling into the next month.
      expect(
        Recur.next(DateTime(2026, 12, 31, 9), Recur.every(2, Recur.unitMonth)),
        DateTime(2027, 2, 28, 9),
      );
      expect(
        Recur.next(DateTime(2028, 2, 29, 9), Recur.every(1, Recur.unitYear)),
        DateTime(2029, 2, 28, 9),
      );
    });

    test('labels read as sentences, and an unknown rule prints itself', () {
      expect(Recur.label(Recur.monthLast), 'Last day of the month');
      expect(Recur.label('month-1-mon'), 'First Monday of the month');
      expect(Recur.label('month-last-fri'), 'Last Friday of the month');
      expect(Recur.label('every-1-w'), 'Every week');
      expect(Recur.label('every-2-w'), 'Every 2 weeks');
      expect(Recur.label('fortnightly-ish'), 'fortnightly-ish');
    });

    test('the new forms are for tasks only', () {
      // A calendar block expands its occurrences through Recur.nth, and nothing
      // can give a block one of these rules. Unknown means "no occurrences",
      // which is also what a rule from a newer device means.
      expect(Recur.nth(DateTime(2026, 9, 1, 9), Recur.monthLast, 1), isNull);
      expect(Recur.rules.contains(Recur.monthLast), isFalse);
      expect(Recur.isKnown(Recur.monthLast), isTrue);
      expect(Recur.isKnown('every-0-w'), isFalse);
      expect(Recur.isKnown('month-9-mon'), isFalse);
    });
  });

  // ------------------------------------------------------------- variables

  group('variables in the title', () {
    final due = DateTime(2026, 9, 30, 17);

    test('name the date the occurrence is for', () {
      expect(
        expandTaskVariables(
            'Send working hours for \$(month) to management', due),
        'Send working hours for September to management',
      );
      expect(expandTaskVariables('\$(mon) \$(mm) \$(yy)', due), 'Sep 09 26');
      expect(expandTaskVariables('\$(weekday) \$(dd)', due), 'Wednesday 30');
      expect(expandTaskVariables('\$(date)', due), '30 Sep 2026');
      expect(expandTaskVariables('\$(quarter) \$(year)', due), 'Q3 2026');
    });

    test('offsets move by that variable-s own unit', () {
      expect(expandTaskVariables('\$(month-1)', due), 'August');
      expect(expandTaskVariables('\$(month+1)', due), 'October');
      // Across the year boundary, in both directions.
      expect(
        expandTaskVariables('\$(month-1) \$(year-1)', DateTime(2026, 1, 15)),
        'December 2025',
      );
      expect(expandTaskVariables('\$(day+1)', DateTime(2026, 9, 30)), '1');
    });

    test('leave anything they do not recognise exactly as it was', () {
      // A title is prose and `$(` is not something anyone writes by accident,
      // but mangling a misspelled name would be worse than printing it.
      expect(expandTaskVariables('costs \$5, \$(nonsense)', due),
          'costs \$5, \$(nonsense)');
      expect(hasTaskVariables('nothing here'), isFalse);
      expect(hasTaskVariables('for \$(month)'), isTrue);
    });

    test('the ISO week is the week of the Thursday', () {
      expect(isoWeek(DateTime(2026, 1, 1)), 1);
      // 3 January 2027 is a Sunday, and so belongs to week 53 of 2026.
      expect(isoWeek(DateTime(2027, 1, 3)), 53);
    });
  });

  // ---------------------------------------------------- counted from a tick

  group('counted from the completion', () {
    Task chore({DateTime? remind, DateTime? done}) => Task(
          uuid: 'chore',
          workspaceUuid: 'ws',
          text: 'clean the kitchen',
          createdAt: stampOf(DateTime(2026, 1, 1, 9)),
          remindAt: remind == null ? null : reminderStamp(remind),
          completedAt: done == null ? null : stampOf(done),
          recur: Recur.every(2, Recur.unitWeek),
          recurFrom: RecurFrom.completion,
          recurLead: 0,
          updatedAt: nowStamp(),
        );

    test('the clock starts when it was ticked, not when it was due', () {
      // Created for the 1st, actually done on the 8th: back on the 22nd. A
      // schedule would say the 15th and hand you a backlog for being late.
      final done = chore(
        remind: DateTime(2026, 1, 1, 9),
        done: DateTime(2026, 1, 8, 19, 43),
      );
      expect(done.nextDueAt(), DateTime(2026, 1, 22, 9));
    });

    test('with no reminder it keeps the time it was ticked', () {
      final done = chore(done: DateTime(2026, 1, 8, 19, 43));
      expect(done.nextDueAt(), DateTime(2026, 1, 22, 19, 43));
      // And the occurrence it produces has no reminder either: coming back onto
      // the list is the nudge, and inventing an alarm would be a second one.
      expect(done.nextOccurrence()!.remindAt, isNull);
    });

    test('an unticked one owes nothing', () {
      expect(chore(remind: DateTime(2026, 1, 1, 9)).nextDueAt(), isNull);
      expect(
        chore(remind: DateTime(2026, 1, 1, 9)).dueOccurrences(DateTime(2027, 1, 1)),
        isEmpty,
      );
    });

    test('and it can never pile up', () {
      // The chain stops after one: the second occurrence is measured from a
      // completion that has not happened.
      final done = chore(done: DateTime(2026, 1, 8, 19, 43));
      expect(done.dueOccurrences(DateTime(2027, 1, 1)), hasLength(1));
    });
  });

  // ------------------------------------------------- created by the clock

  group('created because time passed', () {
    Task report({int? lead, DateTime? done}) => Task(
          uuid: 'report',
          workspaceUuid: 'ws',
          text: 'Send working hours for August to management',
          recurText: 'Send working hours for \$(month) to management',
          createdAt: stampOf(DateTime(2026, 8, 1, 9)),
          remindAt: reminderStamp(DateTime(2026, 8, 31, 17)),
          completedAt: done == null ? null : stampOf(done),
          recur: Recur.monthLast,
          recurLead: lead,
          updatedAt: nowStamp(),
        );

    test('a lead of zero creates it on the day, ticked or not', () {
      final open = report(lead: 0);
      expect(open.dueOccurrences(DateTime(2026, 9, 29)), isEmpty);

      final due = open.dueOccurrences(DateTime(2026, 9, 30, 18));
      expect(due, hasLength(1));
      expect(due.single.remindAtTime, DateTime(2026, 9, 30, 17));
      // The template travels and the expansion is per occurrence.
      expect(due.single.text, 'Send working hours for September to management');
      expect(due.single.recurText,
          'Send working hours for \$(month) to management');
    });

    test('a lead creates it early with the due date still the rule-s', () {
      final open = report(lead: 3 * 24 * 60);
      expect(open.dueOccurrences(DateTime(2026, 9, 26)), isEmpty);

      final due = open.dueOccurrences(DateTime(2026, 9, 28)).single;
      expect(due.remindAtTime, DateTime(2026, 9, 30, 17));
      expect(due.text, 'Send working hours for September to management');
    });

    test('no lead is the old behaviour: nothing until it is ticked', () {
      expect(report().dueOccurrences(DateTime(2027, 1, 1)), isEmpty);
      expect(
        report(done: DateTime(2026, 8, 31, 18))
            .dueOccurrences(DateTime(2026, 8, 31, 18, 1)),
        hasLength(1),
      );
    });

    test('a long absence catches up to the recent ones, not to all of them',
        () {
      final standup = Task(
        uuid: 'standup',
        workspaceUuid: 'ws',
        text: 'stand-up',
        createdAt: stampOf(DateTime(2026, 1, 1, 9)),
        remindAt: reminderStamp(DateTime(2026, 1, 1, 9)),
        recur: Recur.daily,
        recurLead: 0,
        updatedAt: nowStamp(),
      );

      // A year off. 365 rows nobody was going to do is not a catch-up.
      final due = standup.dueOccurrences(DateTime(2027, 1, 1, 12));
      expect(due, hasLength(Task.maxCatchUp));
      // The most recent ones, ending at the last occurrence actually owed.
      expect(due.last.remindAtTime, DateTime(2027, 1, 1, 9));
    });
  });

  // ------------------------------------------------------ through AppState

  group('the sweep', () {
    test('lays down a rule-based todo without anything being ticked', () async {
      final s = await freshState();
      await s.addTask(
        'Send working hours for \$(month) to management',
        remindAt: DateTime(2026, 8, 31, 17),
        recur: Recur.monthLast,
        recurLead: 0,
      );

      // The one just added is written out against its own due date.
      expect(s.tasks.single.text,
          'Send working hours for August to management');

      expect(await s.sweepRecurrences(DateTime(2026, 9, 29)), 0);
      expect(await s.sweepRecurrences(DateTime(2026, 9, 30, 18)), 1);

      expect(
        s.tasks.map((t) => t.text),
        containsAll([
          'Send working hours for August to management',
          'Send working hours for September to management',
        ]),
      );
      // August is still there, unticked and overdue, which is the point: a
      // month you did not answer for is a row that says so.
      expect(s.tasks, hasLength(2));
    });

    test('is idempotent - a second sweep writes nothing', () async {
      final s = await freshState();
      await s.addTask(
        'monthly report',
        remindAt: DateTime(2026, 8, 31, 17),
        recur: Recur.monthLast,
        recurLead: 0,
      );

      expect(await s.sweepRecurrences(DateTime(2026, 9, 30, 18)), 1);
      expect(await s.sweepRecurrences(DateTime(2026, 9, 30, 19)), 0);
      expect(s.tasks, hasLength(2));
    });

    test('a deleted occurrence stays deleted', () async {
      final s = await freshState();
      await s.addTask(
        'monthly report',
        remindAt: DateTime(2026, 8, 31, 17),
        recur: Recur.monthLast,
        recurLead: 0,
      );
      await s.sweepRecurrences(DateTime(2026, 9, 30, 18));

      final september = s.tasks.firstWhere(
        (t) => t.remindAtTime == DateTime(2026, 9, 30, 17),
      );
      await s.deleteTask(september);

      // The tombstone counts as existing, or the next tick would put it back.
      expect(await s.sweepRecurrences(DateTime(2026, 9, 30, 19)), 0);
      expect(s.tasks, hasLength(1));
    });

    test('stopping the repeat stops the sweep', () async {
      final s = await freshState();
      await s.addTask(
        'clean the kitchen',
        recur: Recur.every(2, Recur.unitWeek),
        recurFrom: RecurFrom.completion,
        recurLead: 0,
      );

      await s.completeTask(s.tasks.single);
      expect(s.tasks, isEmpty, reason: 'it comes back in a fortnight, not now');

      await s.toggleHistory();
      await s.stopRepeating(s.historyTasks.single);

      expect(await s.sweepRecurrences(DateTime.now().add(const Duration(days: 30))), 0);
      expect(s.tasks, isEmpty);
    });

    test('a chore comes back a fortnight after it was done, not before',
        () async {
      final s = await freshState();
      await s.addTask(
        'clean the kitchen',
        recur: Recur.every(2, Recur.unitWeek),
        recurFrom: RecurFrom.completion,
        recurLead: 0,
      );
      final at = DateTime.now();
      await s.completeTask(s.tasks.single);

      expect(await s.sweepRecurrences(at.add(const Duration(days: 13))), 0);
      expect(await s.sweepRecurrences(at.add(const Duration(days: 15))), 1);
      expect(s.tasks.single.text, 'clean the kitchen');
    });

    test('a repeat with no reminder survives only when it counts from the tick',
        () async {
      final s = await freshState();

      // Nothing to measure a schedule from, so the rule is dropped rather than
      // stored where it would silently do nothing.
      await s.addTask('scheduled with no clock', recur: Recur.daily);
      expect(s.tasks.single.recur, isNull);

      await s.addTask(
        'counted from the tick',
        recur: Recur.every(1, Recur.unitWeek),
        recurFrom: RecurFrom.completion,
        recurLead: 0,
      );
      expect(
        s.tasks.firstWhere((t) => t.text == 'counted from the tick').recur,
        'every-1-w',
      );
    });
  });

  // --------------------------------------------------------------- storage

  group('storage', () {
    test('the four columns survive a round trip', () async {
      final s = await freshState();
      await s.addTask(
        'Hours for \$(month)',
        notes: 'due \$(date)',
        remindAt: DateTime(2026, 8, 31, 17),
        recur: Recur.monthLast,
        recurLead: 4320,
      );

      final reloaded = await s.store.taskByUuid(s.tasks.single.uuid);
      expect(reloaded!.recur, Recur.monthLast);
      expect(reloaded.recurFrom, RecurFrom.schedule);
      expect(reloaded.recurLead, 4320);
      expect(reloaded.recurText, 'Hours for \$(month)');
      expect(reloaded.recurNotes, 'due \$(date)');
      expect(reloaded.text, 'Hours for August');
      expect(reloaded.notes, 'due 31 Aug 2026');
    });

    test('a task with no variables stores no template', () async {
      final s = await freshState();
      await s.addTask(
        'stand-up',
        remindAt: DateTime(2026, 8, 31, 9),
        recur: Recur.daily,
      );

      // Null already means "the text is its own template", which is true of
      // almost every task and of every row written before v15 - a copy beside
      // it would be a second thing to keep in step.
      expect(s.tasks.single.recurText, isNull);
      expect(s.tasks.single.recurNotes, isNull);
    });

    test('a pre-v15 database gains the four columns and keeps its rules',
        () async {
      // A temp file, not inMemoryDatabasePath: closing an in-memory database
      // discards it, so the reopen below would find an empty one.
      final dir = await Directory.systemTemp.createTemp('todo_recur15');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });
      final path = p.join(dir.path, 'todo.db');

      final store = await LocalStore.open(path: path, singleInstance: false);
      await store.raw.insert('tasks', {
        'uuid': 'old-repeat',
        'workspace_uuid': LocalStore.defaultWorkspaceUuid,
        'text': 'stand-up',
        'created_at': nowStamp(),
        'updated_at': nowStamp(),
        'remind_at': reminderStamp(DateTime(2026, 8, 31, 9)),
        'recur': Recur.daily,
      });
      await store.raw.execute('DROP INDEX idx_tasks_recur');
      await store.raw.execute('ALTER TABLE tasks DROP COLUMN recur_from');
      await store.raw.execute('ALTER TABLE tasks DROP COLUMN recur_lead');
      await store.raw.execute('ALTER TABLE tasks DROP COLUMN recur_text');
      await store.raw.execute('ALTER TABLE tasks DROP COLUMN recur_notes');
      await store.raw.setVersion(14);
      await store.close();

      final upgraded = await LocalStore.open(path: path, singleInstance: false);
      final row = (await upgraded.taskByUuid('old-repeat'))!;

      // Every default is what the row already meant, so nothing is backfilled
      // and the task goes on repeating in exactly the way it did.
      expect(row.recur, Recur.daily);
      expect(row.recurFrom, RecurFrom.schedule);
      expect(row.recurLead, isNull);
      expect(row.recurText, isNull);
      expect(row.recurNotes, isNull);

      // Which is to say: nothing until it is ticked.
      expect(row.dueOccurrences(DateTime(2027, 1, 1)), isEmpty);

      // And the columns are usable, not merely present.
      await upgraded.putTask(row.copyWith(recurLead: 0));
      expect((await upgraded.taskByUuid('old-repeat'))!.recurLead, 0);
      await upgraded.close();
    });

    test('a row from an older peer merges rather than aborting the sync',
        () async {
      final s = await freshState();

      // What a server holds for a device that predates these columns: the rule
      // and nothing else. applyRemote inserts a server row verbatim, so a NOT
      // NULL recur_from would make this a constraint failure - and it would
      // abort the whole merge transaction, so one old peer would stop every row
      // arriving, not just this one.
      await s.store.applyRemote({
        'tasks': [
          {
            'uuid': 'from-an-old-peer',
            'workspace_uuid': LocalStore.defaultWorkspaceUuid,
            'text': 'stand-up',
            'created_at': nowStamp(),
            'updated_at': nowStamp(),
            'completed_at': null,
            'sort_order': 0,
            'in_progress': 0,
            'remind_at': reminderStamp(DateTime(2026, 8, 31, 9)),
            'recur': Recur.daily,
            'recur_from': null,
            'recur_lead': null,
            'recur_text': null,
            'recur_notes': null,
            'group_uuid': null,
            'event_uuid': null,
            'notes': '',
            'priority': 0,
            'deleted_at': null,
          },
        ],
      });

      final row = (await s.store.taskByUuid('from-an-old-peer'))!;
      expect(row.recur, Recur.daily);
      // Read back as what the row meant, so the model still has two states.
      expect(row.recurFrom, RecurFrom.schedule);
    });

    test('turning the repeat off takes the rest of it with it', () async {
      final s = await freshState();
      await s.addTask(
        'Hours for \$(month)',
        remindAt: DateTime(2026, 8, 31, 17),
        recur: Recur.monthLast,
        recurLead: 0,
      );

      await s.saveTaskDetails(
        s.tasks.single,
        text: 'Hours for August',
        notes: '',
        priority: 0,
        remindAt: DateTime(2026, 8, 31, 17),
        recur: null,
      );

      final row = s.tasks.single;
      expect(row.recur, isNull);
      expect(row.recurLead, isNull);
      expect(row.recurText, isNull);
      expect(row.recurFrom, RecurFrom.schedule);
    });
  });
}
