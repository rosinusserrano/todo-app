// The bookkeeping behind "30 minutes of it, on the device".
//
// The fetch is injected, so none of this touches archive.org: what is worth
// pinning is how much of a recording a bout is, that variety survives caching,
// that the index outlives the process, and that a cache which cannot fill is a
// slower app rather than a broken one.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:todo_widget/sound/ambience_cache.dart';
import 'package:todo_widget/sound/sources.dart';

const cafe = AmbiencePreset('cafe', 'Café', 'cafe');
const rain = AmbiencePreset('rain', 'Rain', 'rain');
const city = AmbiencePreset('city', 'City', 'city');

AmbienceTrack track(String id, {int bytes = 0, int seconds = 0}) =>
    AmbienceTrack(
      title: 'Recording $id',
      url: 'https://archive.org/download/$id/$id.mp3',
      bytes: bytes,
      seconds: seconds,
    );

/// A fetch that writes [size] bytes and reports success, and records what it
/// was asked for.
({BoutFetcher fetch, List<int> asked}) fake({int size = 64}) {
  final asked = <int>[];
  Future<bool> fetch(Uri url, File into, int maxBytes) async {
    asked.add(maxBytes);
    await into.writeAsBytes(List.filled(size, 0));
    return true;
  }

  return (fetch: fetch, asked: asked);
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ambience-cache-test');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  AmbienceCache open({
    BoutFetcher? fetch,
    int maxPerPreset = 2,
    int budgetBytes = 400 * 1024 * 1024,
  }) =>
      AmbienceCache(
        dir,
        fetch: fetch,
        maxPerPreset: maxPerPreset,
        budgetBytes: budgetBytes,
      );

  group('how much of a recording is a bout', () {
    test('a proportion of it, from the metadata', () {
      final cache = open();
      // An hour-long file: half an hour is half of it.
      expect(
        cache.boutBytes(track('a', bytes: 60 * 1024 * 1024, seconds: 3600)),
        30 * 1024 * 1024,
      );
    });

    test('all of it when the recording is shorter than a bout', () {
      final cache = open();
      expect(
        cache.boutBytes(track('a', bytes: 5 * 1024 * 1024, seconds: 600)),
        5 * 1024 * 1024,
      );
    });

    test('an assumed bitrate when the metadata says nothing', () {
      final cache = open();
      // 30 minutes at 128kbps. The point is that an unknown duration still
      // gets cached, rather than being refused for want of a number.
      expect(cache.boutBytes(track('a')), 1800 * 16 * 1024);
    });

    test('never more than the file, even when the duration is missing', () {
      final cache = open();
      expect(cache.boutBytes(track('a', bytes: 4096)), 4096);
    });

    test('the length can be a clock as well as a number of seconds', () {
      expect(ArchiveAmbience.parseArchiveLength('1023.45'), 1023);
      expect(ArchiveAmbience.parseArchiveLength('17:03'), 1023);
      expect(ArchiveAmbience.parseArchiveLength('1:17:03'), 4623);
      expect(ArchiveAmbience.parseArchiveLength('who knows'), 0);
      expect(ArchiveAmbience.parseArchiveLength(''), 0);
    });
  });

  group('storing', () {
    test('asks for exactly one bout and keeps what came back', () async {
      final f = fake(size: 128);
      final cache = open(fetch: f.fetch);

      final stored = await cache.store(
        cafe,
        track('a', bytes: 60 * 1024 * 1024, seconds: 3600),
      );

      expect(stored, isNotNull);
      expect(stored!.title, 'Recording a');
      expect(f.asked, [30 * 1024 * 1024]);
      expect(cache.bytes, 128);
      expect(cache.fileFor(stored).existsSync(), isTrue);
    });

    test('holds several per preset, and picks between them', () async {
      final cache = open(fetch: fake().fetch);
      await cache.store(cafe, track('a'));
      await cache.store(cafe, track('b'));

      expect(cache.countFor('cafe'), 2);

      // Variety is the whole reason a preset is a query rather than a file, so
      // caching must not turn it into one. Over enough picks both turn up.
      final seen = <String>{};
      for (var i = 0; i < 40; i++) {
        seen.add((await cache.pick('cafe'))!.title);
      }
      expect(seen, hasLength(2));
    });

    test('stops at the per-preset cap', () async {
      final cache = open(fetch: fake().fetch, maxPerPreset: 2);
      await cache.store(cafe, track('a'));
      await cache.store(cafe, track('b'));
      expect(await cache.store(cafe, track('c')), isNull);
      expect(cache.countFor('cafe'), 2);

      // Another preset is unaffected: the cap is per preset precisely so one
      // heavily used one cannot leave the others streaming for ever.
      expect(await cache.store(rain, track('d')), isNotNull);
    });

    test('does not store the same recording twice', () async {
      final cache = open(fetch: fake().fetch);
      await cache.store(cafe, track('a'));
      expect(await cache.store(cafe, track('a')), isNull);
      expect(cache.countFor('cafe'), 1);
    });

    test('a failed fetch leaves nothing behind', () async {
      Future<bool> broken(Uri url, File into, int maxBytes) async => false;
      final cache = open(fetch: broken);

      expect(await cache.store(cafe, track('a')), isNull);
      expect(cache.bouts, isEmpty);
      expect(
        dir.listSync().where((e) => e.path.endsWith('.mp3')),
        isEmpty,
      );
    });

    test('a fetch that throws is a slower app, not a broken one', () async {
      Future<bool> broken(Uri url, File into, int maxBytes) async =>
          throw const SocketException('no route to host');
      final cache = open(fetch: broken);

      expect(await cache.store(cafe, track('a')), isNull);
      expect(cache.bouts, isEmpty);
    });
  });

  group('the index', () {
    test('survives the process and forgets files that have gone', () async {
      final cache = open(fetch: fake().fetch);
      final a = await cache.store(cafe, track('a'));
      await cache.store(cafe, track('b'));

      // A second cache over the same directory is what a restart is.
      final reopened = open(fetch: fake().fetch);
      await reopened.load();
      expect(reopened.countFor('cafe'), 2);

      await reopened.fileFor(a!).delete();
      final third = open(fetch: fake().fetch);
      await third.load();
      expect(third.countFor('cafe'), 1);
    });

    test('an unreadable index starts empty rather than throwing', () async {
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'index.json')).writeAsString('{oh dear');

      final cache = open(fetch: fake().fetch);
      await cache.load();
      expect(cache.bouts, isEmpty);
      expect(await cache.store(cafe, track('a')), isNotNull);
    });
  });

  group('the budget', () {
    test('evicts the least recently played first', () async {
      // Three bouts of 100 bytes into a budget of 250, one per preset so that
      // which one is picked is a fact and not a coin toss.
      final cache =
          open(fetch: fake(size: 100).fetch, maxPerPreset: 1, budgetBytes: 250);

      await cache.store(cafe, track('a'));
      await cache.store(rain, track('b'));

      // Playing the café again leaves the rain as the oldest thing here.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cache.pick('cafe');

      await cache.store(city, track('c'));

      expect(cache.bytes, lessThanOrEqualTo(250));
      expect(cache.bouts.map((b) => b.preset).toSet(), {'cafe', 'city'});

      // What went took its file with it, and what stayed still has one.
      for (final b in cache.bouts) {
        expect(cache.fileFor(b).existsSync(), isTrue);
      }
      expect(dir.listSync().where((e) => e.path.endsWith('.mp3')).length, 2);
    });

    test('a full preset is not topped up', () async {
      var resolves = 0;
      final cache = open(fetch: fake().fetch, maxPerPreset: 1);
      await cache.store(cafe, track('a'));

      await cache.fill(cafe, () async {
        resolves++;
        return track('b');
      });
      expect(resolves, 0);
      expect(cache.countFor('cafe'), 1);
    });

    test('an empty preset is topped up', () async {
      final cache = open(fetch: fake().fetch);
      await cache.fill(cafe, () async => track('a'));
      expect(cache.countFor('cafe'), 1);
    });
  });

  test('clearing takes the files with it', () async {
    final cache = open(fetch: fake().fetch);
    await cache.store(cafe, track('a'));
    await cache.store(rain, track('b'));

    await cache.clear();

    expect(cache.bouts, isEmpty);
    expect(cache.bytes, 0);
    expect(dir.listSync().where((e) => e.path.endsWith('.mp3')), isEmpty);
    expect(await cache.pick('cafe'), isNull);
  });
}
