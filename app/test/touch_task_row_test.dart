// The task row's two shapes, and the one thing they have in common: the row
// itself carries no actions at all.
//
// The regression this file was written for is still worth stating, because the
// rule that came out of it is what the current design has to keep obeying:
// every action on a row used to be drawn behind `visible: _hovered`, and a
// fingertip produces no hover - so reminders, parking, focus, attachments and
// delete were not *small* on a phone, they were unreachable, and no width would
// ever have revealed them.
//
// The actions have since moved off the row entirely, into an overlay bar. So
// what is pinned here is that each pointer has a gesture that opens that bar,
// that everything the row used to offer is inside it at a size that pointer can
// hit, and that the row at rest is a tick box, a title and its state marks.

import 'package:flutter/gestures.dart'
    show kDoubleTapTimeout, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/markdown_text.dart';
import 'package:todo_widget/ui/task_detail.dart';
import 'package:todo_widget/ui/task_row.dart';

void main() {
  Task task({
    String notes = '',
    int priority = 0,
    String? event,
    String? remindAt,
  }) =>
      Task(
        uuid: 't1',
        workspaceUuid: 'ws',
        text: 'inspect the layers',
        notes: notes,
        priority: priority,
        eventUuid: event,
        remindAt: remindAt,
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );

  /// A row under a [LayoutScope] of the given kind. Everything optional is
  /// wired, because "is this action reachable" is only a real question for a
  /// row that was given the action in the first place.
  Widget row({
    required bool touch,
    Task? of,
    VoidCallback? onOpen,
    VoidCallback? onFocus,
    VoidCallback? onExpand,
    Future<void> Function(bool)? onSetPriority,
    int attachmentCount = 0,
    bool dragHandle = false,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: LayoutScope(
            layout: Layout(const Size(T.designWidth, 600), touch: touch),
            child: TaskRow(
              task: of ?? task(),
              accent: T.accent,
              onComplete: () async {},
              onDelete: () async {},
              onFocus: onFocus ?? () {},
              onSetReminder: (_) async {},
              onPark: (_) async {},
              onSetPriority: onSetPriority ?? (_) async {},
              onOpenAttachments: () {},
              onUnplan: () async {},
              onExpand: onExpand,
              attachmentCount: attachmentCount,
              dragHandle: dragHandle
                  ? const Icon(Icons.drag_indicator, size: 14)
                  : null,
              // Defaulted rather than left null: a null onOpen is "this row
              // has no long form" (the session view's rows), which would take
              // the pencil out of the bar and quietly weaken these tests.
              onOpen: onOpen ?? () {},
            ),
          ),
        ),
      );

  /// Every action the bar can offer, in the order it offers them.
  const actions = [
    Icons.notifications_none_rounded, // remind
    Icons.outlined_flag_rounded, // priority
    Icons.attach_file_rounded, // attachments
    Icons.inbox_rounded, // park
    Icons.play_arrow_rounded, // focus
    Icons.open_in_full_rounded, // expand
    Icons.edit_outlined, // edit
    Icons.close_rounded, // delete
  ];

  /// A right-click, which is what opens the bar under a pointer.
  Future<void> rightClick(WidgetTester tester, Finder at) async {
    await tester.tap(at, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  /// A left-click that is **on its own**: it waits out the double-click window
  /// afterwards, so a second call is a second click rather than the other half
  /// of this one. `pumpAndSettle` alone does not, which is the whole reason
  /// this exists - it advances the clock by about a frame, and two of those in
  /// a row land well inside [kDoubleTapTimeout].
  Future<void> click(WidgetTester tester, Finder at) async {
    await tester.tap(at);
    await tester.pumpAndSettle();
    await tester.pump(kDoubleTapTimeout);
  }

  /// Two clicks inside the window.
  Future<void> doubleClick(WidgetTester tester, Finder at) async {
    await tester.tap(at);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(at);
    await tester.pumpAndSettle();
  }

  group('the row at rest', () {
    for (final touch in [true, false]) {
      testWidgets('carries no actions (touch: $touch)', (tester) async {
        await tester.pumpWidget(row(touch: touch, of: task(notes: 'a note')));
        await tester.pumpAndSettle();

        // Not hidden, not faded out, not behind an IgnorePointer: absent. The
        // row's whole width belongs to its text again.
        for (final icon in actions) {
          expect(find.byIcon(icon), findsNothing, reason: '$icon is on the row');
        }
        expect(find.text('inspect the layers'), findsOneWidget);
      });
    }

    testWidgets('still shows what the task is carrying', (tester) async {
      await tester.pumpWidget(row(
        touch: false,
        of: task(
          remindAt: reminderStamp(DateTime.now().add(const Duration(hours: 2))),
          event: 'e1',
        ),
        attachmentCount: 2,
      ));
      await tester.pumpAndSettle();

      // Marks, not controls: an armed reminder, documents and a slot in the
      // calendar are state, and the row said so before the actions moved out.
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
      expect(find.byIcon(Icons.event_available_rounded), findsOneWidget);
    });
  });

  group('touch', () {
    testWidgets('a tap on the text opens the actions', (tester) async {
      await tester.pumpWidget(row(touch: true));
      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();

      for (final icon in actions) {
        expect(find.byIcon(icon), findsOneWidget, reason: '$icon is missing');
      }
    });

    testWidgets('the actions are at least a fingertip across', (tester) async {
      await tester.pumpWidget(row(touch: true));
      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();

      // Measured on the tap target, not the glyph: a 20px icon inside a 40px
      // button is the point, and asserting on the icon would pass while the
      // button around it was 16px.
      for (final icon in actions) {
        final box = tester.getSize(
          find
              .ancestor(of: find.byIcon(icon), matching: find.byType(SizedBox))
              .first,
        );
        expect(box.width, greaterThanOrEqualTo(Layout.touchTargetSide),
            reason: '$icon is below a fingertip');
        expect(box.height, greaterThanOrEqualTo(Layout.touchTargetSide));
      }
    });

    testWidgets('the fullest bar still fits the design width', (tester) async {
      // Nine fingertips is 360 units against a phone's ~340 (see UiScale), so
      // the bar has to wrap rather than shrink - a tap target below a fingertip
      // is an action the phone does not really have.
      tester.view.physicalSize = const Size(T.designWidth, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(row(
        touch: true,
        of: task(notes: 'a note', priority: 1, event: 'e1'),
        attachmentCount: 1,
      ));
      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();

      // A RenderFlex overflow is reported as an exception rather than a failed
      // layout, so nothing else here would notice one.
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.event_busy_rounded), findsOneWidget); // unplan
      expect(find.byIcon(Icons.close_rounded), findsOneWidget); // and delete
    });

    testWidgets('an action actually fires when tapped', (tester) async {
      var focused = false;
      await tester.pumpWidget(row(touch: true, onFocus: () => focused = true));
      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      expect(focused, isTrue);

      // And the bar closed behind it, rather than sitting over the list.
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('the pencil is the way to the composer', (tester) async {
      var opened = false;
      await tester.pumpWidget(
        row(touch: true, of: task(notes: 'x'), onOpen: () => opened = true),
      );
      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();
      expect(opened, isFalse);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    });

    testWidgets('expand is handed to the shell when it offers to take it',
        (tester) async {
      // On a phone the read view takes the whole screen, which a row inside a
      // scrolling list cannot do for itself.
      var expanded = false;
      await tester.pumpWidget(row(
        touch: true,
        of: task(notes: 'weights'),
        onExpand: () => expanded = true,
      ));
      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.open_in_full_rounded));
      await tester.pumpAndSettle();

      expect(expanded, isTrue);
      // And it did *not* also grow in place, which would be the same view twice.
      expect(find.byType(TaskDetail), findsNothing);
    });
  });

  group('pointer', () {
    testWidgets('a right-click opens the actions', (tester) async {
      await tester.pumpWidget(row(touch: false));
      await rightClick(tester, find.text('inspect the layers'));

      for (final icon in actions) {
        expect(find.byIcon(icon), findsOneWidget, reason: '$icon is missing');
      }
    });

    testWidgets('they are pointer-sized, and named', (tester) async {
      await tester.pumpWidget(row(touch: false));
      await rightClick(tester, find.text('inspect the layers'));

      final box = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.play_arrow_rounded),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(box.width, Layout.pointerTargetSide);

      // A mouse gets tooltips, which is what carries the wording a fingertip
      // only ever hears through Semantics.
      expect(
        find.byTooltip('Work on this — hides everything else'),
        findsOneWidget,
      );
    });

    testWidgets('a left-click expands the row in place', (tester) async {
      await tester.pumpWidget(
        row(touch: false, of: task(notes: 'weights **before** and after')),
      );
      await tester.pumpAndSettle();

      // Closed: the one-line preview, which is a plain Text flattened out of
      // Markdown - no renderer involved.
      expect(find.byType(MarkdownText), findsNothing);
      expect(find.text('weights before and after'), findsOneWidget);

      await click(tester, find.text('inspect the layers'));

      // Open: the details and the body, really rendered, so the `**before**`
      // is bold rather than literal.
      expect(find.byType(TaskDetail), findsOneWidget);
      expect(find.byType(MarkdownText), findsOneWidget);

      // Still exactly once. The preview gave way to the body rather than
      // sitting above it, or the row would show the same sentence twice - what
      // this finds now is the rendered body's own plain text.
      expect(find.text('weights before and after'), findsOneWidget);

      await click(tester, find.text('inspect the layers'));
      expect(find.byType(TaskDetail), findsNothing);
    });

    testWidgets('a task with no notes still expands', (tester) async {
      // There is always something to read: when it was added, whether it is
      // flagged, what it is planned into.
      await tester.pumpWidget(row(touch: false));
      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskDetail), findsOneWidget);
      expect(find.text('No notes on this one.'), findsOneWidget);
    });

    testWidgets('the bar can collapse it again', (tester) async {
      await tester.pumpWidget(row(touch: false, of: task(notes: 'x')));
      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetail), findsOneWidget);

      await rightClick(tester, find.text('inspect the layers'));
      // The action reads as its opposite while the row is open.
      expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);
      await tester.tap(find.byIcon(Icons.close_fullscreen_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(TaskDetail), findsNothing);
    });

    testWidgets('a double-click opens the composer', (tester) async {
      var opened = 0;
      await tester.pumpWidget(row(
        touch: false,
        of: task(notes: 'weights'),
        onOpen: () => opened++,
      ));
      await tester.pumpAndSettle();

      await doubleClick(tester, find.text('inspect the layers'));
      expect(opened, 1);

      // And it left the row as it found it. A double-click is one gesture, not
      // a click plus an edit, so the expansion the first half opened is put
      // back rather than waiting behind the composer.
      expect(find.byType(TaskDetail), findsNothing);
    });

    testWidgets('a double-click on an open row leaves it open', (tester) async {
      await tester.pumpWidget(row(touch: false, of: task(notes: 'weights')));
      await tester.pumpAndSettle();

      await click(tester, find.text('inspect the layers'));
      expect(find.byType(TaskDetail), findsOneWidget);

      await doubleClick(tester, find.text('inspect the layers'));
      expect(find.byType(TaskDetail), findsOneWidget);
    });

    testWidgets('two clicks apart in time are still two clicks',
        (tester) async {
      // The whole reason the double-click is hand-rolled: the first click must
      // not wait to find out whether a second one is coming.
      var opened = 0;
      await tester.pumpWidget(row(
        touch: false,
        of: task(notes: 'weights'),
        onOpen: () => opened++,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('inspect the layers'));
      await tester.pump(const Duration(milliseconds: 1));
      // Open already, one frame in - not after the window has expired.
      expect(find.byType(TaskDetail), findsOneWidget);

      await tester.pump(kDoubleTapTimeout);
      await click(tester, find.text('inspect the layers'));

      expect(find.byType(TaskDetail), findsNothing);
      expect(opened, 0);
    });

    testWidgets('a row with no composer just expands twice', (tester) async {
      // The session view's rows have no long form, so there is nothing for a
      // double-click to open and it stays two clicks.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LayoutScope(
            layout: Layout(const Size(T.designWidth, 600)),
            child: TaskRow(
              task: task(notes: 'weights'),
              accent: T.accent,
              onComplete: () async {},
              onDelete: () async {},
              onFocus: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await doubleClick(tester, find.text('inspect the layers'));
      expect(find.byType(TaskDetail), findsNothing); // opened, then closed
      expect(tester.takeException(), isNull);
    });

    testWidgets('the reorder grip is drawn where it is given', (tester) async {
      await tester.pumpWidget(row(touch: false, dragHandle: true));
      await tester.pumpAndSettle();

      // On the right: past the title, not between the edge and the tick box
      // where it used to indent every row in the list.
      final grip = tester.getCenter(find.byIcon(Icons.drag_indicator));
      final title = tester.getCenter(find.text('inspect the layers'));
      expect(grip.dx, greaterThan(title.dx));
    });
  });
}
