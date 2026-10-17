// Voice notes: a thought said aloud keeps its recording - in the device's
// blobs table, queued for the server - and a task made from it carries it on.

import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/voice_clip.dart';
import 'package:todo_widget/voice_notes.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<LocalStore> freshStore() =>
      LocalStore.open(path: inMemoryDatabasePath, singleInstance: false);

  final bytes = Uint8List.fromList(List.generate(300, (i) => i % 251));
  final digest = sha256.convert(bytes).toString();
  final clip = VoiceClip(bytes, 'audio/mp4', 42000);

  test('a thought said aloud is stored with nothing typed, and its bytes '
      'wait for the server', () async {
    final store = await freshStore();
    final s = AppState(store);
    await s.load();

    await s.addThought('', clip: clip);
    final t = s.thoughts.single;
    expect(t.text, '');
    expect(t.audio, digest);
    expect(t.voice!.length, '0:42');

    expect(await store.pendingBlobs(), [digest]);
    final kept = await store.blob(digest);
    expect(kept!.type, 'audio/mp4');
    expect(kept.data, bytes);

    await store.markBlobUploaded(digest);
    expect(await store.pendingBlobs(), isEmpty);
  });

  test('nothing typed and nothing recorded is not a thought', () async {
    final s = AppState(await freshStore());
    await s.load();
    await s.addThought('  ');
    expect(s.thoughts, isEmpty);
  });

  test('a task made from it carries the recording, and is named by it when '
      'nothing was typed', () async {
    final s = AppState(await freshStore());
    await s.load();
    await s.addThought('', clip: clip);
    await s.addThought('call the bank', clip: clip);

    await s.moveThoughts(
      [...s.thoughts],
      workspaceUuid: s.currentWorkspaceUuid!,
    );
    final titles = {for (final t in s.tasks) t.text: t};
    expect(titles.keys, containsAll(['Voice note (0:42)', 'call the bank']));
    expect(titles['Voice note (0:42)']!.audio, digest);
    expect(titles['call the bank']!.audioMs, 42000);
    expect(s.thoughts, isEmpty);
  });

  test('the fetched copies are trimmed oldest-used first, never one still '
      'waiting to go up', () async {
    final store = await freshStore();
    Uint8List b(int n) => Uint8List(n);
    await store.putBlob('mine', 'audio/mp4', b(100));
    await store.putBlob('old', 'audio/mp4', b(100), uploaded: true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.putBlob('new', 'audio/mp4', b(100), uploaded: true);

    await store.trimBlobs(150);
    expect(await store.blob('old'), isNull);
    expect(await store.blob('new'), isNotNull);
    expect(await store.blob('mine'), isNotNull);
  });

  test('a note with no bytes anywhere says so instead of failing', () async {
    final store = await freshStore();
    final notes = VoiceNotes(store: store, fetch: (_) async => null);
    expect(await notes.bytes(digest), isNull);

    final served = VoiceNotes(
      store: store,
      fetch: (_) async => (type: 'audio/webm', data: bytes),
    );
    expect((await served.bytes(digest))!.type, 'audio/webm');
    // Kept: asked once.
    expect((await notes.bytes(digest))!.data, bytes);
  });

  testWidgets('the pill shows how long the note runs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VoiceNoteButton(
            note: VoiceNote('abc', 65000),
            accent: T.thoughts,
          ),
        ),
      ),
    );
    expect(find.text('1:05'), findsOneWidget);
  });
}
