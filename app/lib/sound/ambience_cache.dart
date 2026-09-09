// Thirty-minute bouts of ambience, kept on the device.
//
// Of the three tiers only this one goes over the wire for something that could
// have been held: noise is synthesised locally already, and a radio station is
// a live stream that cannot be anything but streamed. Ambience is a *finite
// recording*, fetched from archive.org and then looped for an hour - so every
// re-buffer, every stall and every dropout is paid for again and again for a
// file the device could simply have.
//
// A **bout** is a 30-minute prefix of one recording. Three things about that:
//
//   - **A prefix, not the file.** The whole point of the preset is that it is a
//     *query* - "cafe OR coffee OR restaurant" - so it gives a different cafe
//     every time. Some of what it finds is four hours long. Half an hour is
//     already far longer than any sitting this widget is open for, and it is
//     bounded, which a directory of field recordings is not. The byte count
//     comes from the metadata the search already returns (`size` and `length`),
//     and is asked for with a Range header; a truncated mp3 plays to its last
//     whole frame and stops, which is exactly what looping wants.
//   - **Several per preset, and one is picked at random.** Caching one
//     recording would buy the latency and spend the variety, which is the thing
//     the preset exists for. [maxPerPreset] bouts is enough that the same cafe
//     twice running is unlikely and small enough to stay inside a sane disk
//     budget.
//   - **Filled in the background, never waited on.** A play with nothing cached
//     streams exactly as it always did and *then* stores a bout, so the cost of
//     the feature is one extra download the first time or two a preset is used
//     and nothing at all afterwards. Making somebody wait for 29MB before any
//     sound came out would be trading one kind of lag for a worse one.
//
// The index lives in the cache directory rather than in the settings table, so
// this class needs a directory and nothing else - which is also what makes it
// testable against a temp dir with the fetch injected. It is device-local by
// nature and there is nothing here to sync: a file somebody else's phone
// downloaded is not a fact about the todo list.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'sources.dart';

/// One stored recording.
class AmbienceBout {
  const AmbienceBout({
    required this.preset,
    required this.title,
    required this.file,
    required this.source,
    required this.bytes,
    required this.playedAt,
  });

  /// [AmbiencePreset.id] this was found for.
  final String preset;

  /// The recording's own title, for the transport line - the label a cached
  /// bout shows has to be the one it would have shown streaming.
  final String title;

  /// Bare filename inside the cache directory. Not an absolute path: the
  /// application support directory moves between installs on some platforms,
  /// and an index full of stale absolute paths is a cache that empties itself.
  final String file;

  /// Where it came from, so the same recording is not stored twice.
  final String source;

  final int bytes;

  /// Last played, and therefore what eviction sorts on.
  final DateTime playedAt;

  AmbienceBout touched(DateTime at) => AmbienceBout(
        preset: preset,
        title: title,
        file: file,
        source: source,
        bytes: bytes,
        playedAt: at,
      );

  Map<String, Object?> toJson() => {
        'preset': preset,
        'title': title,
        'file': file,
        'source': source,
        'bytes': bytes,
        'playedAt': playedAt.toUtc().toIso8601String(),
      };

