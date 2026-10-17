import 'dart:async';
import 'dart:js_interop';

import 'voice_clip.dart';

@JS('todoRecorder')
external _Recorder? get _recorder;

extension type _Recorder(JSObject _) implements JSObject {
  external bool supported();
  external void start(JSFunction onStarted, JSFunction onError);
  external void stop(JSFunction onDone);
  external void cancel();
}

/// MediaRecorder in the page - see voice_recorder.dart.
class VoiceRecorder {
  static bool get supported {
    try {
      return _recorder?.supported() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Completes once the microphone is live; throws the reason otherwise
  /// (`not-allowed` when the page was refused it).
  Future<void> start() {
    final rec = _recorder;
    if (rec == null) return Future.error('unsupported');
    final done = Completer<void>();
    rec.start(
      (() => done.complete()).toJS,
      ((JSString reason) => done.completeError(reason.toDart)).toJS,
    );
    return done.future;
  }

  /// The recording, or null when there was nothing to stop.
  Future<VoiceClip?> stop() {
    final rec = _recorder;
    if (rec == null) return Future.value();
    final done = Completer<VoiceClip?>();
    rec.stop(
      ((JSUint8Array? bytes, JSString type, JSNumber ms) {
        done.complete(
          bytes == null
              ? null
              : VoiceClip(bytes.toDart, type.toDart, ms.toDartInt),
        );
      }).toJS,
    );
    return done.future;
  }

  void cancel() => _recorder?.cancel();
}
