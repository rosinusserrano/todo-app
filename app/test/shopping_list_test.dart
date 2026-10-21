// The shopping list's rules, below the screen: what "current" means, that a
// tick keeps an item's place, that finishing archives, and that two devices
// starting a list offline lose nothing.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
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

  group('sections', () {
    List<String> order(AppState s) => [
          for (final i in s.listItems) i.isSection ? '# ${i.text}' : i.text,
        ];

    test('a heading, and items added into a section go to its end', () async {
      final s = await fresh();
      await s.addListItem('Bread');
      await s.addListItem('Rewe', asSection: true);
      await s.addListItem('Milk');
      await s.addListItem('Market', asSection: true);
      await s.addListItem('Apples');
      final rewe = s.listItems.firstWhere((i) => i.text == 'Rewe');
      await s.addListItem('Eggs', section: rewe.uuid);

      expect(order(s),
          ['Bread', '# Rewe', 'Milk', 'Eggs', '# Market', 'Apples']);
      final sections = listSections(s.listItems);
      expect(sections.map((x) => x.$1?.text), [null, 'Rewe', 'Market']);
      expect(sections[1].$2.map((i) => i.text), ['Milk', 'Eggs']);
      expect(await s.listItemCounts(), {s.currentList!.uuid: 4},
          reason: 'a heading is not an item');
    });

    test('a ticked item keeps its section through a reorder', () async {
      final s = await fresh();
      await s.addListItem('Rewe', asSection: true);
      await s.addListItem('Milk');
      await s.addListItem('Eggs');
      await s.addListItem('Market', asSection: true);
      await s.addListItem('Apples');
      await s.setListItemChecked(
          s.listItems.firstWhere((i) => i.text == 'Eggs'), true);

      // Edit's list is what is still to get, headings included: Market first.
      final open = [for (final i in s.listItems) if (!i.isChecked) i];
      final ids = [for (final i in open) i.uuid];
      final moved = [...ids.skip(2), ...ids.take(2)];
      await s.reorderListItems(moved);

      expect(order(s), ['# Market', 'Apples', '# Rewe', 'Milk', 'Eggs']);
      expect(s.listItems.last.isChecked, isTrue, reason: 'still after Milk');
      await s.setListItemChecked(
          s.listItems.firstWhere((i) => i.text == 'Eggs'), false);
      expect(listSections(s.listItems)[2].$2.map((i) => i.text),
          ['Milk', 'Eggs']);
    });

    test('a heading is not pushed to a server below protocol 9', () async {
      final s = await fresh();
      await s.addListItem('Milk');
      await s.addListItem('Rewe', asSection: true);
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
        server: const ServerProtocol(speaks: 8, minClient: 1),
      );
      final items = (sent.last['changes'] as Map)['list_items'] as List;
      expect(items.map((r) => r['text']), ['Milk']);
      expect((await s.store.dirtyRows())['list_items'], hasLength(1),
          reason: 'the heading waits for a server that keeps it');
    });

    test('a v23 database gains the column', () async {
      final dir = await Directory.systemTemp.createTemp('todo_list_migrate');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'todo.db');
      final store = await LocalStore.open(path: path, singleInstance: false);
      await store.raw.execute('ALTER TABLE list_items DROP COLUMN section');
      await store.raw.setVersion(23);
      await store.close();

      final upgraded = await LocalStore.open(path: path, singleInstance: false);
      final s = AppState(upgraded);
      await s.load();
      await s.addListItem('Rewe', asSection: true);
      expect(s.listItems.single.isSection, isTrue);
      await upgraded.close();
    });
  });
}
