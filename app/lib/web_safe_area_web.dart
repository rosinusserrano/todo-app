import 'dart:js_interop';

@JS('todoSafeBottom')
external JSNumber? _todoSafeBottom();

/// In CSS pixels, which are Flutter's logical pixels on the web. Zero when the
/// page's helper is missing (an older index.html) or the browser has no such
/// inset - a desktop browser, or Android with gesture navigation off.
double webSafeBottom() {
  try {
    return _todoSafeBottom()?.toDartDouble ?? 0;
  } catch (_) {
    return 0;
  }
}
