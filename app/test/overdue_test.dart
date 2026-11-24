// Overdue tasks said across workspaces (ui/overdue.dart): what counts, where
// it is rolled up, and the dock's blink starting and stopping with it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/dock.dart';
import 'package:todo_widget/ui/overdue.dart';

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

  final past = DateTime.now().subtract(const Duration(hours: 3));
  final future = DateTime.now().add(const Duration(days: 2));

  test('counts open tasks whose reminder went off, in every workspace',
      () async {
    final s = await freshState();
    final home = s.currentWorkspaceUuid!;
    await s.addTask('upload the solutions', remindAt: past);
    await s.addTask('not yet', remindAt: future);
    await s.addTask('no reminder');
    await s.saveWorkspace(name: 'Work', color: '#6c8cff');
    final work = s.currentWorkspaceUuid!;
    await s.addTask('report', remindAt: past);
    final project = await s.addProject('Launch');
    await s.addTask('slides', remindAt: past, workspaceUuid: project!.uuid);

    expect(s.overdueCounts, {home: 1, work: 1, project.uuid: 1});
    expect(s.overdueOf(work), 2, reason: "a workspace includes its projects'");
    expect(s.overdueTotal, 3);
    await s.store.close();
  });

  test('ticking it, clearing the reminder or parking it stops it', () async {
    final s = await freshState();
    await s.addTask('a', remindAt: past);
    await s.addTask('b', remindAt: past);
    await s.addTask('c', remindAt: past);
    expect(s.overdueTotal, 3);

    Future<void> byText(String t, Future<void> Function(dynamic) f) =>
        f(s.tasks.firstWhere((x) => x.text == t));
    await byText('a', (t) => s.completeTask(t));
    await byText('b', (t) => s.setReminder(t, null));
    final shelf = await s.saveGroup(title: 'Later', reviewEveryDays: 30);
    await byText('c', (t) => s.parkTask(t, shelf!.uuid));

    expect(s.overdueTotal, 0);
    await s.store.close();
  });

  test('the clock alone turns a task overdue', () async {
    final s = await freshState();
    final soon = DateTime.now().add(const Duration(minutes: 5));
    await s.addTask('soon', remindAt: soon);
    expect(s.overdueTotal, 0);
    var notified = 0;
    s.addListener(() => notified++);

    await s.refreshOverdue(now: soon.add(const Duration(minutes: 1)));
    expect(s.overdueTotal, 1);
    expect(notified, 1);
    await s.refreshOverdue(now: soon.add(const Duration(minutes: 2)));
    expect(notified, 1, reason: 'a quiet tick rebuilds nothing');
    await s.store.close();
  });

  group('the dock', () {
    Widget dock({required bool alert, int overdue = 0}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Dock(
            segments: [
              DockSegment(
                label: 'Work',
                fill: T.accent,
                ink: T.text,
                alert: alert,
                items: [
                  DockItem(label: 'Home', overdue: overdue, onChoose: () {}),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    Color fill(WidgetTester tester) {
      final box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('Work'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return (box.decoration as BoxDecoration?)?.color ??
          // AnimatedContainer(color:) is stored as a decoration.
          Colors.transparent;
    }

    testWidgets('the workspace segment blinks while something is overdue', (
      tester,
    ) async {
      await tester.pumpWidget(dock(alert: true));
      final a = fill(tester);
      await tester.pump(kOverdueBlink ~/ 2);
      expect(fill(tester), isNot(a));

      await tester.pumpWidget(dock(alert: false));
      await tester.pumpAndSettle();
      expect(fill(tester), T.accent, reason: 'and stops when nothing is');
    });

    testWidgets('a menu row carries the count', (tester) async {
      await tester.pumpWidget(dock(alert: true, overdue: 2));
      await tester.tap(find.text('Work'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(OverdueMark), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(OverdueMark),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}
