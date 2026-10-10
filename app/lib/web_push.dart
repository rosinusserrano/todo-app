// Web Push in the browser build: asking for permission, subscribing, and
// unsubscribing. The page does the work (`todoPush` in web/index.html); this
// is the Dart face of it. The server half is server/push.js.
//
// Conditional for the same reason db_factory is: `dart:js_interop` exists only
// in a web build. Everywhere else the answer is "unsupported", and the native
// apps go on scheduling their own notifications (notifications.dart).
export 'web_push_io.dart' if (dart.library.js_interop) 'web_push_web.dart';
