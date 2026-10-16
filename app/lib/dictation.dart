// Speaking a thought instead of typing it.
//
// The browser build uses the browser's own speech recognition (`todoSpeech`
// in web/index.html): nothing to install, and it is on the phone this is
// for - the web app on an iPhone - as well as Chrome and Edge on a desktop.
// The native builds have no recogniser of their own here: a phone keyboard's
// mic and Windows' Win+H already type into any field, so [Dictation.supported]
// is false there and the pane draws no button rather than one that does
// nothing. Conditional for web_keyboard's reason.
export 'dictation_io.dart' if (dart.library.js_interop) 'dictation_web.dart';
