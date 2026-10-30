import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';

/// #054: the shop must be able to open its own ledger without a server.
///
/// The app is offline-first, but a fresh install (or a restore onto a new
/// phone) had no saved server session and therefore sat on the login screen
/// forever. "Use without a server" records that choice, survives a restart,
/// and is cleared again by Logout or a real login.
void main() {
  late LocalDb local;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_offline_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'offline.db'));
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('no session means the login screen first', () async {
    final state = AppState(local);
    await state.load();
    expect(state.loggedIn, isFalse);
    expect(state.serverUrl, isEmpty);
  });

  test('the offline choice opens the shop and survives a restart', () async {
    final state = AppState(local);
    await state.load();
    await state.continueOffline();
    expect(state.loggedIn, isTrue);

    final nextLaunch = AppState(local);
    await nextLaunch.load();
    expect(nextLaunch.loggedIn, isTrue,
        reason: 'offline mode must persist in the settings table');
    expect(nextLaunch.serverUrl, isEmpty,
        reason: 'offline mode must not invent a server connection');
  });

  test('logout clears offline mode and shows the login form again', () async {
    final state = AppState(local);
    await state.load();
    await state.continueOffline();
    await state.logout();
    expect(state.loggedIn, isFalse);

    final nextLaunch = AppState(local);
    await nextLaunch.load();
    expect(nextLaunch.loggedIn, isFalse);
  });
}
