// The journal pane's three states and the keys that move between them.
//
// Widget tests rather than unit tests because the thing under test *is* the
// navigation: which of list / reader / editor is on screen after a tap or a
// chord. JournalView takes plain callbacks, so none of this needs a database.
//
// The shortcuts are the reason this file exists. Ctrl+S and Ctrl+Alt+S differ
// by one modifier and land in different places, and a Ctrl+Enter that stopped
// moving the caret would be invisible until someone reached for it mid-note.

import 'package:flutter/gestures.dart' show PointerDeviceKind, kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/ui/journal_panel.dart';
import 'package:todo_widget/ui/note_editor.dart';

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
  Future<JournalItem?> save(
    String title,
    String body,
    JournalItem? existing,
  ) async {
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
  ValueChanged<bool>? onFocusChanged,
  ValueChanged<bool>? onEditingChanged,
  bool startNew = false,
  bool locked = false,
  bool codeKeys = false,
  bool preview = false,
  ValueChanged<bool>? onPreview,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: JournalView(
          configured: locked,
          locked: locked,
          items: items,
          onSetup: (_) async {},
          onUnlock: (_) async => true,
          onLock: () {},
          onRemovePassword: () async {},
          onSave: saves.save,
          onDelete: saves.delete,
          onBack: onBack ?? () {},
          onFocusChanged: onFocusChanged,
          onEditingChanged: onEditingChanged,
          startNew: startNew,
          codeKeys: codeKeys,
          preview: preview,
          onPreview: onPreview,
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
    testWidgets('picking an entry renders it rather than opening the editor', (
      tester,
    ) async {
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

    testWidgets('a double-click on the list goes straight to the editor', (
      tester,
    ) async {
      final saves = Saves();
      await pumpPanel(
        tester,
        items: [item('a', 'Trip', 'Leaves at nine')],
        saves: saves,
      );

      // The first click reads at once; the second lands on the reader, which
      // has replaced the list, and makes it the editor.
      final at = tester.getCenter(find.text('Trip'));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('a click on the reader after the window is only a click', (
      tester,
    ) async {
      final saves = Saves();
      await pumpPanel(
        tester,
        items: [item('a', 'Trip', 'Leaves at nine')],
        saves: saves,
      );
      await tester.tap(find.text('Trip'));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.tap(find.text('Leaves at nine'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a new entry skips the reader and lands in the fields', (
      tester,
    ) async {
      final saves = Saves();
      await pumpPanel(tester, items: const [], saves: saves);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('the dock\'s Add a note opens on a blank entry, caret in the '
        'title', (tester) async {
      final saves = Saves();
      await pumpPanel(
        tester,
        items: [item('a', 'Trip', 'Leaves at nine')],
        saves: saves,
        startNew: true,
      );
      expect(find.byType(TextField), findsNWidgets(2));
      final title = tester.widget<TextField>(find.byType(TextField).first);
      expect(title.focusNode!.hasFocus, isTrue);
      expect(title.controller!.text, isEmpty);

      // And Esc is the list, as from any new entry.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Trip'), findsOneWidget);
    });

    testWidgets('locked, it asks for the password and then opens blank', (
      tester,
    ) async {
      final saves = Saves();
      await pumpPanel(
        tester,
        items: const [],
        saves: saves,
        startNew: true,
        locked: true,
      );
      expect(find.byType(TextField), findsOneWidget, reason: 'the password');

      await pumpPanel(tester, items: const [], saves: saves, startNew: true);
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });

  group('the Esc ladder', () {
    testWidgets('editor backs out to the reader, reader to the list', (
      tester,
    ) async {
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
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'back to the reader',
      );

      // The rung that needs the pane to hold focus of its own - there is no
      // text field in the reader to carry the key event up to the handler.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.add),
        findsOneWidget,
        reason: 'back to the list',
      );

      // And the view itself is only closed from the list, by the shell.
      expect(backedOut, 0);
    });
  });

  group('shortcuts', () {
    testWidgets('Ctrl+E edits the note being read, caret in the body', (
      tester,
    ) async {
      final saves = Saves();
      await pumpPanel(
        tester,
        items: [item('a', 'Trip', 'Leaves at nine')],
        saves: saves,
      );
      await tester.tap(find.text('Trip'));
      await tester.pumpAndSettle();

      await chord(tester, LogicalKeyboardKey.keyE);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(2));
      final focused = FocusManager.instance.primaryFocus!.context!;
      final field = focused.findAncestorWidgetOfExactType<TextField>()!;
      expect(field.controller!.text, 'Leaves at nine');
    });

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
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'reading, not editing',
      );
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
    testWidgets('saving a new entry twice rewrites the same row', (
      tester,
    ) async {
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

    testWidgets(
      'an entry cleared to nothing goes to the list, not the reader',
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
      },
    );
  });

  group('a draft outlives the panel', () {
    // Switching workspace closes every view, and so does the calendar; either
    // used to take a half-written note with it. The shell's side of the fix -
    // binding the save to the workspace the note was opened in - is a closure
    // in main.dart; what is pinned here is that the panel asks at all.
    Future<void> closePanel(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
    }

    testWidgets('a new entry being typed is saved when the panel goes away', (
      tester,
    ) async {
      final saves = Saves();
      await pumpPanel(tester, items: const [], saves: saves);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Half a thought');

      await closePanel(tester);

      expect(saves.calls, hasLength(1));
      expect(saves.calls.single.title, 'Half a thought');
      expect(saves.calls.single.existing, isNull);
    });

    testWidgets('an edit in progress is saved onto its own entry', (
      tester,
    ) async {
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
      await tester.enterText(find.byType(TextField).last, 'Leaves at ten');

      await closePanel(tester);

      expect(saves.calls.single.existing, 'a');
      expect(saves.calls.single.body, 'Leaves at ten');
    });

    testWidgets('nothing is written for an unchanged or emptied entry', (
      tester,
    ) async {
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
      await closePanel(tester);
      expect(saves.calls, isEmpty, reason: 'unchanged');

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
      await closePanel(tester);
      expect(
        saves.calls,
        isEmpty,
        reason: 'saving empty fields deletes, which is not ours to do',
      );
    });

    testWidgets('keeps the editor when a GlobalKey moves it to a new parent', (
      tester,
    ) async {
      // The resize case: the shell hands the same view to a Column in a
      // narrow window and a Row in a wide one.
      final saves = Saves();
      final key = GlobalKey();
      var wide = false;
      late StateSetter setOuter;
      Widget panel() => KeyedSubtree(
        key: key,
        child: JournalView(
          configured: false,
          locked: false,
          items: const [],
          onSetup: (_) async {},
          onUnlock: (_) async => true,
          onLock: () {},
          onRemovePassword: () async {},
          onSave: saves.save,
          onDelete: saves.delete,
          onBack: () {},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) {
                setOuter = set;
                return wide
                    ? Row(
                        children: [
                          const SizedBox(width: 10),
                          Expanded(child: panel()),
                        ],
                      )
                    : Column(children: [Expanded(child: panel())]);
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Still here');

      setOuter(() => wide = true);
      await tester.pumpAndSettle();

      expect(find.text('Still here'), findsOneWidget);
      expect(saves.calls, isEmpty, reason: 'it moved, it did not close');
    });
  });

  group('focus', () {
    Future<List<bool>> openInFocus(WidgetTester tester) async {
      final told = <bool>[];
      await pumpPanel(
        tester,
        items: [item('a', 'Trip', 'Leaves at nine')],
        saves: Saves(),
        onFocusChanged: told.add,
      );
      await tester.tap(find.text('Trip'));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.fullscreen_rounded));
      await tester.pumpAndSettle();
      return told;
    }

    testWidgets('leaves the title and the text, and tells the shell', (
      tester,
    ) async {
      final told = await openInFocus(tester);
      expect(told.last, isTrue);
      expect(find.text('Trip'), findsOneWidget);
      expect(find.text('Leaves at nine'), findsOneWidget);
      expect(find.text('Notes'), findsNothing, reason: 'the header goes');
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('carries into the editor, which loses its buttons', (
      tester,
    ) async {
      await openInFocus(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Save'), findsNothing);
      expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
    });

    testWidgets('Esc leaves focus before it leaves the note', (tester) async {
      final told = await openInFocus(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(told.last, isFalse);
      expect(find.text('Notes'), findsOneWidget);
      expect(
        find.byIcon(Icons.edit_outlined),
        findsOneWidget,
        reason: 'still reading',
      );
    });

    testWidgets('the button leaves it too', (tester) async {
      final told = await openInFocus(tester);
      await tester.tap(find.byIcon(Icons.fullscreen_exit_rounded));
      await tester.pumpAndSettle();
      expect(told.last, isFalse);
      expect(find.text('Notes'), findsOneWidget);
    });
  });

  testWidgets('tells the shell when a note is written, not when it is read', (
    tester,
  ) async {
    final told = <bool>[];
    await pumpPanel(
      tester,
      items: [item('a', 'Trip', 'Leaves at nine')],
      saves: Saves(),
      onEditingChanged: told.add,
    );
    await tester.tap(find.text('Trip'));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(told.last, isFalse, reason: 'reading keeps the dock');

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(told.last, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(told.last, isFalse);
  });

  group('the editor', () {
    Future<NoteController> openNew(
      WidgetTester tester, {
      bool codeKeys = false,
    }) async {
      await pumpPanel(
        tester,
        items: const [],
        saves: Saves(),
        startNew: true,
        codeKeys: codeKeys,
      );
      return tester
          .widget<TextField>(find.byType(TextField).last)
          .controller! as NoteController;
    }

    FocusNode? focused() => FocusManager.instance.primaryFocus;

    testWidgets('Tab goes from the title to the body', (tester) async {
      final body = await openNew(tester);
      await tester.enterText(find.byType(TextField).first, 'Trip');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.controller, body);
    });

    testWidgets('the body is monospaced and continues a list', (tester) async {
      final body = await openNew(tester);
      final field = find.byType(TextField).last;
      expect(tester.widget<TextField>(field).style!.fontFamily, 'Space Mono');
      await tester.enterText(field, '- milk');
      await tester.enterText(field, '- milk\n');
      await tester.pump();
      expect(body.text, '- milk\n- ');
    });

    testWidgets('Ctrl+F finds, steps and replaces', (tester) async {
      final body = await openNew(tester);
      final field = find.byType(TextField).last;
      await tester.enterText(field, 'milk and Milk');
      await chord(tester, LogicalKeyboardKey.keyF);
      expect(find.text('Find'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Find'), 'milk');
      await tester.pump();
      expect(body.matches.length, 2);
      expect(find.textContaining('of 2'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Replace with'),
        'oat',
      );
      await tester.tap(find.text('All'));
      await tester.pump();
      expect(body.text, 'oat and oat');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Find'), findsNothing);
      expect(find.byType(TextField), findsNWidgets(2), reason: 'still editing');
    });

    testWidgets('with the code keys, Ctrl+D edits every match at once', (
      tester,
    ) async {
      final body = await openNew(tester, codeKeys: true);
      final field = find.byType(TextField).last;
      await tester.enterText(field, 'cat cat dog');
      body.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();
      expect(focused(), isNotNull);

      await chord(tester, LogicalKeyboardKey.keyD); // the word
      await chord(tester, LogicalKeyboardKey.keyD); // and the next
      expect(body.selection.start, 4);
      expect(body.extras.single, const TextRange(start: 0, end: 3));

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'cat x dog',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();
      expect(body.text, 'x x dog');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(body.extras, isEmpty);
      expect(find.byType(TextField), findsNWidgets(2), reason: 'Esc was spent');
    });

    testWidgets('without them, Ctrl+D is not taken', (tester) async {
      final body = await openNew(tester);
      await tester.enterText(find.byType(TextField).last, 'cat cat');
      body.selection = const TextSelection.collapsed(offset: 1);
      await chord(tester, LogicalKeyboardKey.keyD);
      expect(body.selection.isCollapsed, isTrue);
    });

    testWidgets('the preview shows the note as it reads, beside it', (
      tester,
    ) async {
      final asked = <bool>[];
      await pumpPanel(
        tester,
        items: const [],
        saves: Saves(),
        startNew: true,
        preview: true,
        onPreview: asked.add,
      );
      await tester.enterText(find.byType(TextField).last, '**bold** move');
      await tester.pump();
      expect(find.text('bold move'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide the preview'));
      expect(asked, [false]);
    });

    testWidgets('a hovered row offers Edit, straight into the fields', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        items: [item('a', 'Trip', 'Leaves at nine')],
        saves: Saves(),
      );
      expect(find.byTooltip('Edit'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Trip')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(
        tester.widget<TextField>(find.byType(TextField).last).focusNode!.hasFocus,
        isTrue,
      );
    });
  });
}
