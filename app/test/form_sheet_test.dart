// The panel every form opens as, and the two calendar forms that moved onto it.
//
// The bug this file exists for was reported from a phone: opening a calendar
// entry showed its title, a Delete button, and then a tall empty rectangle
// running to the bottom of the screen. That is what Material's `AlertDialog`
// does when its `actions` are laid out by an `OverflowBar` that cannot fit
// them - the actions claim the height and the card's own content is squeezed
// into what is left. Nothing in a unit test would have caught it, because
// nothing was *wrong*: every widget was where it had been put.
//
// So the assertions here are about shape rather than about values. On a phone
// the panel is full width and against the bottom edge; the body still gets most
// of the height; and no form in the app is an AlertDialog any more.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/calendar/event_details.dart';
import 'package:todo_widget/ui/calendar/event_editor.dart';
import 'package:todo_widget/ui/form_sheet.dart';

void main() {
  const phone = Size(393, 852);
  const desktop = Size(T.designWidth, 600);

  CalendarEvent event({
    String description = '',
    bool allDay = false,
    String? recur,
  }) =>
      CalendarEvent(
        uuid: 'e1',
        calendarUuid: 'cal-1',
        title: 'design review',
        description: description,
        startAt: reminderStamp(DateTime(2026, 8, 18, 9)),
        endAt: reminderStamp(DateTime(2026, 8, 18, 10)),
        allDay: allDay,
        recur: recur,
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );

  final calendar = Calendar(
    uuid: 'cal-1',
    name: 'Work',
    color: '#6c8cff',
    createdAt: nowStamp(),
    updatedAt: nowStamp(),
  );

  /// A host whose button opens one of the forms, so the route is entered the
  /// way the app enters it - `showFormSheet` reads the layout from the context
  /// it is *called* with, which is the shell's, not the route's.
  Widget host({
    required Size size,
    required bool touch,
    required void Function(BuildContext) open,
  }) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(
            body: LayoutScope(
              layout: Layout(size, touch: touch),
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

  /// The drawn surface inside a [FormSheet] - the Container that carries the
  /// colour and the corners.
  Finder panelOf(WidgetTester tester) => find
      .descendant(
        of: find.byType(FormSheet),
        matching: find.byType(Container),
      )
      .first;

  Future<void> openIt(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('the panel', () {
    testWidgets('is full width and against the bottom edge on touch',
        (tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(
        size: phone,
        touch: true,
        open: (context) => showFormSheet<void>(
          context,
          builder: (context, layout) => FormSheet(
            accent: T.accent,
            layout: layout,
            title: 'a form',
            onClose: () {},
            actions: const [],
            child: const SizedBox(height: 40),
          ),
        ),
      ));
      await openIt(tester);

      // The panel, not the FormSheet widget itself - that one is a full-screen
      // Padding whose job is to hold the panel against an edge.
      final box = tester.getRect(panelOf(tester));
      expect(box.width, phone.width,
          reason: 'a card inset on both sides gives away line length');
      expect(box.bottom, phone.height);
    });

    testWidgets('is a centred column under a pointer', (tester) async {
      tester.view.physicalSize = desktop;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(
        size: desktop,
        touch: false,
        open: (context) => showFormSheet<void>(
          context,
          builder: (context, layout) => FormSheet(
            accent: T.accent,
            layout: layout,
            title: 'a form',
            onClose: () {},
            actions: const [],
            child: const SizedBox(height: 40),
          ),
        ),
      ));
      await openIt(tester);

      final box = tester.getRect(panelOf(tester));
      expect(box.bottom < desktop.height, isTrue,
          reason: 'a pointer gets a card, not a sheet against the edge');
      expect((box.center.dx - desktop.width / 2).abs() < 1, isTrue);
    });
  });

  group('the details card', () {
    Widget detailsHost(Size size, bool touch, CalendarEvent e) => host(
          size: size,
          touch: touch,
          open: (context) => showEventDetails(
            context,
            event: e,
            calendarName: 'Work',
            color: T.accent,
            loadTasks: () async => const <Task>[],
            loadAttachments: () async => const <Attachment>[],
          ),
        );

    testWidgets('is not an AlertDialog', (tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(detailsHost(phone, true, event()));
      await openIt(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(FormSheet), findsOneWidget);
    });

    testWidgets('shows its content, not a slab of empty surface',
        (tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(detailsHost(
        phone,
        true,
        event(description: 'the third pass at the layout'),
      ));
      await openIt(tester);

      // The reported symptom: title and Delete, and then nothing but height.
      // Every one of these lines was already being built - they simply had no
      // room left to be laid out in.
      expect(find.text('design review'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('the third pass at the layout'), findsOneWidget);
      expect(find.textContaining('18 Aug'), findsOneWidget);

      // And all four ways out are present and finger-sized, which is what the
      // OverflowBar could not do across 393pt.
      for (final label in ['Delete', 'Todos', 'Edit']) {
        expect(find.text(label), findsOneWidget);
        expect(tester.getSize(find.text(label)).height > 0, isTrue);
      }
    });

    testWidgets('says nothing about repeating when it does not', (tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(detailsHost(phone, true, event()));
      await openIt(tester);

      // "Once" on every other block would be a line of noise on the card whose
      // whole job is answering questions.
      expect(find.text('Every week'), findsNothing);
    });

    testWidgets('names the repeat rule when there is one', (tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
          detailsHost(phone, true, event(recur: Recur.weekly)));
      await openIt(tester);

      expect(find.text('Every week'), findsOneWidget);
    });

    testWidgets('a whole day says so instead of printing 00:00',
        (tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final dayOff = CalendarEvent(
        uuid: 'e2',
        calendarUuid: 'cal-1',
        title: 'day off',
        startAt: reminderStamp(DateTime(2026, 8, 18)),
        endAt: reminderStamp(DateTime(2026, 8, 19)),
        allDay: true,
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );

      await tester.pumpWidget(detailsHost(phone, true, dayOff));
      await openIt(tester);

      // The last day is the one before the stored end - printing the end would
      // add a day to every all-day event on this card.
      expect(find.textContaining('18 Aug · all day'), findsOneWidget);
      expect(find.textContaining('19 Aug'), findsNothing);
    });
  });

  group('the event editor', () {
    testWidgets('opens on the panel with its three ways out', (tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(
        size: phone,
        touch: true,
        open: (context) => showEventForm(
          context,
          existing: event(),
          calendars: [calendar],
          nameFor: (c) => c.name,
          colorFor: (_) => T.accent,
          initialCalendarUuid: calendar.uuid,
          initialStart: DateTime(2026, 8, 18, 9),
          initialEnd: DateTime(2026, 8, 18, 10),
        ),
      ));
      await openIt(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Edit event'), findsOneWidget);
      for (final label in ['Delete', 'Cancel', 'Save']) {
        expect(find.text(label), findsOneWidget);
      }
      // The repeat and all-day controls both live here now.
      expect(find.text('Repeats'), findsOneWidget);
      expect(find.text('All day'), findsOneWidget);
    });

    testWidgets('a new event offers no delete', (tester) async {
      tester.view.physicalSize = desktop;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(
        size: desktop,
        touch: false,
        open: (context) => showEventForm(
          context,
          calendars: [calendar],
          nameFor: (c) => c.name,
          colorFor: (_) => T.accent,
          initialCalendarUuid: calendar.uuid,
          initialStart: DateTime(2026, 8, 18, 9),
          initialEnd: DateTime(2026, 8, 18, 10),
        ),
      ));
      await openIt(tester);

      expect(find.text('New event'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
    });
  });
}
