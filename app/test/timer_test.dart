// The timer as the app holds it: device-local, one at a time, a view of its
// own that every other place closes. The parsing and the model's maths are
// countdown_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/ui/dock.dart';
import 'package:todo_widget/ui/timer_view.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> fresh() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final s = AppState(store);
    await s.load();
    return s;
  }

  test('survives a restart, and stopping forgets it', () async {
    final s = await fresh();
    await s.startCountdown(const Duration(minutes: 25), ' focus ');
    final again = AppState(s.store);
    await again.load();
    expect(again.countdown?.label, 'focus');
    expect(again.countdown?.endsAt, s.countdown!.endsAt);

    await again.pauseCountdown();
    final third = AppState(s.store);
    await third.load();
    expect(third.countdown!.paused, isTrue);

    await third.clearCountdown();
    final fourth = AppState(s.store);
    await fourth.load();
    expect(fourth.countdown, isNull);
    await s.store.close();
  });

  test('its view is a place: opening it closes the rest, and back', () async {
    final s = await fresh();
    await s.setListOpen(true);
    await s.openTimer();
    expect(s.showTimer, isTrue);
    expect(s.showList, isFalse);

    await s.toggleCalendar();
    expect(s.showTimer, isFalse, reason: 'the calendar took the screen');
    await s.openTimer();
    expect(s.showCalendar, isFalse);
    await s.openHome();
    expect(s.showTimer, isFalse);
    await s.store.close();
  });

  Future<AppState> pumpView(
    WidgetTester tester, {
    DateTime Function()? now,
  }) async {
    tester.view.physicalSize = const Size(340, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = (await tester.runAsync(fresh))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: s,
            builder: (_, _) => now == null
                ? TimerView(state: s)
                : TimerView(state: s, now: now),
          ),
        ),
      ),
    );
    await tester.pump();
    return s;
  }

  testWidgets('a line sets it, read back before it starts', (tester) async {
    final s = await pumpView(tester);
    await tester.enterText(find.byType(TextField), '1h for checking mails');
    await tester.pump();
    expect(find.text('1 h · checking mails'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(s.countdown?.total, const Duration(hours: 1));
    expect(s.countdown?.label, 'checking mails');
    expect(find.text('checking mails'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    // Unmounted, so the view's ticker goes with it.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a preset starts at once, with what was typed as the label', (
    tester,
  ) async {
    final s = await pumpView(tester);
    await tester.enterText(find.byType(TextField), 'tea');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('5 min'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(s.countdown?.total, const Duration(minutes: 5));
    expect(s.countdown?.label, 'tea');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('up, it says so, and Enter is Done', (tester) async {
    final s = await pumpView(
      tester,
      now: () => DateTime.now().add(const Duration(hours: 2)),
    );
    await tester.runAsync(
      () => s.startCountdown(const Duration(minutes: 10), 'tea'),
    );
    await tester.pump();
    expect(find.text("Time's up"), findsOneWidget);
    expect(find.text('tea'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(s.countdown, isNull);
    expect(find.byType(TextField), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the dock draws a badge in its segment', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 52,
              child: Dock(
                segments: [
                  DockSegment(
                    label: 'More',
                    fill: Colors.grey,
                    ink: Colors.white,
                    items: const [],
                    badge: const Text('42m'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('42m'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });
}
