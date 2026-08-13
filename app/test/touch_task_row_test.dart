// The task row on a touch device.
//
// The regression this file exists for is not cosmetic and was live for the
// whole life of the mobile build: every action on a row was drawn behind
// `visible: _hovered`, and a fingertip produces no hover. Reminders, parking,
// focus, attachments and delete were therefore not *small* on a phone, they
// were unreachable - the row rendered them at zero opacity behind an
// IgnorePointer and there was no gesture that would ever reveal them.
//
// So what is pinned here is reachability first and layout second: on a touch
// layout each action must be present, opaque, hittable and at least a
// fingertip across. The desktop shape is pinned alongside it, because the fix
// must not quietly cost the mouse its nine-across row.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/markdown_text.dart';
import 'package:todo_widget/ui/task_row.dart';

void main() {
  Task task({String notes = '', int priority = 0}) => Task(
        uuid: 't1',
        workspaceUuid: 'ws',
        text: 'inspect the layers',
        notes: notes,
        priority: priority,
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
    Future<void> Function(bool)? onSetPriority,
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
              // Defaulted rather than left null: a null onOpen is "this row
              // has no long form" (the history list), which would take the
              // pencil out of the bar and quietly weaken most of these tests.
              onOpen: onOpen ?? () {},
            ),
          ),
        ),
      );

  /// Every icon the row draws, mapped to whether it is actually visible.
  ///
  /// The desktop row keeps hidden actions *in the layout* at zero opacity, so
  /// `find.byIcon` finding one proves nothing on its own - this is what tells
  /// "present" apart from "reachable".
  bool visible(WidgetTester tester, IconData icon) {
    final fades = find.ancestor(
      of: find.byIcon(icon),
      matching: find.byType(AnimatedOpacity),
    );
    if (fades.evaluate().isEmpty) return true; // not hover-gated at all
    return tester.widget<AnimatedOpacity>(fades.first).opacity == 1;
  }

  group('touch', () {
    testWidgets('every action is reachable without a hover', (tester) async {
      await tester.pumpWidget(row(touch: true));
      await tester.pumpAndSettle();

      for (final icon in [
        Icons.notifications_none_rounded, // remind
        Icons.outlined_flag_rounded, // priority
        Icons.attach_file_rounded, // attachments
        Icons.inbox_rounded, // park
        Icons.play_arrow_rounded, // focus
        Icons.close_rounded, // delete
      ]) {
        expect(find.byIcon(icon), findsOneWidget, reason: '$icon is missing');
        expect(visible(tester, icon), isTrue, reason: '$icon is not visible');
      }
    });

    testWidgets('the actions are at least a fingertip across', (tester) async {
      await tester.pumpWidget(row(touch: true));
      await tester.pumpAndSettle();

      // Measured on the tap target, not the glyph: a 20px icon inside a 40px
      // button is the point, and asserting on the icon would pass while the
      // button around it was 16px.
      final target = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.play_arrow_rounded),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(target.width, greaterThanOrEqualTo(Layout.touchTargetSide));
      expect(target.height, greaterThanOrEqualTo(Layout.touchTargetSide));
    });

    testWidgets('an action actually fires when tapped', (tester) async {
      // The opacity assertions above would all pass on a row wrapped in an
      // IgnorePointer, which is exactly what the broken version was.
      var focused = false;
      await tester.pumpWidget(row(touch: true, onFocus: () => focused = true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      expect(focused, isTrue);
    });

    testWidgets('tapping the title expands the notes in place', (tester) async {
      await tester.pumpWidget(
        row(touch: true, of: task(notes: 'weights **before** and after')),
      );
      await tester.pumpAndSettle();

      // Closed: the one-line preview, which is a plain Text flattened out of
      // Markdown - no renderer involved.
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      expect(find.byType(MarkdownText), findsNothing);
      expect(find.text('weights before and after'), findsOneWidget);

      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();

      // Open: the chevron flips and the body is now really rendered, so the
      // `**before**` is bold rather than literal.
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
      expect(find.byType(MarkdownText), findsOneWidget);

      // Still exactly once. The preview gave way to the body rather than
      // sitting above it, or the row would show the same sentence twice.
      expect(find.text('weights before and after'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    });

    testWidgets('a task with no notes offers no expander', (tester) async {
      await tester.pumpWidget(row(touch: true));
      await tester.pumpAndSettle();

      // Nothing to expand into. The pencil is how notes get added, which is
      // why it is not conditional the way this is.
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('the pencil is the way to the composer', (tester) async {
      var opened = false;
      await tester.pumpWidget(
        row(touch: true, of: task(notes: 'x'), onOpen: () => opened = true),
      );
      await tester.pumpAndSettle();

      // Tapping the title expands rather than editing, so the editor needs its
      // own affordance or it is unreachable.
      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();
      expect(opened, isFalse);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    });
  });

  group('pointer', () {
    testWidgets('actions stay hidden until hovered', (tester) async {
      // The desktop row is nine controls across a 340px window and only works
      // because they are invisible at rest. The touch bar must not leak into
      // it.
      await tester.pumpWidget(row(touch: false));
      await tester.pumpAndSettle();

      expect(visible(tester, Icons.play_arrow_rounded), isFalse);
      expect(visible(tester, Icons.close_rounded), isFalse);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    });

    testWidgets('tapping the title still opens the composer', (tester) async {
      var opened = false;
      await tester.pumpWidget(
        row(touch: false, of: task(notes: 'x'), onOpen: () => opened = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('inspect the layers'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    });
  });
}
