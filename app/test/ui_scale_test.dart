// The phone zoom, which had two bugs that between them made most of the UI
// unreachable on an iPhone.
//
//   1. The subtree was wrapped in a `SizedBox`, which cannot defy the *tight*
//      constraints MaterialApp passes down. The box was ignored, the layout ran
//      at the full screen width, and Transform then magnified it - so roughly a
//      fifth of the width and height was painted off-screen. Nothing warned:
//      a Transform does not report overflow, and MediaQuery had been shrunk, so
//      anything measuring itself from MediaQuery disagreed with its own box.
//
//   2. The zoom was a flat 1.28, which left a 375pt phone only 293 points of
//      layout - narrower than the 340 window every size here was picked for -
//      so the controls at the ends of the bars were squeezed.
//
// The invariant worth holding on to: **the layout always gets at least its
// design width, and what it lays out in always ends up exactly filling the
// screen.** Both are cheap to assert and neither is visible in a widget test
// that only checks that a button exists.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/theme.dart';

void main() {
  /// The size the subtree is actually laid out in, and the size it occupies on
  /// screen once the transform has been applied.
  Future<(Size layout, Size painted)> measure(
    WidgetTester tester,
    Size screen, {
    double scale = T.mobileScale,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) =>
            UiScale(scale: scale, child: child ?? const SizedBox.shrink()),
        home: SizedBox.expand(key: key),
      ),
    );

    final box = key.currentContext!.findRenderObject() as RenderBox;
    final layout = box.size;
    // Top-left to bottom-right in global coordinates: what the user sees.
    final topLeft = box.localToGlobal(Offset.zero);
    final bottomRight = box.localToGlobal(Offset(layout.width, layout.height));
    return (layout, (bottomRight - topLeft).let());
  }

  group('the zoomed subtree fills the screen exactly', () {
    for (final device in const {
      'iPhone SE': Size(375, 667),
      'iPhone 15': Size(390, 844),
      'iPhone 15 Pro Max': Size(430, 932),
    }.entries) {
      testWidgets(device.key, (tester) async {
        final (layout, painted) = await measure(tester, device.value);

        // What it occupies on screen is the whole screen - not 1.28x of it,
        // which is what put the right-hand controls out of reach.
        expect(painted.width, closeTo(device.value.width, 0.01));
        expect(painted.height, closeTo(device.value.height, 0.01));

        // And it had at least the width every size in this app was picked for.
        expect(layout.width, greaterThanOrEqualTo(T.designWidth - 0.01));
      });
    }
  });

  testWidgets('a tablet is zoomed no further than the cap', (tester) async {
    final (layout, painted) = await measure(tester, const Size(820, 1180));
    expect(painted.width, closeTo(820, 0.01));
    // Capped at mobileScale, so the layout gets the extra room rather than the
    // widget being blown up to fill a tablet.
    expect(layout.width, closeTo(820 / T.mobileScale, 0.01));
  });

  testWidgets('desktop is left completely alone', (tester) async {
    final (layout, painted) =
        await measure(tester, const Size(340, 480), scale: 1.0);
    expect(layout.width, closeTo(340, 0.01));
    expect(painted.width, closeTo(340, 0.01));
  });

  group('effectiveScale', () {
    test('takes the largest zoom that still leaves the design width', () {
      // 390 / 340 = 1.147, which is under the cap, so it is used as-is.
      expect(UiScale.effectiveScale(390, 1.28), closeTo(390 / 340, 0.001));
      expect(390 / UiScale.effectiveScale(390, 1.28), closeTo(340, 0.001));
    });

    test('is capped, so a wide screen is not blown up', () {
      expect(UiScale.effectiveScale(2000, 1.28), 1.28);
    });

    test('never shrinks below the desktop size', () {
      // Narrower than the design width: zooming out to fit would make the text
      // smaller than the desktop build, which is not what this is for.
      expect(UiScale.effectiveScale(300, 1.28), 1.0);
    });

    test('a max of 1 disables it', () {
      expect(UiScale.effectiveScale(390, 1.0), 1.0);
    });
  });
}

extension on Offset {
  Size let() => Size(dx, dy);
}
