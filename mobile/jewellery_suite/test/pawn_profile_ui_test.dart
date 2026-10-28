import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/ui/customer_profile_screen.dart';
import 'package:jewellery_suite/ui/pawn_screen.dart';
import 'package:jewellery_suite/util/format.dart';

/// UI behaviour requested for the 2026-10-28 round:
///
/// * Collection Reminder has one date picker (no duplicate "Calendar…" chip)
///   and the preview follows the date actually picked.
/// * Pawn rows show the customer photo, name + village, and keep ID / date /
///   item / amount.
/// * The Pawn Profile groups customer details into an expandable KYC tile,
///   shows a six-field loan card, and orders the actions as agreed.
/// * The Pawn list filters by village, with no "All" status chip.
void main() {
  late LocalDb local;
  late AppState state;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    // Widget tests run under a fake clock; the isolate-backed factory never
    // completes there. The no-isolate factory runs SQLite in the test zone.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_pawn_ui_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'pawn_ui.db'));
    state = AppState(local);
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> seedPawnLoans() async {
    await local.upsert('villages', {
      'client_uuid': 'v-alpha',
      'village_name': 'Alpha',
      'dirty': 0,
    });
    await local.upsert('villages', {
      'client_uuid': 'v-beta',
      'village_name': 'Beta',
      'dirty': 0,
    });
    await local.upsert('customers', {
      'client_uuid': 'cust-ravi',
      'customer_name': 'Ravi',
      'customer_id': 'A01',
      'village': 'Alpha',
      'address': '12 Main Street',
      'phone': '9000000001',
      'dirty': 0,
    });
    await local.upsert('customers', {
      'client_uuid': 'cust-suresh',
      'customer_name': 'Suresh',
      'customer_id': 'A02',
      'village': 'Beta',
      'address': '8 Lake Road',
      'phone': '9000000002',
      'dirty': 0,
    });
    await local.upsert('pawn_loans', {
      'client_uuid': 'loan-ravi',
      'customer_uuid': 'cust-ravi',
      'customer': 'cust-ravi',
      'customer_name': 'Ravi',
      'phone': '9000000001',
      'village': 'Alpha',
      'status': 'Active',
      'loan_date': '2026-10-20',
      'due_date': '2026-11-20',
      'interest_basis': 'Gold',
      'loan_amount': 63000.0,
      'interest_rate': 2.0,
      'interest_accrued': 0.0,
      'amount_paid': 0.0,
      'last_interest_date': '2026-10-20',
      'dirty': 0,
    });
    await local.upsert('pawn_loans', {
      'client_uuid': 'loan-suresh',
      'customer_uuid': 'cust-suresh',
      'customer': 'cust-suresh',
      'customer_name': 'Suresh',
      'phone': '9000000002',
      'village': 'Beta',
      'status': 'Active',
      'loan_date': '2026-10-18',
      'due_date': '2026-11-18',
      'interest_basis': 'Silver',
      'loan_amount': 15000.0,
      'interest_rate': 2.0,
      'interest_accrued': 0.0,
      'amount_paid': 0.0,
      'last_interest_date': '2026-10-18',
      'dirty': 0,
    });
    await local.upsert('pawn_items', {
      'loan_uuid': 'loan-ravi',
      'item_description': 'Gold chain',
      'metal_type': 'Gold',
      'purity': '22K',
      'quantity': 1,
      'gross_weight': 10.0,
      'net_weight': 9.5,
      'hallmarked': 1,
      'market_value': 65000.0,
    });
  }

  /// Gives real SQLite futures time to finish, then advances the widget clock.
  /// A plain `pumpAndSettle` hangs here because the DB runs outside the fake
  /// async zone while a spinner keeps the frame loop alive.
  Future<void> settleWithDb(WidgetTester tester, {int rounds = 20}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpPawn(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: PawnScreen()),
      ),
    );
    await settleWithDb(tester);
  }

  testWidgets('pawn rows show village and filter by the Villages dropdown',
      (tester) async {
    await seedPawnLoans();
    await pumpPawn(tester);

    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Alpha · ID A01'), findsOneWidget);
    expect(find.text('20-10-26 · Gold · ₹63,000'), findsOneWidget);
    expect(find.text('Suresh'), findsOneWidget);
    expect(find.text('Beta · ID A02'), findsOneWidget);

    // The status row no longer carries "All"; villages live in a dropdown.
    expect(find.widgetWithText(ChoiceChip, 'All'), findsNothing);
    expect(find.text('Villages'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pawn-village-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pawn-village-Alpha')));
    await settleWithDb(tester);

    expect(find.text('Villages: Alpha'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Suresh'), findsNothing);
  });

  testWidgets('metal filter narrows the loan list, not only the summary',
      (tester) async {
    await seedPawnLoans();
    await pumpPawn(tester);

    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Suresh'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Gold'));
    await settleWithDb(tester);

    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Suresh'), findsNothing,
        reason: '#033: the Silver loan must leave the list, not just the total');
  });

  testWidgets(
      'pawn profile expands KYC details, shows loan fields and action order',
      (tester) async {
    await seedPawnLoans();
    await pumpPawn(tester);

    await tester.tap(find.text('Ravi'));
    await settleWithDb(tester);

    expect(find.text('Customer Pawn Profile'), findsOneWidget);
    final loanCard = find.byKey(const ValueKey('pawn-loan-details'));
    for (final label in const [
      'Principal',
      'Interest Rate',
      'Loan Date',
      'Due Date',
      'Amount Paid',
      'Outstanding',
    ]) {
      expect(find.descendant(of: loanCard, matching: find.text(label)),
          findsOneWidget);
    }

    // Thumbnail stays small until tapped, then shows the full-screen viewer.
    await tester.tap(find.byKey(const ValueKey('pawn-customer-photo')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // The KYC tile expands instead of jumping straight to the edit form.
    await tester.tap(find.text('Customer KYC & Details'));
    await tester.pumpAndSettle();
    expect(find.text('Customer Name'), findsOneWidget);
    expect(find.text('Mobile Number'), findsOneWidget);
    expect(find.text('12 Main Street'), findsOneWidget);
    expect(find.text('Edit customer'), findsOneWidget);

    final sheetScroll = find.descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('pawn-actions')),
      300,
      scrollable: sheetScroll.first,
    );
    await tester.pumpAndSettle();

    final labels = tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const ValueKey('pawn-actions')),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(
        labels,
        containsAllInOrder([
          'Interest Paying',
          'Amount Paying',
          'Amount Requesting',
          'Release',
        ]));

    await tester.scrollUntilVisible(
      find.text('Delete Loan'),
      250,
      scrollable: sheetScroll.first,
    );
    expect(find.text('Delete Loan'), findsOneWidget);
  });

  testWidgets('collection reminder keeps one date picker and previews the pick',
      (tester) async {
    await local.upsert('customers', {
      'client_uuid': 'cust-ravi',
      'customer_name': 'Ravi',
      'customer_id': 'A01',
      'village': 'Alpha',
      'phone': '9000000001',
      'dirty': 0,
    });
    final customer = (await local.byUuid('customers', 'cust-ravi'))!;

    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(home: CustomerProfileScreen(customer: customer)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remind: not set'));
    await tester.pumpAndSettle();

    expect(find.text('Collection reminder'), findsOneWidget);
    expect(find.text('Calendar…'), findsNothing);
    expect(find.text('Pick date'), findsOneWidget);

    await tester.tap(find.text('Pick date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // With no collection frequency the dialog opens on "Next week". Tapping OK
    // must preview that exact date, not a hard-coded example.
    final expected = DateTime.now().add(const Duration(days: 7));
    final expectedIso = '${expected.year.toString().padLeft(4, '0')}-'
        '${expected.month.toString().padLeft(2, '0')}-'
        '${expected.day.toString().padLeft(2, '0')}';
    expect(find.text('Remind ${fmtReminder(expectedIso)}'), findsOneWidget);
  });
}
