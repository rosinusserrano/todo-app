import 'dart:js_interop';
import 'dart:typed_data';

@JS('todoAudio')
external _Audio? get _audio;

extension type _Audio(JSObject _) implements JSObject {
  external void prime();
  external void play(JSUint8Array bytes, JSString type, JSFunction onEnd);
  external void stop();
}

/// An audio element in the page - see voice_player.dart.
class VoicePlayer {
  /// Inside the tap, before anything is awaited: iOS plays only from an
  /// element a tap has started (see `todoAudio.prime`).
  static void prime() {
    try {
      _audio?.prime();
    } catch (_) {}
  }

  /// [onEnd] gets null at the end, and the reason when it could not play.
  /// [name] is unused here; it names the native build's temporary file.
  Future<void> play(
    Uint8List bytes,
    String type,
    String name,
    void Function(String? error) onEnd,
  ) async {
    final audio = _audio;
    if (audio == null) {
      onEnd('unsupported');
      return;
    }
    audio.play(
      bytes.toJS,
      type.toJS,
      ((JSString error) {
        final e = error.toDart;
        if (e != 'stopped') onEnd(e.isEmpty ? null : e);
      }).toJS,
    );
  }

  Future<void> stop() async => _audio?.stop();

  void dispose() => _audio?.stop();
}
