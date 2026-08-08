// The shared month grid, and the exact date/time picker built on it.
//
// The grid's tests are about arithmetic rather than looks: where the 1st falls
// and how many rows a month gets are the two things the year view and the
// picker must never disagree about, and they are the reason the widget is
// shared at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/ui/month_grid.dart';
import 'package:todo_widget/ui/reminder_picker.dart';

/// The cells a [MonthGrid] laid out, blanks included.
List<Widget> _cells(WidgetTester tester) {
  final grid = tester.widget<GridView>(find.byType(GridView));
  return (grid.childrenDelegate as SliverChildListDelegate).children;
}

/// Width-constrained: at the full 800px test viewport seven columns are 114px
/// wide, and six rows of them are taller than the screen.
Future<void> _pumpMonth(WidgetTester tester, int year, int month) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: MonthGrid(
              year: year,
              month: month,
              dayBuilder: (d) =>
                  Text('${d.day}', key: ValueKey('day-${d.day}')),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('MonthGrid', () {
    testWidgets('the 1st sits in the column its weekday falls in', (
      tester,
    ) async {
      // Monday-based, matching the week view - a picker that disagreed with the
      // year view about this would be a bug nobody thinks to look for.
      for (final m in [
        DateTime(2026, 8), // starts Saturday
        DateTime(2026, 2), // starts Sunday, and a non-leap February
        DateTime(2027, 3), // starts Monday - the no-blanks edge
        DateTime(2028, 2), // leap February
      ]) {
        await _pumpMonth(tester, m.year, m.month);
        final leading = DateTime(m.year, m.month).weekday - 1;
        final cells = _cells(tester);

        expect(
          cells[leading].key,
          const ValueKey('day-1'),
          reason: '${m.year}-${m.month} puts the 1st in the wrong column',
        );
        // Everything before it is a blank, not a day.
        for (var i = 0; i < leading; i++) {
          expect(cells[i].key, isNull);
        }
      }
    });

    testWidgets('every month is six week rows, however short', (tester) async {
      for (final m in [DateTime(2026, 2), DateTime(2026, 8), DateTime(2027, 3)]) {
        await _pumpMonth(tester, m.year, m.month);
        expect(_cells(tester).length, kMonthWeekRows * 7);
      }
    });

    testWidgets('every day of the month is drawn, and no more', (tester) async {
      await _pumpMonth(tester, 2028, 2);
      // 2028 is a leap year: the 29th exists and the 30th does not.
      expect(find.byKey(const ValueKey('day-29')), findsOneWidget);
      expect(find.byKey(const ValueKey('day-30')), findsNothing);
    });
  });

  group('the reminder picker', () {
    /// A month far enough out that nothing picked inside it can be in the past,
    /// at 09:00 so that the hour box cannot collide with a day number.
    DateTime futureMonth() {
      final ahead = DateTime.now().add(const Duration(days: 45));
      return DateTime(ahead.year, ahead.month, 1, 9);
    }

    /// Opens the picker over a host button. The result lands in the returned
    /// list once the dialog closes - it cannot be a return value, because the
    /// dialog is still open when this future completes.
    Future<List<DateTime?>> open(
      WidgetTester tester, {
      required DateTime initial,
    }) async {
      final out = <DateTime?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  out.add(await showReminderPicker(context, initial: initial)),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return out;
    }

    testWidgets('returns the day and time chosen', (tester) async {
      final initial = futureMonth();
      final out = await open(tester, initial: initial);

      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('18:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('18:00'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set'));
      await tester.pumpAndSettle();

      expect(out.single, DateTime(initial.year, initial.month, 15, 18));
    });

    testWidgets('dismissing reports nothing rather than a default',
        (tester) async {
      final out = await open(tester, initial: futureMonth());

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(out.single, isNull);
    });

    testWidgets('refuses a time in the past', (tester) async {
      await open(
        tester,
        initial: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(
        find.textContaining('in the past'),
        findsOneWidget,
        reason: 'the reason has to be visible, not just a dead button',
      );
      final set = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Set'),
      );
      expect(set.onPressed, isNull);
    });

    testWidgets('opens on an armed reminder rather than on today', (
      tester,
    ) async {
      // Nudging an existing reminder by an hour must not mean finding its month
      // again first.
      final armed = DateTime.now().add(const Duration(days: 70));
      await open(tester, initial: armed);

      expect(
        find.text('${kMonthNames[armed.month - 1]} ${armed.year}'),
        findsOneWidget,
      );
    });
  });
}
