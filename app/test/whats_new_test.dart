// The box after an update: which notes a device has not shown, and that it
// shows them once.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/whats_new.dart';

const _notes = [
  ReleaseNote(id: 'c', title: 'C', points: ['third']),
  ReleaseNote(id: 'b', title: 'B', points: ['second']),
  ReleaseNote(id: 'a', title: 'A', points: ['first']),
];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(LocalStore, AppState)> fresh() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final state = AppState(store);
    await state.load();
    return (store, state);
  }

  group('notesSince', () {
    test('lists what is newer than the one seen, newest first', () {
      expect(notesSince('a', _notes).map((n) => n.id), ['c', 'b']);
      expect(notesSince('b', _notes).map((n) => n.id), ['c']);
    });

    test('is empty once the newest has been seen', () {
      expect(notesSince('c', _notes), isEmpty);
    });

    test('an id that is no longer listed means everything, capped', () {
      final many = [
        for (var i = 9; i >= 0; i--)
          ReleaseNote(id: '$i', title: '$i', points: const []),
      ];
      expect(notesSince('gone', many), hasLength(kMaxNotesShown));
      expect(notesSince('gone', many).first.id, '9');
    });

    test('the real notes have unique ids', () {
      final ids = kReleaseNotes.map((n) => n.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  group('checkWhatsNew', () {
    test('a fresh install shows nothing, and is marked as seen', () async {
      final (_, s) = await fresh();
      await s.checkWhatsNew();
      expect(s.whatsNew, isEmpty);
      // An update after this one is still news.
      await s.checkWhatsNew();
      expect(s.whatsNew, isEmpty);
    });

    test('a device in use before the box existed gets the latest', () async {
      final (_, s) = await fresh();
      await s.addTask('something');
      await s.checkWhatsNew();
      expect(s.whatsNew.map((n) => n.id), [kReleaseNotes.first.id]);
    });

    test('once shown, it does not come back', () async {
      final (store, s) = await fresh();
      await s.addTask('something');
      await s.checkWhatsNew();
      await s.markWhatsNewSeen();
      expect(s.whatsNew, isEmpty);

      final again = AppState(store);
      await again.load();
      await again.checkWhatsNew();
      expect(again.whatsNew, isEmpty);
    });

    test('a device behind by one shows the newer note', () async {
      if (kReleaseNotes.length < 2) return;
      final (store, s) = await fresh();
      await store.setSetting('whats-new:seen', kReleaseNotes[1].id);
      await s.checkWhatsNew();
      expect(s.whatsNew.map((n) => n.id), [kReleaseNotes.first.id]);
    });
  });

  testWidgets('the box lists the notes and closes on Got it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LayoutScope(
          layout: const Layout(Size(340, 600)),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWhatsNew(
                context,
                notes: _notes.take(2).toList(),
                accent: Colors.blue,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text("What's new"), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text("What's new"), findsNothing);
  });
}
