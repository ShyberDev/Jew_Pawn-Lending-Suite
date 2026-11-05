import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/data/backup_service.dart';

/// #080 security: a backup must not name the key that opens it unless the shop
/// explicitly opted in, because anyone holding the file could then read the
/// ledger. Same-phone restores use the keystore key and need nothing here.
void main() {
  Map<String, Object?> manifest({String? key}) => BackupService.buildManifest(
        createdAt: DateTime(2026, 11, 5, 10),
        includePhotos: true,
        photoCount: 2,
        rowCounts: const {'customers': 3},
        schemaVersion: 21,
        key: key,
      );

  test('the database key is not written by default', () {
    final m = manifest();
    expect(m.containsKey('db_key'), isFalse,
        reason: 'a backup carrying its own key is not protected at all');
    expect(m['includes_key'], isFalse);
    expect(m['format'], 'jewellery-suite-backup');
    expect(m['schema_version'], 21);
  });

  test('the key is written only when explicitly included', () {
    final m = manifest(key: 'abc123');
    expect(m['db_key'], 'abc123');
    expect(m['includes_key'], isTrue);
  });
}
