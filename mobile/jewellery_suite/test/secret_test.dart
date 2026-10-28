import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/ui/admin_guard.dart';
import 'package:jewellery_suite/util/app_lock.dart';
import 'package:jewellery_suite/util/secret_hash.dart';

/// #037 / #038: secrets never sit in the database as readable text, and the
/// shipped `admin` default cannot survive first launch.
void main() {
  late LocalDb local;
  late AppState state;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_secret_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'secret.db'));
    state = AppState(local);
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('salted hash', () {
    test('same secret + salt is stable, different salt is not', () {
      const pin = '4821';
      expect(hashSecret(pin, 'salt-a'), hashSecret(pin, 'salt-a'));
      expect(hashSecret(pin, 'salt-a'), isNot(hashSecret(pin, 'salt-b')));
      expect(hashSecret(pin, 'salt-a'), isNot(contains(pin)));
    });

    test('comparison is length-safe and value-exact', () {
      expect(constantTimeEquals('abc', 'abc'), isTrue);
      expect(constantTimeEquals('abc', 'abd'), isFalse);
      expect(constantTimeEquals('abc', 'abcd'), isFalse);
      expect(constantTimeEquals('', ''), isTrue);
    });
  });

  group('admin password', () {
    test('a fresh install is flagged and the default is refused', () async {
      expect(await adminPasswordIsDefault(state), isTrue);

      await expectLater(
          setAdminPassword(state, 'admin'), throwsA(isA<FormatException>()));
      await expectLater(
          setAdminPassword(state, '12345'), throwsA(isA<FormatException>()));

      await setAdminPassword(state, 'shop-2026');
      expect(await adminPasswordIsDefault(state), isFalse);
      expect(await verifyAdminPassword(state, 'shop-2026'), isTrue);
      expect(await verifyAdminPassword(state, 'admin'), isFalse);
      expect(await verifyAdminPassword(state, 'shop-2025'), isFalse);

      // Only a salt + hash are stored — never the password.
      final salt = await local.getSetting(kAdminPasswordSaltKey);
      final hash = await local.getSetting(kAdminPasswordHashKey);
      expect(salt, isNotNull);
      expect(hash, isNotNull);
      expect(hash, isNot(contains('shop-2026')));
      expect(await local.getSetting(kLegacyAdminPasswordKey), isNull);
    });

    test('a legacy plain-text password is migrated, then erased', () async {
      await local.setSetting(kLegacyAdminPasswordKey, 'old-secret');
      await ensureAdminPassword(state);

      expect(await local.getSetting(kLegacyAdminPasswordKey), isNull,
          reason: 'the plain-text copy must be removed');
      expect(await verifyAdminPassword(state, 'old-secret'), isTrue);
    });

    test('verification is case-insensitive like the old gate', () async {
      await setAdminPassword(state, 'ShopPass1');
      expect(await verifyAdminPassword(state, 'shoppass1'), isTrue);
    });
  });

  group('app lock', () {
    test('is off by default', () async {
      expect(await AppLock.isEnabled(local), isFalse);
    });

    test('accepts only a 4–6 digit PIN', () async {
      expect(AppLock.validPin('123'), isFalse);
      expect(AppLock.validPin('1234'), isTrue);
      expect(AppLock.validPin('123456'), isTrue);
      expect(AppLock.validPin('1234567'), isFalse);
      expect(AppLock.validPin('12a4'), isFalse);

      await expectLater(
          AppLock.setPin(local, '12'), throwsA(isA<FormatException>()));
    });

    test('stores a hash, verifies, and clears on disable', () async {
      await AppLock.setPin(local, '2580');
      expect(await AppLock.isEnabled(local), isTrue);
      expect(await AppLock.verify(local, '2580'), isTrue);
      expect(await AppLock.verify(local, '0000'), isFalse);

      final hash = await local.getSetting(AppLock.hashKey);
      expect(hash, isNotNull);
      expect(hash, isNot(contains('2580')));

      await AppLock.disable(local);
      expect(await AppLock.isEnabled(local), isFalse);
      expect(await local.getSetting(AppLock.hashKey), isNull);
      expect(await AppLock.verify(local, '2580'), isFalse);
    });
  });
}
