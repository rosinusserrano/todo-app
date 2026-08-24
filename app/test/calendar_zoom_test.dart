// Ctrl and the wheel stretch the day; the wheel on its own still scrolls it.
//
// The hour height has been pinchable since 0.24.0, which left the input device
// most of this app is used with - a mouse, in a widget parked on a desktop -
// with no way to ask for the same thing. Ctrl+wheel is what every canvas, map
// and drawing program means by "closer", so it needs no explaining.
//
// The part worth pinning is the exclusivity. A scroll signal goes to whichever
// handler registers for it *first*, and dispatch runs deepest-first, so the
// zoom listener has to sit **inside** the scroll view or the day would zoom and
// scroll at the same time. A plain wheel is not claimed at all and still
// belongs to the scrollable.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/calendar/time_grid.dart';

void main() {
  final monday = DateTime(2026, 8, 17);

  /// A day grid that redraws itself at whatever height the zoom asked for, the
  /// way the real one does through AppState.
  Widget grid({
    required void Function(double) onZoom,
    required double height,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: TimeGridView(
            days: [monday],
            events: const [],
            colorFor: (_) => T.accent,
            hasAttachment: (_) => false,
            taskCountFor: (_) => 0,
            onOpenEvent: (_) {},
            onEventMenu: (_, _) {},
            onCreate: (_, _) {},
            hourHeight: height,
            onZoom: onZoom,
          ),
        ),
      );

  /// One notch of the wheel over the middle of the grid.
  Future<void> wheel(WidgetTester tester, double dy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final at = tester.getCenter(find.byType(TimeGridView));
    pointer.hover(at);
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pumpAndSettle();
  }

  double scrolled(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

  testWidgets('ctrl and the wheel stretch the hour', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var height = kHourHeight;
    await tester.pumpWidget(grid(height: height, onZoom: (h) => height = h));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft));

    // Up is closer, the way it is everywhere else.
    await wheel(tester, -100);
    expect(height, greaterThan(kHourHeight));

    final zoomedIn = height;
    await wheel(tester, 100);
    expect(height, lessThan(zoomedIn));
  });

  testWidgets('and the wheel on its own still scrolls the day',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var zooms = 0;
    await tester.pumpWidget(grid(height: kHourHeight, onZoom: (_) => zooms++));

    final before = scrolled(tester);
    await wheel(tester, 120);
    expect(zooms, 0);
    expect(scrolled(tester), greaterThan(before));
  });
}
