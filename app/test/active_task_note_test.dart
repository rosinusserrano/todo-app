// Adding a line to the task you are on, from the home-screen quick action.
//
// The menu entry names whichever task is in focus - `in_progress` is already
// exclusive and global, so "the active task" is a thing the database can
// answer without a new column. What makes this worth its own test is *where*
// the write comes from: the OS keeps the menu across launches, so the press
// arrives with a task the app has not looked at in hours, from a copy of the
// row the shell may have been holding since before the last sync.
//
// Hence an append that re-reads. Saving the notes field the caller was holding
// would silently drop everything that had arrived in it since.

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

  Future<Task> addTask(AppState s, String text) async {
    await s.addTask(text);
    return s.tasks.firstWhere((t) => t.text == text);
  }

  test('the first line is the whole of the notes', () async {
    final s = await freshState();
    final t = await addTask(s, 'rewrite the importer');

    final row = await s.appendToNotes(t, '  check the v9 fixture  ');

    expect(row!.notes, 'check the v9 fixture');
    await s.store.close();
  });

  test('the next one goes on a line of its own', () async {
    final s = await freshState();
    final t = await addTask(s, 'rewrite the importer');

    await s.appendToNotes(t, 'check the v9 fixture');
    final row = await s.appendToNotes(t, 'and the v4 attachments one');

    expect(row!.notes, 'check the v9 fixture\nand the v4 attachments one');
    await s.store.close();
  });

  test('it appends to what is in the database, not to the copy it was handed',
      () async {
    final s = await freshState();
    final t = await addTask(s, 'rewrite the importer');

    // The row moves on underneath - an edit here, a merge from another device
    // in the real case - while `t` still remembers what it said before.
    await s.saveTaskDetails(t, text: t.text, notes: 'from the phone',
        priority: 0);

    final row = await s.appendToNotes(t, 'from the quick action');

    expect(row!.notes, 'from the phone\nfrom the quick action');
    await s.store.close();
  });

  test('a task that has gone takes nothing with it', () async {
    final s = await freshState();
    final t = await addTask(s, 'rewrite the importer');
    await s.deleteTask(t);

    // The menu outlives the app, so it can name a task that was finished on
    // another device an hour ago. Nothing to write to is not an error.
    expect(await s.appendToNotes(t, 'too late'), isNull);
    await s.store.close();
  });

  test('an empty line writes nothing at all', () async {
    final s = await freshState();
    final t = await addTask(s, 'rewrite the importer');

    expect(await s.appendToNotes(t, '   '), isNull);
    expect((await s.store.taskByUuid(t.uuid))!.notes, '');
    await s.store.close();
  });

  test('the shell keeps hold of the row it is focused on', () async {
    final s = await freshState();
    final t = await addTask(s, 'rewrite the importer');
    await s.enterFocus(t);

    await s.appendToNotes(t, 'the tile prints this under the title');

    // The focus tile renders from AppState.focusTask, so a line written into
    // the row while it is on screen has to be on the copy the tile reads or it
    // lands invisibly.
    expect(s.focusTask!.notes, 'the tile prints this under the title');
    await s.store.close();
  });
}
