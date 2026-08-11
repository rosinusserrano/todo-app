// The journal pane's three states and the keys that move between them.
//
// Widget tests rather than unit tests because the thing under test *is* the
// navigation: which of list / reader / editor is on screen after a tap or a
// chord. JournalView takes plain callbacks, so none of this needs a database.
//
// The shortcuts are the reason this file exists. Ctrl+S and Ctrl+Alt+S differ
// by one modifier and land in different places, and a Ctrl+Enter that stopped
// moving the caret would be invisible until someone reached for it mid-note.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/ui/journal_panel.dart';

JournalItem item(String uuid, String title, String body) => JournalItem(
      entry: JournalEntry(
        uuid: uuid,
        workspaceUuid: 'ws',
        title: title,
        text: body,
        encrypted: false,
        createdAt: '2026-08-11T09:00:00.000Z',
        updatedAt: '2026-08-11T09:00:00.000Z',
      ),
      title: title,
      body: body,
    );

/// What the panel asked its owner to do, in order.
class Saves {
  final calls = <({String title, String body, String? existing})>[];
  final deleted = <String>[];

  /// Hands back a saved item the way AppState does, so the panel can adopt it.
  Future<JournalItem?> save(String title, String body, JournalItem? existing) async {
    calls.add((title: title, body: body, existing: existing?.uuid));
    if (title.trim().isEmpty && body.trim().isEmpty) return null;
    return item(existing?.uuid ?? 'minted-uuid', title, body);
  }

  Future<void> delete(JournalItem i) async => deleted.add(i.uuid);
}

Future<void> pumpPanel(
  WidgetTester tester, {
  required List<JournalItem> items,
  required Saves saves,
  VoidCallback? onBack,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: JournalView(
          configured: false,
          locked: false,
          items: items,
          onSetup: (_) async {},
          onUnlock: (_) async => true,
          onLock: () {},
          onRemovePassword: () async {},
          onSave: saves.save,
          onDelete: saves.delete,
          onBack: onBack ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// One chord, held and released around the key itself.
Future<void> chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool alt = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  group('read first', () {
    testWidgets('picking an entry renders it rather than opening the editor',
        (tester) async {
      final saves = Saves();
      await pumpPanel(
        tester,
        items: [item('a', 'Trip', '**Leaves** at nine')],
        saves: saves,
      );

      await tester.tap(find.text('Trip'));
      await tester.pumpAndSettle();

      // Rendered: the asterisks are gone and no field is on screen.
      expect(find.text('Leaves at nine'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('the pencil turns the reader into the editor', (tester) async {
      final saves = Saves();
      await pumpPanel(
        tester,
        items: [item('a', 'Trip', 'Leaves at nine')],
        saves: saves,
      );
      await tester.tap(find.text('Trip'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Leaves at nine'), findsOneWidget); // now in the field
    });

    testWidgets('a new entry skips the reader and lands in the fields',
        (tester) async {
      final saves = Saves();
      await pumpPanel(tester, items: const [], saves: saves);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(2));
    });
  });

  group('the Esc ladder', () {
    testWidgets('editor backs out to the reader, reader to the list',
        (tester) async {
      var backedOut = 0;
      final saves = Saves();
      await pumpPanel(
        tester,
        items: [item('a', 'Trip', 'Leaves at nine')],
        saves: saves,
        onBack: () => backedOut++,
      );

      await tester.tap(find.text('Trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing, reason: 'back to the reader');

      // The rung that needs the pane to hold focus of its own - there is no
      // text field in the reader to carry the key event up to the handler.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add), findsOneWidget, reason: 'back to the list');

      // And the view itself is only closed from the list, by the shell.
      expect(backedOut, 0);
    });
  });

  group('shortcuts', () {
    testWidgets('Ctrl+Enter moves from the title to the body', (tester) async {
      final saves = Saves();
      await pumpPanel(tester, items: const [], saves: saves);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Trip');
      await chord(tester, LogicalKeyboardKey.enter);
      await tester.enterText(find.byType(TextField).last, 'nine sharp');

      // Typing went where the caret was sent, not into the title.
      await chord(tester, LogicalKeyboardKey.keyS);
      expect(saves.calls.single.title, 'Trip');
      expect(saves.calls.single.body, 'nine sharp');
    });

    testWidgets('Ctrl+S saves and shows the rendered entry', (tester) async {
      final saves = Saves();
      await pumpPanel(tester, items: const [], saves: saves);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Trip');

      await chord(tester, LogicalKeyboardKey.keyS);

      expect(saves.calls, hasLength(1));
      expect(find.byType(TextField), findsNothing, reason: 'reading, not editing');
      expect(find.text('Trip'), findsOneWidget);
    });

    testWidgets('Ctrl+Alt+S saves and goes back to the list', (tester) async {
      final saves = Saves();
      await pumpPanel(tester, items: const [], saves: saves);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Trip');

      await chord(tester, LogicalKeyboardKey.keyS, alt: true);

      expect(saves.calls, hasLength(1));
      expect(find.byIcon(Icons.add), findsOneWidget, reason: 'the list');
    });

    // The reason onSave hands the item back. Without the minted uuid the panel
    // would still think it was composing, and the second save would write a
    // second row.
    testWidgets('saving a new entry twice rewrites the same row',
        (tester) async {
      final saves = Saves();
      await pumpPanel(tester, items: const [], saves: saves);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Trip');

      await chord(tester, LogicalKeyboardKey.keyS);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Trip, revised');
      await chord(tester, LogicalKeyboardKey.keyS);

      expect(saves.calls.map((c) => c.existing), [null, 'minted-uuid']);
    });

    testWidgets('an entry cleared to nothing goes to the list, not the reader',
        (tester) async {
      final saves = Saves();
      await pumpPanel(
        tester,
        items: [item('a', 'Trip', 'Leaves at nine')],
        saves: saves,
      );
      await tester.tap(find.text('Trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '');
      await tester.enterText(find.byType(TextField).last, '');
      await chord(tester, LogicalKeyboardKey.keyS);

      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });
}
