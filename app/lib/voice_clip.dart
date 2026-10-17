import 'dart:typed_data';

/// A recording just made, not stored yet: what the thought pane holds
/// between the stop and the save.
class VoiceClip {
  const VoiceClip(this.bytes, this.type, this.ms);

  final Uint8List bytes;

  /// The container the browser made - `audio/mp4` or `audio/webm`.
  final String type;
  final int ms;
}
