// The shopping list's rules, below the screen: what "current" means, that a
// tick keeps an item's place, that finishing archives, and that two devices
// starting a list offline lose nothing.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/protocol.dart';
import 'package:todo_widget/sync/sync_client.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> fresh() async {
    final store =
        await LocalStore.open(path: inMemoryDatabasePath, singleInstance: false);
    final s = AppState(store);
    await s.load();
    return s;
  }

  List<String> texts(AppState s, {required bool checked}) => [
        for (final i in s.listItems)
          if (i.isChecked == checked) i.text,
      ];

  test('the first item starts the list', () async {
    final s = await fresh();
    expect(s.currentList, isNull);

    await s.addListItem('Milk');
    await s.addListItem('  Bread ');
    await s.addListItem('   '); // nothing

    expect(s.currentList!.name, AppState.defaultListName);
    expect(texts(s, checked: false), ['Milk', 'Bread']);
  });

  test('a tick keeps the place an untick goes back to', () async {
    final s = await fresh();
    for (final t in ['Milk', 'Bread', 'Eggs']) {
      await s.addListItem(t);
    }
    await s.setListItemChecked(s.listItems[0], true);
    expect(texts(s, checked: false), ['Bread', 'Eggs']);
    expect(texts(s, checked: true), ['Milk']);

    await s.setListItemChecked(
        s.listItems.firstWhere((i) => i.text == 'Milk'), false);
    expect(texts(s, checked: false), ['Milk', 'Bread', 'Eggs']);
  });

  test('reorder, retitle, and clearing a title deletes', () async {
    final s = await fresh();
    for (final t in ['Milk', 'Bread', 'Eggs']) {
      await s.addListItem(t);
    }
    final byText = {for (final i in s.listItems) i.text: i.uuid};
    await s.reorderListItems([byText['Eggs']!, byText['Milk']!, byText['Bread']!]);
    expect(texts(s, checked: false), ['Eggs', 'Milk', 'Bread']);

    await s.editListItem(s.listItems.first, '6 eggs');
    await s.editListItem(s.listItems.last, '');
    expect(texts(s, checked: false), ['6 eggs', 'Milk']);
  });

  test('finishing archives it as it is, and the next list starts empty',
      () async {
    final s = await fresh();
    await s.addListItem('Milk');
    await s.addListItem('Bread');
    await s.setListItemChecked(s.listItems.first, true);
    final first = s.currentList!;

    await s.finishList();
    expect(s.currentList, isNull);
    expect(s.listItems, isEmpty);

    final archived = await s.archivedLists();
    expect(archived.single.uuid, first.uuid);
    final kept = await s.itemsOfList(first.uuid);
    expect(kept.map((i) => (i.text, i.isChecked)),
        [('Milk', true), ('Bread', false)]);
    expect((await s.listItemCounts())[first.uuid], 2);

    await s.addListItem('Coffee');
    expect(s.currentList!.uuid, isNot(first.uuid));

    await s.deleteList(archived.single);
    expect(await s.archivedLists(), isEmpty);
  });

  test('two lists started offline: the newer is current, the older merges in',
      () async {
    final a = await fresh();
    final b = await fresh();
    await a.addListItem('Milk');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.addListItem('Nails');

    // Each device's rows reach the other, the way a sync would bring them.
    await a.store.applyRemote(await b.store.dirtyRows());
    await b.store.applyRemote(await a.store.dirtyRows());
    await a.loadList();
    await b.loadList();

    // Both agree which is current, without anything having to enforce it.
    expect(a.currentList!.uuid, b.currentList!.uuid);
    expect(a.otherOpenLists, hasLength(1));

    await a.mergeListIntoCurrent(a.otherOpenLists.single);
    expect(a.otherOpenLists, isEmpty);
    expect(texts(a, checked: false), ['Nails', 'Milk']);
  });

  test('opening the list closes the calendar and the views', () async {
    final s = await fresh();
    await s.toggleCalendar();
    await s.setListOpen(true);
    expect(s.showList, isTrue);
    expect(s.showCalendar, isFalse);

    await s.toggleCalendar();
    expect(s.showList, isFalse);
  });

  test('the lists are not pushed to a server below protocol 3', () async {
    final s = await fresh();
    await s.addListItem('Milk');
    final sent = <Map<String, dynamic>>[];
    final client = SyncClient(
      baseUrl: 'http://x',
      token: 't',
      client: MockClient((req) async {
        sent.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'cursor': 1, 'changes': {}}), 200);
      }),
    );

    await client.syncOnce(
      s.store,
      server: const ServerProtocol(speaks: 2, minClient: 1),
    );
    expect((sent.last['changes'] as Map).containsKey('lists'), isFalse);
    expect((await s.store.dirtyRows())['list_items'], hasLength(1));

    await client.syncOnce(
      s.store,
      server: const ServerProtocol(speaks: kListsProtocol, minClient: 1),
    );
    expect((sent.last['changes'] as Map)['list_items'], hasLength(1));
  });
}
