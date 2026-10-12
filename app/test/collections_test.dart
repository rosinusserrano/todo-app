// Collections: the rules below the screen (fields diffed on save, a removed
// field's values kept, the cascades, the protocol hold-back), the sort and
// search helpers, and the entry form's Enter - the part Marco called very
// important: it jumps to the next typed field, skips a checkbox, and on the
// last field adds the entry and starts the next.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/sync/protocol.dart';
import 'package:todo_widget/sync/sync_client.dart';
import 'package:todo_widget/ui/collections.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> fresh() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final s = AppState(store);
    await s.load();
    await s.toggleCollections();
    return s;
  }

  const movies = [
    FieldDraft(name: 'Title'),
    FieldDraft(name: 'Year', kind: FieldKind.number),
    FieldDraft(name: 'Seen', kind: FieldKind.check),
  ];

  group('state', () {
    test('a collection is made with its fields, in order', () async {
      final s = await fresh();
      final c = await s.saveCollection(name: ' Movies ', fields: movies);

      expect(c!.name, 'Movies');
      expect(s.collections.single.uuid, c.uuid);
      expect(s.collectionFields[c.uuid]!.map((f) => f.name), [
        'Title',
        'Year',
        'Seen',
      ]);
      expect(s.collectionFields[c.uuid]!.map((f) => f.kind), [
        FieldKind.text,
        FieldKind.number,
        FieldKind.check,
      ]);
    });

    test('saving fields renames, retypes, reorders, adds and removes', () async {
      final s = await fresh();
      final c = (await s.saveCollection(name: 'Movies', fields: movies))!;
      final [title, year, seen] = s.collectionFields[c.uuid]!;

      await s.saveCollection(
        existing: c,
        name: 'Films',
        fields: [
          FieldDraft(uuid: seen.uuid, name: 'Watched', kind: FieldKind.check),
          FieldDraft(uuid: title.uuid, name: 'Title', kind: FieldKind.text),
          const FieldDraft(name: 'Link', kind: FieldKind.link),
        ],
      );

      expect(s.collections.single.name, 'Films');
      final after = s.collectionFields[c.uuid]!;
      expect(after.map((f) => f.name), ['Watched', 'Title', 'Link']);
      expect(after.first.uuid, seen.uuid);
      expect(after.any((f) => f.uuid == year.uuid), isFalse);
    });

    test('an entry keeps the values of a field removed since', () async {
      final s = await fresh();
      final c = (await s.saveCollection(name: 'Movies', fields: movies))!;
      final [title, year, _] = s.collectionFields[c.uuid]!;
      final e = (await s.saveEntry(c, {title.uuid: 'Heat', year.uuid: '1995'}))!;

      // Year goes; the form now shows only Title.
      await s.saveCollection(
        existing: c,
        name: 'Movies',
        fields: [FieldDraft(uuid: title.uuid, name: 'Title')],
      );
      final edited = await s.saveEntry(c, {
        title.uuid: 'Heat (1995)',
      }, existing: e);

      expect(edited!.valueOf(title.uuid), 'Heat (1995)');
      expect(edited.valueOf(year.uuid), '1995');
    });

    test('empty values are dropped, and an empty entry is not one', () async {
      final s = await fresh();
      final c = (await s.saveCollection(name: 'Movies', fields: movies))!;
      final [title, year, seen] = s.collectionFields[c.uuid]!;

      expect(await s.saveEntry(c, {title.uuid: '  ', seen.uuid: ''}), isNull);
      expect(s.collectionEntries[c.uuid], isEmpty);

      final e = await s.saveEntry(c, {title.uuid: ' Heat ', year.uuid: ''});
      expect(e!.data, {title.uuid: 'Heat'});

      // Cleared to nothing deletes, as a task cleared to nothing does.
      expect(await s.saveEntry(c, {title.uuid: ''}, existing: e), isNull);
      expect(s.collectionEntries[c.uuid], isEmpty);
    });

    test('a checkbox ticks in place', () async {
      final s = await fresh();
      final c = (await s.saveCollection(name: 'Movies', fields: movies))!;
      final [title, _, seen] = s.collectionFields[c.uuid]!;
      final e = (await s.saveEntry(c, {title.uuid: 'Heat'}))!;

      await s.setEntryChecked(e, seen, true);
      expect(s.collectionEntries[c.uuid]!.single.isChecked(seen.uuid), isTrue);

      await s.setEntryChecked(s.collectionEntries[c.uuid]!.single, seen, false);
      expect(s.collectionEntries[c.uuid]!.single.data, {title.uuid: 'Heat'});
    });

    test('deleting a collection tombstones its fields and entries', () async {
      final s = await fresh();
      final c = (await s.saveCollection(name: 'Movies', fields: movies))!;
      final title = s.collectionFields[c.uuid]!.first;
      await s.saveEntry(c, {title.uuid: 'Heat'});

      await s.deleteCollection(c);
      expect(s.collections, isEmpty);

      final dirty = await s.store.dirtyRows();
      for (final table in [
        'collections',
        'collection_fields',
        'collection_entries',
      ]) {
        expect(
          dirty[table]!.every((r) => r['deleted_at'] != null),
          isTrue,
          reason: table,
        );
      }
    });

    test('deleting a workspace takes its collections with it', () async {
      final s = await fresh();
      await s.saveWorkspace(name: 'Home', color: '#83c0a0');
      final home = s.currentWorkspaceUuid!;
      await s.toggleCollections();
      final c = (await s.saveCollection(name: 'Recipes', fields: movies))!;
      await s.saveEntry(c, {s.collectionFields[c.uuid]!.first.uuid: 'Curry'});

      await s.deleteWorkspace(home);
      expect(await s.store.collections(home), isEmpty);
      expect(await s.store.collectionEntries(home), isEmpty);
    });

    test('collections belong to their workspace', () async {
      final s = await fresh();
      await s.saveCollection(name: 'Movies', fields: movies);
      final first = s.currentWorkspaceUuid!;

      await s.saveWorkspace(name: 'Home', color: '#83c0a0');
      expect(s.showCollections, isFalse, reason: 'a switch closes the view');
      await s.toggleCollections();
      expect(s.collections, isEmpty);

      await s.selectWorkspace(first);
      await s.toggleCollections();
      expect(s.collections.single.name, 'Movies');
    });

    test('collections are not pushed to a server below protocol 4', () async {
      final s = await fresh();
      final c = (await s.saveCollection(name: 'Movies', fields: movies))!;
      await s.saveEntry(c, {s.collectionFields[c.uuid]!.first.uuid: 'Heat'});
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
        server: const ServerProtocol(speaks: 3, minClient: 1),
      );
      final held = sent.last['changes'] as Map;
      expect(held.containsKey('collections'), isFalse);
      expect(held.containsKey('collection_fields'), isFalse);
      expect(held.containsKey('collection_entries'), isFalse);
      expect((await s.store.dirtyRows())['collection_entries'], hasLength(1));

      await client.syncOnce(
        s.store,
        server: const ServerProtocol(speaks: kCollectionsProtocol, minClient: 1),
      );
      final now = sent.last['changes'] as Map;
      expect(now['collections'], hasLength(1));
      expect(now['collection_fields'], hasLength(3));
      expect(now['collection_entries'], hasLength(1));
    });

    test('an entry from another device arrives on the open view', () async {
      final s = await fresh();
      final c = (await s.saveCollection(name: 'Movies', fields: movies))!;
      final title = s.collectionFields[c.uuid]!.first;
      const stamp = '2026-10-13T20:00:00+02:00';

      await s.store.applyRemote({
        'collection_entries': [
          {
            'uuid': 'remote',
            'collection_uuid': c.uuid,
            'data': jsonEncode({title.uuid: 'Ronin'}),
            'sort_order': 0,
            'created_at': stamp,
            'updated_at': stamp,
            'deleted_at': null,
          },
        ],
      });
      // What onChangesApplied runs.
      await s.refreshTasks();
      expect(
        s.collectionEntries[c.uuid]!.single.valueOf(title.uuid),
        'Ronin',
      );
    });
  });

  group('helpers', () {
    CollectionField field(String uuid, FieldKind kind) => CollectionField(
      uuid: uuid,
      collectionUuid: 'c',
      name: uuid,
      kind: kind,
      createdAt: 'x',
      updatedAt: 'x',
    );
    CollectionEntry entry(String uuid, Map<String, String> data) =>
        CollectionEntry(
          uuid: uuid,
          collectionUuid: 'c',
          data: data,
          createdAt: 'x',
          updatedAt: 'x',
        );

    final name = field('name', FieldKind.text);
    final year = field('year', FieldKind.number);
    final link = field('link', FieldKind.link);
    final seen = field('seen', FieldKind.check);
    final fields = [name, year, link, seen];

    final entries = [
      entry('a', {'name': 'heat', 'year': '1995'}),
      entry('b', {'name': 'Alien', 'year': '1979', 'seen': '1'}),
      entry('c', {'name': 'Ronin', 'link': 'www.imdb.com/title/tt0122690'}),
      entry('d', {'name': 'Up', 'year': '2009,5'}),
    ];

    List<String> ids(List<CollectionEntry> es) => [for (final e in es) e.uuid];

    test('newest first is the order they came in', () {
      expect(ids(sortEntries(entries, fields)), ['a', 'b', 'c', 'd']);
      expect(ids(sortEntries(entries, fields, descending: true)), [
        'd',
        'c',
        'b',
        'a',
      ]);
    });

    test('text sorts without regard to case', () {
      expect(ids(sortEntries(entries, fields, sortField: 'name')), [
        'b',
        'a',
        'c',
        'd',
      ]);
    });

    test('numbers sort as numbers, a comma is a decimal point, and an empty '
        'value is last either way round', () {
      expect(ids(sortEntries(entries, fields, sortField: 'year')), [
        'b',
        'a',
        'd',
        'c',
      ]);
      expect(
        ids(sortEntries(entries, fields, sortField: 'year', descending: true)),
        ['d', 'a', 'b', 'c'],
      );
    });

    test('a checkbox sorts ticked first', () {
      expect(ids(sortEntries(entries, fields, sortField: 'seen')).first, 'b');
    });

    test('search looks in every typed field, case-insensitively', () {
      expect(ids(filterEntries(entries, fields, 'ALI')), ['b']);
      expect(ids(filterEntries(entries, fields, 'imdb')), ['c']);
      expect(ids(filterEntries(entries, fields, '  ')), ids(entries));
    });

    test('a link is called by its host', () {
      expect(linkLabel('https://www.chefkoch.de/rezepte/1/curry'), 'chefkoch.de');
      expect(linkLabel('chefkoch.de/rezepte/1'), 'chefkoch.de');
      expect(linkUri('chefkoch.de/x').toString(), 'https://chefkoch.de/x');
      expect(linkUri('mailto:a@b.c')!.scheme, 'mailto');
    });

    test('the table needs a column per field', () {
      expect(fitsTable([name], 1000), isFalse);
      expect(fitsTable([name, link], 2 * kCollectionColumn), isTrue);
      expect(fitsTable([name, link], 2 * kCollectionColumn - 1), isFalse);
      expect(
        fitsTable([name, seen], kCollectionColumn + kCollectionCheckColumn),
        isTrue,
      );
    });
  });

  group('the entry form', () {
    final fields = [
      const CollectionField(
        uuid: 'title',
        collectionUuid: 'c',
        name: 'Title',
        createdAt: 'x',
        updatedAt: 'x',
      ),
      const CollectionField(
        uuid: 'seen',
        collectionUuid: 'c',
        name: 'Seen',
        kind: FieldKind.check,
        createdAt: 'x',
        updatedAt: 'x',
      ),
      const CollectionField(
        uuid: 'year',
        collectionUuid: 'c',
        name: 'Year',
        kind: FieldKind.number,
        createdAt: 'x',
        updatedAt: 'x',
      ),
    ];
    const collection = Collection(
      uuid: 'c',
      workspaceUuid: 'w',
      name: 'Movies',
      createdAt: 'x',
      updatedAt: 'x',
    );

    Future<List<Map<String, String>>> open(WidgetTester tester) async {
      final saved = <Map<String, String>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutScope(
              layout: const Layout(Size(400, 700)),
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showEntryForm(
                    context,
                    collection: collection,
                    fields: fields,
                    accent: Colors.teal,
                    onSave: (values, existing) async {
                      saved.add(values);
                      return CollectionEntry(
                        uuid: 'e${saved.length}',
                        collectionUuid: 'c',
                        data: values,
                        createdAt: 'x',
                        updatedAt: 'x',
                      );
                    },
                    onDelete: (_) async {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return saved;
    }

    EditableText editable(WidgetTester tester, String label) =>
        tester.widget<EditableText>(
          find.descendant(
            of: find.widgetWithText(TextField, label),
            matching: find.byType(EditableText),
          ),
        );

    bool focused(WidgetTester tester, String label) =>
        editable(tester, label).focusNode.hasFocus;

    testWidgets('Enter jumps to the next typed field, past the checkbox', (
      tester,
    ) async {
      await open(tester);
      expect(focused(tester, 'Title'), isTrue);

      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Heat');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(focused(tester, 'Year'), isTrue);
    });

    testWidgets('Enter on the last field adds it and starts the next', (
      tester,
    ) async {
      final saved = await open(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Heat');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      await tester.tap(find.text('Seen'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Year'), '1995');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();

      expect(saved.single, {'title': 'Heat', 'year': '1995', 'seen': '1'});
      // Still open, cleared, with the caret back at the top.
      expect(find.text('Added “Heat” · 1'), findsOneWidget);
      expect(editable(tester, 'Title').controller.text, isEmpty);
      expect(editable(tester, 'Year').controller.text, isEmpty);
      expect(focused(tester, 'Title'), isTrue);

      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Ronin');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(saved, hasLength(2));
      expect(saved.last['seen'], '', reason: 'the tick was cleared too');
    });

    testWidgets('Enter on an empty form closes it', (tester) async {
      final saved = await open(tester);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.text('Add to Movies'), findsNothing);
    });
  });

  group('the view', () {
    testWidgets('Esc goes back from a collection to the list, then lets go', (
      tester,
    ) async {
      var backs = 0;
      const c = Collection(
        uuid: 'c',
        workspaceUuid: 'w',
        name: 'Movies',
        createdAt: 'x',
        updatedAt: 'x',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  backs++;
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: CollectionsView(
                collections: const [c],
                fields: const {'c': []},
                entries: const {'c': []},
                accent: Colors.teal,
                onSaveCollection: (_, _, _) async => null,
                onDeleteCollection: (_) async {},
                onSaveEntry: (_, _, _) async => null,
                onDeleteEntry: (_) async {},
                onSetChecked: (_, _, _) async {},
                onBack: () {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();
      expect(find.text('Add an entry'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Collections'), findsOneWidget);
      expect(backs, 0, reason: 'the first Esc is the view\'s own');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(backs, 1);
    });
  });
}
