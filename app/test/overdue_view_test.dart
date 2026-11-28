// The overdue list (ui/overdue_view.dart): what AppState puts in it and in
// which order, how it is opened and left, and the view's groups and the
// home strip that leads to it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/ui/home_view.dart';
import 'package:todo_widget/ui/overdue_view.dart';

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

  final now = DateTime.now();

  test(
    'every overdue task across workspaces, once, longest overdue first',
    () async {
      final s = await freshState();
      final home = s.currentWorkspace!;
      await s.saveWorkspace(
        uuid: home.uuid,
        name: home.name,
        color: home.color,
        stale: (days: 7),
      );
      final later = now.add(const Duration(days: 8));
      // Stale from now + 7 days; and a reminder that went off before that.
      await s.addTask('lingering');
      await s.addTask('both', remindAt: now.add(const Duration(days: 1)));
      await s.saveWorkspace(name: 'Other', color: '#6c8cff');
      await s.addTask('elsewhere', remindAt: now.add(const Duration(days: 2)));
      await s.addTask('quiet');

      await s.refreshOverdue(now: later);
      expect(
        [for (final t in s.overdueTasks) t.text],
        ['both', 'elsewhere', 'lingering'],
      );
      final both = s.overdueTasks.first;
      expect(
        s.overdueSince(both, later),
        both.remindAtTime,
        reason: 'the reminder came before the automatic overdue',
      );

      // Ticking one takes it off.
      await s.completeTask(both);
      await s.refreshOverdue(now: later);
      expect(
        [for (final t in s.overdueTasks) t.text],
        ['elsewhere', 'lingering'],
      );
      await s.store.close();
    },
  );

  test('opened like home, and left the way home is', () async {
    final s = await freshState();
    await s.openHome();
    await s.openOverdue();
    expect(s.showOverdue, isTrue);
    expect(s.showHome, isFalse);

    s.leaveHome();
    expect(s.showOverdue, isFalse, reason: 'the dock leaving home leaves it');

    await s.openOverdue();
    await s.openTimer();
    expect(s.showOverdue, isFalse, reason: 'any other view closes it');
    await s.store.close();
  });

  group('the view', () {
    Task task(String id, String list, String text) => Task(
      uuid: id,
      workspaceUuid: list,
      text: text,
      createdAt: '2026-11-01T10:00:00.000+01:00',
      updatedAt: '2026-11-01T10:00:00.000+01:00',
    );

    Widget view(List<Task> tasks, List<String> opened) => MaterialApp(
      home: Scaffold(
        body: OverdueView(
          tasks: tasks,
          listOf: (uuid) => switch (uuid) {
            'w' => (name: 'Work', color: Colors.blue),
            'p' => (name: 'Work › Launch', color: Colors.blue),
            _ => null,
          },
          onOpenList: opened.add,
          buildRow: (t, accent, divider) =>
              ListTile(key: ValueKey(t.uuid), title: Text(t.text)),
        ),
      ),
    );

    testWidgets('groups by list, in the order the tasks came', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        view([
          task('1', 'p', 'slides'),
          task('2', 'w', 'report'),
          task('3', 'p', 'venue'),
          task('4', 'gone', 'stray'),
        ], opened),
      );

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('4'), findsOneWidget, reason: 'the count by the title');
      final y = [
        for (final t in [
          'Work › Launch',
          'slides',
          'venue',
          'Work',
          'report',
          'Elsewhere',
          'stray',
        ])
          tester.getTopLeft(find.text(t)).dy,
      ];
      expect(y, [...y]..sort());

      await tester.tap(find.text('Work › Launch'));
      await tester.tap(find.text('Elsewhere'));
      expect(opened, ['p'], reason: 'a list that is gone goes nowhere');
    });

    testWidgets('says what lands here when nothing has', (tester) async {
      await tester.pumpWidget(view(const [], []));
      expect(find.textContaining('Nothing overdue'), findsOneWidget);
    });
  });

  testWidgets('home leads to it', (tester) async {
    final ws = Workspace(
      uuid: 'w',
      name: 'Work',
      color: '#6c8cff',
      sortOrder: 0,
      createdAt: '2026-11-01T10:00:00.000+01:00',
      updatedAt: '2026-11-01T10:00:00.000+01:00',
    );
    var opened = 0;
    Widget home(Map<String, int> counts) => MaterialApp(
      home: Scaffold(
        body: HomeView(
          workspaces: [ws],
          projectsOf: (_) => const [],
          openCounts: const {},
          overdueCounts: counts,
          onOpen: (_) {},
          onOpenProject: (_) {},
          onOpenOverdue: () => opened++,
        ),
      ),
    );

    await tester.pumpWidget(home(const {}));
    expect(find.text('Nothing overdue'), findsOneWidget);

    await tester.pumpWidget(home(const {'w': 2, 'p': 1}));
    expect(find.text('3 overdue tasks'), findsOneWidget);
    await tester.tap(find.text('3 overdue tasks'));
    expect(opened, 1);
    // The squares' marks blink for ever: stop before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
