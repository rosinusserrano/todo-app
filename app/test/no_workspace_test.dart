// A new account starts with no workspace (Marco, 2026-10-20): nothing is
// seeded, nothing breaks for want of one, and making the first one lands on
// it. The screen that stands in for the list until then fits a phone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/ui/no_workspace.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> emptyState() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
      seedWorkspace: false,
    );
    final state = AppState(store);
    await state.load();
    return state;
  }

  test(
    'nothing is seeded, and a task with nowhere to go is not written',
    () async {
      final s = await emptyState();
      expect(s.workspaces, isEmpty);
      expect(s.currentWorkspaceUuid, isNull);

      await s.addTask('lost');
      expect(await s.store.hasAnyTask(), isFalse);

      // Thoughts are global and do not need one.
      await s.addThought('remember the milk');
      expect(s.thoughts.single.text, 'remember the milk');
      await s.store.close();
    },
  );

  test('the first workspace made is the one you are in', () async {
    final s = await emptyState();
    await s.saveWorkspace(name: 'Work', color: '#7c9cff');
    expect(s.currentWorkspace?.name, 'Work');
    await s.addTask('first');
    expect(s.tasks.single.text, 'first');
    await s.store.close();
  });

  testWidgets('the instruction fits the design width and makes a workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(340, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NoWorkspace(onCreate: () => asked++)),
      ),
    );
    final button = find.text('Create a workspace');
    // On screen without scrolling.
    expect(tester.getRect(button).bottom, lessThan(560));
    await tester.tap(button);
    expect(asked, 1);
  });
}
