// Projects: a workspace inside a workspace.
//
// What is worth protecting is that a project is a *place*, not a kind of
// task: it shares its parent list's order without being one of its tasks, its
// contents are its own and nowhere else, and archiving it puts the whole thing
// away - nothing in it reminds, holds focus or repeats - without writing a
// single one of its rows, so restoring it brings everything back as it was.

import 'package:flutter_test/flutter_test.dart';
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

  List<String> rowNames(AppState s) => [
    for (final r in s.listRows) r is Task ? r.text : (r as Workspace).name,
  ];

  test('a project is a row of its parent list, not a workspace of its own',
      () async {
    final s = await freshState();
    final home = s.currentWorkspaceUuid!;
    await s.addTask('first');
    final p = await s.addProject('Launch');
    await s.addTask('after it');

    expect(rowNames(s), ['first', 'Launch', 'after it']);
    // Not on the dock, the calendar or anything else that lists workspaces.
    expect(s.workspaces.map((w) => w.uuid), isNot(contains(p!.uuid)));
    expect(s.projects.single.parentUuid, home);
    // But somewhere a task can be moved to, right after its workspace.
    final targets = s.moveTargets.map((w) => w.uuid).toList();
    expect(targets.indexOf(p.uuid), targets.indexOf(home) + 1);
    await s.store.close();
  });

  test('reordering moves projects and tasks in one order', () async {
    final s = await freshState();
    await s.addTask('a');
    final p = await s.addProject('P');
    await s.addTask('b');
    final order = [
      for (final r in s.listRows.reversed)
        r is Task ? r.uuid : (r as Workspace).uuid,
    ];
    await s.reorder(order);
    await s.refreshWorkspaces();
    expect(rowNames(s), ['b', 'P', 'a']);
    expect(s.projects.single.uuid, p!.uuid);
    await s.store.close();
  });

  test('opening a project shows its list, and its tasks stay in it', () async {
    final s = await freshState();
    final home = s.currentWorkspaceUuid!;
    await s.addTask('on the workspace');
    final p = await s.addProject('Launch', open: true);

    expect(s.currentProject?.uuid, p!.uuid);
    expect(s.homeWorkspace?.uuid, home);
    expect(s.listRows, isEmpty);
    await s.addTask('write the copy');
    await s.addTask('pick a date');

    await s.selectWorkspace(home);
    expect(rowNames(s), ['on the workspace', 'Launch']);
    expect(s.projectOpenCounts[p.uuid], 2);
    await s.store.close();
  });

  test('one level only: a project added inside a project goes on the parent',
      () async {
    final s = await freshState();
    final home = s.currentWorkspaceUuid!;
    await s.addProject('Outer', open: true);
    final inner = await s.addProject('Inner');
    expect(inner!.parentUuid, home);
    expect(s.currentProjects, isEmpty);
    await s.store.close();
  });

  test('archiving puts the whole project away, and restoring brings it back',
      () async {
    final s = await freshState();
    final home = s.currentWorkspaceUuid!;
    final p = await s.addProject('Launch', open: true);
    final due = DateTime.now().subtract(const Duration(minutes: 5));
    await s.addTask('overdue', remindAt: due);
    await s.addTask(
      'weekly',
      remindAt: due,
      recur: 'weekly',
    );
    final t = s.tasks.firstWhere((t) => t.text == 'overdue');
    await s.enterFocus(t);

    await s.archiveProject(s.currentProject!);

    // Back on the parent, with the project gone from its list.
    expect(s.currentWorkspaceUuid, home);
    expect(rowNames(s), isEmpty);
    expect(s.archivedProjects.single.uuid, p!.uuid);
    // Quiet: no reminder, no focus, no repeat. Focus is dropped rather than
    // kept, or restoring would drop straight back into it.
    expect(s.focusTask, isNull);
    expect(await s.store.dueReminders(), isEmpty);
    expect(await s.store.inProgressTask(), isNull);
    expect(await s.store.recurringSeeds(), isEmpty);
    // Frozen as it was: both tasks still open in it.
    final contents = await s.archivedContents(s.archivedProjects.single);
    expect(contents.open.map((t) => t.text), ['overdue', 'weekly']);

    await s.restoreProject(s.archivedProjects.single);
    expect(rowNames(s), ['Launch']);
    expect(s.archivedProjects, isEmpty);
    expect((await s.store.dueReminders()).length, 2);
    await s.store.close();
  });

  test('a task becomes a project in its place, its notes the first note',
      () async {
    final s = await freshState();
    await s.addTask('before');
    await s.addTask('Move flat', notes: 'boxes from the shop');
    await s.addTask('after');
    final t = s.tasks.firstWhere((t) => t.text == 'Move flat');

    final p = await s.taskToProject(t);

    expect(rowNames(s), ['before', 'Move flat', 'after']);
    expect(s.listRows[1], isA<Workspace>());
    final notes = await s.store.journalEntries(p!.uuid);
    expect(notes.single.text, 'boxes from the shop');
    await s.store.close();
  });

  test('deleting a workspace deletes its projects and what is in them',
      () async {
    final s = await freshState();
    await s.saveWorkspace(name: 'Side', color: '#7c9cff');
    final side = s.currentWorkspaceUuid!;
    final p = await s.addProject('Shop', open: true);
    await s.addTask('stock list');

    await s.deleteWorkspace(side);

    expect(s.projects, isEmpty);
    expect(s.archivedProjects, isEmpty);
    expect(await s.store.allTasksInWorkspace(p!.uuid), isEmpty);
    await s.store.close();
  });

  test('a project takes its workspace colour, and follows a recolour',
      () async {
    final s = await freshState();
    final home = s.currentWorkspace!;
    final p = await s.addProject('Launch');
    expect(p!.color, home.color);

    await s.saveWorkspace(uuid: home.uuid, name: home.name, color: '#ff8800');
    expect(s.projects.single.color, '#ff8800');
    await s.store.close();
  });

  test('a project whose workspace has gone is a workspace, not lost',
      () async {
    final s = await freshState();
    final stamp = nowStamp();
    await s.store.putWorkspace(
      Workspace(
        uuid: 'orphan',
        name: 'Orphan',
        color: '#888888',
        sortOrder: 9,
        parentUuid: 'deleted-elsewhere',
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
    await s.refreshWorkspaces();
    expect(s.workspaces.map((w) => w.uuid), contains('orphan'));
    expect(s.projects, isEmpty);
    await s.store.close();
  });
}
