import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/ui/app_lock_gate.dart';
import 'package:jewellery_suite/util/app_lock.dart';

/// #037: the PIN gate must cover whatever screen is on top when the app is
/// backgrounded — not only the Home route.
///
/// The gate used to sit inside `MaterialApp.home`. Navigated screens (Settings,
/// a customer profile, Cashbook) are pushed above that route, so the lock was
/// painted underneath them and the shop stayed readable on the counter. The
/// gate now wraps the Navigator itself, which this test pins down.
void main() {
  late LocalDb local;
  late AppState state;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_lock_gate_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'gate.db'));
    state = AppState(local);
    await AppLock.setPin(local, '2468');
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Lets the database future finish, then draws the result.
  ///
  /// `pumpAndSettle` cannot be used here: while `_check()` is waiting on the
  /// database the lock gate shows a spinner, and the spinner never settles.
  /// The no-isolate factory completes DB futures on the test's own event loop,
  /// so ordinary pumps are enough.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget app() {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        builder: (context, child) => AppLockGate(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('deep screen')),
                    ),
                  ),
                ),
                child: const Text('open screen'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a cold start is locked', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('Jewellery Suite is locked'), findsOneWidget);
  });

  testWidgets('wrong PIN keeps it locked; the right PIN opens the shop',
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(find.text('Unlock'));
    await settle(tester);
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
    expect(find.text('Jewellery Suite is locked'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '2468');
    await tester.tap(find.text('Unlock'));
    await settle(tester);
    expect(find.text('Jewellery Suite is locked'), findsNothing);
    expect(find.text('open screen'), findsOneWidget);
  });

  testWidgets('backgrounding on a pushed screen covers that screen too',
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.enterText(find.byType(TextField), '2468');
    await tester.tap(find.text('Unlock'));
    await settle(tester);

    await tester.tap(find.text('open screen'));
    await settle(tester);
    expect(find.text('deep screen'), findsOneWidget);

    // Walk the legal lifecycle sequence (paused is not reachable directly
    // from resumed, and Flutter asserts on an invalid transition).
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(find.text('Jewellery Suite is locked'), findsOneWidget,
        reason: 'the gate must sit above the pushed route');
    expect(find.text('deep screen'), findsNothing);
  });

  testWidgets('disabling the PIN in Settings disarms the gate', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.enterText(find.byType(TextField), '2468');
    await tester.tap(find.text('Unlock'));
    await settle(tester);

    // The Settings screen turns the switch off in the database; the gate must
    // notice on the next foreground instead of staying armed forever.
    await AppLock.disable(local);
    // Walk the legal lifecycle sequence (paused is not reachable directly
    // from resumed, and Flutter asserts on an invalid transition).
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(find.text('Jewellery Suite is locked'), findsNothing);
    expect(find.text('open screen'), findsOneWidget);
  });
}
