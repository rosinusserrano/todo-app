// Which kind of device this is, asked in a way that also works in a browser.
//
// `dart:io`'s `Platform` compiles into a web build and then throws
// `Unsupported operation` the first time anything reads it - so every
// `Platform.isWindows` in a path the web build runs is a crash on startup, not
// a false. These getters check `kIsWeb` first and are the only place the app
// should ask. A web build is none of desktop, mobile, Windows, iOS or Android:
// it gets no window manager, no tray, no hotkeys and no OS notifications, and
// each of those already has a `supported` getter that now reads from here.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Running in a browser.
const bool isWeb = kIsWeb;

/// A native desktop window (Windows, Linux, macOS) - the always-on-top widget.
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

bool get isWindows => !kIsWeb && Platform.isWindows;

/// A native phone or tablet build.
bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
