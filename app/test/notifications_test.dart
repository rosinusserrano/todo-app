// Mobile reminder notifications.
//
// The plugin itself only exists on iOS and Android, so what is testable here is
// the part that decides *what* gets scheduled: the split between reminders the
// OS should hold and reminders the in-app poll owns, and the uuid to
// notification-id mapping that keeps rescheduling from stacking duplicates.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/notifications.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<LocalStore> freshStore() => LocalStore.open(
        path: inMemoryDatabasePath,
        singleInstance: false,
      );

  Future<void> arm(LocalStore store, String uuid, DateTime at) => store.putTask(
        Task(
          uuid: uuid,
          workspaceUuid: 'ws-1',
          text: uuid,
          createdAt: nowStamp(),
          remindAt: reminderStamp(at),
          updatedAt: nowStamp(),
        ),
      );

  test('only reminders still ahead are handed to the OS', () async {
    final store = await freshStore();
    await arm(store, 'past', DateTime.now().subtract(const Duration(hours: 2)));
    await arm(store, 'future', DateTime.now().add(const Duration(hours: 2)));

    // Anything already past belongs to ReminderService, which surfaces the
    // window. Scheduling it with the OS would either fire on every launch or
    // be dropped outright.
    expect((await store.pendingReminders()).map((t) => t.uuid), ['future']);
    expect((await store.dueReminders()).map((t) => t.uuid), ['past']);
    await store.close();
  });

  test('a completed task stops being scheduled', () async {
    final store = await freshStore();
    final at = DateTime.now().add(const Duration(hours: 2));
    await arm(store, 't1', at);
    expect(await store.pendingReminders(), hasLength(1));

    final t = (await store.pendingReminders()).single;
    await store.putTask(t.copyWith(completedAt: nowStamp()));
    expect(await store.pendingReminders(), isEmpty);
    await store.close();
  });

  test('notification ids are stable and derived only from the uuid', () {
    const uuid = 'e6f1c2a0-1111-4222-8333-444455556666';
    expect(NotificationService.idFor(uuid), NotificationService.idFor(uuid));
    expect(
      NotificationService.idFor(uuid),
      isNot(NotificationService.idFor('$uuid-other')),
    );
  });

  test('notification ids stay inside the 32-bit range the platforms accept',
      () {
    for (var i = 0; i < 500; i++) {
      final id = NotificationService.idFor(newId());
      expect(id, greaterThanOrEqualTo(0));
      expect(id, lessThan(1 << 31));
    }
  });

  test('the service is inert off mobile, so desktop keeps its own alert', () {
    // Desktop surfaces the always-on-top window instead - see reminders.dart.
    expect(NotificationService.supported, isFalse);
  });
}
