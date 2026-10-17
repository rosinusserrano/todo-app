// Recording a thought aloud instead of typing it.
//
// Recorded, not transcribed. The browser's own recognisers (this was
// dictation until 2026-10-17) turned anything past the plainest sentence into
// something else, and what is wanted afterwards is what was *said*. The
// browser build records with MediaRecorder (`todoRecorder` in
// web/index.html), which every browser has, iOS Safari included. The native
// builds have no recorder yet - it needs a plugin and a microphone
// permission on each platform - so [VoiceRecorder.supported] is false there
// and the pane draws no button. Playing is everywhere (voice_player.dart).
// Conditional for web_keyboard's reason.
export 'voice_recorder_io.dart'
    if (dart.library.js_interop) 'voice_recorder_web.dart';
