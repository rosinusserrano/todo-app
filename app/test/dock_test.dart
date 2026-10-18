import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/ui/dock.dart';

void main() {
  late List<String> fired;

  DockItem item(
    String name, {
    bool second = false,
    List<String> children = const [],
  }) => DockItem(
    label: name,
    onChoose: () => fired.add(name),
    secondaryIcon: second ? Icons.edit : null,
    secondaryLabel: second ? 'Edit $name' : null,
    onSecondary: second ? () => fired.add('edit $name') : null,
    children: [for (final c in children) item(c)],
  );

  Future<void> pump(
    WidgetTester tester, {
    DockEdge edge = DockEdge.bottom,
  }) async {
    fired = [];
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dock = Dock(
      edge: edge,
      segments: [
        DockSegment(
          label: 'Work',
          onClick: () => fired.add('click Work'),
          fill: Colors.blue,
          ink: Colors.black,
          items: [
            item(
              'Home',
              second: true,
              children: ['Home notes', 'Home history'],
            ),
            item('Work', second: true),
          ],
        ),
        DockSegment(
          label: 'Tasks',
          fill: Colors.grey,
          ink: Colors.white,
          items: [item('Notes'), item('Tasks')],
        ),
        DockSegment(
          label: 'More',
          fill: Colors.black,
          ink: Colors.white,
          items: [item('Calendar')],
        ),
        DockSegment(
          label: '',
          icon: Icons.add,
          extent: 56,
          fill: Colors.white,
          ink: Colors.black,
          items: [item('Add a task'), item('Add a thought')],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: switch (edge) {
            DockEdge.bottom => Column(
              children: [
                const Expanded(child: SizedBox()),
                dock,
              ],
            ),
            DockEdge.top => Column(
              children: [
                dock,
                const Expanded(child: SizedBox()),
              ],
            ),
            DockEdge.left => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                dock,
                const Expanded(child: SizedBox()),
              ],
            ),
          },
        ),
      ),
    );
  }

  // The bar is 48 tall at the bottom of an 800 screen. The last segment is a
  // fixed 56 wide and the other three share the remaining 344 (~115 each). Menu rows are Dock.rowHeight tall, stacked up from the bar's top.
  const barY = 800 - 24.0;
  Offset rowCentre(int fromBottom, {double x = 60}) =>
      Offset(x, 800 - 48 - Dock.rowHeight * (fromBottom + 0.5));

  testWidgets('press, slide up to a row, let go: that row is chosen', (
    tester,
  ) async {
    await pump(tester);
    final g = await tester.startGesture(const Offset(60, barY));
    await tester.pump();
    expect(find.text('Home'), findsNothing, reason: 'it may yet be a tap');

    await g.moveTo(rowCentre(1)); // Home: the top of two rows
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(fired, ['Home']);
    expect(find.text('Home'), findsNothing, reason: 'the menu closes');
  });

  testWidgets('letting go off the menu chooses nothing', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(const Offset(60, barY));
    await tester.pump();
    await g.moveTo(const Offset(60, 100)); // far above the menu
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(fired, isEmpty);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('sliding right onto a row\'s end is its second action', (
    tester,
  ) async {
    await pump(tester);
    final g = await tester.startGesture(const Offset(60, barY));
    await tester.pump();
    await g.moveTo(rowCentre(0));
    await tester.pump();
    // The menu is Dock.menuMinWidth wide from the left edge.
    await g.moveTo(rowCentre(0, x: Dock.menuMinWidth - 10));
    await tester.pump();
    expect(find.text('Edit Work'), findsOneWidget, reason: 'the row says so');
    await g.up();
    await tester.pumpAndSettle();

    expect(fired, ['edit Work']);
  });

  testWidgets('a short tap is the segment\'s own action, not its menu', (
    tester,
  ) async {
    await pump(tester);
    await tester.tapAt(const Offset(60, barY));
    await tester.pumpAndSettle();
    expect(fired, ['click Work']);
    expect(find.text('Home'), findsNothing, reason: 'no menu left standing');
  });

  testWidgets('a short tap on a segment with no action opens its menu, and '
      'a second puts it away', (tester) async {
    await pump(tester);
    await tester.tapAt(const Offset(200, barY));
    await tester.pumpAndSettle();
    expect(fired, isEmpty);
    expect(find.text('Notes'), findsOneWidget);

    await tester.tapAt(const Offset(200, barY));
    await tester.pumpAndSettle();
    expect(fired, isEmpty);
    expect(find.text('Notes'), findsNothing);
  });

  testWidgets('a tap shows no menu on its way to the action', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(const Offset(60, barY));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Home'), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
    expect(fired, ['click Work']);
  });

  testWidgets('a tap on a menu another tap opened goes to its own action', (
    tester,
  ) async {
    await pump(tester);
    await tester.tapAt(const Offset(200, barY));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsOneWidget);
    await tester.tapAt(const Offset(60, barY));
    await tester.pumpAndSettle();
    expect(fired, ['click Work']);
    expect(find.text('Notes'), findsNothing);
  });

  testWidgets('holding still and letting go leaves the menu up for a tap', (
    tester,
  ) async {
    await pump(tester);
    final g = await tester.startGesture(const Offset(60, barY));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await g.up();
    await tester.pumpAndSettle();
    expect(fired, isEmpty, reason: 'a hold is not a tap');
    expect(find.text('Home'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(fired, ['Home']);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('sliding along the bar switches menus', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(const Offset(60, barY));
    await tester.pump();
    await g.moveTo(const Offset(290, barY));
    await tester.pump();
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Home'), findsNothing);

    await g.moveTo(rowCentre(0, x: 300));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(fired, ['Calendar']);
  });

  testWidgets(
    'a fixed-width segment is found by the slide, and its menu fits',
    (tester) async {
      await pump(tester);
      final g = await tester.startGesture(const Offset(60, barY));
      await tester.pump();
      await g.moveTo(const Offset(380, barY));
      await tester.pump();
      expect(find.text('Add a thought'), findsOneWidget);

      // The menu is wider than its segment and kept inside the bar, so its
      // rows reach well left of the segment itself.
      await g.moveTo(rowCentre(0, x: 250));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(fired, ['Add a thought']);
    },
  );

  group('along the top', () {
    testWidgets('the menu grows down, nearest row first', (tester) async {
      await pump(tester, edge: DockEdge.top);
      final g = await tester.startGesture(const Offset(60, 24));
      await tester.pump();
      // Under a bottom bar Work is the row nearest the bar, and it still is.
      await g.moveTo(Offset(60, 48 + Dock.rowHeight * 0.5));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(fired, ['Work']);
    });
  });

  group('down the side', () {
    // 800 tall: the ＋ is 56 at the foot, the three places share 744.
    testWidgets('the menu opens to the right, level with its segment', (
      tester,
    ) async {
      await pump(tester, edge: DockEdge.left);
      final g = await tester.startGesture(const Offset(24, 100));
      await tester.pump();
      await g.moveTo(Offset(150, Dock.rowHeight * 0.5));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(fired, ['Home']);
    });

    testWidgets('sliding down the bar switches menus, and one at the foot '
        'stays on screen', (tester) async {
      await pump(tester, edge: DockEdge.left);
      final g = await tester.startGesture(const Offset(24, 100));
      await tester.pump();
      await g.moveTo(const Offset(24, 780));
      await tester.pump();
      expect(find.text('Add a thought'), findsOneWidget);
      // Two rows, moved up to end at the screen's foot.
      await g.moveTo(Offset(150, 800 - Dock.rowHeight * 0.5));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(fired, ['Add a thought']);
    });

    testWidgets('a label stands up', (tester) async {
      await pump(tester, edge: DockEdge.left);
      final label = find.ancestor(
        of: find.text('Work').first,
        matching: find.byType(RotatedBox),
      );
      expect(tester.widget<RotatedBox>(label.first).quarterTurns, 1);
    });
  });
  group('with a mouse', () {
    Future<TestGesture> mouse(WidgetTester tester) async {
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: const Offset(200, 100));
      addTearDown(g.removePointer);
      return g;
    }

    testWidgets('resting on a segment opens its menu, leaving closes it', (
      tester,
    ) async {
      await pump(tester);
      final g = await mouse(tester);
      await g.moveTo(const Offset(60, barY));
      await tester.pump();
      expect(find.text('Home'), findsNothing, reason: 'not on the way past');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);

      // Into the menu: it stays, and a click there chooses.
      await g.moveTo(rowCentre(0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Home'), findsOneWidget);

      // Away from both: it goes.
      await g.moveTo(const Offset(300, 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsNothing);
      expect(fired, isEmpty);
    });

    testWidgets('crossing the bar quickly opens nothing', (tester) async {
      await pump(tester);
      final g = await mouse(tester);
      await g.moveTo(const Offset(60, barY));
      await tester.pump(const Duration(milliseconds: 50));
      await g.moveTo(const Offset(60, 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Home'), findsNothing);
    });

    testWidgets('moving along the bar switches at once, and a click on a '
        'row chooses it', (tester) async {
      await pump(tester);
      final g = await mouse(tester);
      await g.moveTo(const Offset(60, barY));
      await tester.pump(const Duration(milliseconds: 200));
      await g.moveTo(const Offset(290, barY));
      await tester.pump();
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Home'), findsNothing);

      await g.moveTo(rowCentre(0, x: 300));
      await tester.pumpAndSettle();
      await g.down(rowCentre(0, x: 300));
      await g.up();
      await tester.pumpAndSettle();
      expect(fired, ['Calendar']);
      expect(find.text('Calendar'), findsNothing);
    });

    testWidgets('a click on a segment with its own action does that', (
      tester,
    ) async {
      await pump(tester);
      final g = await mouse(tester);
      await g.moveTo(const Offset(60, barY));
      await tester.pump(const Duration(milliseconds: 200));
      await g.down(const Offset(60, barY));
      await g.up();
      await tester.pumpAndSettle();
      expect(fired, ['click Work']);
      expect(find.text('Home'), findsNothing, reason: 'the menu closes');
    });

    testWidgets('a click on a hovered segment with no action leaves the '
        'menu to the hover', (tester) async {
      await pump(tester);
      final g = await mouse(tester);
      await g.moveTo(const Offset(200, barY));
      await tester.pump(const Duration(milliseconds: 200));
      await g.down(const Offset(200, barY));
      await g.up();
      await tester.pumpAndSettle();
      expect(fired, isEmpty);
      expect(find.text('Notes'), findsOneWidget, reason: 'not closed');

      await g.moveTo(const Offset(300, 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Notes'), findsNothing, reason: 'not pinned either');
    });
  });

  group('a submenu', () {
    // The menu is 220 wide from the left; a 190-wide submenu does not fit
    // either side of it on a 400 screen, so it sits against the right edge,
    // level with Home: Home notes beside Home, Home history beside Work.
    const subX = 300.0;

    testWidgets('a held finger staying on a row opens it; slide across and '
        'let go', (tester) async {
      await pump(tester);
      final g = await tester.startGesture(const Offset(60, barY));
      await tester.pump();
      await g.moveTo(rowCentre(1));
      await tester.pump();
      expect(find.text('Home notes'), findsNothing, reason: 'not yet');
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Home notes'), findsOneWidget);

      await g.moveTo(rowCentre(0, x: subX));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(fired, ['Home history']);
    });

    testWidgets('sliding through a row quickly opens nothing', (tester) async {
      await pump(tester);
      final g = await tester.startGesture(const Offset(60, barY));
      await tester.pump();
      await g.moveTo(rowCentre(1));
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveTo(rowCentre(0));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Home notes'), findsNothing);
      await g.up();
      await tester.pumpAndSettle();
      expect(fired, ['Work']);
    });

    testWidgets('a long press in a held-open menu opens it', (tester) async {
      await pump(tester);
      final g = await tester.startGesture(const Offset(60, barY));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await g.up();
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home notes'));
      await tester.pumpAndSettle();
      expect(fired, ['Home notes']);
    });

    testWidgets('a mouse resting on the row opens it, and it stays while the '
        'mouse goes over', (tester) async {
      await pump(tester);
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: const Offset(200, 100));
      addTearDown(g.removePointer);
      await g.moveTo(const Offset(60, barY));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await g.moveTo(rowCentre(1));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Home history'), findsOneWidget);

      await g.moveTo(rowCentre(0, x: subX));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Home history'), findsOneWidget);
      await tester.tapAt(rowCentre(0, x: subX), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(fired, ['Home history']);
    });
  });
}
