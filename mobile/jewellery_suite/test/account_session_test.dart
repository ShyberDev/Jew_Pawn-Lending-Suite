import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/util/account.dart';

/// #057: sign in once, stay signed in until Logout.
///
/// Reported from the phone on 2026-11-01 (v1.1.8): after the PIN the app showed
/// the account login instead of Home, even though the shop's ledger was on the
/// phone. Root cause: [AppState.load] only applied the "phone already holds the
/// ledger" fallback when no account existed, and the session flag had been
/// lost. These tests lock both halves of the rule:
///
/// * a lost session flag on a phone with data reopens the shop;
/// * a deliberate Logout still shows the login screen, and signing in again
///   clears that marker.
void main() {
  late LocalDb local;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_account_session_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'account.db'));
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> seedLedger() async {
    await local.upsert('customers', {
      'client_uuid': 'cust-ravi',
      'customer_name': 'Ravi',
      'customer_id': 'A01',
      'village': 'Alpha',
      'dirty': 0,
    });
  }

  Future<AppState> createAccount() async {
    final state = AppState(local);
    await state.load();
    await state.createAccount(
      name: 'Shop',
      identifier: '9876543210',
      password: 'shop123456',
    );
    return state;
  }

  test('a lost session flag reopens a phone that holds the ledger', () async {
    await seedLedger();
    final state = await createAccount();
    expect(state.loggedIn, isTrue);

    // Simulate the reported state: the account is still there, the ledger is
    // still there, but nothing has an active session.
    await local.setSetting(LocalAccount.sessionKey, null);
    expect(await LocalAccount.hasSession(local), isFalse);
    expect(await LocalAccount.exists(local), isTrue);

    final relaunch = AppState(local);
    await relaunch.load();
    expect(relaunch.loggedIn, isTrue,
        reason: 'the shop must not be locked out of its own ledger (#057)');
    expect(relaunch.hasAccount, isTrue,
        reason: 'the account is still known, it just had no session');
  });

  test('an account on a phone with no ledger still shows Login', () async {
    await createAccount();
    await local.setSetting(LocalAccount.sessionKey, null);

    final relaunch = AppState(local);
    await relaunch.load();
    expect(relaunch.loggedIn, isFalse,
        reason: 'nothing to show yet, so the login form is the honest screen');
  });

  test('a fresh phone with no account and no data shows Login', () async {
    final state = AppState(local);
    await state.load();
    expect(state.loggedIn, isFalse);
  });

  test('Logout is honoured even when the ledger is on the phone', () async {
    await seedLedger();
    final state = await createAccount();
    await state.logout();
    expect(state.loggedIn, isFalse);

    final relaunch = AppState(local);
    await relaunch.load();
    expect(relaunch.loggedIn, isFalse,
        reason:
            'a deliberate Logout must not be undone by the ledger fallback');
  });

  test('signing in again clears the Logout marker and sticks', () async {
    await seedLedger();
    final state = await createAccount();
    await state.logout();

    final relaunch = AppState(local);
    await relaunch.load();
    expect(relaunch.loggedIn, isFalse);

    await relaunch.signInWithPassword('9876543210', 'shop123456');
    expect(relaunch.loggedIn, isTrue);
    expect(await LocalAccount.signedOutByUser(local), isFalse);

    final again = AppState(local);
    await again.load();
    expect(again.loggedIn, isTrue,
        reason: 'the session must survive the next restart');
  });

  test('creating the account signs the shop in immediately', () async {
    await seedLedger();
    await createAccount();
    expect(await LocalAccount.hasSession(local), isTrue);

    final relaunch = AppState(local);
    await relaunch.load();
    expect(relaunch.loggedIn, isTrue);
  });
}
