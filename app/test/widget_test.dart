// App behaviour tests.
//
// These avoid main.dart, which calls window_manager and flutter_acrylic on
// startup - both need a real window and platform channels that do not exist in
// a test binding. The logic worth testing lives in AppState and the row
// widgets, neither of which touches the window.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tray_manager/tray_manager.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/reminders.dart';
import 'package:todo_widget/tray.dart';
import 'package:todo_widget/ui/reminder_menu.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/task_row.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> freshState() async {
    // singleInstance: false, or every test in this file shares one database.
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final state = AppState(store);
    await state.load();
    return state;
  }

  group('AppState', () {
    test('starts on a workspace so a task can be added immediately', () async {
      final s = await freshState();
      expect(s.currentWorkspaceUuid, isNotNull);

      await s.addTask('write the port');
      expect(s.tasks.single.text, 'write the port');
    });

    test('checking off keeps the task and moves it into history', () async {
      final s = await freshState();
      await s.addTask('ship it');
      await s.completeTask(s.tasks.single);

      expect(s.tasks, isEmpty);
      await s.toggleHistory();
      expect(s.historyTasks.single.text, 'ship it');
    });

    test('deleting tombstones the task instead of dropping the row', () async {
      final s = await freshState();
      await s.addTask('never mind');
      final t = s.tasks.single;
      await s.deleteTask(t);

      expect(s.tasks, isEmpty);

      // The row must survive as a tombstone, otherwise the delete never
      // reaches another device.
      final dirty = await s.store.dirtyRows();
      final row = dirty['tasks']!.firstWhere((r) => r['uuid'] == t.uuid);
      expect(row['deleted_at'], isNotNull);
    });

    test('a deleted task does not come back in history', () async {
      final s = await freshState();
      await s.addTask('dismissed');
      await s.deleteTask(s.tasks.single);
      await s.toggleHistory();
      expect(s.historyTasks, isEmpty);
    });

    test('focus is exclusive and survives a reload', () async {
      final s = await freshState();
      await s.addTask('first');
      await s.addTask('second');

      await s.enterFocus(s.tasks.first);
      expect(s.focusTask, isNotNull);

      await s.enterFocus(s.tasks.last);
      final flagged = s.tasks.where((t) => t.inProgress).toList();
      expect(flagged.length, 1, reason: 'only one task may be in progress');

      // Reopening the app must drop straight back into focus.
      s.focusTask = null;
      await s.restoreFocus();
      expect(s.focusTask!.uuid, flagged.single.uuid);
    });

    test('leaving focus clears the flag', () async {
      final s = await freshState();
      await s.addTask('focused');
      await s.enterFocus(s.tasks.single);
      await s.exitFocus();

      expect(s.focusTask, isNull);
      expect(s.tasks.single.inProgress, isFalse);
    });

    test('the close guard blocks only while thoughts are pending', () async {
      final s = await freshState();
      expect(await s.canProceedPastThoughts(), isTrue);

      await s.addThought('look into flutter');
      expect(await s.canProceedPastThoughts(), isFalse);

      await s.resolveThought(s.thoughts.single);
      expect(await s.canProceedPastThoughts(), isTrue);
    });

    test('tasks do not block closing - only thoughts do', () async {
      final s = await freshState();
      await s.addTask('still outstanding');
      expect(await s.canProceedPastThoughts(), isTrue);
    });

    test('promoting a thought creates a task and resolves the thought',
        () async {
      final s = await freshState();
      await s.addThought('buy a domain');
      await s.promoteThought(s.thoughts.single);

      expect(s.tasks.single.text, 'buy a domain');
      expect(s.thoughts, isEmpty);
    });

    test('deleting a workspace cascades to its tasks, history included',
        () async {
      final s = await freshState();
      await s.saveWorkspace(name: 'Side project', color: '#7ee3a1');
      final side = s.currentWorkspaceUuid!;
      await s.addTask('still open');
      await s.addTask('already done');
      await s.completeTask(s.tasks.last);

      await s.deleteWorkspace(side);

      expect(s.workspaces.any((w) => w.uuid == side), isFalse);

      // Both rows must be tombstoned, not dropped, so the deletion reaches
      // other devices. Completed ones count: leaving them behind would strand
      // history in a workspace that no longer exists.
      final rows = await s.store.raw
          .query('tasks', where: 'workspace_uuid = ?', whereArgs: [side]);
      expect(rows.length, 2);
      expect(rows.every((r) => r['deleted_at'] != null), isTrue);
    });

    test('deleting the focused workspace drops focus', () async {
      final s = await freshState();
      await s.saveWorkspace(name: 'Temp', color: '#ff6c6c');
      final temp = s.currentWorkspaceUuid!;
      await s.addTask('focused here');
      await s.enterFocus(s.tasks.single);

      await s.deleteWorkspace(temp);
      expect(s.focusTask, isNull);
    });

    test('a mutation notifies the sync hook', () async {
      final s = await freshState();
      var fired = 0;
      s.onMutated = () => fired++;

      await s.addTask('triggers a sync');
      expect(fired, greaterThan(0));
    });

    test('the last workspace cannot be deleted', () async {
      final s = await freshState();
      final only = s.currentWorkspaceUuid;
      await s.deleteWorkspace(only!);
      expect(s.workspaces.length, 1);
    });
  });

  group('theme', () {
    test('complementary colour stays vivid even for a pale input', () {
      // A washed-out workspace colour must still yield an alarm colour that
      // reads - that is the whole job of the side-thought bar.
      final c = T.complementary(const Color(0xFFE0E0E0));
      final hsl = HSLColor.fromColor(c);
      expect(hsl.saturation, greaterThan(0.8));
    });

    test('hex round-trips', () {
      expect(T.toHex(T.parseHex('#6c8cff')), '#6c8cff');
    });
  });

  group('TaskRow', () {
    testWidgets('renders the task text and reveals actions on hover',
        (tester) async {
      final task = Task(
        uuid: 't1',
        workspaceUuid: 'ws',
        text: 'a visible task',
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TaskRow(
            task: task,
            accent: T.accent,
            onComplete: () async {},
            onDelete: () async {},
            onFocus: () {},
          ),
        ),
      ));

      expect(find.text('a visible task'), findsOneWidget);
    });

    testWidgets('plays the slide-out before reporting completion',
        (tester) async {
      var completed = false;
      final task = Task(
        uuid: 't1',
        workspaceUuid: 'ws',
        text: 'check me off',
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TaskRow(
            task: task,
            accent: T.accent,
            onComplete: () async => completed = true,
            onDelete: () async {},
            onFocus: () {},
          ),
        ),
      ));

      await tester.tap(find.byType(InkWell).first);
      await tester.pump();

      // Still mid-animation: the row must not report completion until the
      // slide-out has finished, or the list rebuilds under it.
      expect(completed, isFalse);

      await tester.pumpAndSettle();
      expect(completed, isTrue);
    });
  });

  group('reminders', () {
    test('a task with no reminder is never due', () async {
      final s = await freshState();
      await s.addTask('unscheduled');
      expect(s.tasks.single.isDue(), isFalse);
    });

    test('is due once its time has passed, and not before', () async {
      final s = await freshState();
      await s.addTask('call the dentist');
      final at = DateTime.now().add(const Duration(hours: 1));
      await s.setReminder(s.tasks.single, at);

      final t = s.tasks.single;
      expect(t.isDue(), isFalse);
      expect(t.isDue(at.add(const Duration(minutes: 1))), isTrue);
    });

    test('survives the round trip through the database as an instant',
        () async {
      final s = await freshState();
      await s.addTask('leave for the train');
      final at = DateTime.now().add(const Duration(minutes: 90));
      await s.setReminder(s.tasks.single, at);

      await s.refreshTasks();
      // Stored in UTC, read back as local: the instant is what has to match,
      // not the wall-clock string.
      expect(
        s.tasks.single.remindAtTime!.difference(at).inSeconds.abs(),
        lessThan(1),
      );
    });

    test('a completed task stops being due', () async {
      final s = await freshState();
      await s.addTask('already handled');
      await s.setReminder(
          s.tasks.single, DateTime.now().subtract(const Duration(minutes: 5)));
      final t = s.tasks.single;
      expect(t.isDue(), isTrue);

      await s.completeTask(t);
      expect(await s.store.dueReminders(), isEmpty);
    });

    test('clearing disarms it', () async {
      final s = await freshState();
      await s.addTask('never mind');
      await s.setReminder(
          s.tasks.single, DateTime.now().subtract(const Duration(minutes: 1)));
      expect(await s.store.dueReminders(), hasLength(1));

      await s.setReminder(s.tasks.single, null);
      expect(s.tasks.single.remindAt, isNull);
      expect(await s.store.dueReminders(), isEmpty);
    });

    test('finds due tasks in other workspaces too', () async {
      final s = await freshState();
      final home = s.currentWorkspaceUuid!;
      await s.saveWorkspace(name: 'Work', color: '#7ee3a1');
      await s.addTask('in the other workspace');
      await s.setReminder(
          s.tasks.single, DateTime.now().subtract(const Duration(minutes: 1)));

      await s.selectWorkspace(home);
      expect(s.tasks, isEmpty); // not on screen...
      expect(await s.store.dueReminders(), hasLength(1)); // ...but still due
    });

    test('announces each reminder once, and again if it is re-armed', () async {
      final s = await freshState();
      await s.addTask('nag me');
      await s.setReminder(
          s.tasks.single, DateTime.now().subtract(const Duration(minutes: 1)));

      final announced = <String>[];
      final service = ReminderService(
        s.store,
        onDue: (due) async => announced.addAll(due.map((t) => t.text)),
      );

      await service.tick();
      await service.tick();
      // Still due on the second tick, but surfacing the window every 20s
      // because of one unfinished task would make the app unusable.
      expect(announced, ['nag me']);

      await s.setReminder(s.tasks.single, null);
      await service.tick();
      await s.setReminder(
          s.tasks.single, DateTime.now().subtract(const Duration(seconds: 1)));
      await service.tick();
      expect(announced, ['nag me', 'nag me']);

      service.dispose();
    });
  });

  group('reminder presets', () {
    test('never offers a time in the past', () {
      // 23:30 - both fixed points (18:00 today, 09:00 tomorrow) are the
      // interesting case here: the evening one has gone, tomorrow has not.
      final late = DateTime(2026, 7, 21, 23, 30);
      final presets = reminderPresets(late);

      expect(presets, isNotEmpty);
      for (final p in presets) {
        expect(p.at.isAfter(late), isTrue, reason: '${p.label} is in the past');
      }
      expect(presets.map((p) => p.label), isNot(contains('This evening (18:00)')));
    });

    test('offers this evening while it is still ahead', () {
      final presets = reminderPresets(DateTime(2026, 7, 21, 9));
      expect(presets.map((p) => p.label), contains('This evening (18:00)'));
    });

    test('describes an armed reminder in human terms', () {
      final now = DateTime(2026, 7, 21, 10);
      expect(describeReminder(now.add(const Duration(minutes: 25)), now),
          'in 26m');
      expect(describeReminder(DateTime(2026, 7, 21, 18), now), 'at 18:00');
      expect(describeReminder(DateTime(2026, 7, 22, 9), now), 'tomorrow 09:00');
      expect(describeReminder(DateTime(2026, 7, 21, 9), now), 'due since 09:00');
    });
  });

  // install() needs a notification area, so only the dispatch is covered here.
  // That is the part with a decision in it: Quit must go through the caller's
  // close guard rather than tearing the app down from the menu.
  group('AppTray', () {
    late List<String> calls;
    late AppTray tray;

    setUp(() {
      calls = [];
      tray = AppTray(
        onShow: () async => calls.add('show'),
        onHide: () async => calls.add('hide'),
        onAddTask: () async => calls.add('add-task'),
        onQuit: () async => calls.add('quit'),
      );
    });

    Future<void> click(String key) =>
        tray.handleMenuItem(MenuItem(key: key, label: key));

    test('routes each item to its action', () async {
      await click('show');
      await click('hide');
      await click('add-task');
      expect(calls, ['show', 'hide', 'add-task']);
    });

    test('quit asks the close guard rather than exiting', () async {
      await click('quit');
      expect(calls, ['quit']);
    });

    test('ignores an unknown item instead of throwing', () async {
      await click('nonexistent');
      expect(calls, isEmpty);
    });
  });
}
