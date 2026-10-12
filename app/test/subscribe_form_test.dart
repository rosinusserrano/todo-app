// The two surfaces of a subscribed calendar a person touches: the card a
// subscribed block opens, which must offer nothing that writes to it, and the
// subscribe form, which must check an address before it will subscribe to it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/feeds.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/calendar/event_details.dart';
import 'package:todo_widget/ui/calendar/subscribe_form.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const size = Size(T.designWidth, 700);

  Widget host(void Function(BuildContext) open) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: Scaffold(
            body: LayoutScope(
              layout: const Layout(size),
              child: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => open(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  final event = CalendarEvent(
    uuid: 'e1',
    calendarUuid: 'cal-1',
    title: 'Standup',
    startAt: reminderStamp(DateTime(2026, 8, 18, 9)),
    endAt: reminderStamp(DateTime(2026, 8, 18, 9, 15)),
    feedUuid: 'f1',
    createdAt: nowStamp(),
    updatedAt: nowStamp(),
  );

  testWidgets('a subscribed block reads, and offers no Edit or Delete',
      (tester) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(host((context) => showEventDetails(
          context,
          event: event,
          calendarName: 'Work',
          color: T.accent,
          loadTasks: () async => const [],
          loadAttachments: () async => const [],
          feedName: 'Team calendar',
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('From Team calendar'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('the form checks the address before it will subscribe',
      (tester) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late AppState state;
    await tester.runAsync(() async {
      final store = await LocalStore.open(
        path: inMemoryDatabasePath,
        singleInstance: false,
      );
      state = AppState(store);
      await state.load();
      await state.refreshCalendars();
    });
    var answer = '<html>not this</html>';
    state.fetchFeed = (_) async => checkFeedText(answer);

    await tester.pumpWidget(host((context) => showSubscribeForm(context, state)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'webcal://x/a.ics');
    await tester.runAsync(() async {
      await tester.tap(find.text('Check'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    // The page link, not the calendar: said so, and nothing to subscribe to.
    expect(find.textContaining('did not return a calendar'), findsOneWidget);
    expect(find.text('Put the events in'), findsNothing);

    answer = 'BEGIN:VCALENDAR\r\nX-WR-CALNAME:Team\r\nEND:VCALENDAR';
    await tester.runAsync(() async {
      await tester.tap(find.text('Check'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    // Found, named from the feed, and both destinations on offer.
    expect(find.text('Put the events in'), findsOneWidget);
    expect(find.text('A new calendar'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget); // the workspace's calendar
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .any((f) => f.controller?.text == 'Team'),
      isTrue,
    );
  });
}
