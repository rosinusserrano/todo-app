import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/thought_sheet.dart';

void main() {
  late List<String> added;
  late List<DateTime?> reminders;
  late int closed;

  Future<void> pump(
    WidgetTester tester, {
    bool enterSaves = true,
    bool canRemind = false,
  }) async {
    added = [];
    reminders = [];
    closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ThoughtSheet(
                accent: T.thoughts,
                enterSaves: enterSaves,
                canRemind: canRemind,
                onAdd: (t, _, at) async {
                  added.add(t);
                  reminders.add(at);
                },
                onClose: () => closed++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Enter saves and closes', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'a book');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(added, ['a book']);
    expect(closed, 1);
  });

  testWidgets('"in 10 minutes" is a reminder, and out of the thought', (
    tester,
  ) async {
    await pump(tester, canRemind: true);
    final before = DateTime.now();
    await tester.enterText(
      find.byType(TextField),
      'keys when leaving in 10 minutes',
    );
    await tester.pump();
    expect(find.textContaining('Reminds you in'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(added, ['keys when leaving']);
    final at = reminders.single!;
    expect(at.difference(before).inMinutes, inInclusiveRange(9, 10));
  });

  testWidgets('the reminder line\'s × keeps the words as words', (
    tester,
  ) async {
    await pump(tester, canRemind: true);
    await tester.enterText(find.byType(TextField), 'call in 2 hours');
    await tester.pump();
    await tester.tap(find.byTooltip('Keep those words in the thought'));
    await tester.pump();
    expect(find.textContaining('Reminds you'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(added, ['call in 2 hours']);
    expect(reminders, [null]);
  });

  testWidgets('without canRemind the words are only words', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'note in 10 minutes');
    await tester.pump();
    expect(find.byTooltip('Remind me'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(added, ['note in 10 minutes']);
    expect(reminders, [null]);
  });

  testWidgets('Ctrl+Enter saves and stays, empty, for the next one', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'first');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(added, ['first']);
    expect(closed, 0);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('1 saved'), findsOneWidget);
  });

  testWidgets('Shift+Enter saves nothing: it is the new line', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'two\nlines');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(added, isEmpty);
    expect(closed, 0);
  });

  testWidgets('on touch Enter is left to the field', (tester) async {
    await pump(tester, enterSaves: false);
    await tester.enterText(find.byType(TextField), 'note');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(added, isEmpty);
    expect(closed, 0);
  });

  testWidgets('the field takes focus on opening, even from a focused shell', (
    tester,
  ) async {
    // The shell's key handler holds focus whenever nothing else does, which
    // is exactly the case `autofocus` gives up on.
    final shell = FocusNode();
    addTearDown(shell.dispose);
    var open = false;
    late StateSetter setOpen;
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: shell,
          autofocus: true,
          child: StatefulBuilder(
            builder: (context, set) {
              setOpen = set;
              return Scaffold(
                body: Stack(
                  children: [
                    if (open)
                      ThoughtSheet(
                        accent: T.thoughts,
                        enterSaves: true,
                        onAdd: (_, _, _) async {},
                        onClose: () {},
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(shell.hasPrimaryFocus, isTrue);
    setOpen(() => open = true);
    await tester.pump();
    await tester.pump();
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasPrimaryFocus, isTrue);
  });
}
