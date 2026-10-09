// The bottom view bar, and the swipe that shares its order.
//
// Two things are worth pinning. The bar and the swipe are two offers of one
// navigation, so they have to walk the same list - if they ever disagree about
// what is next to what, a swipe lands somewhere the bar says is elsewhere. And
// the ends of that list must not wrap: a strip of four with no first and last
// is one you cannot tell your position in.
//
// It is also the whole side-thought control on a phone: the pile is its fourth
// entry, a swipe up on it writes a thought, and the hint saying so shows only
// while the pile is open.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/layout.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/view_bar.dart';
import 'package:todo_widget/ui/workspace_bar.dart';

void main() {
  Widget bar(
    WorkspaceView? open, {
    required ValueChanged<WorkspaceView?> onSelect,
    bool parkedReviewDue = false,
    int thoughtCount = 0,
    VoidCallback? onSwipeUp,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: LayoutScope(
            layout: const Layout(Size(T.designWidth, 600), touch: true),
            child: Column(
              children: [
                const Spacer(),
                ViewBar(
                  accent: T.accent,
                  openView: open,
                  onSelect: onSelect,
                  parkedReviewDue: parkedReviewDue,
                  thoughtCount: thoughtCount,
                  onSwipeUp: onSwipeUp,
                ),
              ],
            ),
          ),
        ),
      );

  test('Tasks is first, and the order is the swipe order', () {
    // Null is Tasks, and it leads: it is the one you come back to.
    expect(kBarViews.first, isNull);
    expect(kBarViews, [
      null,
      WorkspaceView.notes,
      WorkspaceView.parked,
      WorkspaceView.thoughts,
    ]);
  });

  test('History is not on the bar - it lives in settings on a phone', () {
    expect(kBarViews.contains(WorkspaceView.history), isFalse);
  });

  testWidgets('every view is one tap away and says which it is',
      (tester) async {
    final picked = <WorkspaceView?>[];
    await tester.pumpWidget(bar(null, onSelect: picked.add));
    await tester.pumpAndSettle();

    for (final label in ['Tasks', 'Notes', 'Parked', 'Thoughts']) {
      expect(find.text(label), findsOneWidget, reason: '$label is missing');
    }

    await tester.tap(find.text('Notes'));
    await tester.tap(find.text('Thoughts'));
    await tester.pumpAndSettle();
    expect(picked, [WorkspaceView.notes, WorkspaceView.thoughts]);
  });

  testWidgets('Tasks is an entry, not just the absence of a selection',
      (tester) async {
    // The way back has to be as visible as the way in - otherwise leaving a
    // view is something you have to know rather than something you can see.
    final picked = <WorkspaceView?>[];
    await tester.pumpWidget(
      bar(WorkspaceView.thoughts, onSelect: picked.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(picked, [null]);
  });

  testWidgets('the entries are a fingertip tall', (tester) async {
    await tester.pumpWidget(bar(null, onSelect: (_) {}));
    await tester.pumpAndSettle();

    final box = tester.getSize(
      find.ancestor(
        of: find.text('Parked'),
        matching: find.byType(SizedBox),
      ).first,
    );
    expect(box.height, greaterThanOrEqualTo(Layout.touchTargetSide));
  });

  testWidgets('a due parked review shows without opening anything',
      (tester) async {
    // The panel is closed most of the time, so this dot is the only thing that
    // ever says a shelf has gone stale.
    await tester.pumpWidget(bar(null, onSelect: (_) {}));
    await tester.pumpAndSettle();
    final quiet = tester.widgetList(find.byType(Container)).length;

    await tester.pumpWidget(
      bar(null, onSelect: (_) {}, parkedReviewDue: true),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widgetList(find.byType(Container)).length,
      greaterThan(quiet),
      reason: 'the dot should add a marker to the Parked entry',
    );
  });

  testWidgets('a swipe up on the bar writes a thought; a tap does not',
      (tester) async {
    var swiped = 0;
    final picked = <WorkspaceView?>[];
    await tester.pumpWidget(
      bar(null, onSelect: picked.add, onSwipeUp: () => swiped++),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('Notes'), const Offset(0, -40));
    await tester.pumpAndSettle();
    expect(swiped, 1);
    expect(picked, isEmpty, reason: 'a swipe is not also a tap');

    // A slow nudge past the drag slop is not a swipe: the bar drops back and
    // nothing opens. (Anything shorter than the slop is a tap, as it should be.)
    await tester.timedDrag(
      find.text('Notes'),
      const Offset(0, -26),
      const Duration(milliseconds: 800),
    );
    await tester.pumpAndSettle();
    expect(swiped, 1);
    expect(picked, isEmpty);

    await tester.tap(find.text('Parked'));
    await tester.pumpAndSettle();
    expect(swiped, 1);
    expect(picked, [WorkspaceView.parked]);
  });

  testWidgets('the hint shows only while the pile is open', (tester) async {
    await tester.pumpWidget(bar(null, onSelect: (_) {}, onSwipeUp: () {}));
    await tester.pumpAndSettle();
    expect(find.text(ViewBar.swipeHint), findsNothing);

    await tester.pumpWidget(
      bar(WorkspaceView.thoughts, onSelect: (_) {}, onSwipeUp: () {}),
    );
    await tester.pumpAndSettle();
    expect(find.text(ViewBar.swipeHint), findsOneWidget);
  });

  testWidgets('the pile\'s count rides on its entry, and a full pile pulses',
      (tester) async {
    await tester.pumpWidget(bar(null, onSelect: (_) {}, thoughtCount: 2));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse,
        reason: 'two thoughts tint the bar but do not pulse yet');

    await tester.pumpWidget(bar(null, onSelect: (_) {}, thoughtCount: 9));
    await tester.pump();
    expect(find.text('9'), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);
  });
}
