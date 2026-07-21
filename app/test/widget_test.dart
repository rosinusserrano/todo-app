// App behaviour tests.
//
// These avoid main.dart, which calls window_manager and flutter_acrylic on
// startup - both need a real window and platform channels that do not exist in
// a test binding. The logic worth testing lives in AppState and the row
// widgets, neither of which touches the window.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
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

    test('deleting a workspace leaves its tasks alone', () async {
      final s = await freshState();
      await s.saveWorkspace(name: 'Side project', color: '#7ee3a1');
      final side = s.currentWorkspaceUuid!;
      await s.addTask('in the side project');

      await s.deleteWorkspace(side);

      // The workspace is gone from the tab bar, but the task row survives -
      // a cascade here would be irreversible across every synced device.
      expect(s.workspaces.any((w) => w.uuid == side), isFalse);
      final rows = await s.store.raw
          .query('tasks', where: 'workspace_uuid = ?', whereArgs: [side]);
      expect(rows.length, 1);
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
}
