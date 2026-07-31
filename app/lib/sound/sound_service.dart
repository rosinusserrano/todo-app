// The sound subapp's transport.
//
// One player, one volume, three tiers of source. Everything the UI needs to
// render is on this notifier; the widgets themselves hold no playback state.
//
// Noise is played from a generated WAV on disk rather than from memory: it is
// looped indefinitely, and handing libmpv a file lets it stream from disk
// instead of holding ~5MB of PCM resident for the whole session. The file is
// written once per kind into the temp directory and reused.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../sync/local_store.dart';
import 'noise.dart';
import 'sources.dart';

const _kVolume = 'ui:sound-volume';

enum SoundTier { noise, ambience, radio }

/// What is playing right now, for the transport line.
class NowPlaying {
  const NowPlaying({required this.tier, required this.id, required this.label});

  final SoundTier tier;

  /// Identifies the row to highlight: a NoiseKind name, a preset id, or a
  /// station uuid.
  final String id;
  final String label;
}

class SoundService extends ChangeNotifier {
  SoundService(this._store);

  final LocalStore _store;

  late final Player _player = Player();

  NowPlaying? _now;
  NowPlaying? get now => _now;

  /// A source is loaded - playing *or* paused. This is what lights the
  /// headphones and what decides the transport button exists at all, because a
  /// paused source is still "the thing this widget is playing".
  bool get isPlaying => _now != null;

  bool _paused = false;

  /// Paused rather than stopped: [now] survives, so the label stays put and
  /// resuming needs no lookup. Only ever true while [now] is non-null.
  bool get isPaused => _paused;

  double _volume = 0.5;
  double get volume => _volume;

  /// Transient one-liner shown in place of the track name — "Finding a café
  /// recording…", or why something failed.
  String? _status;
  String? get status => _status;

  /// Paused is called out here rather than left to the icons: the sheet can be
  /// opened long after the pause happened, possibly from the taskbar, and a
  /// source name sitting there unqualified reads as "this is playing".
  String get transportLabel {
    final label = _status ?? _now?.label ?? 'Nothing playing';
    return _paused ? '$label · paused' : label;
  }

  /// Guards against a slow archive.org lookup landing after the user has moved
  /// on to something else.
  int _requestSeq = 0;

  final _noiseFiles = <NoiseKind, String>{};

  Future<void> load() async {
    final stored = double.tryParse(await _store.setting(_kVolume) ?? '');
    _volume = (stored ?? 0.5).clamp(0.0, 1.0);
    await _player.setVolume(_volume * 100);
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    await _player.setVolume(_volume * 100);
    await _store.setSetting(_kVolume, _volume.toStringAsFixed(3));
    notifyListeners();
  }

  // ---------------------------------------------------------------- tier 1

  Future<void> playNoise(NoiseKind kind) async {
    final seq = await _beginRequest('Generating ${kind.label.toLowerCase()} noise…');

    try {
      final path = await _noiseFile(kind);
      if (seq != _requestSeq) return;
      await _player.open(Media(path));
      await _player.setPlaylistMode(PlaylistMode.loop);
      _set(
        now: NowPlaying(tier: SoundTier.noise, id: kind.name, label: '${kind.label} noise'),
      );
    } catch (e) {
      debugPrint('Noise playback failed: $e');
      await _stopPlayer();
      _set(status: 'Could not start ${kind.label.toLowerCase()} noise.');
    }
  }

  /// Synthesis is ~1.3M samples per channel, so it runs on a background isolate
  /// — on the main isolate it would drop frames for a noticeable beat.
  Future<String> _noiseFile(NoiseKind kind) async {
    final cached = _noiseFiles[kind];
    if (cached != null && File(cached).existsSync()) return cached;

    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'todo-widget-noise-${kind.name}.wav');
    final bytes = await compute(NoiseSynth.wav, kind);
    await File(path).writeAsBytes(bytes, flush: true);

    _noiseFiles[kind] = path;
    return path;
  }

  // ---------------------------------------------------------------- tier 2

  Future<void> playAmbience(AmbiencePreset preset) async {
    final seq = await _beginRequest('Finding a ${preset.label.toLowerCase()} recording…');

    try {
      final track = await ArchiveAmbience.resolve(preset);
      if (seq != _requestSeq) return;

      if (track == null) {
        _set(status: 'No ${preset.label.toLowerCase()} recording found.');
        return;
      }

      await _player.open(Media(track.url));
      // Field recordings are finite, so they have to repeat to be ambience.
      await _player.setPlaylistMode(PlaylistMode.loop);
      _set(
        now: NowPlaying(
          tier: SoundTier.ambience,
          id: preset.id,
          label: '${preset.label} · ${track.title}',
        ),
      );
    } catch (e) {
      debugPrint('Ambience playback failed: $e');
      if (seq != _requestSeq) return;
      await _stopPlayer();
      _set(status: 'Could not reach the Internet Archive.');
    }
  }

  // ---------------------------------------------------------------- tier 3

  Future<void> playStation(Station station) async {
    final seq = await _beginRequest('Connecting to ${station.name}…');

    try {
      await _player.open(Media(station.url));
      // A live stream never ends, so looping it would be meaningless.
      await _player.setPlaylistMode(PlaylistMode.none);
      if (seq != _requestSeq) return;
      _set(
        now: NowPlaying(tier: SoundTier.radio, id: station.uuid, label: station.name),
      );
      RadioBrowser.reportPlay(station.uuid);
    } catch (e) {
      debugPrint('Station playback failed: $e');
      if (seq != _requestSeq) return;
      await _stopPlayer();
      _set(status: 'Could not connect to ${station.name}.');
    }
  }

  // ----------------------------------------------------------------- common

  /// Every play path starts here: silence whatever was playing, claim the
  /// request slot, and show why the user is waiting. Stopping up front matters
  /// — a lookup that then fails must not leave the previous source audible
  /// while the UI reports an error.
  Future<int> _beginRequest(String status) async {
    final seq = ++_requestSeq;
    await _stopPlayer();
    _set(status: status);
    return seq;
  }

  /// Pause/resume without giving up the source. Radio is the awkward case: a
  /// live stream has no meaningful "where we were", so resuming it picks up
  /// wherever the stream is now rather than where it was left - which is the
  /// only thing a live stream can honestly do.
  Future<void> togglePause() async {
    if (_now == null) return;
    try {
      if (_paused) {
        await _player.play();
      } else {
        await _player.pause();
      }
      _paused = !_paused;
      notifyListeners();
    } catch (e) {
      debugPrint('Pause toggle failed: $e');
    }
  }

  Future<void> stop() async {
    _requestSeq++;
    await _stopPlayer();
    _set();
  }

  Future<void> _stopPlayer() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('Player stop failed: $e');
    }
  }

  /// Single mutation point, so `now` and `status` can never both be stale.
  /// Passing neither clears both, which is the stopped state.
  ///
  /// Clearing `_paused` here is what keeps it honest: every play path and every
  /// stop path ends in this method, so a new source can never inherit the
  /// previous one's paused flag and strand the transport showing ▶ over
  /// something that is audibly running.
  void _set({NowPlaying? now, String? status}) {
    _now = now;
    _status = status;
    _paused = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
