import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/thought_sheet.dart';

void main() {
  late List<String> added;
  late int closed;

  Future<void> pump(WidgetTester tester, {bool enterSaves = true}) async {
    added = [];
    closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ThoughtSheet(
                accent: T.thoughts,
                enterSaves: enterSaves,
                onAdd: (t) async => added.add(t),
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
}
