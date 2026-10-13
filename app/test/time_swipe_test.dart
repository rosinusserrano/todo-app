// The calendar's swipe follows the finger, then turns the page or puts it back.
//
// What is worth pinning is the part the eye cannot check: the page that slides
// back in is the *same* element, so the grid keeps the hour it was scrolled to.
// A page keyed per week would land every swipe at the top of the day. And a
// drag draws the neighbouring page beside it, so a short one is a glimpse.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/ui/calendar/time_swipe.dart';

void main() {
  late List<int> steps;
  late ScrollController scroll;
  late int page;

  setUp(() {
    steps = [];
    page = 0;
    scroll = ScrollController();
  });
  tearDown(() => scroll.dispose());

  /// The middle page keeps one key whatever it shows, as the calendar's grid
  /// does; a neighbour is keyed by what it shows.
  Widget pageOf(int n, {ScrollController? controller}) => ListView(
    key: ValueKey(controller != null ? 'middle' : 'list $n'),
    controller: controller,
    children: [
      for (var h = 0; h < 24; h++)
        SizedBox(height: 60, child: Text('page $n, $h:00')),
    ],
  );

  Widget host({bool neighbours = true}) => MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => TimeSwipe(
          onStep: (d) async {
            steps.add(d);
            setState(() => page += d);
          },
          page: page,
          builder: (delta, _) => delta == 0
              ? pageOf(page, controller: scroll)
              : neighbours
              ? pageOf(page + delta)
              : null,
        ),
      ),
    ),
  );

  Future<void> pumpHost(WidgetTester tester, {bool neighbours = true}) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(neighbours: neighbours));
  }

  /// The middle page's offset, as a fraction of the width.
  double offset(WidgetTester tester) => tester
      .widget<FractionalTranslation>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('middle')),
              matching: find.byType(FractionalTranslation),
            )
            .first,
      )
      .translation
      .dx;

  testWidgets('a fling left is forwards, a fling right is back', (
    tester,
  ) async {
    await pumpHost(tester);

    await tester.fling(
      find.byKey(const ValueKey('middle')),
      const Offset(-120, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(steps, [1]);
    expect(offset(tester), 0);

    await tester.fling(
      find.byKey(const ValueKey('middle')),
      const Offset(120, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(steps, [1, -1]);
    expect(offset(tester), 0);
  });

  testWidgets('the page follows the finger, and a short drag puts it back', (
    tester,
  ) async {
    await pumpHost(tester);

    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('middle'))),
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
      tester.getCenter(find.byKey(const ValueKey('middle'))),
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

    await tester.fling(
      find.byKey(const ValueKey('middle')),
      const Offset(-120, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(steps, [1]);
    expect(scroll.offset, 540);
  });

  testWidgets('a drag draws the next page beside this one, and letting go '
      'short of the threshold puts both back', (tester) async {
    await pumpHost(tester);
    expect(find.text('page 1, 0:00'), findsNothing);

    final g = await tester.startGesture(const Offset(200, 300));
    await g.moveBy(const Offset(-20, 0));
    await g.moveBy(const Offset(-60, 0));
    await tester.pump();
    // The next page's left edge is on screen, at the right.
    final next = tester.getTopLeft(find.byKey(const ValueKey('list 1')));
    expect(next.dx, greaterThan(200));
    expect(next.dx, lessThan(400));

    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    expect(steps, isEmpty);
    expect(find.byKey(const ValueKey('list 1')), findsNothing);
  });

  testWidgets('dragging right shows the page before', (tester) async {
    await pumpHost(tester);
    final g = await tester.startGesture(const Offset(200, 300));
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('list -1')), findsOneWidget);
    expect(find.byKey(const ValueKey('list 1')), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a turn lands with the new page centred', (tester) async {
    await pumpHost(tester);
    await tester.fling(
      find.byKey(const ValueKey('middle')),
      const Offset(-120, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(steps, [1]);
    expect(tester.getTopLeft(find.text('page 1, 0:00')).dx, 0);
    expect(find.byKey(const ValueKey('list 1')), findsNothing);
    expect(find.byKey(const ValueKey('list 2')), findsNothing);
  });

  testWidgets('with no neighbour to draw it still turns', (tester) async {
    await pumpHost(tester, neighbours: false);
    await tester.fling(
      find.byKey(const ValueKey('middle')),
      const Offset(-120, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(steps, [1]);
    expect(offset(tester), 0);
  });
}
