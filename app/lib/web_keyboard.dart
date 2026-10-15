// Getting the keyboard up on an iPhone for a field that does not exist yet.
//
// iOS only shows the keyboard when focus moves *during* a touch's own event
// handler. A pane that opens on a tap is built in the next frame, so the
// focus its field asks for arrives after the touch has finished and iOS
// ignores it: the caret blinks and no keyboard comes. A web page cannot
// change that rule, so it works round it: inside the tap, the page focuses a
// throwaway input of its own (`todoPrimeKeyboard` in web/index.html), which
// brings the keyboard up; when the real field takes focus a frame later the
// keyboard is already showing and iOS lets it move. Conditional for the same
// reason web_safe_area is: `dart:js_interop` exists only in a web build.
export 'web_keyboard_io.dart'
    if (dart.library.js_interop) 'web_keyboard_web.dart';