  static AmbienceBout? fromJson(Map<String, Object?> m) {
    final file = m['file'] as String?;
    if (file == null || file.isEmpty) return null;
    return AmbienceBout(
      preset: (m['preset'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      file: file,
      source: (m['source'] as String?) ?? '',
      bytes: (m['bytes'] as num?)?.toInt() ?? 0,
      playedAt: DateTime.tryParse((m['playedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

/// Pull at most [maxBytes] of [url] into [into]. Injected so the cache can be
/// tested without a network.
typedef BoutFetcher = Future<bool> Function(Uri url, File into, int maxBytes);

class AmbienceCache {
  AmbienceCache(
    this.dir, {
    BoutFetcher? fetch,
    this.bout = const Duration(minutes: 30),
    this.maxPerPreset = 2,
    this.budgetBytes = 400 * 1024 * 1024,
  }) : _fetch = fetch ?? _rangeFetch;

  final Directory dir;
  final BoutFetcher _fetch;

  /// How much of a recording is kept. The name of the feature.
  final Duration bout;

  /// Per preset, so one heavily used preset cannot fill the budget on its own
  /// and leave every other one streaming forever.
  final int maxPerPreset;

  /// Total disk, across every preset. At the ~29MB a 30-minute 128kbps mp3
  /// comes to, this is a dozen bouts - far more than [maxPerPreset] times the
  /// six presets will ever reach, so in practice the per-preset cap is what
  /// binds and this is the backstop for a directory of unusually fat files.
  final int budgetBytes;

  /// What a bout is assumed to weigh when the metadata says nothing useful.
  /// 128kbps, which is what the collection mostly holds.
  static const _assumedBytesPerSecond = 16 * 1024;

  final _rng = Random();
  final _bouts = <AmbienceBout>[];

  /// Presets with a fill in flight, so a second play while the first download
  /// is still running does not start a second copy of it.
  final _filling = <String>{};

  bool _loaded = false;

  List<AmbienceBout> get bouts => List.unmodifiable(_bouts);

  int get bytes => _bouts.fold(0, (sum, b) => sum + b.bytes);

  int countFor(String preset) =>
      _bouts.where((b) => b.preset == preset).length;

  File fileFor(AmbienceBout b) => File(p.join(dir.path, b.file));

  /// Read the index, dropping anything whose file has gone (a cleared cache
  /// directory, a restore from a backup that did not include it). Safe to call
  /// more than once.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final index = File(p.join(dir.path, 'index.json'));
      if (!index.existsSync()) return;
      final raw = jsonDecode(await index.readAsString());
      final list = (raw is Map ? raw['bouts'] : null) as List? ?? const [];
      for (final entry in list) {
        if (entry is! Map) continue;
        final b = AmbienceBout.fromJson(Map<String, Object?>.from(entry));
        if (b == null) continue;
        if (!fileFor(b).existsSync()) continue;
        _bouts.add(b);
      }
    } catch (e) {
      debugPrint('Ambience index unreadable, starting empty: $e');
      _bouts.clear();
    }
  }

  Future<void> _save() async {
    try {
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'index.json')).writeAsString(
        jsonEncode({'bouts': [for (final b in _bouts) b.toJson()]}),
        flush: true,
      );
    } catch (e) {
      debugPrint('Could not write the ambience index: $e');
    }
  }

  /// A stored bout for [preset], chosen at random, or null if there are none.
  ///
  /// Picking marks it played, which is what eviction sorts on: the bouts that
  /// go are the ones for presets nobody reaches for.
  Future<AmbienceBout?> pick(String preset) async {
    await load();
    final mine = _bouts.where((b) => b.preset == preset).toList();
    if (mine.isEmpty) return null;

    final chosen = mine[_rng.nextInt(mine.length)];
    final touched = chosen.touched(DateTime.now());
    _bouts[_bouts.indexOf(chosen)] = touched;
    await _save();
    return touched;
  }

  /// Store a bout of [track] for [preset], unless there is already one for that
  /// recording or the preset is full.
  ///
  /// Returns what was stored, or null if nothing was - a full preset, a failed
  /// fetch, or a recording already held. Never throws: a cache that cannot fill
  /// is a slower app, not a broken one.
  Future<AmbienceBout?> store(AmbiencePreset preset, AmbienceTrack track) async {
    await load();
    if (countFor(preset.id) >= maxPerPreset) return null;
    if (_bouts.any((b) => b.source == track.url)) return null;

    final url = Uri.tryParse(track.url);
    if (url == null) return null;

    final name = '${preset.id}-${track.url.hashCode.toUnsigned(32)}.mp3';
    final file = File(p.join(dir.path, name));

    try {
      await dir.create(recursive: true);
      final ok = await _fetch(url, file, boutBytes(track));
      if (!ok || !file.existsSync() || await file.length() == 0) {
        if (file.existsSync()) await file.delete();
        return null;
      }

      final stored = AmbienceBout(
        preset: preset.id,
        title: track.title,
        file: name,
        source: track.url,
        bytes: await file.length(),
        playedAt: DateTime.now(),
      );
      _bouts.add(stored);
      await _evict();
      await _save();
      return stored;
    } catch (e) {
      debugPrint('Could not store a ${preset.label} bout: $e');
      try {
        if (file.existsSync()) await file.delete();
      } catch (_) {
        // Nothing to be done about it, and it is one stray file.
      }
      return null;
    }
  }

  /// Top up [preset] in the background: resolve a recording that is not already
  /// held and store a bout of it. A no-op once the preset is full.
  ///
  /// [resolve] is passed in rather than called directly so the caller decides
  /// what "another recording" means - and so this stays testable.
  Future<void> fill(
    AmbiencePreset preset,
    Future<AmbienceTrack?> Function() resolve,
  ) async {
    await load();
    if (countFor(preset.id) >= maxPerPreset) return;
    if (bytes >= budgetBytes) return;
    if (!_filling.add(preset.id)) return;
    try {
      final track = await resolve();
      if (track != null) await store(preset, track);
    } catch (e) {
      debugPrint('Could not top up ${preset.label}: $e');
    } finally {
      _filling.remove(preset.id);
    }
  }

  /// How many bytes of [track] make up one bout.
  ///
  /// From the metadata when it says enough, and from an assumed bitrate when it
  /// does not. Never more than the file: asking for a range past the end is a
  /// 416 on a strict server, and a whole recording shorter than a bout is the
  /// commonest case there is.
  int boutBytes(AmbienceTrack track) {
    final seconds = track.seconds;
    final size = track.bytes;
    if (seconds > 0 && size > 0) {
      if (seconds <= bout.inSeconds) return size;
      return (size * bout.inSeconds / seconds).ceil();
    }
    final assumed = bout.inSeconds * _assumedBytesPerSecond;
    return size > 0 ? min(size, assumed) : assumed;
  }

  /// Drop least-recently-played bouts until the budget is met.
  Future<void> _evict() async {
    if (bytes <= budgetBytes) return;
    final byAge = List.of(_bouts)
      ..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    for (final b in byAge) {
      if (bytes <= budgetBytes) break;
      await _remove(b);
    }
  }

  Future<void> _remove(AmbienceBout b) async {
    _bouts.remove(b);
    try {
      final f = fileFor(b);
      if (f.existsSync()) await f.delete();
    } catch (e) {
      debugPrint('Could not delete a cached bout: $e');
    }
  }

  /// Everything, and the directory with it. What the sound sheet's Clear does.
  Future<void> clear() async {
    await load();
    for (final b in List.of(_bouts)) {
      await _remove(b);
    }
    await _save();
  }

  /// Range-request the first [maxBytes] and stop reading there.
  ///
  /// The cap is applied on the way in as well as being asked for, because a
  /// server is free to ignore `Range` and answer 200 with the whole file -
  /// which for a four-hour recording is most of a gigabyte nobody asked for.
  static Future<bool> _rangeFetch(Uri url, File into, int maxBytes) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', url)
        ..headers['Range'] = 'bytes=0-${maxBytes - 1}'
        ..headers['User-Agent'] = ambienceUserAgent;
      final response = await client.send(request);
      if (response.statusCode != 200 && response.statusCode != 206) {
        return false;
      }

      final sink = into.openWrite();
      var written = 0;
      try {
        await for (final chunk in response.stream) {
          final room = maxBytes - written;
          if (room <= 0) break;
          final take = chunk.length <= room ? chunk : chunk.sublist(0, room);
          sink.add(take);
          written += take.length;
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      return written > 0;
    } finally {
      client.close();
    }
  }
}
