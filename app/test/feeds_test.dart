// Subscribed calendars, from a fetched .ics to rows and back out again.
//
// The properties worth pinning are the ones that only show up over time or
// across devices: a refresh of an unchanged feed writes nothing (or every
// device would push the whole calendar every half hour), a meeting that moved
// keeps its row, a feed merged into an existing calendar never touches what was
// already there, and unsubscribing takes exactly the feed's events.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/sync/feeds.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/models.dart';
import 'package:todo_widget/sync/sync_client.dart';
import 'package:todo_widget/sync/protocol.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // Relative to today, because the window is: a feed is expanded from three
  // months back to a year ahead of whenever the suite runs.
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  String stamp(DateTime d) {
    final u = d.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}'
        '${two(u.minute)}${two(u.second)}Z';
  }

  final monday = today.add(Duration(days: 8 - today.weekday)); // next Monday
  final standup = DateTime(monday.year, monday.month, monday.day, 9);
  final lunch = DateTime(today.year, today.month, today.day + 2, 12);

  String feed({
    bool moveSecond = false,
    bool dropLunch = false,
    String lunchTitle = 'Lunch',
  }) {
    final second = standup.add(const Duration(days: 7));
    return [
      'BEGIN:VCALENDAR',
      'X-WR-CALNAME:Work',
      'BEGIN:VEVENT',
      'UID:standup@example',
      'SUMMARY:Standup',
      'DTSTART:${stamp(standup)}',
      'DTEND:${stamp(standup.add(const Duration(minutes: 15)))}',
      'RRULE:FREQ=WEEKLY;COUNT=4',
      'END:VEVENT',
      if (moveSecond) ...[
        'BEGIN:VEVENT',
        'UID:standup@example',
        'RECURRENCE-ID:${stamp(second)}',
        'SUMMARY:Standup (moved)',
        'DTSTART:${stamp(second.add(const Duration(hours: 2)))}',
        'DTEND:${stamp(second.add(const Duration(hours: 2, minutes: 15)))}',
        'END:VEVENT',
      ],
      if (!dropLunch) ...[
        'BEGIN:VEVENT',
        'UID:lunch@example',
        'SUMMARY:$lunchTitle',
        'LOCATION:Canteen',
        'DTSTART:${stamp(lunch)}',
        'DTEND:${stamp(lunch.add(const Duration(hours: 1)))}',
        'END:VEVENT',
      ],
      'END:VCALENDAR',
    ].join('\r\n');
  }

  late String served;
  late int fetches;

  Future<AppState> freshState() async {
    final store = await LocalStore.open(
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    final state = AppState(store);
    served = feed();
    fetches = 0;
    state.fetchFeed = (_) async {
      fetches++;
      return served;
    };
    await state.load();
    await state.refreshCalendars();
    return state;
  }

  Future<List<CalendarEvent>> feedEvents(AppState s, CalendarFeed f) =>
      s.store.feedEvents(f.uuid);

  Future<int> dirtyEvents(AppState s) async =>
      (await s.store.dirtyRows())['calendar_events']!.length;

  Future<void> markClean(AppState s) async =>
      s.store.clearDirty(await s.store.dirtyRows());

  test('subscribing makes a calendar and fills it, read-only', () async {
    final s = await freshState();
    final f = (await s.subscribe(
      url: 'webcal://example.com/work.ics',
      name: 'Work',
      text: served,
    ))!;

    final cal = s.calendars.firstWhere((c) => c.uuid == f.calendarUuid);
    expect(cal.name, 'Work');
    expect(cal.isWorkspaceCalendar, isFalse);

    final rows = await feedEvents(s, f);
    expect(rows, hasLength(5)); // four standups and a lunch
    expect(rows.every((e) => e.fromFeed), isTrue);
    expect(rows.every((e) => e.calendarUuid == cal.uuid), isTrue);
    // Quiet unless asked: the feed's own app is already alerting.
    expect(rows.every((e) => e.notifyMinutes == CalendarEvent.notifySilent),
        isTrue);
    final l = rows.firstWhere((e) => e.title == 'Lunch');
    expect(l.description, 'Canteen');
    expect(s.feedStatus[f.uuid]!.count, 5);
    expect(s.feedStatus[f.uuid]!.error, isNull);
  });

  test('refreshing an unchanged feed writes nothing', () async {
    final s = await freshState();
    final f = (await s.subscribe(url: 'https://x/a.ics', name: 'W', text: served))!;
    await markClean(s);

    await s.refreshFeed(f);
    expect(fetches, 1);
    expect(await dirtyEvents(s), 0);
  });

  test('a second device computes the same rows', () async {
    // Ids are derived from the feed and the occurrence, so a device that
    // refreshes the same subscription writes the same uuids - not a copy each.
    final a = await freshState();
    final f = (await a.subscribe(url: 'https://x/a.ics', name: 'W', text: served))!;
    final w = feedWindow();
    final again = feedRows(f, served, from: w.from, to: w.to);
    final stored = await feedEvents(a, f);
    expect(again.map((e) => e.uuid).toSet(), stored.map((e) => e.uuid).toSet());
  });

  test('a moved occurrence is an edit to its row, a removed event a tombstone',
      () async {
    final s = await freshState();
    final f = (await s.subscribe(url: 'https://x/a.ics', name: 'W', text: served))!;
    final before = {for (final e in await feedEvents(s, f)) e.uuid: e};
    await markClean(s);

    served = feed(moveSecond: true, dropLunch: true);
    await s.refreshFeed(f);

    final after = {for (final e in await feedEvents(s, f)) e.uuid: e};
    // Same set of standups, by id: the moved one kept its row.
    final moved = after.values.singleWhere((e) => e.title == 'Standup (moved)');
    expect(before.containsKey(moved.uuid), isTrue);
    // Two hours after it was scheduled - as an instant, since the feed is in
    // UTC and the week may cross a clock change.
    expect(moved.start.toUtc(),
        standup.add(const Duration(days: 7, hours: 2)).toUtc());
    // Lunch is gone - tombstoned, so the removal propagates.
    expect(after.values.where((e) => e.title == 'Lunch'), isEmpty);
    expect(await dirtyEvents(s), 2);
  });

  test('a failed fetch keeps what is there and says why', () async {
    final s = await freshState();
    final f = (await s.subscribe(url: 'https://x/a.ics', name: 'W', text: served))!;
    s.fetchFeed = (_) async => throw const FeedError('Not found.');

    await s.refreshFeed(f);
    expect(await feedEvents(s, f), hasLength(5));
    expect(s.feedStatus[f.uuid]!.error, 'Not found.');
    expect(s.feedStatus[f.uuid]!.fetchedAt, isNotNull);
  });

  test('a page instead of a calendar is refused, not read as empty', () {
    expect(() => checkFeedText('<html>Google Calendar</html>'),
        throwsA(isA<FeedError>()));
  });

  test('merged into an existing calendar, and unsubscribing takes only the '
      "feed's events", () async {
    final s = await freshState();
    final work = s.calendars.first; // the workspace's own calendar
    final mine = await s.saveEvent(
      calendarUuid: work.uuid,
      title: 'Deep work',
      start: lunch.subtract(const Duration(hours: 3)),
      end: lunch.subtract(const Duration(hours: 1)),
    );

    final f = (await s.subscribe(
      url: 'https://x/a.ics',
      name: 'Meetings',
      calendarUuid: work.uuid,
      text: served,
    ))!;
    // No new calendar: the events landed beside the one already there.
    expect(s.calendars, hasLength(1));
    final onWork = await s.store.eventsOnCalendar(work.uuid);
    expect(onWork, hasLength(6));

    await s.unsubscribe(f);
    final left = await s.store.eventsOnCalendar(work.uuid);
    expect(left.map((e) => e.uuid), [mine!.uuid]);
    expect(s.calendars.map((c) => c.uuid), contains(work.uuid));
    expect(s.feeds, isEmpty);
  });

  test('unsubscribing removes the calendar subscribing made', () async {
    final s = await freshState();
    final f = (await s.subscribe(url: 'https://x/a.ics', name: 'W', text: served))!;
    expect(s.calendars, hasLength(2));

    await s.unsubscribe(f);
    expect(s.calendars, hasLength(1));
    expect(await s.store.feedEvents(f.uuid), isEmpty);
  });

  test('deleting the calendar ends the subscription', () async {
    final s = await freshState();
    final f = (await s.subscribe(url: 'https://x/a.ics', name: 'W', text: served))!;
    final cal = s.calendars.firstWhere((c) => c.uuid == f.calendarUuid);

    await s.deleteCalendar(cal);
    expect(s.feeds, isEmpty);
  });

  test('turning alerts on lets the calendar decide', () async {
    final s = await freshState();
    final f = (await s.subscribe(url: 'https://x/a.ics', name: 'W', text: served))!;
    await s.updateFeed(f, alerts: true);
    final rows = await s.store.feedEvents(f.uuid);
    expect(rows.every((e) => e.notifyMinutes == null), isTrue);
  });

  test('a feed is fetched again only once its interval has passed', () async {
    final s = await freshState();
    await s.subscribe(url: 'https://x/a.ics', name: 'W', text: served);
    final t = DateTime.now();

    await s.refreshFeeds(now: t.add(const Duration(minutes: 5)));
    expect(fetches, 0);
    await s.refreshFeeds(now: t.add(feedInterval + const Duration(minutes: 1)));
    expect(fetches, 1);
  });

  test('a column the server did not send keeps its local value', () async {
    // A server one release behind drops feed_uuid on the way in and so cannot
    // send it back. Taking its row verbatim would reset the column to null,
    // and the event would stop being read-only on the next pull.
    final s = await freshState();
    final f = (await s.subscribe(url: 'https://x/a.ics', name: 'W', text: served))!;
    final row = (await feedEvents(s, f)).first.toMap()
      ..remove('feed_uuid')
      ..['updated_at'] = nowStamp();
    await s.store.applyRemote({'calendar_events': [row]});

    final back = await s.store.eventByUuid(row['uuid']! as String);
    expect(back!.feedUuid, f.uuid);
  });

  test('webcal is https', () {
    expect(feedUri('webcal://p01-calendars.icloud.com/x.ics').toString(),
        'https://p01-calendars.icloud.com/x.ics');
    expect(feedUri('  calendar.google.com/a.ics ')!.scheme, 'https');
    expect(feedUri(''), isNull);
  });

  test('an unexpandable rule keeps its first occurrence', () {
    final t = stamp(standup);
    final ics = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:odd\r\nSUMMARY:Odd\r\n'
        'DTSTART:$t\r\nRRULE:FREQ=YEARLY;BYWEEKNO=20\r\nEND:VEVENT\r\n'
        'END:VCALENDAR';
    final w = feedWindow();
    final f = CalendarFeed(
      uuid: 'f',
      calendarUuid: 'c',
      name: 'n',
      url: 'u',
      createdAt: nowStamp(),
      updatedAt: nowStamp(),
    );
    expect(feedRows(f, ics, from: w.from, to: w.to), hasLength(1));
  });

  test('subscriptions are held back from a server that does not know them, '
      'and go up once it does', () async {
    // A protocol-1 server rejects a push naming a table it does not know -
    // the whole push, so every other row would stop moving too.
    final s = await freshState();
    await s.subscribe(url: 'https://x/a.ics', name: 'W', text: served);

    final sent = <Map<String, dynamic>>[];
    final client = SyncClient(
      baseUrl: 'http://sync',
      token: 't',
      client: MockClient((req) async {
        sent.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'cursor': 1, 'changes': {}}), 200);
      }),
    );

    await client.syncOnce(s.store);
    expect((sent.last['changes'] as Map).containsKey('calendar_feeds'), isFalse);
    expect((sent.last['changes'] as Map)['calendar_events'], isNotEmpty);
    // Still waiting, not lost.
    expect((await s.store.dirtyRows())['calendar_feeds'], hasLength(1));

    await client.syncOnce(
      s.store,
      server: const ServerProtocol(speaks: kFeedsProtocol, minClient: 1),
    );
    expect((sent.last['changes'] as Map)['calendar_feeds'], hasLength(1));
    expect((await s.store.dirtyRows())['calendar_feeds'], isEmpty);
    // And says what it can store, or the server would hold feed_uuid back.
    expect(sent.last['protocol'], kSyncProtocol);
  });

  test('a pulled column this build does not have is dropped, not fatal',
      () async {
    // The insert failing on it would abort the whole merge, and one stray
    // column would stop every row moving - which is what a server sending
    // feed_uuid did to every build from before it.
    final store =
        await LocalStore.open(path: inMemoryDatabasePath, singleInstance: false);
    final ws = (await store.workspaces()).single;
    await store.applyRemote({
      'tasks': [
        {
          'uuid': 't1',
          'workspace_uuid': ws.uuid,
          'text': 'from the future',
          'created_at': nowStamp(),
          'updated_at': nowStamp(),
          'deleted_at': null,
          'seq': 7,
          'column_from_the_future': 'x',
        },
      ],
    });
    expect((await store.activeTasks(ws.uuid)).single.text, 'from the future');
    await store.close();
  });

  test('upgrading to v16 pulls everything again', () async {
    // A protocol-1 build was not sent feed_uuid or the feeds table, and its
    // cursor walked past those rows anyway; starting over brings them in.
    final dir = await Directory.systemTemp.createTemp('todo_feeds_migrate');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'todo.db');

    final store = await LocalStore.open(path: path, singleInstance: false);
    await store.setCursor(42);
    await store.raw.execute('DROP TABLE calendar_feeds');
    await store.raw.execute('DROP INDEX idx_events_feed');
    await store.raw.execute('ALTER TABLE calendar_events DROP COLUMN feed_uuid');
    await store.raw.setVersion(15);
    await store.close();

    final upgraded = await LocalStore.open(path: path, singleInstance: false);
    expect(await upgraded.cursor(), 0);
    expect(await upgraded.calendarFeeds(), isEmpty);
    await upgraded.close();
  });
}
