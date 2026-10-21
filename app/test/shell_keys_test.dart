// The shell's keys keep arriving after a text field lets go of focus.
//
// Ctrl+E worked "only sometimes": a click outside a field on a desktop
// unfocuses it, and unfocusing hands focus to the nearest scope - which, with
// the handler on a plain Focus, was the route's, above it. The first test
// pins that mechanism so the second one means something.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/ui/shell_keys.dart';

void main() {
  Future<List<String>> run(
    WidgetTester tester,
    Widget Function(FocusOnKeyEventCallback, Widget) wrap,
  ) async {
    final heard = <String>[];
    KeyEventResult onKey(FocusNode node, KeyEvent e) {
      if (e is KeyDownEvent &&
          e.logicalKey == LogicalKeyboardKey.keyE &&
          HardwareKeyboard.instance.isControlPressed) {
        heard.add('ctrl+e');
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: wrap(
            onKey,
            const Column(
              children: [
                SizedBox(width: 300, child: TextField()),
                SizedBox(height: 300),
              ],
            ),
          ),
        ),
      ),
    );
    Future<void> ctrlE() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await ctrlE(); // straight after launch
    await tester.tap(find.byType(TextField), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.tapAt(const Offset(150, 200), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await ctrlE(); // after the field let go
    return heard;
  }

  testWidgets(
    'on a plain Focus the key is lost once a field is clicked away from',
    (tester) async {
      final heard = await run(
        tester,
        (onKey, child) =>
            Focus(autofocus: true, onKeyEvent: onKey, child: child),
      );
      expect(heard, ['ctrl+e']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'ShellKeys still hears it',
    (tester) async {
      final heard = await run(
        tester,
        (onKey, child) => ShellKeys(onKeyEvent: onKey, child: child),
      );
      expect(heard, ['ctrl+e', 'ctrl+e']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
