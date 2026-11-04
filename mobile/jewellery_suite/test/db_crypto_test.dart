import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/db_crypto.dart';
import 'package:jewellery_suite/data/local_db.dart';

/// #049 — encryption must be honest about where it is available, and must
/// never stop the ledger opening where it is not. These run on the test VM
/// (Linux), which deliberately uses the plain driver.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('this build reports encryption as unavailable', () async {
    expect(DbCrypto.supported, isFalse);
    expect(await DbCrypto.key(), isNull);
  });

  test('a plaintext database is recognised by its header', () async {
    final dir = await Directory.systemTemp.createTemp('js_crypto_');
    addTearDown(() => dir.delete(recursive: true));

    final file = p.join(dir.path, 'plain.db');
    final db = await openDatabase(file);
    await db.execute('CREATE TABLE t (a INTEGER)');
    await db.close();
    expect(DbCrypto.looksPlaintext(file), isTrue);

    final blob = p.join(dir.path, 'blob.bin');
    await File(blob).writeAsBytes(List<int>.filled(64, 7));
    expect(DbCrypto.looksPlaintext(blob), isFalse);

    // 256 bits, hex encoded — the helper is platform-neutral, the *usage* is
    // what is gated by `supported`.
    expect(DbCrypto.newKey(), hasLength(64));
  });

  test('openExternal still reads a plaintext snapshot', () async {
    final dir = await Directory.systemTemp.createTemp('js_crypto_open_');
    addTearDown(() => dir.delete(recursive: true));

    final file = p.join(dir.path, 'snapshot.db');
    final db = await openDatabase(file);
    await db.execute('CREATE TABLE t (a INTEGER)');
    await db.insert('t', {'a': 7});
    await db.close();

    final copy = await LocalDb.openExternal(file, readOnly: true);
    final rows = await copy.rawQuery('SELECT a FROM t');
    expect(rows.single['a'], 7);
    await copy.close();
  });

  test('the live database stays plain where SQLCipher is unavailable',
      () async {
    final dir = await Directory.systemTemp.createTemp('js_crypto_live_');
    addTearDown(() => dir.delete(recursive: true));

    final local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'live.db'));
    expect(local.encrypted, isFalse);
    await local.close();
  });
}
