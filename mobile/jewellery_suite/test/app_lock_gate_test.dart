import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/ui/admin_guard.dart';
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

  testWidgets('a resume right after unlocking does not re-lock the gate',
      (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.enterText(find.byType(TextField), '2468');
    await tester.tap(find.text('Unlock'));
    await settle(tester);
    expect(find.text('open screen'), findsOneWidget);

    // #066: the system fingerprint prompt backgrounds and then resumes the
    // app. An unlocked app must stay open across that resume — re-locking here
    // rebuilt the lock screen and re-armed its auto-prompt in a loop.
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(find.text('Jewellery Suite is locked'), findsNothing);
    expect(find.text('open screen'), findsOneWidget);
  });

  testWidgets('Forgot PIN names the PIN and asks the admin password with no account',
      (tester) async {
    await setAdminPassword(state, 'Admin@123');
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Forgot PIN?'));
    await settle(tester);

    // This used to read "Forgot always" and, with no Gmail / mobile account,
    // ended in "No account registered" — advice the lock screen cannot act on.
    expect(find.text('Forgot PIN'), findsOneWidget);
    expect(find.textContaining('No account registered'), findsNothing);
    expect(find.text('Admin password'), findsOneWidget);
  });

  testWidgets('the admin password resets the PIN on a locked phone',
      (tester) async {
    await setAdminPassword(state, 'Admin@123');
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Forgot PIN?'));
    await settle(tester);
    // The lock screen's own PIN field is behind the dialog, so target the
    // dialog's field by its label rather than by position.
    await tester.enterText(
        find.widgetWithText(TextField, 'Admin password'), 'Admin@123');
    await tester.tap(find.text('Continue'));
    await settle(tester);

    expect(find.text('Set a new PIN'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'New PIN (4–6 digits)'), '135790');
    await tester.enterText(find.widgetWithText(TextField, 'Repeat PIN'), '135790');
    await tester.tap(find.text('Save'));
    await settle(tester);

    // The reset must also open the shop — a new PIN on a still-locked screen
    // would be the same dead end in a different suit.
    expect(find.text('Jewellery Suite is locked'), findsNothing);
    expect(find.text('open screen'), findsOneWidget);
  });

  testWidgets('a wrong admin password does not reset the PIN', (tester) async {
    // The lock screen must not be talkable-into a reset: a wrong secret has to
    // stop at the snackbar and leave the phone locked.
    await setAdminPassword(state, 'Admin@123');
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Forgot PIN?'));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Admin password'), 'not-the-password');
    await tester.tap(find.text('Continue'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('That admin password is wrong.'), findsOneWidget);
    expect(find.text('Set a new PIN'), findsNothing);
    expect(find.text('Jewellery Suite is locked'), findsOneWidget);
  });

  testWidgets('Forgot PIN with an account asks for the code and shows it offline',
      (tester) async {
    // With a Gmail / mobile account the lock screen sends a one-time code.
    // v1.4.20 phone finding: tapping **Send code** closed the dialog and then
    // nothing appeared at all, so the reset looked dead. This pins the step
    // that must follow the send.
    state.hasAccount = true;
    state.accountIdentifier = 'shop@gmail.com';
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Forgot PIN?'));
    await settle(tester);
    expect(find.text('Send a 6-digit code to'), findsOneWidget);
    expect(find.text('shop@gmail.com'), findsOneWidget);

    await tester.tap(find.text('Send code'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Enter the 6-digit code'), findsOneWidget,
        reason: 'the code box must appear after Send code');
    expect(find.text('Offline code (valid 10 minutes)'), findsOneWidget);
    // #085: the "Sending the code…" dialog must be gone, not left on top.
    expect(find.text('Sending the code…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a wrong one-time code keeps the phone locked', (tester) async {
    state.hasAccount = true;
    state.accountIdentifier = 'shop@gmail.com';
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Forgot PIN?'));
    await settle(tester);
    await tester.tap(find.text('Send code'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Enter the 6-digit code'), findsOneWidget);

    // 000000 is the issued code with a one-in-a-million chance; the point of the
    // case is that a wrong code is refused instead of opening the shop.
    await tester.enterText(find.widgetWithText(TextField, 'Code'), '000000');
    await tester.tap(find.text('Verify'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('The code is wrong or has expired. Try again.'),
        findsOneWidget);
    expect(find.text('Set a new PIN'), findsNothing);
    expect(find.text('Jewellery Suite is locked'), findsOneWidget);
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
