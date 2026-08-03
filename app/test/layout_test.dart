// The adaptive layout.
//
// Two things are worth pinning here and neither is visible in a test that only
// checks a widget renders:
//
//   1. **Every feature survives every size.** The breakpoints change a view's
//      shape, never its existence - so the interesting assertions are about the
//      narrow end, where the year still has to fit twelve months and the week
//      still has to show seven days.
//   2. **The thresholds are worked backwards from contents**, so they are
//      asserted against contents: the week grid appears exactly when a day
//      column clears [Layout.minDayColumn], not at a number someone liked.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/calendar/agenda_view.dart';
import 'package:todo_widget/ui/calendar/time_grid.dart' show kGutterCompact;
import 'package:todo_widget/ui/calendar/year_view.dart';
import 'package:todo_widget/ui/workspace_bar.dart' show WorkspaceView;
import 'package:todo_widget/ui/workspace_rail.dart';

void main() {
  /// The window this app was designed against.
  const design = Layout(Size(T.designWidth, 480));

  group('the design window keeps the layout it was drawn for', () {
    test('no rail, no split - the bar and its menus, exactly as before', () {
      expect(design.hasRail, isFalse);
      expect(design.splitsContent, isFalse);
      expect(design.contentWidth, T.designWidth);
    });

    test('the calendar still works: a real week grid, single-column year', () {
      expect(design.weekGridFits, isTrue);
      expect(design.yearColumns, 1);
    });
  });

  group('the week grid appears exactly when a day column is usable', () {
    test('at the design width - which is what a phone lays out at', () {
      // An iPhone 15 is 393pt, UiScale zooms it to the 340 design width, and
      // the window frame takes two of those: this is the case the compact
      // geometry exists for, and it has to be the grid, not the list.
      expect(const Layout(Size(338, 737)).weekGridFits, isTrue);
      expect((338 - kGutterCompact) / 7,
          greaterThanOrEqualTo(Layout.minDayColumn));
    });

    test('at the width where seven columns clear the minimum', () {
      final needed = Layout.minDayColumn * 7 + kGutterCompact;
      expect(Layout(Size(needed - 1, 600)).weekGridFits, isFalse);
      expect(Layout(Size(needed + 1, 600)).weekGridFits, isTrue);
    });

    test('and the agenda still catches the narrowest window there is', () {
      // 260px is the resize floor: 34px columns, which is where a grid stops
      // being a grid. The fallback is not dead code, it is what that gets.
      expect(const Layout(Size(260, 480)).weekGridFits, isFalse);
    });
  });

  group('the year reflows down to one column', () {
    test('never zero, however narrow the window gets', () {
      // 260x200 is the smallest the window may be resized to.
      expect(const Layout(Size(260, 200)).yearColumns, 1);
      expect(const Layout(Size(120, 200)).yearColumns, 1);
    });

    test('and never so many that the tiles fall under the legible width', () {
      for (final width in [340.0, 520.0, 760.0, 1000.0, 1600.0]) {
        final columns = Layout(Size(width, 800)).yearColumns;
        final each = (width - 16 - (columns - 1) * Layout.monthTileGap) / columns;
        expect(each, greaterThanOrEqualTo(Layout.monthTileMin - 0.01),
            reason: '$width split into $columns columns of $each');
      }
    });

    test('more room means more columns', () {
      expect(const Layout(Size(340, 800)).yearColumns, 1);
      expect(const Layout(Size(600, 800)).yearColumns, greaterThan(1));
      expect(const Layout(Size(1200, 800)).yearColumns,
          greaterThan(const Layout(Size(600, 800)).yearColumns));
    });
  });

  group('the rail and the split pane', () {
    test('the rail leaves the task column at least its design width', () {
      const narrowest = Layout(Size(Layout.railMinWidth, 800));
      expect(narrowest.hasRail, isTrue);
      expect(narrowest.contentWidth, greaterThanOrEqualTo(T.designWidth));
    });

    test('a wide but short window keeps the bar', () {
      // Landscape on a phone, or the widget squashed against a taskbar: there
      // is width for a rail but no height to list anything in it.
      expect(const Layout(Size(900, 300)).hasRail, isFalse);
      expect(const Layout(Size(900, 300)).splitsContent, isFalse);
    });

    test('splitting needs more than the rail does', () {
      expect(Layout.splitMinWidth, greaterThan(Layout.railMinWidth));
      expect(const Layout(Size(700, 800)).splitsContent, isFalse);
      expect(const Layout(Size(1000, 800)).splitsContent, isTrue);
    });
  });

  group('the focus tile', () {
    test('fills a narrow window, minus its margins', () {
      expect(design.focusTileWidth, T.designWidth - Layout.focusTileMargin * 2);
    });

    test('stops growing on a wide one', () {
      expect(const Layout(Size(1600, 900)).focusTileWidth, Layout.focusTileMax);
    });
  });

  group('YearView', () {
    Widget host(double width) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 4000,
              child: YearView(
                year: 2026,
                events: const [],
                colorFor: (_) => T.accent,
                onPickDay: (_) {},
              ),
            ),
          ),
        );

    testWidgets('stacks the months in a 340px widget', (tester) async {
      tester.view.physicalSize = const Size(340, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(340));

      // All twelve are there - the narrow year is the whole year, not a
      // truncated one.
      expect(find.text('January'), findsOneWidget);
      expect(find.text('December'), findsOneWidget);

      // And they are in one column: February begins below January, not beside
      // it, which is the whole point of the reflow.
      final jan = tester.getTopLeft(find.text('January'));
      final feb = tester.getTopLeft(find.text('February'));
      expect(feb.dx, closeTo(jan.dx, 0.01));
      expect(feb.dy, greaterThan(jan.dy));
    });

    testWidgets('puts them side by side when there is room', (tester) async {
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(1000));

      final jan = tester.getTopLeft(find.text('January'));
      final feb = tester.getTopLeft(find.text('February'));
      expect(feb.dx, greaterThan(jan.dx));
      expect(feb.dy, closeTo(jan.dy, 0.01));
    });
  });

  group('AgendaView', () {
    CalendarEvent event(String title, DateTime from, DateTime to) =>
        CalendarEvent(
          uuid: title,
          calendarUuid: 'c1',
          title: title,
          startAt: reminderStamp(from),
          endAt: reminderStamp(to),
          createdAt: nowStamp(),
          updatedAt: nowStamp(),
        );

    final monday = DateTime(2026, 7, 27);
    final week = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];

    Future<void> pump(WidgetTester tester, List<CalendarEvent> events) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            height: 900,
            child: AgendaView(
              days: week,
              events: events,
              colorFor: (_) => T.accent,
              hasAttachment: (_) => false,
              taskCountFor: (_) => 0,
              onOpenEvent: (_) {},
              onCreate: (_, _) {},
              onPickDay: (_) {},
            ),
          ),
        ),
      ));
    }

    testWidgets('shows every day, empty ones included', (tester) async {
      await pump(tester, [
        event('standup', monday.add(const Duration(hours: 9)),
            monday.add(const Duration(hours: 10))),
      ]);

      // Which days are free is half of what a week view is for, so an empty
      // day still gets a line rather than being skipped.
      expect(find.text('Mon 27'), findsOneWidget);
      expect(find.text('Sun 2'), findsOneWidget);
      expect(find.text('free'), findsNWidgets(6));
      expect(find.text('09:00\n10:00'), findsOneWidget);
    });

    testWidgets('an event across midnight lands on both days', (tester) async {
      await pump(tester, [
        event('long night', monday.add(const Duration(hours: 22)),
            monday.add(const Duration(hours: 26))),
      ]);

      // A list keyed on the start time would drop it from Tuesday, which is
      // the day you would be looking at when it matters.
      expect(find.text('long night'), findsNWidgets(2));
      expect(find.text('til 02:00'), findsOneWidget);
    });

    testWidgets('an event ending at midnight belongs to the day it ran on',
        (tester) async {
      await pump(tester, [
        event('evening', monday.add(const Duration(hours: 20)),
            monday.add(const Duration(hours: 24))),
      ]);
      expect(find.text('evening'), findsOneWidget);
    });

    testWidgets('creating is still reachable with no grid to drag on',
        (tester) async {
      DateTime? created;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            height: 900,
            child: AgendaView(
              days: week,
              events: const [],
              colorFor: (_) => T.accent,
              hasAttachment: (_) => false,
              taskCountFor: (_) => 0,
              onOpenEvent: (_) {},
              onCreate: (start, _) => created = start,
              onPickDay: (_) {},
            ),
          ),
        ),
      ));

      await tester.tap(find.byIcon(Icons.add).first);
      expect(created, monday.add(const Duration(hours: 9)));
    });
  });

  group('WorkspaceRail', () {
    Workspace ws(String uuid, String name) => Workspace(
          uuid: uuid,
          name: name,
          color: '#6c8cff',
          sortOrder: 0,
          createdAt: nowStamp(),
          updatedAt: nowStamp(),
        );

    Future<void> pump(
      WidgetTester tester, {
      WorkspaceView? open,
      void Function(Workspace)? onSelect,
      void Function(Workspace)? onEdit,
      VoidCallback? onShowTasks,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            WorkspaceRail(
              workspaces: [ws('w1', 'Home'), ws('w2', 'Work')],
              currentUuid: 'w1',
              accent: T.accent,
              onSelect: onSelect ?? (_) {},
              onEdit: onEdit ?? (_) {},
              onCreate: () {},
              onShowTasks: onShowTasks ?? () {},
              onOpenNotes: () {},
              onOpenParked: () {},
              onOpenHistory: () {},
              onOpenThoughts: () {},
              thoughtCount: 0,
              parkedReviewDue: false,
              openView: open,
            ),
          ]),
        ),
      ));
    }

    testWidgets('every workspace and every view is on screen', (tester) async {
      await pump(tester);
      // The point of the rail: nothing behind a menu press.
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Parked'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
    });

    testWidgets('tapping another workspace switches, tapping yours edits',
        (tester) async {
      final selected = <String>[];
      final edited = <String>[];
      await pump(
        tester,
        onSelect: (w) => selected.add(w.name),
        onEdit: (w) => edited.add(w.name),
      );

      await tester.tap(find.text('Work'));
      expect(selected, ['Work']);
      expect(edited, isEmpty);

      // Carried over from the tab, where the name was always the edit control.
      await tester.tap(find.text('Home'));
      expect(edited, ['Home']);
    });

    testWidgets('Tasks is a destination, not just the absence of one',
        (tester) async {
      var back = 0;
      await pump(tester, open: WorkspaceView.history, onShowTasks: () => back++);

      await tester.tap(find.text('Tasks'));
      expect(back, 1);
    });
  });
}
