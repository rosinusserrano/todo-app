import 'dart:js_interop';

@JS('todoSafeBottom')
external JSNumber? _todoSafeBottom();

@JS('todoSafeTop')
external JSNumber? _todoSafeTop();

@JS('todoStandalone')
external JSBoolean? _todoStandalone();

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

/// The status bar's strip, the same way. Zero in a browser tab: the page is
/// only laid out under the bar as a home-screen app (viewport-fit=cover).
double webSafeTop() {
  try {
    return _todoSafeTop()?.toDartDouble ?? 0;
  } catch (_) {
    return 0;
  }
}

/// Opened from the home screen rather than in a browser tab.
bool webStandalone() {
  try {
    return _todoStandalone()?.toDart ?? false;
  } catch (_) {
    return false;
  }
}
