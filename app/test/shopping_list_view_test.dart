// The shopping list screen: what a person in a shop actually touches.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/shopping_list.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const size = Size(T.designWidth, 640);

  Future<AppState> fresh(WidgetTester tester, [List<String> items = const []]) async {
    late AppState s;
    await tester.runAsync(() async {
      final store = await LocalStore.open(
          path: inMemoryDatabasePath, singleInstance: false);
      s = AppState(store);
      await s.load();
      for (final t in items) {
        await s.addListItem(t);
      }
    });
    return s;
  }

  Future<void> show(WidgetTester tester, AppState s) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LayoutScope(
          layout: const Layout(size, touch: true),
          child: ShoppingListView(state: s),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Let a store write finish, then the frames it causes.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty list opens ready to type into', (tester) async {
    final s = await fresh(tester);
    await show(tester, s);

    expect(find.text('New list'), findsOneWidget);
    expect(find.text('Add an item'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(s.listItems.single.text, 'Milk');
    expect(s.currentList!.name, AppState.defaultListName);
  });

  testWidgets('Enter keeps adding: a new list stays in Edit until Done', (
    tester,
  ) async {
    final s = await fresh(tester);
    await show(tester, s);
    final addField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Add an item',
    );

    for (final item in ['Milk', 'Eggs', 'Bread']) {
      await tester.enterText(addField, item);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      // Still the field, still focused: the next item goes straight in.
      expect(addField, findsOneWidget, reason: 'after $item');
      expect(
        tester.widget<TextField>(addField).focusNode!.hasFocus,
        isTrue,
        reason: 'after $item',
      );
    }
    expect([for (final i in s.listItems) i.text], ['Milk', 'Eggs', 'Bread']);

    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(addField, findsNothing, reason: 'Done is what settles it');
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('Ctrl+Enter adds what is typed and leaves Edit', (tester) async {
    final s = await fresh(tester, ['Milk']);
    await show(tester, s);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final addField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Add an item',
    );
    await tester.enterText(addField, 'Eggs');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    expect([for (final i in s.listItems) i.text], ['Milk', 'Eggs']);
    expect(addField, findsNothing);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('a list with items opens in Use, where a tap ticks and the row '
      'slides below the rest', (tester) async {
    final s = await fresh(tester, ['Milk', 'Bread', 'Eggs']);
    await show(tester, s);

    // Use: no add field, the big Edit button.
    expect(find.text('Add an item'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);

    final before = tester.getTopLeft(find.text('Milk')).dy;
    await tester.tap(find.text('Milk'));
    await settle(tester);

    expect(find.text('Ticked · 1'), findsOneWidget);
    // It moved down past the two still to get, and Bread took its place.
    expect(tester.getTopLeft(find.text('Milk')).dy, greaterThan(before));
    expect(tester.getTopLeft(find.text('Bread')).dy, before);

    // And back up when unticked.
    await tester.tap(find.text('Milk'));
    await settle(tester);
    expect(find.text('Ticked · 1'), findsNothing);
    expect(tester.getTopLeft(find.text('Milk')).dy, before);
  });

  testWidgets('Edit retitles, and Done saves it', (tester) async {
    final s = await fresh(tester, ['Milk']);
    await show(tester, s);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Add an item'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Milk'), '2× milk');
    await tester.tap(find.text('Done'));
    await settle(tester);

    expect(s.listItems.single.text, '2× milk');
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('Finished archives it, quietly reachable afterwards',
      (tester) async {
    final s = await fresh(tester, ['Milk']);
    await show(tester, s);

    await tester.tap(find.text('Milk'));
    await settle(tester);
    await tester.tap(find.text('Finished'));
    await settle(tester);

    expect(s.currentList, isNull);
    expect(find.text('New list'), findsOneWidget);

    await tester.tap(find.text('Archived lists →'));
    await settle(tester);
    await settle(tester); // two queries, one after the other
    expect(find.text(AppState.defaultListName), findsOneWidget);
    expect(find.textContaining('1 item'), findsOneWidget);
  });

  testWidgets('sections: a heading over what is left to get there', (
    tester,
  ) async {
    final s = await fresh(tester, ['Bread']);
    await tester.runAsync(() async {
      await s.addListItem('Rewe', asSection: true);
      await s.addListItem('Milk');
      await s.addListItem('Market', asSection: true);
      await s.addListItem('Apples');
    });
    await show(tester, s);
    expect(find.text('Rewe'), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);

    // Everything at the market ticked: its heading has nothing to say.
    await tester.tap(find.text('Apples'));
    await settle(tester);
    expect(find.text('Market'), findsNothing);
    expect(find.text('Apples'), findsOneWidget, reason: 'under Ticked');
  });

  testWidgets('Edit adds a heading, and a heading aims the add field', (
    tester,
  ) async {
    final s = await fresh(tester, ['Milk']);
    await show(tester, s);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final addField = find.byWidgetPredicate(
      (w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Add'),
    );

    await tester.enterText(addField, 'Rewe');
    await tester.tap(find.byTooltip('Add as a section heading'));
    await settle(tester);
    expect(s.listItems.last.isSection, isTrue);

    await tester.enterText(addField, 'Bread');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await tester.enterText(addField, 'Apples');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    // A second heading, then aim back at Rewe - no longer the last section,
    // so an add there lands in the middle of the list.
    await tester.enterText(addField, 'Market');
    await tester.tap(find.byTooltip('Add as a section heading'));
    await settle(tester);
    await tester.tap(find.byTooltip('Add to this section').first);
    await tester.pumpAndSettle();
    expect(find.text('Add to Rewe'), findsOneWidget);
    await tester.enterText(addField, 'Eggs');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect([for (final i in s.listItems) i.text],
        ['Milk', 'Rewe', 'Bread', 'Apples', 'Eggs', 'Market']);
  });
}
