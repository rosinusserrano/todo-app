// The movable boundary between the task list and whatever sits beside it.
//
// What is pinned: a drag reports a fraction, a drag past the left edge folds
// the list rather than squeezing it, a double-click goes back to the default,
// and folding does not rebuild the pane on the right - that last one is what
// keeps a calendar's scroll or a note's editor alive through the gesture that
// was meant to give it room.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/ui/split_pane.dart';

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => setState(() => n++),
        child: Text('right $n'),
      );
}

void main() {
  const size = Size(1000, 600);

  Future<void> pump(
    WidgetTester tester, {
    double? fraction,
    bool collapsed = false,
    ValueChanged<double?>? onFraction,
    ValueChanged<bool>? onCollapsed,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SplitPane(
          left: const Text('left'),
          right: const _Counter(),
          fraction: fraction,
          defaultLeft: (w) => w / 2,
          collapsed: collapsed,
          onFraction: onFraction ?? (_) {},
          onCollapsed: onCollapsed ?? (_) {},
        ),
      ),
    ));
  }

  Finder handle() => find.byKey(const ValueKey('split-handle'));

  testWidgets('starts at the default and follows a stored fraction',
      (tester) async {
    await pump(tester);
    expect(tester.getSize(find.byKey(const ValueKey('split-left'))).width, 500);

    await pump(tester, fraction: 0.3);
    expect(tester.getSize(find.byKey(const ValueKey('split-left'))).width, 300);
  });

  testWidgets('a drag reports where the boundary was let go', (tester) async {
    double? reported;
    await pump(tester, onFraction: (f) => reported = f);

    await tester.timedDrag(
        handle(), const Offset(200, 0), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(reported, isNotNull);
    expect(reported!, closeTo(0.7, 0.02));
  });

  testWidgets('a drag past the left edge folds the pane instead',
      (tester) async {
    bool? folded;
    double? reported;
    await pump(tester,
        onCollapsed: (c) => folded = c, onFraction: (f) => reported = f);

    await tester.timedDrag(
        handle(), const Offset(-480, 0), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(folded, isTrue);
    expect(reported, isNull, reason: 'the chosen position is kept for later');
  });

  testWidgets('double-click goes back to the default', (tester) async {
    var reset = false;
    await pump(tester, fraction: 0.3, onFraction: (f) => reset = f == null);

    final at = tester.getCenter(handle());
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(reset, isTrue);
  });

  testWidgets('folded, the strip brings the pane back', (tester) async {
    bool? folded;
    await pump(tester, collapsed: true, onCollapsed: (c) => folded = c);

    expect(find.text('left'), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('split-left'))).width,
        SplitPane.collapsedWidth);
    await tester.tap(find.byTooltip('Show the task list'));
    expect(folded, isFalse);
  });

  testWidgets('folding does not rebuild the right pane', (tester) async {
    var collapsed = false;
    late StateSetter set;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setter) {
          set = setter;
          return SplitPane(
            left: const Text('left'),
            right: const _Counter(),
            fraction: null,
            defaultLeft: (w) => w / 2,
            collapsed: collapsed,
            onFraction: (_) {},
            onCollapsed: (_) {},
          );
        }),
      ),
    ));

    await tester.tap(find.text('right 0'));
    await tester.pump();
    set(() => collapsed = true);
    await tester.pumpAndSettle();

    expect(find.text('right 1'), findsOneWidget);
  });
}
