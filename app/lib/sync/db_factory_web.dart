// Web implementation: SQLite compiled to WebAssembly, persisted in IndexedDB,
// running in a shared worker. Never loaded in a native build - see
// db_factory.dart.
//
// `web/sqlite3.wasm` and `web/sqflite_sw.js` must be present for this to work.
// They are fetched by `dart run sqflite_common_ffi_web:setup` and deliberately
// not committed; server/build-web.sh runs that step before building.

import 'package:sqflite_common/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

bool _installed = false;

/// Installs the WASM-backed `databaseFactory`. Safe to call more than once.
Future<void> initDatabaseFactory() async {
  if (_installed) return;
  databaseFactory = databaseFactoryFfiWeb;
  _installed = true;
}

/// A name, not a filesystem path: this keys an IndexedDB store, and there is
/// no application-support directory in a browser.
///
/// That makes the database per-origin *and* per-browser-profile, so a second
/// browser is a second device as far as sync is concerned - with its own
/// `settings`, journal password included, since those never sync.
Future<String> defaultDatabasePath() async => 'todo.db';
