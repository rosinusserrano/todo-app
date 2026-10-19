// The browser build's safe area: the strip an iPhone keeps for its home
// indicator, and the one at the top for the clock and the camera.
//
// Flutter's web engine reports no safe area at all (`viewPadding` is always
// zero), so a home-screen web app laid the view bar out over the indicator,
// and a swipe up on the bar was a swipe from the screen's edge - iOS took it
// and went home. The top one matters since the page runs under the status
// bar (`black-translucent` in index.html), which is what lets that strip be
// the app's background instead of a white system bar. The page measures `env(safe-area-inset-bottom)` itself
// (`todoSafeBottom` in web/index.html) and this asks it. Conditional for the
// same reason db_factory is: `dart:js_interop` exists only in a web build.
export 'web_safe_area_io.dart'
    if (dart.library.js_interop) 'web_safe_area_web.dart';
