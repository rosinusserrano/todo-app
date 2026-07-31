// App behaviour tests.
//
// These avoid main.dart, which calls window_manager and flutter_acrylic on
// startup - both need a real window and platform channels that do not exist in
// a test binding. The logic worth testing lives in AppState and the row
// widgets, neither of which touches the window.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tray_manager/tray_manager.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/reminders.dart';
import 'package:todo_widget/tray.dart';
import 'package:todo_widget/ui/reminder_menu.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/panel_header.dart';
import 'package:todo_widget/ui/task_row.dart';
import 'package:todo_widget/ui/title_bar.dart';
import 'package:todo_widget/ui/workspace_bar.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> freshState() async {
    // singleInstance: false, or every test in this file shares one database.
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final state = AppState(store);
    await state.load();
    return state;
  }

  group('AppState', () {
    test('starts on a workspace so a task can be added immediately', () async {
      final s = await freshState();
      expect(s.currentWorkspaceUuid, isNotNull);

      await s.addTask('write the port');
      expect(s.tasks.single.text, 'write the port');
    });

    test('checking off keeps the task and moves it into history', () async {
      final s = await freshState();
      await s.addTask('ship it');
      await s.completeTask(s.tasks.single);

      expect(s.tasks, isEmpty);
      await s.toggleHistory();
      expect(s.historyTasks.single.text, 'ship it');
    });

    test('deleting tombstones the task instead of dropping the row', () async {
      final s = await freshState();
      await s.addTask('never mind');
      final t = s.tasks.single;
      await s.deleteTask(t);

      expect(s.tasks, isEmpty);

      // The row must survive as a tombstone, otherwise the delete never
      // reaches another device.
      final dirty = await s.store.dirtyRows();
      final row = dirty['tasks']!.firstWhere((r) => r['uuid'] == t.uuid);
      expect(row['deleted_at'], isNotNull);
    });

    test('a deleted task does not come back in history', () async {
      final s = await freshState();
      await s.addTask('dismissed');
      await s.deleteTask(s.tasks.single);
      await s.toggleHistory();
      expect(s.historyTasks, isEmpty);
    });

    test('focus is exclusive and survives a reload', () async {
      final s = await freshState();
      await s.addTask('first');
      await s.addTask('second');

      await s.enterFocus(s.tasks.first);
      expect(s.focusTask, isNotNull);

      await s.enterFocus(s.tasks.last);
      final flagged = s.tasks.where((t) => t.inProgress).toList();
      expect(flagged.length, 1, reason: 'only one task may be in progress');

      // Reopening the app must drop straight back into focus.
      s.focusTask = null;
      await s.restoreFocus();
      expect(s.focusTask!.uuid, flagged.single.uuid);
    });

    test('leaving focus clears the flag', () async {
      final s = await freshState();
      await s.addTask('focused');
      await s.enterFocus(s.tasks.single);
      await s.exitFocus();

      expect(s.focusTask, isNull);
      expect(s.tasks.single.inProgress, isFalse);
    });

    test('the close guard blocks only while thoughts are pending', () async {
      final s = await freshState();
      expect(await s.canProceedPastThoughts(), isTrue);

      await s.addThought('look into flutter');
      expect(await s.canProceedPastThoughts(), isFalse);

      await s.resolveThought(s.thoughts.single);
      expect(await s.canProceedPastThoughts(), isTrue);
    });

    test('tasks do not block closing - only thoughts do', () async {
      final s = await freshState();
      await s.addTask('still outstanding');
      expect(await s.canProceedPastThoughts(), isTrue);
    });

    test('promoting a thought creates a task and resolves the thought',
        () async {
      final s = await freshState();
      await s.addThought('buy a domain');
      await s.promoteThought(s.thoughts.single);

      expect(s.tasks.single.text, 'buy a domain');
      expect(s.thoughts, isEmpty);
    });

    test('deleting a workspace cascades to its tasks, history included',
        () async {
      final s = await freshState();
      await s.saveWorkspace(name: 'Side project', color: '#7ee3a1');
      final side = s.currentWorkspaceUuid!;
      await s.addTask('still open');
      await s.addTask('already done');
      await s.completeTask(s.tasks.last);

      await s.deleteWorkspace(side);

      expect(s.workspaces.any((w) => w.uuid == side), isFalse);

      // Both rows must be tombstoned, not dropped, so the deletion reaches
      // other devices. Completed ones count: leaving them behind would strand
      // history in a workspace that no longer exists.
      final rows = await s.store.raw
          .query('tasks', where: 'workspace_uuid = ?', whereArgs: [side]);
      expect(rows.length, 2);
      expect(rows.every((r) => r['deleted_at'] != null), isTrue);
    });

    test('deleting the focused workspace drops focus', () async {
      final s = await freshState();
      await s.saveWorkspace(name: 'Temp', color: '#ff6c6c');
      final temp = s.currentWorkspaceUuid!;
      await s.addTask('focused here');
      await s.enterFocus(s.tasks.single);

      await s.deleteWorkspace(temp);
      expect(s.focusTask, isNull);
    });

    test('a mutation notifies the sync hook', () async {
      final s = await freshState();
      var fired = 0;
      s.onMutated = () => fired++;

      await s.addTask('triggers a sync');
      expect(fired, greaterThan(0));
    });

    test('the last workspace cannot be deleted', () async {
      final s = await freshState();
      final only = s.currentWorkspaceUuid;
      await s.deleteWorkspace(only!);
      expect(s.workspaces.length, 1);
    });

    test('thoughts and history cannot own the content area at once', () async {
      final s = await freshState();
      await s.addThought('look up that paper');

      s.toggleThoughts();
      expect(s.showThoughts, isTrue);

      // Opening history has to evict thoughts, and vice versa - the content
      // area holds exactly one view.
      await s.toggleHistory();
      expect(s.showHistory, isTrue);
      expect(s.showThoughts, isFalse);

      s.toggleThoughts();
      expect(s.showThoughts, isTrue);
      expect(s.showHistory, isFalse);
    });

    test('the thoughts panel closes itself once the last one is cleared',
        () async {
      final s = await freshState();
      await s.addThought('only one');
      s.toggleThoughts();
      expect(s.showThoughts, isTrue);

      // The count badge is the only way back to the tasks and it is hidden at
      // zero, so an empty panel would strand the user with no way out.
      await s.resolveThought(s.thoughts.single);
      expect(s.thoughts, isEmpty);
      expect(s.showThoughts, isFalse);
    });

    test('promoting the last thought also closes the panel', () async {
      final s = await freshState();
      await s.addThought('turn me into a task');
      s.toggleThoughts();

      await s.promoteThought(s.thoughts.single);
      expect(s.tasks.single.text, 'turn me into a task');
      expect(s.showThoughts, isFalse);
    });
  });

  group('theme', () {
    test('complementary colour stays vivid even for a pale input', () {
      // A washed-out workspace colour must still yield an alarm colour that
      // reads - that is the whole job of the side-thought bar.
      final c = T.complementary(const Color(0xFFE0E0E0));
      final hsl = HSLColor.fromColor(c);
      expect(hsl.saturation, greaterThan(0.8));
    });

    test('hex round-trips', () {
      expect(T.toHex(T.parseHex('#6c8cff')), '#6c8cff');
    });
  });

  group('UiScale', () {
    testWidgets('is a no-op at 1.0, so desktop is untouched', (tester) async {
      late Size seen;
      await tester.pumpWidget(
        MaterialApp(
          home: UiScale(
            scale: 1.0,
            child: Builder(builder: (context) {
              seen = MediaQuery.of(context).size;
              return const SizedBox.shrink();
            }),
          ),
        ),
      );
      expect(seen, tester.view.physicalSize / tester.view.devicePixelRatio);
      expect(find.byType(Transform), findsNothing);
    });

    testWidgets('lays the subtree out smaller than the viewport it fills',
        (tester) async {
      // The transform draws the child back up to full size, so a subtree that
      // still measured itself against the real viewport would overflow by
      // exactly the scale factor.
      final full = tester.view.physicalSize / tester.view.devicePixelRatio;
      late MediaQueryData seen;
      await tester.pumpWidget(
        MaterialApp(
          home: UiScale(
            scale: 2.0,
            child: Builder(builder: (context) {
              seen = MediaQuery.of(context);
              return const SizedBox.shrink();
            }),
          ),
        ),
      );
      expect(seen.size, full / 2);
    });

    testWidgets('scales safe-area insets with the rest', (tester) async {
      // Insets arrive in real screen pixels; left unscaled they would be
      // multiplied by the transform and push the title bar too far down.
      //
      // The size matters: the zoom applied is the largest that still leaves the
      // design width, so a MediaQueryData with no size gets no zoom at all.
      // 680 is twice the design width, which is what pins the factor at 2.
      late EdgeInsets seen;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(T.designWidth * 2, 900),
            padding: EdgeInsets.only(top: 60),
          ),
          child: MaterialApp(
            home: UiScale(
              scale: 2.0,
              child: Builder(builder: (context) {
                seen = MediaQuery.of(context).padding;
                return const SizedBox.shrink();
              }),
            ),
          ),
        ),
      );
      expect(seen.top, 30);
    });
  });

  group('TaskRow', () {
    testWidgets('renders the task text and reveals actions on hover',
        (tester) async {
      final task = Task(
        uuid: 't1',
        workspaceUuid: 'ws',
        text: 'a visible task',
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TaskRow(
            task: task,
            accent: T.accent,
            onComplete: () async {},
            onDelete: () async {},
            onFocus: () {},
          ),
        ),
      ));

      expect(find.text('a visible task'), findsOneWidget);
    });

    testWidgets('plays the slide-out before reporting completion',
        (tester) async {
      var completed = false;
      final task = Task(
        uuid: 't1',
        workspaceUuid: 'ws',
        text: 'check me off',
        createdAt: nowStamp(),
        updatedAt: nowStamp(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TaskRow(
            task: task,
            accent: T.accent,
            onComplete: () async => completed = true,
            onDelete: () async {},
            onFocus: () {},
          ),
        ),
      ));

      await tester.tap(find.byType(InkWell).first);
      await tester.pump();

      // Still mid-animation: the row must not report completion until the
      // slide-out has finished, or the list rebuilds under it.
      expect(completed, isFalse);

      await tester.pumpAndSettle();
      expect(completed, isTrue);
    });
  });

  group('TitleBar', () {
    const ws = Color(0xFF7EE3A1);

    Widget host({
      bool playing = true,
      bool paused = false,
      bool isDesktop = false,
      double volume = 0.5,
      ValueChanged<double>? onVolume,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: TitleBar(
              isDesktop: isDesktop,
              pinned: true,
              onTogglePin: () {},
              onToggleSound: () {},
              soundPlaying: playing,
              soundPaused: paused,
              onTogglePause: () {},
              volume: volume,
              onVolumeChanged: onVolume ?? (_) {},
              accent: ws,
              onClose: () {},
              onOpenSettings: () {},
              onToggleCalendar: () {},
              calendarOpen: false,
              syncColor: T.muted,
              syncTooltip: 'Sync off',
            ),
          ),
        );

    /// Pumps at the widget's real 340x480, not the 800x600 test default. The
    /// title bar's controls are all in its right-hand end, so how much room the
    /// hover panel has is entirely a function of the window width - testing it
    /// on a wide viewport would not exercise the case that matters.
    Future<void> pumpBar(
      WidgetTester tester, {
      bool playing = true,
      bool paused = false,
      bool isDesktop = false,
      double volume = 0.5,
      ValueChanged<double>? onVolume,
    }) async {
      tester.view.physicalSize = const Size(340, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(
        playing: playing,
        paused: paused,
        isDesktop: isDesktop,
        volume: volume,
        onVolume: onVolume,
      ));
    }

    /// A mouse that stays attached for the life of the test, so hover enters
    /// and exits actually fire.
    Future<TestGesture> mouse(WidgetTester tester) async {
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: Offset.zero);
      addTearDown(() => g.removePointer());
      return g;
    }

    testWidgets('the pin lights in the workspace colour, not the theme accent',
        (tester) async {
      await pumpBar(tester, isDesktop: true);
      expect(tester.widget<Icon>(find.byIcon(Icons.push_pin)).color, ws);
    });

    testWidgets('no transport button while nothing is loaded', (tester) async {
      await pumpBar(tester, playing: false);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('a paused source shows resume, and dims the headphones',
        (tester) async {
      await pumpBar(tester, paused: true);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      // Outlined headphones while paused: filled would claim audio is running.
      expect(find.byIcon(Icons.headphones_outlined), findsOneWidget);
    });

    testWidgets('hovering the transport button drops out a volume slider',
        (tester) async {
      await pumpBar(tester);
      expect(find.byType(Slider), findsNothing);

      final m = await mouse(tester);
      await m.moveTo(tester.getCenter(find.byIcon(Icons.pause_rounded)));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('the panel stays inside the window', (tester) async {
      await pumpBar(tester);
      final m = await mouse(tester);
      await m.moveTo(tester.getCenter(find.byIcon(Icons.pause_rounded)));
      await tester.pumpAndSettle();

      // The button sits in the right-hand end of the bar, so a panel centred
      // on it hangs off the edge and the far half of the slider cannot be
      // reached at all. It is right-anchored for exactly this reason.
      final panel = tester.getRect(find.byType(Slider));
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(panel.right, lessThanOrEqualTo(screen.width));
      expect(panel.left, greaterThanOrEqualTo(0.0));
    });

    testWidgets('the panel survives the pointer crossing the gap to it',
        (tester) async {
      await pumpBar(tester);
      final m = await mouse(tester);
      await m.moveTo(tester.getCenter(find.byIcon(Icons.pause_rounded)));
      await tester.pumpAndSettle();

      // Off the button, into the gap between it and the panel. Closing on the
      // spot here would make the slider unreachable by hand.
      await m.moveTo(const Offset(4, 400));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(Slider), findsOneWidget,
          reason: 'must not close inside the grace period');

      await m.moveTo(tester.getCenter(find.byType(Slider)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Slider), findsOneWidget,
          reason: 'hovering the panel itself holds it open');

      // And it does eventually go away once the pointer really leaves.
      await m.moveTo(const Offset(4, 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('dragging the slider reports the new volume', (tester) async {
      final seen = <double>[];
      await pumpBar(tester, volume: 0.5, onVolume: seen.add);

      final m = await mouse(tester);
      await m.moveTo(tester.getCenter(find.byIcon(Icons.pause_rounded)));
      await tester.pumpAndSettle();

      final track = tester.getRect(find.byType(Slider));
      await tester.tapAt(Offset(track.right - 4, track.center.dy));
      await tester.pump(const Duration(milliseconds: 400));

      expect(seen, isNotEmpty);
      expect(seen.last, greaterThan(0.5));
    });
  });

  group('getting back to the task list', () {
    testWidgets('the panel header title is itself the way back',
        (tester) async {
      var back = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PanelHeader(title: 'Parked', onBack: () => back++),
        ),
      ));

      // The label is the control - there is no separate button, which is the
      // whole point: no extra row on a 340px window.
      expect(find.text('Parked'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

      await tester.tap(find.text('Parked'));
      expect(back, 1);
    });

    testWidgets('view actions still sit on the header beside the title',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PanelHeader(
            title: 'Parked',
            onBack: () {},
            actions: const [Icon(Icons.add)],
          ),
        ),
      ));
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('the views menu ticks whichever view is open', (tester) async {
      Widget bar(WorkspaceView? open) => MaterialApp(
            home: Scaffold(
              body: WorkspaceBar(
                workspaces: [
                  Workspace(
                    uuid: 'w1',
                    name: 'Tasks',
                    color: '#6c8cff',
                    sortOrder: 0,
                    createdAt: nowStamp(),
                    updatedAt: nowStamp(),
                  ),
                ],
                currentUuid: 'w1',
                accent: T.accent,
                onSelect: (_) {},
                onEdit: (_) {},
                onCreate: () {},
                onOpenNotes: () {},
                onOpenParked: () {},
                onOpenHistory: () {},
                parkedReviewDue: false,
                openView: open,
              ),
            ),
          );

      // Nothing open: the menu offers three plain entries.
      await tester.pumpWidget(bar(null));
      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      await tester.tapAt(const Offset(5, 400)); // dismiss
      await tester.pumpAndSettle();

      // Parked open: exactly one tick, so re-picking it to close is findable.
      await tester.pumpWidget(bar(WorkspaceView.parked));
      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });

  group('reminders', () {
    test('a task with no reminder is never due', () async {
      final s = await freshState();
      await s.addTask('unscheduled');
      expect(s.tasks.single.isDue(), isFalse);
    });

    test('is due once its time has passed, and not before', () async {
      final s = await freshState();
      await s.addTask('call the dentist');
      final at = DateTime.now().add(const Duration(hours: 1));
      await s.setReminder(s.tasks.single, at);

      final t = s.tasks.single;
      expect(t.isDue(), isFalse);
      expect(t.isDue(at.add(const Duration(minutes: 1))), isTrue);
    });

    test('survives the round trip through the database as an instant',
        () async {
      final s = await freshState();
      await s.addTask('leave for the train');
      final at = DateTime.now().add(const Duration(minutes: 90));
      await s.setReminder(s.tasks.single, at);

      await s.refreshTasks();
      // Stored in UTC, read back as local: the instant is what has to match,
      // not the wall-clock string.
      expect(
        s.tasks.single.remindAtTime!.difference(at).inSeconds.abs(),
        lessThan(1),
      );
    });

    test('a completed task stops being due', () async {
      final s = await freshState();
      await s.addTask('already handled');
      await s.setReminder(
          s.tasks.single, DateTime.now().subtract(const Duration(minutes: 5)));
      final t = s.tasks.single;
      expect(t.isDue(), isTrue);

      await s.completeTask(t);
      expect(await s.store.dueReminders(), isEmpty);
    });

    test('clearing disarms it', () async {
      final s = await freshState();
      await s.addTask('never mind');
      await s.setReminder(
          s.tasks.single, DateTime.now().subtract(const Duration(minutes: 1)));
      expect(await s.store.dueReminders(), hasLength(1));

      await s.setReminder(s.tasks.single, null);
      expect(s.tasks.single.remindAt, isNull);
      expect(await s.store.dueReminders(), isEmpty);
    });

    test('finds due tasks in other workspaces too', () async {
      final s = await freshState();
      final home = s.currentWorkspaceUuid!;
      await s.saveWorkspace(name: 'Work', color: '#7ee3a1');
      await s.addTask('in the other workspace');
      await s.setReminder(
          s.tasks.single, DateTime.now().subtract(const Duration(minutes: 1)));

      await s.selectWorkspace(home);
      expect(s.tasks, isEmpty); // not on screen...
      expect(await s.store.dueReminders(), hasLength(1)); // ...but still due
    });

    test('announces each reminder once, and again if it is re-armed', () async {
      final s = await freshState();
      await s.addTask('nag me');
      await s.setReminder(
          s.tasks.single, DateTime.now().subtract(const Duration(minutes: 1)));

      final announced = <String>[];
      final service = ReminderService(
        s.store,
        onDue: (due) async => announced.addAll(due.map((t) => t.text)),
      );

      await service.tick();
      await service.tick();
      // Still due on the second tick, but surfacing the window every 20s
      // because of one unfinished task would make the app unusable.
      expect(announced, ['nag me']);

      await s.setReminder(s.tasks.single, null);
      await service.tick();
      await s.setReminder(
          s.tasks.single, DateTime.now().subtract(const Duration(seconds: 1)));
      await service.tick();
      expect(announced, ['nag me', 'nag me']);

      service.dispose();
    });
  });

  group('reminder presets', () {
    test('never offers a time in the past', () {
      // 23:30 - both fixed points (18:00 today, 09:00 tomorrow) are the
      // interesting case here: the evening one has gone, tomorrow has not.
      final late = DateTime(2026, 7, 21, 23, 30);
      final presets = reminderPresets(late);

      expect(presets, isNotEmpty);
      for (final p in presets) {
        expect(p.at.isAfter(late), isTrue, reason: '${p.label} is in the past');
      }
      expect(presets.map((p) => p.label), isNot(contains('This evening (18:00)')));
    });

    test('offers this evening while it is still ahead', () {
      final presets = reminderPresets(DateTime(2026, 7, 21, 9));
      expect(presets.map((p) => p.label), contains('This evening (18:00)'));
    });

    test('describes an armed reminder in human terms', () {
      final now = DateTime(2026, 7, 21, 10);
      expect(describeReminder(now.add(const Duration(minutes: 25)), now),
          'in 26m');
      expect(describeReminder(DateTime(2026, 7, 21, 18), now), 'at 18:00');
      expect(describeReminder(DateTime(2026, 7, 22, 9), now), 'tomorrow 09:00');
      expect(describeReminder(DateTime(2026, 7, 21, 9), now), 'due since 09:00');
    });
  });

  // install() needs a notification area, so only the dispatch is covered here.
  // That is the part with a decision in it: Quit must go through the caller's
  // close guard rather than tearing the app down from the menu.
  group('AppTray', () {
    late List<String> calls;
    late AppTray tray;

    setUp(() {
      calls = [];
      tray = AppTray(
        onShow: () async => calls.add('show'),
        onHide: () async => calls.add('hide'),
        onAddTask: () async => calls.add('add-task'),
        onQuit: () async => calls.add('quit'),
      );
    });

    Future<void> click(String key) =>
        tray.handleMenuItem(MenuItem(key: key, label: key));

    test('routes each item to its action', () async {
      await click('show');
      await click('hide');
      await click('add-task');
      expect(calls, ['show', 'hide', 'add-task']);
    });

    test('quit asks the close guard rather than exiting', () async {
      await click('quit');
      expect(calls, ['quit']);
    });

    test('ignores an unknown item instead of throwing', () async {
      await click('nonexistent');
      expect(calls, isEmpty);
    });
  });
}
