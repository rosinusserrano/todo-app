// Native implementation: mobile uses the plugin bundled with `sqflite`, desktop
// uses the FFI build. Never loaded in a web build - see db_factory.dart.

import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show databaseFactorySqflitePlugin;
// Re-exports the sqflite_common API, including the global databaseFactory
// this installs into, alongside the desktop FFI implementation.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// sqflite has no default factory on desktop - the getter throws until one is
// installed - and setting it a second time prints a warning about changing the
// global. So this happens once.
bool _installed = false;

/// Installs the right `databaseFactory`. Safe to call more than once.
Future<void> initDatabaseFactory() async {
  if (_installed) return;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // sqflite ships a mobile implementation only; desktop needs the FFI one.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else {
    databaseFactory = databaseFactorySqflitePlugin;
  }
  _installed = true;
}

/// `%APPDATA%\com.marco\todo_widget\todo.db` on Windows, and the equivalent
/// application-support directory elsewhere. The application id is baked in
/// here by `getApplicationSupportDirectory`, which is why changing it strands
/// data.
Future<String> defaultDatabasePath() async =>
    p.join((await getApplicationSupportDirectory()).path, 'todo.db');
