/// No recogniser outside the browser - see dictation.dart.
class Dictation {
  static bool get supported => false;

  /// [onText] gets the whole transcript so far; [onEnd] gets null for a
  /// plain stop and the recogniser's reason for anything else.
  void start({
    required void Function(String text) onText,
    required void Function(String? error) onEnd,
  }) => onEnd('unsupported');

  void stop() {}
}
