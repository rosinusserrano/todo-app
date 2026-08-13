// The bottom view bar, and the swipe that shares its order.
//
// Two things are worth pinning. The bar and the swipe are two offers of one
// navigation, so they have to walk the same list - if they ever disagree about
// what is next to what, a swipe lands somewhere the bar says is elsewhere. And
// the ends of that list must not wrap: a strip of four with no first and last
// is one you cannot tell your position in.

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
      WorkspaceView.history,
    ]);
  });

  test('side thoughts are deliberately not on the bar', () {
    // The pile is global rather than per-workspace, and its way in is the
    // count on the footer directly below - which also says how full it is.
    expect(kBarViews.contains(WorkspaceView.thoughts), isFalse);
  });

  testWidgets('every view is one tap away and says which it is',
      (tester) async {
    final picked = <WorkspaceView?>[];
    await tester.pumpWidget(bar(null, onSelect: picked.add));
    await tester.pumpAndSettle();

    for (final label in ['Tasks', 'Notes', 'Parked', 'History']) {
      expect(find.text(label), findsOneWidget, reason: '$label is missing');
    }

    await tester.tap(find.text('Notes'));
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(picked, [WorkspaceView.notes, WorkspaceView.history]);
  });

  testWidgets('Tasks is an entry, not just the absence of a selection',
      (tester) async {
    // The way back has to be as visible as the way in - otherwise leaving a
    // view is something you have to know rather than something you can see.
    final picked = <WorkspaceView?>[];
    await tester.pumpWidget(
      bar(WorkspaceView.history, onSelect: picked.add),
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
}
