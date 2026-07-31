// Tiers 2 and 3: where the streamed audio comes from.
//
// Both directories were picked because they need no API key and impose no
// licence obligation on the listener:
//
//   * The Internet Archive's `radio-aporee-maps` collection is a large body of
//     field recordings, all CC0 or public-domain-mark. Searching it by keyword
//     gives café chatter, rain, cities and forests without shipping a single
//     audio file or crediting anyone.
//
//   * Radio Browser is a free, open-source directory of internet radio. No key,
//     no quota. It asks three things of clients, all honoured below: send a
//     descriptive user agent, do not hardcode one server, and report plays so
//     its rankings stay accurate.

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

const _userAgent = 'TodoWidget/0.10 (concentration sound)';

// ------------------------------------------------------------------- ambience

/// A preset is a keyword query into the aporee collection rather than a fixed
/// recording, so the same button gives a different café every time.
class AmbiencePreset {
  const AmbiencePreset(this.id, this.label, this.query);

  final String id;
  final String label;
  final String query;

  static const all = [
    AmbiencePreset('cafe', 'Café', 'cafe OR coffee OR restaurant OR pub OR bar'),
    AmbiencePreset('rain', 'Rain', 'rain OR storm OR thunder'),
    AmbiencePreset('city', 'City', 'city OR street OR traffic OR market'),
    AmbiencePreset('forest', 'Forest', 'forest OR birds OR woods'),
    AmbiencePreset('train', 'Train', 'train OR subway OR metro OR station'),
    AmbiencePreset('sea', 'Sea', 'waves OR sea OR ocean OR beach'),
  ];
}

class AmbienceTrack {
  const AmbienceTrack({required this.title, required this.url});

  final String title;
  final String url;
}

class ArchiveAmbience {
  static final _rng = Random();

  /// Resolve a preset to a playable recording. Two hops: search the collection,
  /// then read the chosen item's file list for an mp3.
  static Future<AmbienceTrack?> resolve(AmbiencePreset preset) async {
    final search = Uri.https('archive.org', '/advancedsearch.php', {
      'q': 'collection:(radio-aporee-maps) AND (${preset.query})',
      'fl[]': ['identifier', 'title'],
      'rows': '60',
      'output': 'json',
    });

    final res = await http.get(search, headers: {'User-Agent': _userAgent});
    if (res.statusCode != 200) return null;

    final docs = (jsonDecode(res.body)['response']?['docs'] as List?) ?? [];
    if (docs.isEmpty) return null;

    final doc = docs[_rng.nextInt(docs.length)] as Map<String, dynamic>;
    final id = doc['identifier'] as String;

    final metaRes = await http.get(
      Uri.https('archive.org', '/metadata/$id'),
      headers: {'User-Agent': _userAgent},
    );
    if (metaRes.statusCode != 200) return null;

    final files = (jsonDecode(metaRes.body)['files'] as List?) ?? [];
    final mp3 = files.cast<Map<String, dynamic>>().where((f) {
      final name = (f['name'] as String?) ?? '';
      return name.toLowerCase().endsWith('.mp3');
    }).firstOrNull;
    if (mp3 == null) return null;

    final name = Uri.encodeComponent(mp3['name'] as String);
    return AmbienceTrack(
      title: (doc['title'] as String?) ?? id,
      url: 'https://archive.org/download/$id/$name',
    );
  }
}

// ---------------------------------------------------------------------- radio

class RadioGenre {
  const RadioGenre(this.tag, this.label);

  final String tag;
  final String label;

  static const all = [
    RadioGenre('ambient', 'Ambient'),
    RadioGenre('drone', 'Drone'),
    RadioGenre('dub techno', 'Dub techno'),
    RadioGenre('minimal techno', 'Minimal'),
    RadioGenre('techno', 'Techno'),
    RadioGenre('lofi', 'Lo-fi'),
  ];
}

class Station {
  const Station({
    required this.uuid,
    required this.name,
    required this.url,
    required this.codec,
    required this.bitrate,
  });

  final String uuid;
  final String name;
  final String url;
  final String codec;
  final int bitrate;

  String get subtitle => bitrate > 0 ? '$codec · ${bitrate}kbps' : codec;
}

class RadioBrowser {
  /// The documented mirrors. Radio Browser explicitly asks clients not to pin a
  /// single server, so a failure falls through to the next one.
  static const _mirrors = [
    'de1.api.radio-browser.info',
    'nl1.api.radio-browser.info',
    'at1.api.radio-browser.info',
  ];

  static Future<http.Response?> _get(String path, Map<String, String>? query) async {
    for (final host in _mirrors) {
      try {
        final res = await http
            .get(Uri.https(host, path, query), headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) return res;
      } catch (_) {
        // Try the next mirror.
      }
    }
    return null;
  }

  static Future<List<Station>> byGenre(String tag) async {
    final res = await _get('/json/stations/bytag/${Uri.encodeComponent(tag)}', {
      'limit': '40',
      'hidebroken': 'true',
      'order': 'clickcount',
      'reverse': 'true',
    });
    if (res == null) return [];

    final raw = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    final seen = <String>{};
    final out = <Station>[];

    for (final s in raw) {
      final url = (s['url_resolved'] as String?) ?? '';
      if (s['lastcheckok'] != 1 || url.isEmpty) continue;

      // The directory carries plenty of near-duplicate entries for the same
      // station at different bitrates; keep the highest-ranked of each.
      final name = ((s['name'] as String?) ?? '').trim();
      if (name.isEmpty || !seen.add(name.toLowerCase())) continue;

      out.add(Station(
        uuid: (s['stationuuid'] as String?) ?? '',
        name: name,
        url: url,
        codec: (s['codec'] as String?) ?? '',
        bitrate: (s['bitrate'] as num?)?.toInt() ?? 0,
      ));
    }
    return out;
  }

  /// Report a play so the directory's rankings stay accurate. Fire-and-forget:
  /// a failure here must never affect playback.
  static void reportPlay(String uuid) {
    if (uuid.isEmpty) return;
    _get('/json/url/$uuid', null).ignore();
  }
}
