import 'dart:js_interop';

@JS('todoSpeech')
external _Speech? get _speech;

extension type _Speech(JSObject _) implements JSObject {
  external bool supported();
  external void start(JSFunction onText, JSFunction onEnd);
  external void stop();
}

/// The browser's speech recognition - see dictation.dart.
class Dictation {
  static bool get supported {
    try {
      return _speech?.supported() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// [onText] gets the whole transcript so far; [onEnd] gets null for a
  /// plain stop and the recogniser's reason for anything else.
  void start({
    required void Function(String text) onText,
    required void Function(String? error) onEnd,
  }) {
    final speech = _speech;
    if (speech == null) {
      onEnd('unsupported');
      return;
    }
    speech.start(
      ((JSString text) => onText(text.toDart)).toJS,
      ((JSString error) {
        final e = error.toDart;
        onEnd(e.isEmpty ? null : e);
      }).toJS,
    );
  }

  void stop() => _speech?.stop();
}
