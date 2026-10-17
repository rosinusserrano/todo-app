import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// media_kit's player - see voice_player.dart. The bytes go to a temporary
/// file first: mpv opens a path or a URL, and the server's URL would need
/// the token in it.
class VoicePlayer {
  static void prime() {}

  Player? _player;
  StreamSubscription<bool>? _done;
  StreamSubscription<String>? _failed;

  /// [onEnd] gets null at the end, and the reason when it could not play.
  /// [name] names the temporary file - the note's digest, so playing it
  /// again writes nothing.
  Future<void> play(
    Uint8List bytes,
    String type,
    String name,
    void Function(String? error) onEnd,
  ) async {
    await stop();
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'voice-$name${_extension(type)}'));
    if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
    final player = _player ??= Player();
    var ended = false;
    void end(String? error) {
      if (ended) return;
      ended = true;
      unawaited(_done?.cancel());
      unawaited(_failed?.cancel());
      _done = null;
      _failed = null;
      onEnd(error);
    }

    _done = player.stream.completed.listen((done) {
      if (done) end(null);
    });
    _failed = player.stream.error.listen(end);
    await player.open(Media(file.path));
  }

  Future<void> stop() async {
    await _done?.cancel();
    await _failed?.cancel();
    _done = null;
    _failed = null;
    await _player?.stop();
  }

  void dispose() {
    _done?.cancel();
    _failed?.cancel();
    _player?.dispose();
  }

  static String _extension(String type) {
    if (type.contains('mp4') || type.contains('aac')) return '.m4a';
    if (type.contains('webm')) return '.webm';
    if (type.contains('ogg')) return '.ogg';
    if (type.contains('wav')) return '.wav';
    return '';
  }
}
