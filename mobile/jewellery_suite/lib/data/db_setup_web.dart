import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web: run SQLite through the wasm build of sqlite3 so the whole app works
/// in Chromium with no server.
Future<void> setupDatabase() async {
  databaseFactory = databaseFactoryFfiWeb;
}