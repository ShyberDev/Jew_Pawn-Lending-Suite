import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/data/backup_key_wrap.dart';
import 'package:jewellery_suite/data/backup_service.dart';

/// #080 security: a backup must not name the key that opens it. When the shop
/// asks to move a backup to another phone, the key is wrapped with a passphrase
/// they choose; the file alone cannot open the ledger.
void main() {
  Map<String, Object?> manifest({
    String? key,
    String? passphrase,
    int iterations = 1000,
  }) =>
      BackupService.buildManifest(
        createdAt: DateTime(2026, 11, 5, 10),
        includePhotos: true,
        photoCount: 2,
        rowCounts: const {'customers': 3},
        schemaVersion: 21,
        key: key,
        keyPassphrase: passphrase,
        keyIterations: iterations,
      );

  test('the database key is not written by default', () {
    final m = manifest();
    expect(m.containsKey('db_key'), isFalse,
        reason: 'a backup carrying its own key is not protected at all');
    expect(m.containsKey('db_key_wrapped'), isFalse);
    expect(m['includes_key'], isFalse);
    expect(m['format'], 'jewellery-suite-backup');
    expect(m['schema_version'], 21);
  });

  test('including the key requires a passphrase', () {
    expect(() => manifest(key: 'abc123'), throwsArgumentError);
  });

  test('the key is wrapped, never stored in clear text', () {
    final m = manifest(key: 'abc123', passphrase: 'shop-pass');
    expect(m.containsKey('db_key'), isFalse);
    expect(m['includes_key'], isTrue);
    expect(m['key_wrap'], BackupKeyWrap.format);
    expect(m['key_salt'], isNotEmpty);
    expect(m['key_iterations'], 1000);
    expect(m['db_key_wrapped'], isNotEmpty);
    expect(BackupKeyWrap.unwrap(m, 'shop-pass'), 'abc123');
  });

  test('a wrong passphrase does not open the wrapped key', () {
    final m = manifest(key: 'abc123', passphrase: 'shop-pass');
    expect(
      () => BackupKeyWrap.unwrap(m, 'wrong-pass'),
      throwsA(isA<FormatException>().having(
          (e) => e.message, 'message', contains('does not open'))),
    );
  });

  test('a damaged key block is refused', () {
    final m = manifest(key: 'abc123', passphrase: 'shop-pass');
    final blob = base64Decode(m['db_key_wrapped'] as String);
    blob[blob.length - 1] ^= 0xff;
    final damaged = {...m, 'db_key_wrapped': base64Encode(blob)};
    expect(
      () => BackupKeyWrap.unwrap(damaged, 'shop-pass'),
      throwsA(isA<FormatException>()),
    );
  });

  test('a realistic 64-character key round-trips', () {
    final key = 'a' * 64;
    final m = manifest(key: key, passphrase: 'long-enough');
    expect(BackupKeyWrap.unwrap(m, 'long-enough'), key);
  });
}
