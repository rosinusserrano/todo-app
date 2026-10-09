// Selects the sqflite implementation for the platform being compiled for.
//
// This indirection exists because the implementations cannot coexist in one
// import list: the desktop one reaches for `dart:ffi`, which does not exist in a
// web build, and the web one reaches for `dart:js_interop`, which does not exist
// anywhere else. A conditional export is resolved at compile time, so each build
// only ever sees the one it can actually load.
//
// `local_store.dart` is written against the sqflite API alone and does not know
// which of these it got. Same file as `../link-gateway-app`'s.
export 'db_factory_io.dart'
    if (dart.library.js_interop) 'db_factory_web.dart';
