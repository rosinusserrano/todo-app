// The calendar's swipe follows the finger, then turns the page or puts it back.
//
// What is worth pinning is the part the eye cannot check: the page that slides
// back in is the *same* element, so the grid keeps the hour it was scrolled to.
// A page keyed per week would land every swipe at the top of the day.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/ui/calendar/time_swipe.dart';

void main() {
  late List<int> steps;
  late ScrollController scroll;

  setUp(() {
    steps = [];
    scroll = ScrollController();
  });
  tearDown(() => scroll.dispose());

  Widget host() => MaterialApp(
    home: Scaffold(
      body: TimeSwipe(
        onStep: (d) async => steps.add(d),
        child: ListView(
          controller: scroll,
          children: [
            for (var h = 0; h < 24; h++)
              SizedBox(height: 60, child: Text('$h:00')),
          ],
        ),
      ),
    ),
  );

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
  }

  double offset(WidgetTester tester) => tester
      .widget<FractionalTranslation>(
        find.descendant(
          of: find.byType(TimeSwipe),
          matching: find.byType(FractionalTranslation),
        ),
      )
      .translation
      .dx;

  testWidgets('a fling left is forwards, a fling right is back', (
    tester,
  ) async {
    await pumpHost(tester);

    await tester.fling(find.byType(ListView), const Offset(-120, 0), 1000);
    await tester.pumpAndSettle();
    expect(steps, [1]);
    expect(offset(tester), 0);

    await tester.fling(find.byType(ListView), const Offset(120, 0), 1000);
    await tester.pumpAndSettle();
    expect(steps, [1, -1]);
    expect(offset(tester), 0);
  });

  testWidgets('the page follows the finger, and a short drag puts it back', (
    tester,
  ) async {
    await pumpHost(tester);

    final g = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await g.moveBy(const Offset(-20, 0));
    await g.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(offset(tester), lessThan(0));

    // Held still before letting go, so there is no fling in it.
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    expect(steps, isEmpty);
    expect(offset(tester), 0);
  });

  testWidgets('a slow drag past a third of the width still turns', (
    tester,
  ) async {
    await pumpHost(tester);

    final g = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    expect(steps, [1]);
  });

  testWidgets('the page keeps its scroll through a turn', (tester) async {
    await pumpHost(tester);
    scroll.jumpTo(540);
    await tester.pump();

    await tester.fling(find.byType(ListView), const Offset(-120, 0), 1000);
    await tester.pumpAndSettle();
    expect(steps, [1]);
    expect(scroll.offset, 540);
  });
}
