import 'voice_clip.dart';

/// No recorder outside the browser yet - see voice_recorder.dart.
class VoiceRecorder {
  static bool get supported => false;

  /// Completes once the microphone is live; throws the reason otherwise.
  Future<void> start() async => throw 'unsupported';

  /// The recording, or null when there was nothing to stop.
  Future<VoiceClip?> stop() async => null;

  void cancel() {}
}
