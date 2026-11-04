import 'package:sqflite/sqflite.dart';

import 'db_crypto_stub.dart'
    if (dart.library.io) 'db_crypto_io.dart' as impl;

/// #049 — the ledger is encrypted at rest.
///
/// On Android and iOS the database is opened through SQLCipher with a 256-bit
/// key generated on this phone and kept in the platform keystore
/// (`flutter_secure_storage`). Nothing derives that key from the PIN, so
/// forgetting or changing the PIN can never make the books unreadable.
///
/// Web and the desktop build have no keystore-backed SQLCipher here, so they
/// keep the plain driver; [supported] reports which one is in use so About can
/// say so plainly instead of claiming protection it does not have.
class DbCrypto {
  const DbCrypto._();

  /// True when this build and phone can encrypt the database.
  static bool get supported => impl.supported;

  /// This phone's database key, or null when it cannot encrypt.
  static Future<String?> key() => impl.key();

  /// A fresh 256-bit key, hex encoded. Exposed for tests.
  static String newKey() => impl.newKey();

  /// True when [path] still carries SQLite's plaintext file header.
  static bool looksPlaintext(String path) => impl.looksPlaintext(path);

  static Future<bool> exists(String path) => impl.exists(path);

  static Future<void> deleteFile(String path) => impl.deleteFile(path);

  static Future<void> rename(String from, String to) =>
      impl.rename(from: from, to: to);

  static Future<void> copyFile(String from, String to) =>
      impl.copyFile(from: from, to: to);

  /// Writes an encrypted copy of [plain] at [target]; the original is untouched.
  static Future<String?> encryptFile({
    required String plain,
    required String target,
    required String key,
    required int version,
  }) =>
      impl.encryptFile(
          plain: plain, target: target, key: key, version: version);

  /// Opens [path] read-only and runs SQLite's integrity check on it.
  static Future<String?> verify(String path, String key) =>
      impl.verify(path, key);

  /// Re-encrypts a file from one key to another (a backup from another phone).
  static Future<String?> rekeyFile(
    String path, {
    required String from,
    required String to,
  }) =>
      impl.rekeyFile(path, from: from, to: to);

  /// A consistent, still-encrypted copy of the live database.
  static Future<String?> snapshot(Database db, {required String dest}) =>
      impl.snapshot(db, dest: dest);

  /// Opens the live database. The bool is true when SQLCipher is in use.
  static Future<(Database, bool)> open({
    required String path,
    required int version,
    required OnDatabaseCreateFn onCreate,
    required OnDatabaseVersionChangeFn onUpgrade,
  }) =>
      impl.open(
        path: path,
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
      );

  /// Opens a backup snapshot or archive member, which may be encrypted with a
  /// different phone's key ([key]) or be a legacy plaintext file.
  static Future<Database> openExternal(
    String path, {
    bool readOnly = false,
    String? key,
  }) =>
      impl.openExternal(path, readOnly: readOnly, password: key);
}
