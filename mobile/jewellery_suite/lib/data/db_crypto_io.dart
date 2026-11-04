import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart'
    show
        Database,
        OnDatabaseCreateFn,
        OnDatabaseVersionChangeFn,
        openDatabase;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

/// Storage name of the database key inside the platform keystore.
const String _keyName = 'jewellery_suite_db_key_v1';

final FlutterSecureStorage _storage = FlutterSecureStorage();

String? _cached;
bool _refused = false;

/// SQLCipher ships for Android and iOS here. Linux and the web keep the plain
/// driver, which is what the desktop preview and `flutter test` run on.
bool get supported => Platform.isAndroid || Platform.isIOS;

Future<String?> key() async {
  if (!supported || _refused) return null;
  if (_cached != null) return _cached;
  try {
    var value = await _storage.read(key: _keyName);
    if (value == null || value.length < 32) {
      value = newKey();
      await _storage.write(key: _keyName, value: value);
    }
    _cached = value;
    return value;
  } catch (error) {
    _refused = true;
    debugPrint(
        '[db] keystore unavailable — the database stays unencrypted: $error');
    return null;
  }
}

String newKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

bool looksPlaintext(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return false;
    final raf = file.openSync();
    try {
      final head = raf.readSync(16);
      return head.length == 16 &&
          utf8.decode(head, allowMalformed: true) == 'SQLite format 3\u0000';
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return false;
  }
}

Future<bool> exists(String path) => File(path).exists();

Future<void> deleteFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

Future<void> rename({required String from, required String to}) async {
  final file = File(from);
  if (await file.exists()) await file.rename(to);
}

Future<void> copyFile({required String from, required String to}) async {
  final source = File(from);
  if (await source.exists()) await source.copy(to);
}

/// SQLCipher needs single quotes inside SQL literals escaped; the key is hex,
/// but the path is not, so both are quoted the same way.
String _quote(String value) => value.replaceAll("'", "''");

Future<String?> encryptFile({
  required String plain,
  required String target,
  required String key,
  required int version,
}) async {
  cipher.Database? source;
  try {
    await deleteFile(target);
    // No password means SQLCipher reads the plaintext file as-is; the EXPORT
    // below writes the encrypted copy.
    source = await cipher.openDatabase(plain, singleInstance: false);
    await source.execute(
        "ATTACH DATABASE '${_quote(target)}' AS encrypted KEY '${_quote(key)}'");
    await source.rawQuery("SELECT sqlcipher_export('encrypted')");
    // sqlcipher_export copies the schema and the rows but NOT `user_version`,
    // so the encrypted file would look like a brand-new database and the open
    // path would run onCreate over tables that already exist.
    await source.execute('PRAGMA encrypted.user_version = $version');
    await source.execute('DETACH DATABASE encrypted');
    return null;
  } catch (error) {
    debugPrint('[db] encryption failed: $error');
    return 'The database could not be encrypted.';
  } finally {
    try {
      await source?.close();
    } catch (_) {/* the caller reports the failure */}
  }
}

Future<String?> verify(String path, String key) async {
  cipher.Database? check;
  try {
    check = await cipher.openDatabase(path,
        password: key, readOnly: true, singleInstance: false);
    final rows = await check.rawQuery('PRAGMA integrity_check');
    final verdict = rows.isEmpty ? '' : '${rows.first.values.first}';
    return verdict.toLowerCase() == 'ok'
        ? null
        : 'The encrypted database failed its integrity check.';
  } catch (error) {
    debugPrint('[db] encrypted verification failed: $error');
    return 'The encrypted database could not be read back.';
  } finally {
    try {
      await check?.close();
    } catch (_) {/* reported above */}
  }
}

Future<String?> rekeyFile(
  String path, {
  required String from,
  required String to,
}) async {
  cipher.Database? db;
  try {
    db = await cipher.openDatabase(path, password: from, singleInstance: false);
    await db.execute("PRAGMA rekey = '${_quote(to)}'");
    return null;
  } catch (error) {
    debugPrint('[db] rekey failed: $error');
    return 'The backup database could not be re-encrypted for this phone.';
  } finally {
    try {
      await db?.close();
    } catch (_) {/* reported above */}
  }
}

