// The two ways a task crosses between the list and a shelf, from the UI side.
//
// `parked_test.dart` covers what the moves do to the database. These cover the
// gestures that ask for them: the drag that only exists when there is a list
// beside the panel, and the confirmation that stands between a click and a
// dozen tasks reappearing on the list at once.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/ui/parked_panel.dart';

const _stamp = '2026-08-11T09:00:00.000Z';

ParkedGroup shelf(String uuid, String title) => ParkedGroup(
      uuid: uuid,
      workspaceUuid: 'ws',
      title: title,
      // Far enough out that nothing here is review-due: an overdue group opens
      // itself, and these tests are about what a *closed* shelf can do.
      reviewEveryDays: 3650,
      createdAt: _stamp,
      updatedAt: _stamp,
    );

Task task(String uuid, String text, {String? groupUuid}) => Task(
      uuid: uuid,
      workspaceUuid: 'ws',
      text: text,
      groupUuid: groupUuid,
      createdAt: _stamp,
      updatedAt: _stamp,
    );

/// What the panel asked the shell to do.
class Calls {
  final activated = <String>[];
  final parked = <({String group, String task})>[];
  final added = <({String group, String text})>[];
  final unparked = <String>[];
  final completed = <String>[];
  final deleted = <String>[];
  final reviewed = <String>[];
}

