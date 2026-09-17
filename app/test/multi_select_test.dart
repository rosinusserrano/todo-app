// Selecting several tasks, and sending them somewhere together.
//
// Three layers, pinned separately because each can break alone: the row's
// gestures (Ctrl+click selects, and once something is selected a plain click
// extends the selection instead of expanding), the picker (every workspace's
// list and shelves are destinations), and the batch writes in AppState (a
// move is still a move - the same rows, keeping their uuids).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/move_picker.dart';
import 'package:todo_widget/ui/task_actions.dart';
import 'package:todo_widget/ui/task_row.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AppState', () {
    Future<AppState> freshState() async {
      final store = await LocalStore.open(
        path: inMemoryDatabasePath,
        singleInstance: false,
      );
      final state = AppState(store);
      await state.load();
      return state;
    }

    Future<List<Task>> addAll(AppState s, List<String> texts) async {
      for (final t in texts) {
        await s.addTask(t);
      }
      return [for (final t in texts) s.tasks.firstWhere((x) => x.text == t)];
    }

    test('moves a batch onto another workspace list, same rows, in order',
        () async {
      final s = await freshState();
      final home = s.currentWorkspaceUuid!;
      await s.saveWorkspace(name: 'Work', color: '#6c8cff');
      final work = s.currentWorkspaceUuid!;
      await s.addTask('already on Work');
      await s.selectWorkspace(home);
      final picked = await addAll(s, ['one', 'two', 'stays']);

      await s.moveTasks(picked.take(2).toList(), workspaceUuid: work);

      expect(s.tasks.map((t) => t.text), ['stays']);
      final there = await s.store.activeTasks(work);
      expect(there.map((t) => t.text), ['already on Work', 'one', 'two']);
      expect(there[1].uuid, picked[0].uuid, reason: 'a move, not a copy');
      await s.store.close();
    });

    test('parks a batch on a shelf in another workspace', () async {
      final s = await freshState();
      final home = s.currentWorkspaceUuid!;
      await s.saveWorkspace(name: 'Work', color: '#6c8cff');
      final work = s.currentWorkspaceUuid!;
      final shelf = await s.saveGroup(title: 'Later', reviewEveryDays: 30);
      await s.selectWorkspace(home);
      final picked = await addAll(s, ['a', 'b']);

      await s.moveTasks(picked, workspaceUuid: work, groupUuid: shelf!.uuid);

      expect(s.tasks, isEmpty);
      expect(await s.store.activeTasks(work), isEmpty,
          reason: 'shelved rows are not on the list');
      final grouped = await s.store.parkedTasks(work);
      expect(grouped[shelf.uuid]!.map((t) => t.text), ['a', 'b']);
      await s.store.close();
    });

    test('groupsByWorkspace lists every workspace, empty ones included',
        () async {
      final s = await freshState();
      final home = s.currentWorkspaceUuid!;
      await s.saveGroup(title: 'Backlog', reviewEveryDays: 30);
      await s.saveWorkspace(name: 'Work', color: '#6c8cff');

      final all = await s.groupsByWorkspace();
      expect(all[home]!.single.title, 'Backlog');
      expect(all[s.currentWorkspaceUuid!], isEmpty);
      await s.store.close();
    });

    test('completes and deletes a batch with one refresh', () async {
      final s = await freshState();
      final picked = await addAll(s, ['done 1', 'done 2', 'gone', 'kept']);

      await s.finishTasks(picked.take(2).toList(), complete: true);
      await s.finishTasks([picked[2]], complete: false);

      expect(s.tasks.map((t) => t.text), ['kept']);
      final history =
          await s.store.history(s.currentWorkspaceUuid!);
      expect(history.map((t) => t.text).toSet(), {'done 1', 'done 2'});
      await s.store.close();
    });
  });

  group('TaskRow', () {
    Task task(String uuid, String text) => Task(
          uuid: uuid,
          workspaceUuid: 'ws',
          text: text,
          createdAt: nowStamp(),
          updatedAt: nowStamp(),
        );

    Widget row({
      required bool touch,
      bool selected = false,
      bool selecting = false,
      VoidCallback? onToggleSelect,
      VoidCallback? onExpand,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: LayoutScope(
              layout: Layout(const Size(T.designWidth, 600), touch: touch),
              child: TaskRow(
                task: task('t1', 'inspect the layers'),
                accent: T.accent,
                onComplete: () async {},
                onDelete: () async {},
                onFocus: () {},
                onOpen: () {},
                onExpand: onExpand,
                selected: selected,
                selecting: selecting,
                onToggleSelect: onToggleSelect,
              ),
            ),
          ),
        );

    testWidgets('Ctrl+click selects rather than expanding', (tester) async {
      var toggled = 0;
      var expanded = 0;
      await tester.pumpWidget(row(
        touch: false,
        onToggleSelect: () => toggled++,
        onExpand: () => expanded++,
      ));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('inspect the layers'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(toggled, 1);
      expect(expanded, 0);
    });

    testWidgets('a plain click still expands when nothing is selected',
        (tester) async {
      var toggled = 0;
      var expanded = 0;
      await tester.pumpWidget(row(
        touch: false,
        onToggleSelect: () => toggled++,
        onExpand: () => expanded++,
      ));

      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();

      expect(toggled, 0);
      expect(expanded, 1);
    });

    testWidgets('once something is selected a plain click extends it',
        (tester) async {
      var toggled = 0;
      await tester.pumpWidget(
          row(touch: false, selecting: true, onToggleSelect: () => toggled++));
      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();
      expect(toggled, 1);
    });

    testWidgets('on touch, Select is in the action bar', (tester) async {
      var toggled = 0;
      await tester.pumpWidget(
          row(touch: true, onToggleSelect: () => toggled++));
      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check_box_outline_blank_rounded));
      await tester.pumpAndSettle();
      expect(toggled, 1);
      expect(TaskAction.values, contains(TaskAction.select));
    });
  });

  group('the move picker', () {
    Workspace ws(String uuid, String name) => Workspace(
          uuid: uuid,
          name: name,
          color: '#6c8cff',
          sortOrder: 0,
          createdAt: nowStamp(),
          updatedAt: nowStamp(),
        );

    ParkedGroup shelf(String uuid, String ws, String title) => ParkedGroup(
          uuid: uuid,
          workspaceUuid: ws,
          title: title,
          sortOrder: 0,
          reviewEveryDays: 30,
          createdAt: nowStamp(),
          updatedAt: nowStamp(),
        );

    Future<MoveTarget?> pick(WidgetTester tester, String label) async {
      MoveTarget? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await showMovePicker(
                context,
                position: RelativeRect.fill,
                currentWorkspaceUuid: 'home',
                workspaces: [ws('home', 'Home'), ws('work', 'Work')],
                groups: {
                  'home': [shelf('g-home', 'home', 'Backlog')],
                  'work': [shelf('g-work', 'work', 'Someday')],
                },
                onCreateGroup: () async => null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      return picked;
    }

    testWidgets('a shelf here', (tester) async {
      expect(await pick(tester, 'Backlog'), const MoveTarget('home', 'g-home'));
    });

    testWidgets("another workspace's list", (tester) async {
      expect(await pick(tester, 'Its list'), const MoveTarget('work'));
    });

    testWidgets("another workspace's shelf", (tester) async {
      expect(await pick(tester, 'Someday'), const MoveTarget('work', 'g-work'));
    });
  });
}
