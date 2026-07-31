// The per-workspace journal: titled, timestamped, and *optionally* encrypted.
//
// By default it is plaintext and needs no password. Setting a password turns on
// encryption and re-encrypts what is already there; removing it decrypts
// everything back. The things worth pinning down: plaintext works with no
// password, setting one makes the stored words ciphertext (and removing it
// undoes that), the lock gates reading, editing keeps an entry's timestamp,
// removal tombstones, and the whole thing is scoped to one workspace.

import 'dart:io' show Directory;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/journal_crypto.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';

const _pw = 'correct horse battery staple';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // No password set: the journal is plaintext.
  Future<AppState> plainState() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final crypto = JournalCrypto(store);
    await crypto.load();
    final state = AppState(store, journalCrypto: crypto);
    await state.load();
    return state;
  }

  // Password set and unlocked: the journal is encrypted.
  Future<AppState> unlockedState() async {
    final s = await plainState();
    await s.setupJournalPassword(_pw);
    return s;
  }

  Future<JournalItem> addEntry(AppState s, String title, String body) async {
    await s.addJournalEntry(title, body);
    return s.journal.firstWhere((i) => i.title == title);
  }

  Future<Map<String, Object?>> onlyRow(AppState s) async =>
      (await s.store.raw.query('journal_entries', where: 'deleted_at IS NULL'))
          .single;

  group('plaintext (no password)', () {
    test('a fresh journal takes entries with no password, stored as typed',
        () async {
      final s = await plainState();
      expect(s.journalConfigured, isFalse);
      expect(s.journalLocked, isFalse);

      await s.refreshJournal();
      await addEntry(s, 'a plain title', 'a plain body');

      final row = await onlyRow(s);
      expect(row['encrypted'], 0);
      expect(row['title'], 'a plain title');
      expect(row['text'], 'a plain body');
      await s.store.close();
    });

    test('setting a password encrypts what is already there', () async {
      final s = await plainState();
      await s.refreshJournal();
      await addEntry(s, 'Rough day', 'I felt terrible.');

      await s.setupJournalPassword(_pw);
      expect(s.journalConfigured, isTrue);
      expect(s.journalUnlocked, isTrue);

      final row = await onlyRow(s);
      expect(row['encrypted'], 1);
      expect(row['title'], isNot(contains('Rough')));
      expect(row['text'], isNot(contains('terrible')));
      // Still readable in the UI, decrypted.
      expect(s.journal.single.title, 'Rough day');
      expect(s.journal.single.body, 'I felt terrible.');
      await s.store.close();
    });

    test('removing the password decrypts entries back to plaintext', () async {
      final s = await unlockedState();
      await addEntry(s, 'secret', 'was encrypted');

      await s.removeJournalPassword();
      expect(s.journalConfigured, isFalse);
      expect(s.journalLocked, isFalse);

      final row = await onlyRow(s);
      expect(row['encrypted'], 0);
      expect(row['title'], 'secret');
      expect(row['text'], 'was encrypted');
      // And it still reads normally.
      expect(s.journal.single.body, 'was encrypted');
      await s.store.close();
    });
  });

  group('vault', () {
    test('setup leaves it configured and unlocked', () async {
      final s = await plainState();
      await s.setupJournalPassword(_pw);
      expect(s.journalConfigured, isTrue);
      expect(s.journalUnlocked, isTrue);
      expect(s.journalLocked, isFalse);
      await s.store.close();
    });

    test('locking hides entries; the wrong password stays out, the right one in',
        () async {
      final s = await unlockedState();
      await addEntry(s, 'a title', 'a body');
      s.lockJournal();
      expect(s.journalLocked, isTrue);
      expect(s.journal, isEmpty);

      expect(await s.unlockJournal('not it'), isFalse);
      expect(s.journalLocked, isTrue);

      expect(await s.unlockJournal(_pw), isTrue);
      expect(s.journalLocked, isFalse);
      expect(s.journal.single.body, 'a body');
      await s.store.close();
    });

    test('a wrong password is rejected rather than throwing', () async {
      final s = await unlockedState();
      s.lockJournal();
      for (final guess in ['', 'x', _pw.toUpperCase(), '$_pw ']) {
        expect(await s.unlockJournal(guess), isFalse, reason: guess);
      }
      expect(await s.unlockJournal(_pw), isTrue);
      await s.store.close();
    });
  });

  group('at rest', () {
    test('with a password, the typed words are not in the row', () async {
      final s = await unlockedState();
      await addEntry(s, 'Rough day', 'I felt terrible about the meeting.');

      final row = await onlyRow(s);
      expect(row['encrypted'], 1);
      expect(row['title'] as String, isNot(contains('Rough')));
      expect(row['text'] as String, isNot(contains('terrible')));
      expect(row['text'] as String, isNot(contains('meeting')));
      expect(row['title'] as String, isNotEmpty);
      await s.store.close();
    });

    test('re-encrypting the same text yields a different blob (fresh nonce)',
        () async {
      final s = await unlockedState();
      final c = s.journalCrypto!;
      final a = await c.encrypt('same words');
      final b = await c.encrypt('same words');
      expect(a, isNot(equals(b)));
      expect(await c.decrypt(a), 'same words');
      expect(await c.decrypt(b), 'same words');
      await s.store.close();
    });
  });

  group('entries', () {
    test('an entry round-trips its title and body, scoped to the workspace',
        () async {
      final s = await unlockedState();
      final ws = s.currentWorkspaceUuid!;
      await s.addJournalEntry('  Title  ', '  the body  ');
      final item = s.journal.single;

      expect(item.title, 'Title'); // trimmed
      expect(item.body, 'the body');
      expect(item.entry.workspaceUuid, ws);
      expect(item.createdAtTime, isNotNull);
      await s.store.close();
    });

    test('an entry with neither title nor body is dropped', () async {
      final s = await unlockedState();
      await s.addJournalEntry('   ', '   ');
      expect(s.journal, isEmpty);
      await s.store.close();
    });

    test('a title alone, or a body alone, is enough to keep it', () async {
      final s = await unlockedState();
      await s.addJournalEntry('just a title', '');
      await s.addJournalEntry('', 'just a body');
      expect(s.journal, hasLength(2));
      await s.store.close();
    });

    test('editing changes content but keeps the row and its timestamp',
        () async {
      final s = await unlockedState();
      final before = await addEntry(s, 'draft', 'first pass');

      await s.editJournalEntry(before, 'draft', 'second pass, better');
      final after = s.journal.single;

      expect(after.uuid, before.uuid);
      expect(after.body, 'second pass, better');
      expect(after.entry.createdAt, before.entry.createdAt);
      await s.store.close();
    });

    test('editing an entry to empty deletes it', () async {
      final s = await unlockedState();
      final item = await addEntry(s, 'ephemeral', 'on reflection, no');
      await s.editJournalEntry(item, '  ', '  ');
      expect(s.journal, isEmpty);
      await s.store.close();
    });

    test('deleting tombstones the row rather than dropping it', () async {
      final s = await unlockedState();
      final ws = s.currentWorkspaceUuid!;
      final item = await addEntry(s, 'logged', 'then removed');

      await s.deleteJournalEntry(item);
      expect(s.journal, isEmpty);

      final rows = await s.store.raw.query('journal_entries',
          where: 'workspace_uuid = ?', whereArgs: [ws]);
      expect(rows, hasLength(1));
      expect(rows.single['deleted_at'], isNotNull);
      await s.store.close();
    });

    test('entries read newest-first', () async {
      final s = await unlockedState();
      final c = s.journalCrypto!;
      final ws = s.currentWorkspaceUuid!;
      for (final at in [
        '2026-07-20T09:00:00',
        '2026-07-22T09:00:00',
        '2026-07-19T09:00:00',
      ]) {
        await s.store.putJournal(JournalEntry(
          uuid: newId(),
          workspaceUuid: ws,
          title: await c.encrypt(at),
          text: await c.encrypt(''),
          encrypted: true,
          createdAt: at,
          updatedAt: at,
        ));
      }
      await s.refreshJournal();
      expect(s.journal.map((i) => i.title), [
        '2026-07-22T09:00:00',
        '2026-07-20T09:00:00',
        '2026-07-19T09:00:00',
      ]);
      await s.store.close();
    });
  });

  group('scope', () {
    test('the journal is per-workspace', () async {
      final s = await unlockedState();
      final first = s.currentWorkspaceUuid!;
      await addEntry(s, 'in the first', 'body');

      await s.saveWorkspace(name: 'Second', color: '#7EE3A1');
      await s.refreshJournal();
      expect(s.journal, isEmpty);

      await s.selectWorkspace(first);
      await s.refreshJournal();
      expect(s.journal.single.title, 'in the first');
      await s.store.close();
    });

    test('deleting a workspace tombstones its journal', () async {
      final s = await unlockedState();
      final other = s.workspaces.single;
      await s.saveWorkspace(name: 'Second', color: '#7EE3A1');
      final second = s.currentWorkspaceUuid!;
      await addEntry(s, 'doomed', 'goes with the workspace');

      await s.selectWorkspace(other.uuid);
      await s.deleteWorkspace(second);

      expect(await s.store.journalEntries(second), isEmpty);
      await s.store.close();
    });
  });

  test('a database from before journal titles/encryption migrates cleanly',
      () async {
    // A v5 database: journal_entries exists but has no title or encrypted
    // column, and its rows were plaintext. The upgrade must add both columns
    // without colliding and without dropping the old row.
    final dir = await Directory.systemTemp.createTemp('todo_journal_v5');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'todo.db');

    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('''
      CREATE TABLE journal_entries (
        uuid           TEXT PRIMARY KEY,
        workspace_uuid TEXT NOT NULL,
        text           TEXT NOT NULL,
        created_at     TEXT NOT NULL,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT,
        dirty          INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute(
        'CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await db.insert('journal_entries', {
      'uuid': 'j-old',
      'workspace_uuid': 'ws-1',
      'text': 'a plaintext note from before',
      'created_at': nowStamp(),
      'updated_at': nowStamp(),
    });
    await db.setVersion(5);
    await db.close();

    final store = await LocalStore.open(path: path, singleInstance: false);
    final rows = await store.journalEntries('ws-1');
    expect(rows.single.uuid, 'j-old');
    expect(rows.single.title, ''); // new column, default empty
    expect(rows.single.encrypted, isFalse); // pre-encryption row
    expect(rows.single.text, 'a plaintext note from before');
    await store.close();
  });

  test('a v6 database (always-encrypted) flags its rows as encrypted', () async {
    // v6 was the short-lived build where the journal was mandatorily encrypted:
    // it has a title column but no encrypted column, and its rows are ciphertext.
    // The upgrade must mark them encrypted, not leave them looking plaintext.
    final dir = await Directory.systemTemp.createTemp('todo_journal_v6');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'todo.db');

    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('''
      CREATE TABLE journal_entries (
        uuid           TEXT PRIMARY KEY,
        workspace_uuid TEXT NOT NULL,
        title          TEXT NOT NULL DEFAULT '',
        text           TEXT NOT NULL,
        created_at     TEXT NOT NULL,
        updated_at     TEXT NOT NULL,
        deleted_at     TEXT,
        dirty          INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute(
        'CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await db.insert('journal_entries', {
      'uuid': 'j-enc',
      'workspace_uuid': 'ws-1',
      'title': 'ciphertext-blob',
      'text': 'ciphertext-blob',
      'created_at': nowStamp(),
      'updated_at': nowStamp(),
    });
    await db.setVersion(6);
    await db.close();

    final store = await LocalStore.open(path: path, singleInstance: false);
    expect((await store.journalEntries('ws-1')).single.encrypted, isTrue);
    await store.close();
  });
}