/// The panel, optionally with a draggable task beside it - which is the split
/// layout the drop target is gated on, in miniature.
Future<void> pumpPanel(
  WidgetTester tester, {
  required List<ParkedGroup> groups,
  required Map<String, List<Task>> parked,
  required Calls calls,
  Task? draggable,
  bool droppable = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 200,
              child: draggable == null
                  ? const SizedBox.expand()
                  : Align(
                      alignment: Alignment.topLeft,
                      child: Draggable<Task>(
                        data: draggable,
                        affinity: Axis.horizontal,
                        feedback: const SizedBox(width: 10, height: 10),
                        child: Text(draggable.text),
                      ),
                    ),
            ),
            Expanded(
              child: ParkedPanel(
                groups: groups,
                parked: parked,
                accent: const Color(0xFF6C8CFF),
                onUnpark: (t) async => calls.unparked.add(t.uuid),
                onComplete: (t) async => calls.completed.add(t.uuid),
                onDelete: (t) async => calls.deleted.add(t.uuid),
                onAddTask: (g, text) async =>
                    calls.added.add((group: g.uuid, text: text)),
                onReviewed: (g) async => calls.reviewed.add(g.uuid),
                onEditGroup: (_) {},
                onCreateGroup: () {},
                onBack: () {},
                onActivateGroup: (g) async => calls.activated.add(g.uuid),
                onPark: droppable
                    ? (g, t) async =>
                        calls.parked.add((group: g.uuid, task: t.uuid))
                    : null,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The ↗ on a group header. The per-task ↗ carries the same icon, so this is
/// only unambiguous while no shelf is open.
Finder activateButton() => find.byIcon(Icons.north_east_rounded);

void main() {
  group('activating a whole shelf', () {
    testWidgets('an empty shelf offers no activate button', (tester) async {
      await pumpPanel(
        tester,
        groups: [shelf('g1', 'Backlog')],
        parked: const {},
        calls: Calls(),
      );
      expect(activateButton(), findsNothing);
    });

    testWidgets('it asks first, and says how many', (tester) async {
      final calls = Calls();
      await pumpPanel(
        tester,
        groups: [shelf('g1', 'Backlog')],
        parked: {
          'g1': [task('t1', 'read the spec'), task('t2', 'draft the reply')],
        },
        calls: calls,
      );

      await tester.tap(activateButton());
      await tester.pumpAndSettle();

      expect(find.text('Activate this group?'), findsOneWidget);
      expect(
        find.textContaining('All 2 todos in "Backlog"'),
        findsOneWidget,
      );
      expect(calls.activated, isEmpty, reason: 'nothing has happened yet');
    });

    testWidgets('cancelling leaves the shelf alone', (tester) async {
      final calls = Calls();
      await pumpPanel(
        tester,
        groups: [shelf('g1', 'Backlog')],
        parked: {
          'g1': [task('t1', 'read the spec')],
        },
        calls: calls,
      );

      await tester.tap(activateButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(calls.activated, isEmpty);
    });

    testWidgets('confirming activates it, once', (tester) async {
      final calls = Calls();
      await pumpPanel(
        tester,
        groups: [shelf('g1', 'Backlog')],
        parked: {
          'g1': [task('t1', 'read the spec')],
        },
        calls: calls,
      );

      await tester.tap(activateButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();

      expect(calls.activated, ['g1']);
    });

    testWidgets('one todo is said in the singular', (tester) async {
      await pumpPanel(
        tester,
        groups: [shelf('g1', 'Backlog')],
        parked: {
          'g1': [task('t1', 'read the spec')],
        },
        calls: Calls(),
      );

      await tester.tap(activateButton());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The one todo in "Backlog"'),
        findsOneWidget,
      );
    });
  });

  group('dragging a task onto a shelf', () {
    testWidgets('dropping on a closed group parks it there and opens it',
        (tester) async {
      final calls = Calls();
      await pumpPanel(
        tester,
        groups: [shelf('g1', 'Backlog')],
        parked: const {'g1': []},
        calls: calls,
        draggable: task('t1', 'rewrite the importer'),
      );

      // Closed to begin with: the shelf's contents are not on screen. Its own
      // add field is the marker for "open", because it is there whether or not
      // the shelf has anything on it.
      expect(find.text('Add to Backlog'), findsNothing);

      final from = tester.getCenter(find.text('rewrite the importer'));
      final onto = tester.getCenter(find.text('Backlog'));
      final drag = await tester.startGesture(from);
      await drag.moveTo(onto);
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(calls.parked, [(group: 'g1', task: 't1')]);
      // Opened by the drop, so the landing is visible rather than being a
      // count that ticked up on a collapsed row.
      expect(find.text('Add to Backlog'), findsOneWidget);
    });

    testWidgets('the right shelf gets it when there are several',
        (tester) async {
      final calls = Calls();
      await pumpPanel(
        tester,
        groups: [shelf('g1', 'Backlog'), shelf('g2', 'Someday')],
        parked: const {},
        calls: calls,
        draggable: task('t1', 'rewrite the importer'),
      );

      final drag =
          await tester.startGesture(tester.getCenter(find.text('rewrite the importer')));
      await drag.moveTo(tester.getCenter(find.text('Someday')));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(calls.parked, [(group: 'g2', task: 't1')]);
    });

    // No list beside the panel means nothing to drag from, so the target does
    // not exist rather than sitting there inert.
    testWidgets('with no list beside it there is no drop target',
        (tester) async {
      await pumpPanel(
        tester,
        groups: [shelf('g1', 'Backlog')],
        parked: const {},
        calls: Calls(),
        droppable: false,
      );
      expect(find.byType(DragTarget<Task>), findsNothing);
    });
  });

  group('adding straight to a shelf', () {
    testWidgets('the field is on the open shelf and only on the open one',
        (tester) async {
      final calls = Calls();
      await pumpPanel(
        tester,
        groups: [shelf('g1', 'Backlog'), shelf('g2', 'Someday')],
        parked: const {},
        calls: calls,
      );

      // Both shelves start closed, so neither offers a field.
      expect(find.text('Add to Backlog'), findsNothing);
      expect(find.text('Add to Someday'), findsNothing);

      await tester.tap(find.text('Backlog'));
      await tester.pumpAndSettle();

      expect(find.text('Add to Backlog'), findsOneWidget);
      expect(find.text('Add to Someday'), findsNothing);
    });

    testWidgets('submitting adds to that shelf and keeps the caret',
        (tester) async {
      final calls = Calls();
      await pumpPanel(
        tester,
        groups: [shelf('g1', 'Backlog')],
        parked: const {},
        calls: calls,
      );
      await tester.tap(find.text('Backlog'));
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      await tester.enterText(field, 'read the Erlang book');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(calls.added, [(group: 'g1', text: 'read the Erlang book')]);
      // Cleared and still focused: several things at once is the reason to be
      // typing in here at all.
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

      // Blank input is not a task.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(calls.added, hasLength(1));
    });
  });

  group('reviewing a shelf', () {
    Future<void> openReview(WidgetTester tester, Calls calls) async {
      await pumpPanel(
        tester,
        groups: [shelf('g1', 'Backlog')],
        parked: {
          'g1': [
            task('t1', 'rewrite the importer', groupUuid: 'g1'),
            task('t2', 'read the Erlang book', groupUuid: 'g1'),
          ],
        },
        calls: calls,
      );
      await tester.tap(find.text('Backlog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
    }

    testWidgets('walks the shelf one task at a time', (tester) async {
      final calls = Calls();
      await openReview(tester, calls);

      expect(find.text('Review: Backlog'), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('rewrite the importer'), findsOneWidget);
      expect(find.text('read the Erlang book'), findsNothing);

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.text('read the Erlang book'), findsOneWidget);
      // Keep writes nothing at all - that is what makes it the safe answer.
      expect(calls.unparked, isEmpty);
      expect(calls.completed, isEmpty);
      expect(calls.deleted, isEmpty);
      // And the clock has not restarted, because the shelf is not finished.
      expect(calls.reviewed, isEmpty);
    });

    testWidgets('the clock restarts only at the end', (tester) async {
      final calls = Calls();
      await openReview(tester, calls);

      await tester.tap(find.text('Do it now'));
      await tester.pumpAndSettle();
      expect(calls.unparked, ['t1']);
      expect(calls.reviewed, isEmpty);

      await tester.tap(find.text('Drop'));
      await tester.pumpAndSettle();
      expect(calls.deleted, ['t2']);
      expect(calls.reviewed, ['g1']);
      expect(find.text('Reviewed 2 todos.'), findsOneWidget);
    });

    testWidgets('leaving early keeps the decisions and not the clock',
        (tester) async {
      final calls = Calls();
      await openReview(tester, calls);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(calls.completed, ['t1']);

      // Esc backs out of the review before the shell gets to close the panel.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Review: Backlog'), findsNothing);
      expect(find.text('Backlog'), findsOneWidget);
      expect(calls.reviewed, isEmpty);
    });

    testWidgets('an empty shelf is reviewed by looking at it', (tester) async {
      final calls = Calls();
      await pumpPanel(
        tester,
        groups: [shelf('g1', 'Backlog')],
        parked: const {'g1': []},
        calls: calls,
      );
      await tester.tap(find.text('Backlog'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review (nothing on it)'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing on this shelf.'), findsOneWidget);
      expect(calls.reviewed, ['g1']);
    });
  });
}
