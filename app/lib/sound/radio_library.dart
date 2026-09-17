// The stations you keep: favourites starred from the directory, and streams
// you added yourself by URL.
//
// Both are device-local `settings` rows holding JSON, like the volume. Not
// synced: which stations sound right is a fact about the person, but a
// directory stream that is fine on the desktop's wired connection may be the
// wrong bitrate for a phone, and nothing else about the sound tier syncs
// either. If that turns out to be the wrong call it is a table and a
// migration, and nothing here would need to change shape.
//
// A station is identified by [RadioLibrary.keyOf]: the directory's uuid when it
// has one, the stream URL when it does not. A custom station has no uuid - it
// is not in the directory, and inventing one would make [RadioBrowser.reportPlay]
// report plays of a station the directory has never heard of.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../sync/local_store.dart';
import 'sources.dart';

const _kFavourites = 'ui:radio-favourites';
const _kCustom = 'ui:radio-custom';

class RadioLibrary extends ChangeNotifier {
  RadioLibrary(this._store);

  final LocalStore _store;

  List<Station> _favourites = [];
  List<Station> _custom = [];

  /// Starred directory stations, most recently starred last.
  List<Station> get favourites => List.unmodifiable(_favourites);

  /// Streams added by hand, in the order they were added.
  List<Station> get custom => List.unmodifiable(_custom);

  /// Everything kept, custom streams first: those were typed in on purpose and
  /// cannot be found any other way.
  List<Station> get saved => [..._custom, ..._favourites];

  static String keyOf(Station s) => s.uuid.isNotEmpty ? s.uuid : s.url;

  Future<void> load() async {
    _favourites = _decode(await _store.setting(_kFavourites));
    _custom = _decode(await _store.setting(_kCustom));
    notifyListeners();
  }

  bool isFavourite(Station s) {
    final key = keyOf(s);
    return _favourites.any((f) => keyOf(f) == key);
  }

  bool isCustom(Station s) {
    final key = keyOf(s);
    return _custom.any((c) => keyOf(c) == key);
  }

  Future<void> toggleFavourite(Station s) async {
    final key = keyOf(s);
    if (isFavourite(s)) {
      _favourites = [
        for (final f in _favourites)
          if (keyOf(f) != key) f,
      ];
    } else {
      _favourites = [..._favourites, s];
    }
    notifyListeners();
    await _store.setSetting(_kFavourites, _encode(_favourites));
  }

  /// Returns the station as stored, or null when [url] is not something a
  /// player could open. Checked only for shape: whether the stream is alive is
  /// the player's question, and a dead one reports itself when it is played.
  Future<Station?> addCustom(String name, String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return null;
    }
    final station = Station(
      uuid: '',
      name: name.trim().isEmpty ? uri.host : name.trim(),
      url: uri.toString(),
      codec: 'custom',
      bitrate: 0,
    );
    _custom = [
      for (final c in _custom)
        if (keyOf(c) != keyOf(station)) c,
      station,
    ];
    notifyListeners();
    await _store.setSetting(_kCustom, _encode(_custom));
    return station;
  }

  Future<void> removeCustom(Station s) async {
    final key = keyOf(s);
    _custom = [
      for (final c in _custom)
        if (keyOf(c) != key) c,
    ];
    notifyListeners();
    await _store.setSetting(_kCustom, _encode(_custom));
  }

  static String _encode(List<Station> stations) =>
      jsonEncode([for (final s in stations) s.toJson()]);

  /// A corrupt row reads as empty rather than throwing: losing a list of
  /// favourites is a nuisance, a sound sheet that will not open is worse.
  static List<Station> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          Station.fromJson(item as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }
}
