// Picking a quick-add block up and putting it somewhere else.
//
// The gesture this replaces was a long-press-*drag* that fed the block vertical
// deltas, and it was wrong twice over: a block could only ever move inside its
// own column - so putting Tuesday's block on Wednesday meant deleting it and
// placing it again - and it was re-laid-out on every update, so what followed
// the finger was a block being rebuilt underneath it rather than a thing being
// carried.
//
// What is pinned here is the part a screenshot cannot show: where a block
// *lands*. The drop is resolved from the top-left corner of the ghost, which is
// what the user is aiming with, and the day is resolved from the column that
// corner is over - the whole point of the change.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/calendar/time_grid.dart';

void main() {
  final monday = DateTime(2026, 8, 17);
  final week = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];

  /// A week grid holding one pending block on Monday at 09:00.
  Widget grid({
    required List<({DateTime start, DateTime end})> pending,
    required void Function(int, DateTime, DateTime) onAdjust,
    void Function(int)? onStep,
    void Function(int)? onRemove,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: TimeGridView(
            days: week,
            events: const [],
            colorFor: (_) => T.accent,
            hasAttachment: (_) => false,
            taskCountFor: (_) => 0,
            onOpenEvent: (_) {},
            onEventMenu: (_, _) {},
            onCreate: (_, _) {},
            blockTitle: 'Work',
            blockColor: T.accent,
            pending: pending,
            onPlacePending: (_, _) {},
            onAdjustPending: onAdjust,
            onRemovePending: onRemove,
            onStep: onStep,
          ),
        ),
      );

  ({DateTime start, DateTime end}) block(DateTime at) =>
      (start: at, end: at.add(const Duration(hours: 1)));

  /// Long-press the block, carry it to [to], and let go.
  Future<void> lift(WidgetTester tester, Offset from, Offset to) async {
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(to);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a lifted block lands on the day it is dropped on',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final moved = <(int, DateTime, DateTime)>[];
    final at9 = monday.add(const Duration(hours: 9));

    await tester.pumpWidget(grid(
      pending: [block(at9)],
      onAdjust: (i, s, e) => moved.add((i, s, e)),
    ));
    // No scrolling needed: the grid opens on the working day, so 09:00 is
    // already on screen.
    await tester.pumpAndSettle();

    final start = tester.getCenter(find.byType(TimeGridView));
    final gridBox = tester.getRect(find.byType(TimeGridView));
    final blockAt = tester.getTopLeft(find.text('Work'));

    // Two columns to the right, and a little further down.
    final columnWidth = (gridBox.width - kGutter) / week.length;
    await lift(
      tester,
      blockAt + const Offset(6, 6),
      blockAt + Offset(columnWidth * 2 + 6, 6),
    );

    expect(moved, hasLength(1));
    final (index, newStart, newEnd) = moved.single;
    expect(index, 0);
    expect(newStart.day, 19, reason: 'two columns right of Monday is Wednesday');
    // The length travels with it - a move is not a resize.
    expect(newEnd.difference(newStart), const Duration(hours: 1));
    expect(start, isNotNull);
  });

  testWidgets('the day is kept when the block only moves down', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final moved = <(int, DateTime, DateTime)>[];
    final at9 = monday.add(const Duration(hours: 9));

    await tester.pumpWidget(grid(
      pending: [block(at9)],
      onAdjust: (i, s, e) => moved.add((i, s, e)),
    ));
    await tester.pumpAndSettle();

    final blockAt = tester.getTopLeft(find.text('Work'));
    // kHourHeight is the height of one hour, so this is two hours down.
    await lift(
      tester,
      blockAt + const Offset(6, 6),
      blockAt + Offset(6, kHourHeight * 2 + 6),
    );

    expect(moved, hasLength(1));
    final (_, newStart, _) = moved.single;
    expect(newStart.day, 17, reason: 'straight down stays on Monday');
    expect(newStart.hour, 11);
  });

  testWidgets('holding it against an edge steps the grid', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final steps = <int>[];
    final at9 = monday.add(const Duration(hours: 9));

    await tester.pumpWidget(grid(
      pending: [block(at9)],
      onAdjust: (_, _, _) {},
      onStep: steps.add,
    ));
    await tester.pumpAndSettle();

    final gridBox = tester.getRect(find.byType(TimeGridView));
    final blockAt = tester.getTopLeft(find.text('Work'));

    final gesture = await tester.startGesture(blockAt + const Offset(6, 6));
    await tester.pump(const Duration(milliseconds: 600));
    // Out into the middle first. A block in the first column starts its own
    // drag inside the left-hand zone, so the zones only arm once the block has
    // been somewhere that is not an edge - otherwise picking Monday up to move
    // it two hours down would step back a week before the finger moved.
    await gesture.moveTo(Offset(gridBox.center.dx, blockAt.dy + 6));
    await tester.pump(const Duration(milliseconds: 50));
    expect(steps, isEmpty);

    // Then held hard against the right-hand edge.
    await gesture.moveTo(Offset(gridBox.right - 6, blockAt.dy + 6));
    await tester.pump(const Duration(milliseconds: 50));

    // The first step is immediate: waiting for the timer's first beat before
    // acknowledging the edge reads as nothing happening.
    expect(steps, [1]);

    // And it repeats while the block stays there.
    await tester.pump(kEdgeStepInterval);
    await tester.pump(kEdgeStepInterval);
    expect(steps.length, greaterThan(1));
    expect(steps.every((s) => s == 1), isTrue);

    // Letting go stops it, and nothing keeps firing afterwards.
    await gesture.up();
    await tester.pumpAndSettle();
    final settled = steps.length;
    await tester.pump(kEdgeStepInterval * 3);
    expect(steps.length, settled);
  });

  testWidgets('a block in the middle of the grid steps nothing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final steps = <int>[];
    final at9 = monday.add(const Duration(hours: 9));

    await tester.pumpWidget(grid(
      pending: [block(at9)],
      onAdjust: (_, _, _) {},
      onStep: steps.add,
    ));
    await tester.pumpAndSettle();

    final blockAt = tester.getTopLeft(find.text('Work'));
    await lift(tester, blockAt + const Offset(6, 6),
        blockAt + const Offset(180, 40));

    expect(steps, isEmpty);
  });

  testWidgets('a tap still takes a block back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final removed = <int>[];
    final at9 = monday.add(const Duration(hours: 9));

    await tester.pumpWidget(grid(
      pending: [block(at9)],
      onAdjust: (_, _, _) {},
      onRemove: removed.add,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    // Nothing is written yet, so a mis-tap costs one tap to put back - which is
    // why removing is the cheap gesture and moving is the deliberate one.
    expect(removed, [0]);
  });
}