Future<String?> snapshot(Database db, {required String dest}) async {
  final key = _cached;
  if (key == null) return 'The database key is unavailable.';
  try {
    await deleteFile(dest);
    // sqlcipher_export does not copy `PRAGMA user_version`, so carry it across
    // by hand or the snapshot looks like a brand-new database on restore — and
    // `onCreate` then trips over tables that already exist.
    final versionRows = await db.rawQuery('PRAGMA user_version');
    final version = versionRows.isEmpty
        ? 0
        : ((versionRows.first.values.first as num?)?.toInt() ?? 0);
    await db.execute(
        "ATTACH DATABASE '${_quote(dest)}' AS _snapshot KEY '${_quote(key)}'");
    await db.rawQuery("SELECT sqlcipher_export('_snapshot')");
    await db.execute('PRAGMA _snapshot.user_version = $version');
    await db.execute('DETACH DATABASE _snapshot');
    if (await File(dest).exists()) return null;
    return 'The encrypted database could not be copied.';
  } catch (error) {
    debugPrint('[db] encrypted snapshot failed: $error');
    return 'The encrypted database could not be copied.';
  }
}

Future<(Database, bool)> open({
  required String path,
  required int version,
  required OnDatabaseCreateFn onCreate,
  required OnDatabaseVersionChangeFn onUpgrade,
}) async {
  final phoneKey = await key();
  if (phoneKey == null) {
    return (
      await openDatabase(path,
          version: version, onCreate: onCreate, onUpgrade: onUpgrade),
      false,
    );
  }
  try {
    final db = await cipher.openDatabase(path,
        password: phoneKey,
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade);
    return (db, true);
  } catch (error) {
    // Falling back to plain SQLite is only safe on a file that really is
    // plaintext. A ciphertext file is repaired, or surfaces the error, instead
    // of being opened by the wrong driver.
    if (!looksPlaintext(path)) {
      if (await _repairSchemaVersion(path, phoneKey, version)) {
        try {
          final db = await cipher.openDatabase(path,
              password: phoneKey,
              version: version,
              onCreate: onCreate,
              onUpgrade: onUpgrade);
          return (db, true);
        } catch (repairError) {
          debugPrint('[db] encrypted open still failed ($repairError)');
        }
      }
      debugPrint('[db] encrypted open failed ($error) and the file is not '
          'plaintext — not falling back');
      rethrow;
    }
    debugPrint('[db] encrypted open failed ($error); using plain SQLite');
    return (
      await openDatabase(path,
          version: version, onCreate: onCreate, onUpgrade: onUpgrade),
      false,
    );
  }
}

/// A SQLCipher file whose `user_version` is 0 (written by an export before
/// this was carried across) opens as a schema-0 database and trips `onCreate`
/// over the tables that are already there. Stamp the version back when the
/// file is clearly a populated ledger.
Future<bool> _repairSchemaVersion(String path, String key, int version) async {
  cipher.Database? probe;
  try {
    probe = await cipher.openDatabase(path, password: key, singleInstance: false);
    final versionRows = await probe.rawQuery('PRAGMA user_version');
    final current = versionRows.isEmpty
        ? 0
        : ((versionRows.first.values.first as num?)?.toInt() ?? 0);
    if (current != 0) return false;
    final tables = await probe.rawQuery("SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'");
    if (tables.isEmpty) return false;
    await probe.execute('PRAGMA user_version = $version');
    debugPrint('[db] repaired the missing schema version on the encrypted file');
    return true;
  } catch (error) {
    debugPrint('[db] could not repair the schema version ($error)');
    return false;
  } finally {
    try {
      await probe?.close();
    } catch (_) {/* reported above */}
  }
}

Future<Database> openExternal(
  String path, {
  bool readOnly = false,
  String? password,
}) async {
  final candidate = password ?? await key();
  if (candidate != null) {
    try {
      return await cipher.openDatabase(path,
          password: candidate, readOnly: readOnly, singleInstance: false);
    } catch (error) {
      debugPrint('[db] external open with a key failed ($error)');
    }
  }
  return openDatabase(path, readOnly: readOnly, singleInstance: false);
}
