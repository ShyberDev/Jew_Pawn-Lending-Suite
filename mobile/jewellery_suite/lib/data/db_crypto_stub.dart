import 'package:sqflite/sqflite.dart';

/// Web build of the #049 database helpers. There is no keystore-backed
/// SQLCipher on this target, so everything reports "not encrypted" and the
/// plain driver is used — the same behaviour [DbCrypto.supported] exposes.
bool get supported => false;

Future<String?> key() async => null;

String newKey() => '';

bool looksPlaintext(String path) => false;

Future<bool> exists(String path) async => false;

Future<void> deleteFile(String path) async {}

Future<void> rename({required String from, required String to}) async {}

Future<void> copyFile({required String from, required String to}) async {}

Future<String?> encryptFile({
  required String plain,
  required String target,
  required String key,
  required int version,
}) async =>
    'Encrypting the database is not available on this build.';

Future<String?> verify(String path, String key) async => null;

Future<String?> rekeyFile(
  String path, {
  required String from,
  required String to,
}) async =>
    'Encrypting the database is not available on this build.';

Future<String?> snapshot(Database db, {required String dest}) async =>
    'Encrypting the database is not available on this build.';

Future<(Database, bool)> open({
  required String path,
  required int version,
  required OnDatabaseCreateFn onCreate,
  required OnDatabaseVersionChangeFn onUpgrade,
}) async =>
    (
      await openDatabase(path,
          version: version, onCreate: onCreate, onUpgrade: onUpgrade),
      false,
    );

Future<Database> openExternal(
  String path, {
  bool readOnly = false,
  String? password,
}) =>
    openDatabase(path, readOnly: readOnly, singleInstance: false);
