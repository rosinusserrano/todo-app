// Playing a voice note. The browser plays it in an audio element
// (`todoAudio` in web/index.html); the native builds through media_kit,
// which the concentration sounds already bring. Conditional for
// web_keyboard's reason.
export 'voice_player_io.dart' if (dart.library.js_interop) 'voice_player_web.dart';
