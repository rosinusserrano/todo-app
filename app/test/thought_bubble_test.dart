// Capturing a side thought on a phone: the bubble, and where the pane it opens
// is allowed to start.
//
// Two things are worth pinning, and both are about controls colliding rather
// than about the field itself.
//
// There must be exactly **one** way in on touch. The bubble and the footer's
// 💭 are the same door, and a build that drew both would have the capture
// button in one place on the task list and another in the thoughts panel.
//
// And the pane it opens must start below the title bar. It used to start at the
// top of the window and be drawn *under* the bar - the bar sits above every
// sheet in the shell's Stack so it stays draggable - which put this pane's ✕
// exactly under the concentration-sound button.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/footer.dart';
import 'package:todo_widget/ui/thought_bubble.dart';
import 'package:todo_widget/ui/thought_sheet.dart';
import 'package:todo_widget/ui/title_bar.dart';

void main() {
  SideThought thought(String text) => SideThought(
        uuid: text,
        text: text,
        createdAt: '2026-08-19T09:00:00+02:00',
        updatedAt: '2026-08-19T09:00:00+02:00',
      );

  Widget footer({
    required bool showCaptureButton,
    List<SideThought> thoughts = const [],
    String? blockedMessage,
    VoidCallback? onCapture,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Spacer(),
              ThoughtFooter(
                thoughts: thoughts,
                workspaceColor: T.accent,
                blockedMessage: blockedMessage,
                onAdd: (_) async {},
                onCapture: onCapture,
                showCaptureButton: showCaptureButton,
                listOpen: false,
                onToggleList: () {},
              ),
            ],
          ),
        ),
      );

  group('the bubble', () {
    testWidgets('is one tap, and says what it is', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  right: ThoughtBubble.margin,
                  bottom: ThoughtBubble.margin,
                  child: ThoughtBubble(accent: T.accent, onTap: () => taps++),
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(ThoughtBubble)).label,
        'Capture a side thought',
      );
      await tester.tap(find.byType(ThoughtBubble));
      expect(taps, 1);
    });

    testWidgets('is finger-sized, and bigger than a bar icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ThoughtBubble(accent: T.accent, onTap: () {}),
            ),
          ),
        ),
      );

      final box = tester.getSize(find.byType(ThoughtBubble));
      expect(box.width, ThoughtBubble.side);
      expect(box.height, ThoughtBubble.side);
      // Before UiScale magnifies it, and already past the 40 a row action gets.
      expect(ThoughtBubble.side, greaterThan(40));
    });
  });

  group('the footer beside it', () {
    testWidgets('keeps its 💭 where there is no bubble', (tester) async {
      await tester.pumpWidget(footer(showCaptureButton: true));
      expect(find.text('💭'), findsOneWidget);
    });

    testWidgets('drops its 💭 where the bubble is the way in', (tester) async {
      // One door. The count badge is a different control and carries its own
      // number with it, so it is not what this looks for.
      await tester.pumpWidget(
        footer(showCaptureButton: false, thoughts: [thought('a book')]),
      );
      expect(find.text('💭'), findsNothing);
      expect(find.text('💭 1'), findsOneWidget);
    });

    testWidgets('takes no height at all with nothing to say', (tester) async {
      await tester.pumpWidget(footer(showCaptureButton: false));
      expect(tester.getSize(find.byType(ThoughtFooter)).height, 0);
    });

    testWidgets('comes back the moment a thought is pending', (tester) async {
      await tester.pumpWidget(
        footer(showCaptureButton: false, thoughts: [thought('a book')]),
      );
      expect(
        tester.getSize(find.byType(ThoughtFooter)).height,
        greaterThan(0),
      );
    });

    testWidgets('and for a refusal, which has nothing to do with the count',
        (tester) async {
      await tester.pumpWidget(
        footer(showCaptureButton: false, blockedMessage: 'Ctrl+Alt+H taken'),
      );
      expect(find.text('Ctrl+Alt+H taken'), findsOneWidget);
    });
  });

  group('the pane it opens', () {
    Future<void> pumpSheet(WidgetTester tester, {VoidCallback? onClose}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(height: TitleBar.height),
                  ),
                  ThoughtSheet(
                    accent: T.accent,
                    onAdd: (_) async {},
                    onClose: onClose ?? () {},
                  ),
                ],
              ),
            ),
          ),
        );

    testWidgets('starts below the title bar, not under it', (tester) async {
      await pumpSheet(tester);
      expect(
        tester.getTopLeft(find.byType(ThoughtSheet)).dy,
        TitleBar.height,
      );
    });

    testWidgets('so its ✕ cannot land on the sound button', (tester) async {
      await pumpSheet(tester);
      final close = tester.getRect(find.byIcon(Icons.close_rounded));
      // The whole target, not just its centre: half a button inside the bar is
      // still a press that can go to the wrong control.
      expect(close.top, greaterThanOrEqualTo(TitleBar.height));
    });

    testWidgets('still covers everything the workspace is named in',
        (tester) async {
      // The privacy point is unchanged - what it hides is the workspace bar and
      // the tasks, and both of those are below the title bar.
      await pumpSheet(tester);
      final sheet = tester.getRect(find.byType(ThoughtSheet));
      final screen = tester.getRect(find.byType(Scaffold));
      expect(sheet.bottom, screen.bottom);
      expect(sheet.width, screen.width);
    });
  });
}
