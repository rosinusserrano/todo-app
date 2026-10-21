// A parked shelf's review, reminded: the morning it falls due, only while
// something is on the shelf, and announced once per review on a device - a
// restart does not announce it again, reviewing it starts the next one.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/reminders.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  ParkedGroup shelf(String lastReviewed) => ParkedGroup(
    uuid: 'g',
    workspaceUuid: 'ws',
    title: 'Backlog',
    reviewEveryDays: 30,
    lastReviewedAt: lastReviewed,
    createdAt: lastReviewed,
    updatedAt: lastReviewed,
  );

  test('reminds at nine on the morning it falls due', () {
    final late = shelf(DateTime(2026, 9, 10, 22, 30).toUtc().toIso8601String());
    expect(late.reviewDueAt, DateTime(2026, 10, 10, 22, 30));
    expect(late.reviewRemindAt, DateTime(2026, 10, 11, 9));

    final early = shelf(DateTime(2026, 9, 10, 7).toUtc().toIso8601String());
    expect(early.reviewRemindAt, DateTime(2026, 10, 10, 9));
  });

  Future<(AppState, ParkedGroup)> overdueShelf({bool withTask = true}) async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final s = AppState(store);
    await s.load();
    final g = (await s.saveGroup(title: 'Backlog', reviewEveryDays: 1))!;
    if (withTask) await s.addTask('someday', groupUuid: g.uuid);
    return (s, g);
  }

  final inTwoDays = DateTime.now().add(const Duration(days: 2));

  test('an overdue shelf with something on it is due; an empty one is not',
      () async {
    final (s, _) = await overdueShelf();
    expect((await s.store.dueGroupReviews(inTwoDays)).single.title, 'Backlog');
    expect(await s.store.dueGroupReviews(), isEmpty, reason: 'not yet');
    expect((await s.store.pendingGroupReviews()).length, 1);

    final (empty, _) = await overdueShelf(withTask: false);
    expect(await empty.store.dueGroupReviews(inTwoDays), isEmpty);
    await s.store.close();
    await empty.store.close();
  });

  test('the poll announces it once, restarts included, until reviewed',
      () async {
    final (s, g) = await overdueShelf();
    final fired = <String>[];
    ReminderService poll() => ReminderService(
      s.store,
      onDue: (_) async {},
      onReviewsDue: (due) async => fired.addAll(due.map((g) => g.title)),
    );
    await poll().tick(inTwoDays);
    await poll().tick(inTwoDays); // a restart: a new service, same database
    expect(fired, ['Backlog']);

    await s.markGroupReviewed(s.groups.single);
    final later = DateTime.now().add(const Duration(days: 4));
    await poll().tick(later);
    expect(fired, ['Backlog', 'Backlog'], reason: 'the next review is new');
    expect(g.uuid, s.groups.single.uuid);
    await s.store.close();
  });
}
