// Kept stations, and what a directory answer turns into.
//
// No network here: the library is settings rows, and the directory's search
// shares one parser with the genre lists, which is tested on a fixture.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/sound/radio_library.dart';
import 'package:todo_widget/sound/sound_service.dart';
import 'package:todo_widget/sound/sources.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/sound_sheet.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<LocalStore> store() =>
      LocalStore.open(path: inMemoryDatabasePath, singleInstance: false);

  const fip = Station(
    uuid: 'uuid-fip',
    name: 'FIP',
    url: 'https://icecast.radiofrance.fr/fip-hifi.aac',
    codec: 'AAC',
    bitrate: 192,
  );

  group('RadioLibrary', () {
    test('a star survives a restart, and a second press takes it off',
        () async {
      final db = await store();
      final lib = RadioLibrary(db);
      await lib.load();
      await lib.toggleFavourite(fip);

      final again = RadioLibrary(db);
      await again.load();
      expect(again.isFavourite(fip), isTrue);
      expect(again.favourites.single.url, fip.url);

      await again.toggleFavourite(fip);
      expect(again.isFavourite(fip), isFalse);
      await db.close();
    });

    test('a custom stream is kept by URL and has no directory uuid', () async {
      final db = await store();
      final lib = RadioLibrary(db);
      await lib.load();

      final added =
          await lib.addCustom('', 'https://stream.example.org/live.mp3');
      expect(added, isNotNull);
      expect(added!.uuid, isEmpty,
          reason: 'reportPlay must not tell the directory about it');
      expect(added.name, 'stream.example.org');

      final again = RadioLibrary(db);
      await again.load();
      expect(again.isCustom(added), isTrue);
      expect(again.saved.first.url, 'https://stream.example.org/live.mp3');

      await again.removeCustom(added);
      expect(again.custom, isEmpty);
      await db.close();
    });

    test('refuses something that is not a stream URL', () async {
      final db = await store();
      final lib = RadioLibrary(db);
      await lib.load();
      expect(await lib.addCustom('x', 'not a url'), isNull);
      expect(await lib.addCustom('x', 'ftp://example.org/a'), isNull);
      expect(lib.custom, isEmpty);
      await db.close();
    });

    test('adding the same stream twice keeps one', () async {
      final db = await store();
      final lib = RadioLibrary(db);
      await lib.load();
      await lib.addCustom('One', 'https://example.org/s');
      await lib.addCustom('Renamed', 'https://example.org/s');
      expect(lib.custom.single.name, 'Renamed');
      await db.close();
    });

    test('a corrupt row reads as nothing saved', () async {
      final db = await store();
      await db.setSetting('ui:radio-favourites', '{not json');
      final lib = RadioLibrary(db);
      await lib.load();
      expect(lib.favourites, isEmpty);
      await db.close();
    });
  });

  group('RadioBrowser.parseStations', () {
    Map<String, dynamic> entry(String name, {int ok = 1, String url = 'u'}) => {
          'stationuuid': 'id-$name',
          'name': name,
          'url_resolved': url,
          'lastcheckok': ok,
          'codec': 'MP3',
          'bitrate': 128,
        };

    test('keeps playable stations, one per name', () {
      final body = jsonEncode([
        entry('SomaFM Drone Zone'),
        entry('somafm drone zone'), // same station, lower in the ranking
        entry('Broken', ok: 0),
        entry('No URL', url: ''),
        entry('FIP'),
      ]);
      final parsed = RadioBrowser.parseStations(body);
      expect(parsed.map((s) => s.name), ['SomaFM Drone Zone', 'FIP']);
      expect(parsed.first.subtitle, 'MP3 · 128kbps');
    });

    test('a station round-trips through JSON', () {
      final back = Station.fromJson(fip.toJson());
      expect(back.uuid, fip.uuid);
      expect(back.bitrate, 192);
    });
  });

  group('the radio tab', () {
    testWidgets('opens on the saved stations, and the star takes one off',
        (tester) async {
      late LocalStore db;
      late SoundService sound;
      await tester.runAsync(() async {
        db = await store();
        sound = SoundService(db);
        await sound.radio.load();
        await sound.radio.toggleFavourite(fip);
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: sound,
            builder: (context, _) => Stack(children: [
              SoundSheet(sound: sound, accent: T.accent, onClose: () {}),
            ]),
          ),
        ),
      ));
      await tester.tap(find.text('Radio'));
      await tester.pump();

      expect(find.text('FIP'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.text('+ Add a stream URL'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.star_rounded));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('FIP'), findsNothing);
      await tester.runAsync(db.close);
    });
  });
}
