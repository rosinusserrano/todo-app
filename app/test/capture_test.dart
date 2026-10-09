// Capturing into somewhere other than the list on screen.
//
// Two paths do it: the add field's workspace chip, which writes a task into
// another workspace without switching to it, and moving side thoughts - one or
// several - onto any workspace's list or shelf. Both must leave the screen
// where it was, and a moved thought must be resolved rather than deleted:
// thoughts are never hard-removed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/footer.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> freshState() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final state = AppState(store);
    await state.load();
    return state;
  }

  /// A second workspace, with the first one still the one on screen.
  Future<(String home, String other)> twoWorkspaces(AppState s) async {
    final home = s.currentWorkspaceUuid!;
    await s.saveWorkspace(name: 'Meine Apps', color: '#d4a84b');
    final other = s.currentWorkspaceUuid!;
    await s.selectWorkspace(home);
    return (home, other);
  }

  test('a task aimed at another workspace lands there, and the list stays',
      () async {
    final s = await freshState();
    final (home, other) = await twoWorkspaces(s);

    await s.addTask('here');
    await s.addTask('over there', workspaceUuid: other);

    expect(s.currentWorkspaceUuid, home);
    expect(s.tasks.map((t) => t.text), ['here']);
    final there = await s.store.allTasksInWorkspace(other);
    expect(there.map((t) => t.text), ['over there']);
    await s.store.close();
  });

  test('moving thoughts writes tasks and resolves the thoughts', () async {
    final s = await freshState();
    final (home, other) = await twoWorkspaces(s);
    await s.addThought('book recommendation');
    await s.addThought('call mum');
    await s.addThought('stays');

    final moving = s.thoughts.where((t) => t.text != 'stays').toList();
    await s.moveThoughts(moving, workspaceUuid: other);

    expect(s.thoughts.map((t) => t.text), ['stays']);
    expect(s.currentWorkspaceUuid, home);
    final there = await s.store.allTasksInWorkspace(other);
    expect(
      there.map((t) => t.text).toSet(),
      {'book recommendation', 'call mum'},
    );
    await s.store.close();
  });

  test('a thought can go straight onto a shelf', () async {
    final s = await freshState();
    final g = await s.saveGroup(title: 'Someday', reviewEveryDays: 30);
    await s.addThought('learn the cello');

    await s.moveThoughts(
      s.thoughts,
      workspaceUuid: s.currentWorkspaceUuid!,
      groupUuid: g!.uuid,
    );

    expect(s.tasks, isEmpty, reason: 'shelved, not on the list');
    expect(s.parked[g.uuid]!.single.text, 'learn the cello');
    expect(s.thoughts, isEmpty);
    await s.store.close();
  });

  group('the thoughts panel', () {
    SideThought thought(String id, String text) => SideThought(
          uuid: id,
          text: text,
          createdAt: '2026-10-09T10:00:00.000+02:00',
          updatedAt: '2026-10-09T10:00:00.000+02:00',
        );

    Widget panel({
      required List<SideThought> thoughts,
      required Future<void> Function(List<SideThought>, RelativeRect) onMove,
      bool touch = true,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: LayoutScope(
              layout: Layout(const Size(T.designWidth, 600), touch: touch),
              child: ThoughtsPanel(
                thoughts: thoughts,
                onPromote: (_) async {},
                onDiscard: (_) async {},
                onMove: onMove,
              ),
            ),
          ),
        );

    testWidgets('a long press selects, and the bar moves the selection',
        (tester) async {
      final moved = <List<String>>[];
      await tester.pumpWidget(panel(
        thoughts: [thought('a', 'one'), thought('b', 'two'), thought('c', 'three')],
        onMove: (list, _) async => moved.add([for (final t in list) t.uuid]),
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('one'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      // Once selecting, a plain tap toggles.
      await tester.tap(find.text('three'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Move to a list or shelf'));
      await tester.pumpAndSettle();
      expect(moved, [
        ['a', 'c'],
      ]);
      expect(find.text('Parked thoughts'), findsOneWidget,
          reason: 'moving ends the selection');
    });

    testWidgets('one thought moves from its own row', (tester) async {
      final moved = <List<String>>[];
      await tester.pumpWidget(panel(
        thoughts: [thought('a', 'one'), thought('b', 'two')],
        onMove: (list, _) async => moved.add([for (final t in list) t.uuid]),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Move to a list or shelf').last);
      await tester.pumpAndSettle();
      expect(moved, [
        ['b'],
      ]);
    });

    testWidgets('its controls are a fingertip on touch', (tester) async {
      await tester.pumpWidget(panel(
        thoughts: [thought('a', 'one')],
        onMove: (_, _) async {},
      ));
      await tester.pumpAndSettle();

      final button = find.ancestor(
        of: find.byIcon(Icons.close_rounded),
        matching: find.byType(SizedBox),
      );
      expect(
        tester.getSize(button.first).height,
        greaterThanOrEqualTo(Layout.touchTargetSide),
      );
    });
  });
}
