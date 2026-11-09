// Four rows from the "Todo Widget" shelf, 2026-11-09: a collection moved to
// another workspace or project, tasks copied onto the open checklist, the
// home screen of workspace squares, and the admin's traffic overview.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/admin_client.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/sync_service.dart';
import 'package:todo_widget/ui/home_view.dart';
import 'package:todo_widget/ui/server_traffic_view.dart';
import 'package:todo_widget/ui/task_actions.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> fresh() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final s = AppState(store);
    await s.load();
    return s;
  }

  group('moving a collection', () {
    test('it goes, with its fields and entries, to a project', () async {
      final s = await fresh();
      final home = s.currentWorkspaceUuid!;
      final project = await s.addProject('Launch');
      await s.toggleCollections();
      final c = await s.saveCollection(
        name: 'Movies',
        fields: const [FieldDraft(name: 'Title')],
      );
      final title = s.collectionFields[c!.uuid]!.single;
      await s.saveEntry(c, {title.uuid: 'Heat'});

      await s.moveCollection(c, project!.uuid);
      expect(s.collections, isEmpty, reason: 'it left this workspace');
      expect(await s.store.collections(home), isEmpty);

      final there = await s.store.collections(project.uuid);
      expect(there.single.uuid, c.uuid);
      expect(
        (await s.store.collectionFields(project.uuid)).single.name,
        'Title',
      );
      final entries = await s.store.collectionEntries(project.uuid);
      expect(entries.single.valueOf(title.uuid), 'Heat');
      await s.store.close();
    });

    test('it lands at the end of the collections already there', () async {
      final s = await fresh();
      final home = s.currentWorkspaceUuid!;
      await s.saveWorkspace(name: 'Home', color: '#83c0a0');
      await s.toggleCollections();
      await s.saveCollection(
        name: 'Books',
        fields: const [FieldDraft(name: 'Title')],
      );
      await s.saveCollection(
        name: 'Plants',
        fields: const [FieldDraft(name: 'Name')],
      );
      final other = s.currentWorkspaceUuid!;
      await s.selectWorkspace(home);
      await s.toggleCollections();
      final c = await s.saveCollection(
        name: 'Recipes',
        fields: const [FieldDraft(name: 'Name')],
      );
      await s.moveCollection(c!, other);
      final there = await s.store.collections(other);
      expect(there.map((x) => x.name), ['Books', 'Plants', 'Recipes']);
      await s.store.close();
    });
  });

  group('copying tasks to the checklist', () {
    test('needs an open checklist, and leaves the tasks alone', () async {
      final s = await fresh();
      await s.addTask('milk');
      expect(s.currentList, isNull);
      expect(await s.copyTasksToList(s.tasks), 0);
      expect(s.currentList, isNull, reason: 'it does not start one');

      await s.addListItem('bread');
      expect(await s.copyTasksToList(s.tasks), 1);
      expect(s.listItems.map((i) => i.text), ['bread', 'milk']);
      expect(s.tasks.single.text, 'milk', reason: 'a copy, not a move');
      await s.store.close();
    });

    test('a title already waiting on the list is not added twice', () async {
      final s = await fresh();
      await s.addListItem('Milk');
      await s.addTask('milk');
      await s.addTask('eggs');
      expect(await s.copyTasksToList(s.tasks), 1);
      expect(s.listItems.map((i) => i.text), ['Milk', 'eggs']);

      // Ticked is got: wanting it again is a new item.
      await s.setListItemChecked(s.listItems.first, true);
      expect(await s.copyTasksToList([s.tasks.first]), 1);
      await s.store.close();
    });

    test('the action is drawn only with a callback', () {
      expect(TaskAction.values, contains(TaskAction.copyToList));
    });
  });

  group('home', () {
    test('counts open tasks per workspace and project', () async {
      final s = await fresh();
      final ws = s.currentWorkspaceUuid!;
      final p = await s.addProject('Launch');
      await s.addTask('a');
      await s.addTask('b');
      await s.selectWorkspace(p!.uuid);
      await s.addTask('c');
      await s.completeTask(s.tasks.single);

      await s.openHome();
      expect(s.showHome, isTrue);
      expect(s.openCounts[ws], 2);
      expect(s.openCounts[p.uuid], isNull, reason: 'its only task is done');
      await s.store.close();
    });

    test('anything opened, or a workspace picked, leaves it', () async {
      final s = await fresh();
      await s.openHome();
      await s.toggleCalendar();
      expect(s.showHome, isFalse);

      await s.openHome();
      expect(s.showCalendar, isFalse);
      await s.selectWorkspace(s.currentWorkspaceUuid!);
      expect(s.showHome, isFalse);

      await s.openHome();
      await s.setListOpen(true);
      expect(s.showHome, isFalse);
      await s.store.close();
    });

    testWidgets('a square per workspace, its projects inside', (tester) async {
      tester.view.physicalSize = const Size(340, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final s = await tester.runAsync(fresh);
      final work = s!.workspaces.single;
      final launch = await tester.runAsync(() => s.addProject('Launch'));
      await tester.runAsync(
        () => s.saveWorkspace(name: 'Home', color: '#83c0a0'),
      );

      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeView(
              workspaces: s.workspaces,
              projectsOf: s.projectsOf,
              openCounts: {work.uuid: 4, launch!.uuid: 2},
              onOpen: (w) => opened.add(w.name),
              onOpenProject: (p) => opened.add('project ${p.name}'),
            ),
          ),
        ),
      );

      expect(find.text(work.name), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('4 open'), findsOneWidget);
      expect(find.text('Nothing open'), findsOneWidget);
      expect(find.text('Launch'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Two columns at phone width, and squares.
      final box = tester.getSize(find.byType(HomeView));
      expect(HomeView.columnsFor(box.width), 2);

      await tester.tap(find.text('Launch'));
      await tester.tap(find.text('Home'));
      expect(opened, ['project Launch', 'Home']);
      await tester.runAsync(s.store.close);
    });
  });

  group('server traffic', () {
    TrafficOverview sample(int days) => TrafficOverview.fromJson({
      'daily': [
        for (var i = 0; i < days; i++)
          {
            'day': '2026-11-${(i % 28 + 1).toString().padLeft(2, '0')}',
            'requests': i == days - 1 ? 120 : i,
            'syncs': 3,
            'rows_in': 1,
            'rows_out': 2,
            'bytes_in': 100,
            'bytes_out': 2048,
            'active_users': 1,
          },
      ],
      'users': [
        {
          'id': 'local',
          'label': 'Marco',
          'admin': true,
          'requests': 300,
          'syncs': 90,
          'rows_in': 12,
          'rows_out': 40,
          'bytes_in': 5000,
          'bytes_out': 3 * 1024 * 1024,
          'active_days': 7,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          'devices_online': 2,
          'rows_stored': 1234,
          'blob_bytes': 0,
        },
        {
          'id': 'u2',
          'label': 'Ana',
          'admin': false,
          'active_days': 0,
          'last_seen_at': null,
          'devices_online': 0,
          'rows_stored': 0,
          'blob_bytes': 0,
        },
      ],
      'totals': {'requests': 300, 'syncs': 90, 'bytes_in': 0, 'bytes_out': 0},
      'devices_online': 2,
    });

    test('bytes and days read the way a person says them', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(812), '812 B');
      expect(formatBytes(4300), '4.2 KB');
      expect(formatBytes(31 * 1024 * 1024), '31 MB');
      expect(describeDay('2026-11-09'), 'Mon 9 Nov');
      expect(describeDay('2026-11-09', short: true), '9 Nov');
    });

    testWidgets('the window, a picked day, and every account', (tester) async {
      tester.view.physicalSize = const Size(340, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final asked = <int>[];
      final store = await tester.runAsync(
        () =>
            LocalStore.open(path: inMemoryDatabasePath, singleInstance: false),
      );
      final sync = SyncService(store!);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutScope(
              layout: const Layout(Size(340, 900)),
              child: ServerTrafficView(
                sync: sync,
                onBack: () {},
                load: (days) async {
                  asked.add(days);
                  return sample(days);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(asked, [30]);
      expect(find.text('Last 30 days'), findsOneWidget);
      expect(find.textContaining('Marco', findRichText: true), findsOneWidget);
      expect(find.textContaining('Ana', findRichText: true), findsOneWidget);
      expect(find.textContaining('2 connected now'), findsOneWidget);
      expect(find.textContaining('never seen'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // A day's bar puts that day in the readout; again puts the window back.
      final busiest = find.bySemanticsLabel(RegExp(r': 120 requests$'));
      await tester.tap(busiest);
      await tester.pump();
      expect(find.text('Last 30 days'), findsNothing);
      expect(find.text('120'), findsOneWidget);
      await tester.tap(busiest);
      await tester.pump();
      expect(find.text('Last 30 days'), findsOneWidget);

      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(asked, [30, 7]);
      expect(find.text('Last 7 days'), findsOneWidget);
      await tester.runAsync(store.close);
    });
  });
}
