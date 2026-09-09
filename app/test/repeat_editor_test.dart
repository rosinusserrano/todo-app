// The panel behind "Repeat…", from the UI side.
//
// `recurrence_rules_test.dart` covers what the rules do. This covers the thing
// the panel is actually for: that the two settings which decide whether a
// repeat can pile up are askable, that they produce the rule string the store
// expects, and that the second question is not put where it cannot be answered.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/ui/repeat_editor.dart';

void main() {
  /// Opens the editor and hands back whatever it returned.
  Future<RepeatSpec?> open(
    WidgetTester tester, {
    RepeatSpec initial = RepeatSpec.once,
    bool hasReminder = true,
  }) async {
    RepeatSpec? result;
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                opened = true;
                result = await showRepeatEditor(
                  context,
                  initial: initial,
                  hasReminder: hasReminder,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    return result;
  }

  /// The panel scrolls, so anything below the fold has to be brought into view
  /// before it can be hit - a tap on an off-screen finder lands on whatever is
  /// actually at those coordinates.
  Future<void> press(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> done(WidgetTester tester) => press(tester, 'Done');

  testWidgets('a plain rule comes back as it went in', (tester) async {
    RepeatSpec? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => saved = await showRepeatEditor(
                context,
                initial: RepeatSpec.once,
                hasReminder: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await press(tester, 'Repeats');
    await press(tester, 'Every week');
    await done(tester);

    expect(saved!.recur, Recur.weekly);
    expect(saved!.from, RecurFrom.schedule);
    // The default lead is the one that cannot pile up.
    expect(saved!.lead, isNull);
  });

  testWidgets('the last day of the month is a rule of its own', (tester) async {
    RepeatSpec? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => saved = await showRepeatEditor(
                context,
                initial: const RepeatSpec(recur: Recur.monthly),
                hasReminder: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await press(tester, 'Last day of the month');
    await press(tester, 'When it is due');
    await done(tester);

    expect(saved!.recur, Recur.monthLast);
    expect(saved!.lead, 0);
  });

  testWidgets('an interval counted from the tick forces a lead of zero',
      (tester) async {
    RepeatSpec? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => saved = await showRepeatEditor(
                context,
                initial: const RepeatSpec(recur: Recur.weekly),
                hasReminder: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Without a reminder a scheduled repeat is dropped on save, and the panel
    // says so rather than letting it be found out later.
    expect(
      find.textContaining('measured from the reminder'),
      findsOneWidget,
    );

    await press(tester, 'After it is done');

    // That warning is gone: this kind needs no clock at all.
    expect(find.textContaining('measured from the reminder'), findsNothing);
    // And the second question is not asked, because it cannot be answered -
    // nothing can appear before the completion it is counted from.
    expect(find.text('The next one appears'), findsNothing);

    await press(tester, 'weeks');
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await done(tester);

    expect(saved!.recur, 'every-3-w');
    expect(saved!.from, RecurFrom.completion);
    expect(saved!.lead, 0);
  });

  testWidgets('an existing rule opens on its own settings', (tester) async {
    await open(
      tester,
      initial: RepeatSpec(
        recur: Recur.nthWeekday(Recur.ordLast, DateTime.friday),
        lead: 3 * 24 * 60,
      ),
    );

    // The shape, the ordinal and the weekday are all found again rather than
    // the panel resetting to a default nobody chose.
    expect(find.text('Nth weekday'), findsOneWidget);
    expect(find.text('Three days before'), findsOneWidget);
    expect(find.textContaining('3 days before it is due'), findsOneWidget);
  });

  test('the label says both halves of what was set', () {
    expect(const RepeatSpec().label, 'Once');
    expect(const RepeatSpec(recur: Recur.monthLast).label,
        'Last day of the month');
    expect(
      const RepeatSpec(recur: 'every-2-w', from: RecurFrom.completion).label,
      'Every 2 weeks, after it is done',
    );
  });
}
