// Attachments.
//
// Two things here are easy to get wrong and invisible when you do. Blobs are
// content-addressed, so removing one attachment must not delete a file another
// task is still using; and rows sync while bytes do not, so "the row is here but
// the file is not" has to be a supported state rather than a crash.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/attachment_store.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('todo_attach');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<AppState> freshState() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final state = AppState(
      store,
      blobs: await AttachmentStore.open(root: root.path),
    );
    await state.load();
    return state;
  }

  /// A source document sitting somewhere outside the app's storage.
  Future<File> sourceFile(String name, String contents) async {
    final f = File(p.join(root.path, 'src_$name'));
    await f.writeAsString(contents);
    return f;
  }

  Future<Task> addTask(AppState s, String text) async {
    await s.addTask(text);
    return s.tasks.firstWhere((t) => t.text == text);
  }

  test('attaching copies the file in and records it against the task',
      () async {
    final s = await freshState();
    final t = await addTask(s, 'file the tax return');
    final src = await sourceFile('return.pdf', 'pretend this is a pdf');

    final a = await s.attachFile(t, src);

    expect(a, isNotNull);
    expect(a!.filename, 'src_return.pdf');
    expect(a.size, 21);
    expect(await s.blobs!.hasLocal(a), isTrue);
    expect((await s.attachmentsFor(t)).single.uuid, a.uuid);
    // The original is untouched where it was.
    expect(await src.exists(), isTrue);
    await s.store.close();
  });

  test('the same document attached twice is stored once', () async {
    final s = await freshState();
    final one = await addTask(s, 'first task');
    final two = await addTask(s, 'second task');
    final src = await sourceFile('spec.txt', 'identical bytes');

    final a = await s.attachFile(one, src);
    final b = await s.attachFile(two, src);

    // Two rows, one blob - content addressing is what makes that work.
    expect(a!.sha256, b!.sha256);
    expect(a.uuid, isNot(b.uuid));
    final blobs = s.blobs!.directory.listSync().whereType<File>();
    expect(blobs, hasLength(1));
    await s.store.close();
  });

  test('removing one attachment keeps bytes another row still points at',
      () async {
    final s = await freshState();
    final one = await addTask(s, 'first task');
    final two = await addTask(s, 'second task');
    final src = await sourceFile('shared.txt', 'shared bytes');

    final a = await s.attachFile(one, src);
    final b = await s.attachFile(two, src);

    await s.removeAttachment(a!);

    expect(await s.attachmentsFor(one), isEmpty);
    // The other task can still open it.
    expect(await s.blobs!.hasLocal(b!), isTrue);

    // Once the last reference goes, so do the bytes.
    await s.removeAttachment(b);
    expect(await s.blobs!.hasLocal(b), isFalse);
    await s.store.close();
  });

  test('removing an attachment tombstones it rather than dropping the row',
      () async {
    final s = await freshState();
    final t = await addTask(s, 'a task');
    final a = await s.attachFile(t, await sourceFile('x.txt', 'x'));

    await s.removeAttachment(a!);

    // A dropped row would look to a peer like one it had never seen, and the
    // attachment would come straight back on the next merge.
    final dirty = await s.store.dirtyRows();
    final row = dirty['attachments']!
        .firstWhere((r) => r['uuid'] == a.uuid);
    expect(row['deleted_at'], isNotNull);
    await s.store.close();
  });

  test('a row whose bytes never arrived is a normal, readable state', () async {
    final s = await freshState();
    final t = await addTask(s, 'a task');

    // Exactly what sync produces on a second device: the row, no file.
    final a = Attachment(
      uuid: newId(),
      taskUuid: t.uuid,
      filename: 'from-the-desktop.pdf',
      size: 4096,
      sha256: 'a' * 64,
      createdAt: nowStamp(),
      updatedAt: nowStamp(),
    );
    await s.store.putAttachment(a);
    await s.refreshTasks();

    expect((await s.attachmentsFor(t)).single.filename,
        'from-the-desktop.pdf');
    expect(await s.blobs!.hasLocal(a), isFalse);
    // It still counts towards the paperclip - the task does have a document,
    // this device just cannot open it yet.
    expect(s.attachmentCounts[t.uuid], 1);
    await s.store.close();
  });

  test('counts cover the workspace in one query, and skip removed rows',
      () async {
    final s = await freshState();
    final one = await addTask(s, 'with two');
    final two = await addTask(s, 'with none');

    await s.attachFile(one, await sourceFile('a.txt', 'a'));
    final second = await s.attachFile(one, await sourceFile('b.txt', 'b'));

    expect(s.attachmentCounts[one.uuid], 2);
    expect(s.attachmentCounts[two.uuid], isNull);

    await s.removeAttachment(second!);
    expect(s.attachmentCounts[one.uuid], 1);
    await s.store.close();
  });

  test('the sweep collects blobs no live row references any more', () async {
    final s = await freshState();
    final t = await addTask(s, 'a task');
    final kept = await s.attachFile(t, await sourceFile('keep.txt', 'keep'));
    final orphan = await s.attachFile(t, await sourceFile('drop.txt', 'drop'));

    // A tombstone arriving from another device: the row is updated by the
    // merge, so removeAttachment never runs and the bytes are left behind.
    await s.store.putAttachment(
      orphan!.copyWith(deletedAt: nowStamp(), updatedAt: nowStamp()),
    );

    expect(await s.sweepAttachments(), 1);
    expect(await s.blobs!.hasLocal(orphan), isFalse);
    expect(await s.blobs!.hasLocal(kept!), isTrue);
    await s.store.close();
  });

  test('an interrupted copy cannot be mistaken for the real file', () async {
    final s = await freshState();
    final blobs = s.blobs!;

    // A .part left behind by a copy that died halfway. The sweep must not
    // collect it - it may belong to an add still running - and it must never
    // be served as the blob itself, which is why the name differs.
    final partial = File(p.join(blobs.directory.path, '${'b' * 64}.part'));
    await partial.writeAsString('half a file');

    expect(await s.sweepAttachments(), 0);
    expect(await partial.exists(), isTrue);
    expect(await blobs.fileFor('b' * 64).exists(), isFalse);
    await s.store.close();
  });

  group('size formatting', () {
    test('bytes below a kilobyte are shown as bytes', () {
      expect(AttachmentStore.formatSize(0), '0 B');
      expect(AttachmentStore.formatSize(1023), '1023 B');
    });

    test('larger sizes get one decimal until they get wide', () {
      expect(AttachmentStore.formatSize(1024), '1.0 KB');
      expect(AttachmentStore.formatSize(1024 * 512), '512 KB');
      expect(AttachmentStore.formatSize(1024 * 1024 * 3), '3.0 MB');
    });
  });

  test('a database from before attachments migrates without losing tasks',
      () async {
    final dir = await Directory.systemTemp.createTemp('todo_attach_migrate');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'todo.db');

    // v3: parked groups exist, attachments do not.
    final store = await LocalStore.open(path: path, singleInstance: false);
    final ws = (await store.workspaces()).single;
    await store.putTask(Task(
      uuid: 't1',
      workspaceUuid: ws.uuid,
      text: 'survives again',
      createdAt: nowStamp(),
      updatedAt: nowStamp(),
    ));
    // Roll the freshly-created schema back to what v3 actually had: no
    // attachments table, no journal_entries (which arrived in v5) and no
    // calendars (v8). Dropping them is what makes the reopen exercise the real
    // upgrade path rather than colliding on a table _create already made.
    await store.raw.execute('DROP TABLE attachments');
    await store.raw.execute('DROP TABLE journal_entries');
    await store.raw.execute('DROP TABLE calendars');
    await store.raw.execute('DROP TABLE calendar_events');
    // ...and no event_uuid on tasks (v10). Its index has to go first: SQLite
    // refuses to drop a column an index is built on.
    await store.raw.execute('DROP INDEX idx_tasks_event');
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN event_uuid');
    // ...and no notes or priority (v11), or the migration that adds them
    // collides with the columns _create already made.
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN notes');
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN priority');
    await store.raw.execute('ALTER TABLE tasks DROP COLUMN recur');
    await store.raw.setVersion(3);
    await store.close();

    final upgraded = await LocalStore.open(path: path, singleInstance: false);
    expect((await upgraded.activeTasks(ws.uuid)).single.text, 'survives again');
    expect(await upgraded.attachmentsFor('t1'), isEmpty);
    await upgraded.close();
  });
}
