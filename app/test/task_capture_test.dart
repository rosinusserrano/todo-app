import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/task_capture.dart';

Workspace ws(String uuid, String name, String color) => Workspace(
  uuid: uuid,
  name: name,
  color: color,
  sortOrder: 0,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

/// The card in a host that owns `open` the way the shell does.
class _Host extends StatefulWidget {
  const _Host({
    required this.controller,
    required this.submitted,
    required this.shortcuts,
  });

  final KeywordController controller;
  final List<CaptureResult> submitted;
  final List<(String, String)> shortcuts;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool open = false;
  bool shown = false;
  final focus = FocusNode();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 60,
          left: 8,
          child: TextButton(
            onPressed: () => setState(() {
              open = true;
              shown = true;
            }),
            child: const Text('fold'),
          ),
        ),
        Positioned.fill(
          child: TaskCapture(
            open: open,
            controller: widget.controller,
            focusNode: focus,
            workspaces: [
              ws('here', 'Tasks', '#6F86CC'),
              ws('work', 'Work', '#CC9A6A'),
            ],
            hereUuid: 'here',
            layout: const Layout(Size(340, 480)),
            originOf: () => const Rect.fromLTWH(8, 60, 324, 34),
            onSubmit: (r) async => widget.submitted.add(r),
            onExpand: (r) async => false,
            onClose: () => setState(() => open = false),
            onClosed: () => setState(() => shown = false),
            onAddShortcut: (uuid, sc) async => widget.shortcuts.add((uuid, sc)),
          ),
        ),
      ],
    );
  }
}

void main() {
  late KeywordController controller;
  late List<CaptureResult> submitted;
  late List<(String, String)> shortcuts;

  Future<void> pump(WidgetTester tester) async {
    controller = KeywordController();
    submitted = [];
    shortcuts = [];
    tester.view.physicalSize = const Size(340, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: T.bgSolid,
          body: _Host(
            controller: controller,
            submitted: submitted,
            shortcuts: shortcuts,
          ),
        ),
      ),
    );
    await tester.tap(find.text('fold'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens centred and focused', (tester) async {
    await pump(tester);
    final field = tester.getRect(find.byType(TextField));
    expect(field.center.dx, closeTo(170, 3));
    // Well below where it lifted off from.
    expect(field.top, greaterThan(120));
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    expect(find.byIcon(Icons.outlined_flag_rounded), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);
  });

  Future<void> key(
    WidgetTester tester,
    LogicalKeyboardKey k, {
    LogicalKeyboardKey? holding,
  }) async {
    if (holding != null) await tester.sendKeyDownEvent(holding);
    await tester.sendKeyEvent(k);
    if (holding != null) await tester.sendKeyUpEvent(holding);
    await tester.pump();
  }

  testWidgets('keywords set the workspace and reminder and leave the title', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(
      find.byType(TextField),
      'ring Anna #Work tomorrow 9:30',
    );
    await tester.pump();
    // The bar says what was read.
    expect(find.text('Work'), findsOneWidget);
    expect(find.textContaining('tomorrow 09:30'), findsOneWidget);

    await key(
      tester,
      LogicalKeyboardKey.enter,
      holding: LogicalKeyboardKey.controlLeft,
    );
    expect(submitted, hasLength(1));
    final r = submitted.single;
    final now = DateTime.now();
    expect(r.title, 'ring Anna');
    expect(r.workspaceUuid, 'work');
    expect(r.remindAt, DateTime(now.year, now.month, now.day + 1, 9, 30));
    // Ctrl+Enter: ready for the next one, and saying where that one went.
    expect(controller.text, isEmpty);
    expect(find.text('Added to Work'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a bare workspace name is just a word', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'Work on the report');
    await key(tester, LogicalKeyboardKey.enter);
    expect(submitted.single.title, 'Work on the report');
    expect(submitted.single.workspaceUuid, isNull);
  });

  testWidgets('Enter adds and closes', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'one thing');
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(submitted.single.title, 'one thing');
    expect(find.byType(TextField), findsNothing);
    expect(controller.text, isEmpty);
  });

  testWidgets('Shift+Enter does not add', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'two lines');
    await key(
      tester,
      LogicalKeyboardKey.enter,
      holding: LogicalKeyboardKey.shiftLeft,
    );
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the × hands a word back to the title', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'tidy up #Work');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await key(tester, LogicalKeyboardKey.enter);
    expect(submitted.single.title, 'tidy up #Work');
    expect(submitted.single.workspaceUuid, isNull);
  });

  testWidgets('priority is a toggle and resets after adding', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.outlined_flag_rounded));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'urgent thing');
    await key(
      tester,
      LogicalKeyboardKey.enter,
      holding: LogicalKeyboardKey.controlLeft,
    );
    expect(submitted.single.priority, 1);
    expect(find.byIcon(Icons.outlined_flag_rounded), findsOneWidget);
  });

  testWidgets('a recognised #workspace offers a shortcut', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'read #Work');
    await tester.pump();
    await tester.pump();
    expect(find.text('Shortcut'), findsOneWidget);

    await tester.tap(find.text('Shortcut'));
    await tester.pumpAndSettle();
    expect(find.text('Shortcut for Work'), findsOneWidget);
    // Taken: another workspace's name.
    await tester.enterText(find.byType(TextField).last, '#tasks');
    await tester.pump();
    expect(find.text('#tasks is Tasks'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '#W');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(shortcuts, [('work', 'W')]);
    // The title is left as it was.
    expect(controller.text, 'read #Work');
  });

  testWidgets('the scrim closes it and keeps the draft', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'half a thou');
    await tester.tapAt(const Offset(10, 470));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(controller.text, 'half a thou');
    expect(submitted, isEmpty);
  });

  testWidgets('Enter on nothing closes', (tester) async {
    await pump(tester);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });
}
