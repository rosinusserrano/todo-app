// How a sheet arrives and leaves.
//
// The exit is the whole reason this widget exists, and it is the part that
// looks like it works when it does not: a sheet removed from the tree the
// instant its flag flips still *closes*, it just closes between two frames. So
// what is pinned here is that the child outlives the flag - and, just as
// importantly, that it does not outlive it forever, because a sheet left
// mounted keeps its controllers and its listeners alive behind an invisible
// panel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/sheet_transition.dart';

void main() {
  /// The slide this widget applies, scoped to it.
  ///
  /// Not `find.byType(FractionalTranslation).first`: the page route wrapping
  /// `home` contributes one of its own *above* this widget, and it sits at zero
  /// forever - so the unscoped finder silently measured the wrong thing and
  /// every assertion here passed by accident.
  final slide = find.descendant(
    of: find.byType(SheetTransition),
    matching: find.byType(FractionalTranslation),
  );

  /// A stand-in for a real sheet: it returns a Positioned, exactly as
  /// SettingsSheet and the others do, which is what the nested Stack is for.
  Widget host(bool open, {VoidCallback? onDispose}) => MaterialApp(
        home: Stack(
          children: [
            SheetTransition(
              open: open,
              builder: (_) => _FakeSheet(onDispose: onDispose),
            ),
          ],
        ),
      );

  testWidgets('a closed sheet is not in the tree at all', (tester) async {
    await tester.pumpWidget(host(false));
    await tester.pumpAndSettle();
    expect(find.byType(_FakeSheet), findsNothing);
  });

  testWidgets('opening puts it on screen and settles', (tester) async {
    await tester.pumpWidget(host(false));
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();

    expect(find.byType(_FakeSheet), findsOneWidget);

    // Fully arrived: no residual offset, or the panel would sit permanently
    // below where it belongs.
    final shift = tester.widget<FractionalTranslation>(slide);
    expect(shift.translation.dy, moreOrLessEquals(0, epsilon: 0.001));
  });

  testWidgets('closing keeps it mounted until the slide finishes',
      (tester) async {
    var disposed = false;
    await tester.pumpWidget(host(true, onDispose: () => disposed = true));
    await tester.pumpAndSettle();

    await tester.pumpWidget(host(false, onDispose: () => disposed = true));
    // The first pump starts the ticker and sets its epoch; only the next one
    // actually advances it. Without this the assertion below reads t = 0 and
    // would pass on a widget that never animated at all.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Mid-flight: still there, and on its way down rather than simply gone.
    expect(find.byType(_FakeSheet), findsOneWidget);
    expect(disposed, isFalse);
    final shift = tester.widget<FractionalTranslation>(slide);
    expect(shift.translation.dy, greaterThan(0));

    await tester.pumpAndSettle();

    // And then genuinely gone - not merely invisible. A sheet that stays
    // mounted keeps whatever it was listening to alive.
    expect(find.byType(_FakeSheet), findsNothing);
    expect(disposed, isTrue);
  });

  testWidgets('the child survives its own data disappearing', (tester) async {
    // The sublist sheet is built from `_sublist!`, which goes null the moment
    // it closes. The builder must not be called again on the way out, or the
    // exit animation crashes on a null.
    var built = 0;
    Widget shell(bool open) => MaterialApp(
          home: Stack(
            children: [
              SheetTransition(
                open: open,
                builder: (_) {
                  built++;
                  return const _FakeSheet();
                },
              ),
            ],
          ),
        );

    await tester.pumpWidget(shell(true));
    await tester.pumpAndSettle();
    final whileOpen = built;

    await tester.pumpWidget(shell(false));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();

    expect(built, whileOpen, reason: 'the builder must not run while closing');
  });

  testWidgets('opening already-open does not replay the entrance',
      (tester) async {
    // A rebuild with the flag already set - a hot reload, or any setState in
    // the shell - must not send the panel back down and up again.
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(true));
    await tester.pump();

    final shift = tester.widget<FractionalTranslation>(slide);
    expect(shift.translation.dy, moreOrLessEquals(0, epsilon: 0.001));
  });

  testWidgets('a closed sheet does not collapse the Stack it sits in',
      (tester) async {
    // The regression, and it shipped: a Stack sizes itself to its
    // *non-positioned* children, and the shell's Stack sits in a Scaffold
    // body, which lays out **loose**. A closed sheet returning a bare
    // SizedBox.shrink() therefore made the widest non-positioned child zero and
    // collapsed the whole window to 0x0 - the app opened blank, with only the
    // background and border still painting because those are drawn above it.
    //
    // The `Align` is what makes this test able to see it at all. The earlier
    // tests here put the Stack straight under `home:`, which hands down *tight*
    // constraints, and under tight constraints the collapse cannot happen -
    // which is exactly why they all passed while the app was broken.
    Widget shell(bool open) => MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Color(0xFF101014))),
                SheetTransition(open: open, builder: (_) => const _FakeSheet()),
              ],
            ),
          ),
        );

    await tester.pumpWidget(shell(false));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(Stack).first),
      isNot(Size.zero),
      reason: 'a closed sheet must not size the Stack',
    );

    // And it must still be out of the way once it has finished closing.
    await tester.pumpWidget(shell(true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(shell(false));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Stack).first), isNot(Size.zero));
  });

  test('the sheet timings are shared, not per-panel', () {
    // Two panels animating at different speeds is the kind of difference
    // nobody can name and everybody notices.
    expect(T.sheetDur, const Duration(milliseconds: 220));
    expect(T.sheetDur, lessThan(T.heroDur));
  });
}

class _FakeSheet extends StatefulWidget {
  const _FakeSheet({this.onDispose});

  final VoidCallback? onDispose;

  @override
  State<_FakeSheet> createState() => _FakeSheetState();
}

class _FakeSheetState extends State<_FakeSheet> {
  @override
  void dispose() {
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      top: 40,
      left: 0,
      right: 0,
      bottom: 0,
      child: ColoredBox(color: Color(0xFF202028)),
    );
  }
}
