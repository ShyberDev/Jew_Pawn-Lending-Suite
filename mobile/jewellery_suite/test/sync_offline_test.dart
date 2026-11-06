import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/api_client.dart';
import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/features/home/screens/home_screen.dart';
import 'package:jewellery_suite/features/sync/screens/sync_screen.dart';
import 'package:jewellery_suite/state/app_state.dart';

/// #082: this shop runs without a server, so sync has no session to use.
///
/// Tapping the home Sync button used to answer "Sync failed: Not logged in",
/// which reads like a fault. Offline mode must say it is offline instead, and
/// the state must still refuse a real sync rather than pretend it happened.
void main() {
  late LocalDb local;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_sync_offline_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'sync.db'));
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('offline mode has no sync client and says so', () async {
    final state = AppState(local);
    await state.load();
    await state.continueOffline();

    expect(state.canSync, isFalse);
    expect(AppState.offlineSyncNotice, contains('Offline mode'));
    expect(AppState.offlineSyncNotice, isNot(contains('Not logged in')));

    // The guard is only about the message: a sync with no client must still
    // fail instead of silently doing nothing.
    await expectLater(
      state.sync(),
      throwsA(isA<ApiException>()
          .having((e) => e.toString(), 'message', contains('Not logged in'))),
    );
  });

  testWidgets('Sync now explains offline mode instead of a failed sync',
      (tester) async {
    final state = AppState(local);
    // Real database I/O does not run under the widget test's fake clock.
    await tester.runAsync(() async {
      await state.load();
      await state.continueOffline();
    });

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: SyncScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sync now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(AppState.offlineSyncNotice), findsOneWidget);
    expect(find.textContaining('Sync failed'), findsNothing);
  });

  testWidgets('the home Sync button says offline instead of failing',
      (tester) async {
    final state = AppState(local);
    await tester.runAsync(() async {
      await state.load();
      await state.continueOffline();
    });

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: HomeScreen()),
    ));
    // HomeScreen reads its dashboard from the database in initState, which needs
    // the real clock to finish.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    // The drawer carries the same icon; the header one comes first.
    await tester.tap(find.byIcon(Icons.sync).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(AppState.offlineSyncNotice), findsOneWidget);
    expect(find.textContaining('Sync failed'), findsNothing);
  });
}
