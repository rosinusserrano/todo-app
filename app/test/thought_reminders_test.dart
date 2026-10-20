// A reminder on a thought: "keys when leaving, in 10 minutes".
//
// What matters: it fires while the thought is in the pile and not after -
// resolving it, or turning it into a task, is dealing with it - the poll says
// so once rather than every tick, and a thought that becomes a task hands
// its reminder to the task.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/reminders.dart';
import 'package:todo_widget/sync/local_store.dart';

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

  final past = DateTime.now().subtract(const Duration(minutes: 1));
  final soon = DateTime.now().add(const Duration(minutes: 10));

  test('due while in the pile, quiet once resolved', () async {
    final s = await freshState();
    await s.addThought('keys', remindAt: past);
    await s.addThought('later', remindAt: soon);

    expect((await s.store.dueThoughtReminders()).map((t) => t.text), ['keys']);
    expect((await s.store.pendingThoughtReminders()).map((t) => t.text), [
      'later',
    ]);

    await s.resolveThought(s.thoughts.firstWhere((t) => t.text == 'keys'));
    expect(await s.store.dueThoughtReminders(), isEmpty);
    await s.store.close();
  });

  test('set, moved and cleared', () async {
    final s = await freshState();
    await s.addThought('call back');
    expect(s.thoughts.single.remindAt, isNull);

    await s.setThoughtReminder(s.thoughts.single, past);
    expect(s.thoughts.single.isDue(), isTrue);

    await s.setThoughtReminder(s.thoughts.single, null);
    expect(s.thoughts.single.remindAt, isNull);
    expect(await s.store.dueThoughtReminders(), isEmpty);
    await s.store.close();
  });

  test('a thought made a task hands the task its reminder', () async {
    final s = await freshState();
    await s.addThought('book the dentist', remindAt: soon);
    await s.promoteThought(s.thoughts.single);

    expect(s.thoughts, isEmpty);
    final task = s.tasks.single;
    expect(task.text, 'book the dentist');
    expect(task.remindAtTime!.difference(soon).inSeconds.abs(), lessThan(1));
    await s.store.close();
  });

  test('the poll announces a due thought once', () async {
    final s = await freshState();
    await s.addThought('keys', remindAt: past);
    final fired = <String>[];
    final reminders = ReminderService(
      s.store,
      onDue: (_) async {},
      onThoughtsDue: (due) async => fired.addAll(due.map((t) => t.text)),
    );
    await reminders.tick();
    await reminders.tick();
    expect(fired, ['keys']);
    await s.store.close();
  });
}
