import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/ui/dock.dart';

void main() {
  late List<String> fired;

  DockItem item(String name, {bool second = false}) => DockItem(
    label: name,
    onChoose: () => fired.add(name),
    secondaryIcon: second ? Icons.edit : null,
    secondaryLabel: second ? 'Edit $name' : null,
    onSecondary: second ? () => fired.add('edit $name') : null,
  );

  Future<void> pump(WidgetTester tester) async {
    fired = [];
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              Dock(
                segments: [
                  DockSegment(
                    label: 'Work',
                    fill: Colors.blue,
                    ink: Colors.black,
                    items: [item('Home', second: true), item('Work', second: true)],
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
                    width: 56,
                    fill: Colors.white,
                    ink: Colors.black,
                    items: [item('Add a task'), item('Add a thought')],
                  ),
                ],
              ),
            ],
          ),
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
    expect(find.text('Home'), findsOneWidget);

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

  testWidgets('a tap leaves the menu open for a second tap', (tester) async {
    await pump(tester);
    await tester.tapAt(const Offset(200, barY));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsOneWidget);

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(fired, ['Notes']);
    expect(find.text('Notes'), findsNothing);
  });

  testWidgets('tapping the open segment again closes it', (tester) async {
    await pump(tester);
    await tester.tapAt(const Offset(200, barY));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, barY));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsNothing);
    expect(fired, isEmpty);
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

  testWidgets('a fixed-width segment is found by the slide, and its menu fits', (
    tester,
  ) async {
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
  });
}
