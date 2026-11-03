import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/features/customers/screens/customer_profile_screen.dart';
import 'package:jewellery_suite/features/pawn/screens/pawn_screen.dart';
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

  Future<void> pumpLoanForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: PawnLoanForm()),
      ),
    );
    await settleWithDb(tester);
  }

  testWidgets('pawn rows show village and filter by the Villages dropdown',
      (tester) async {
    await seedPawnLoans();
    await pumpPawn(tester);

    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('ID A01'), findsOneWidget);
    expect(find.text('Alpha · 20-10-26 · Gold'), findsOneWidget);
    expect(find.text('₹63,000'), findsOneWidget);
    expect(find.text('Suresh'), findsOneWidget);
    expect(find.text('ID A02'), findsOneWidget);
    expect(find.text('Beta · 18-10-26 · Silver'), findsOneWidget);
    // The Active / Released word is gone from the tile; the filter row says it.
    expect(find.text('Active'), findsOneWidget);

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

  testWidgets('search by ID / amount; tapping Active shows released too',
      (tester) async {
    await seedPawnLoans();
    await local.upsert('pawn_loans', {
      'client_uuid': 'loan-old',
      'customer_uuid': 'cust-ravi',
      'customer': 'cust-ravi',
      'customer_name': 'Ravi',
      'phone': '9000000001',
      'village': 'Alpha',
      'status': 'Released',
      'loan_date': '2026-09-01',
      'due_date': '2026-10-01',
      'interest_basis': 'Gold',
      'loan_amount': 5000.0,
      'interest_rate': 2.0,
      'interest_accrued': 0.0,
      'amount_paid': 0.0,
      'dirty': 0,
    });
    await pumpPawn(tester);

    // Default is Active, so the released ₹5,000 row is hidden.
    expect(find.text('₹5,000'), findsNothing);

    // Tapping the selected Active chip clears it: both lists are shown.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Active'));
    await settleWithDb(tester);
    expect(find.text('₹5,000'), findsOneWidget);

    // Search understands the book ID, not just the name.
    await tester.enterText(find.byType(TextField).first, 'A02');
    await settleWithDb(tester);
    expect(find.text('Suresh'), findsOneWidget);
    expect(find.text('Ravi'), findsNothing);

    // ...and the amount.
    await tester.enterText(find.byType(TextField).first, '63000');
    await settleWithDb(tester);
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
        reason:
            '#033: the Silver loan must leave the list, not just the total');
  });

  testWidgets('pawn filter offers loan-date and due-date ranges',
      (tester) async {
    await seedPawnLoans();
    await pumpPawn(tester);

    final filterPill = find.byKey(const ValueKey('pawn-filter'));
    await tester.ensureVisible(filterPill);
    await tester.pumpAndSettle();
    await tester.tap(filterPill);
    await tester.pumpAndSettle();

    expect(find.text('Loan date range'), findsOneWidget);
    expect(find.text('Due date range'), findsOneWidget);
  });

  testWidgets('amount range narrows the pledge list and the summary strip',
      (tester) async {
    await seedPawnLoans();
    await pumpPawn(tester);

    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Suresh'), findsOneWidget);

    // Both active loans: ₹63,000 + ₹15,000 invested.
    final summary = find.byKey(const ValueKey('pawn-summary'));
    expect(summary, findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('₹78,000')),
        findsOneWidget);

    // The filter row scrolls horizontally; the Filter pill sits past the right
    // edge on a 430 dp phone, so bring it into view first.
    final filterPill = find.byKey(const ValueKey('pawn-filter'));
    await tester.ensureVisible(filterPill);
    await tester.pumpAndSettle();
    await tester.tap(filterPill);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amount range'));
    await tester.pumpAndSettle();

    // "Above ₹50,000": leave the upper bound blank.
    await tester.enterText(
        find.widgetWithText(TextField, 'From ₹ (blank = any)'), '50000');
    await tester.tap(find.text('Apply'));
    await settleWithDb(tester);

    expect(find.descendant(of: filterPill, matching: find.text('≥ ₹50,000')),
        findsOneWidget,
        reason: 'the filter pill must say what is filtered');
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Suresh'), findsNothing);

    // #06G: the summary is the Active book, narrowed by the same range.
    expect(find.descendant(of: summary, matching: find.text('≥ ₹50,000')),
        findsOneWidget,
        reason: 'the summary caption must say what it is filtered by');
    expect(find.descendant(of: summary, matching: find.text('₹63,000')),
        findsOneWidget,
        reason: '#06G: the summary must follow the amount range');
    expect(find.descendant(of: summary, matching: find.text('₹78,000')),
        findsNothing);

    // Clear puts both pledges back.
    await tester.ensureVisible(filterPill);
    await tester.pumpAndSettle();
    await tester.tap(filterPill);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amount range'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await settleWithDb(tester);

    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Suresh'), findsOneWidget);
    expect(find.descendant(of: summary, matching: find.text('₹78,000')),
        findsOneWidget);
  });

  testWidgets('pawn tile shows the sync state and a visible caller menu',
      (tester) async {
    await seedPawnLoans();
    // Only Ravi's pledge has reached the server: Suresh's is still queued.
    await local.db.update(
      'pawn_loans',
      {'server_name': 'srv-ravi', 'dirty': 0},
      where: 'client_uuid = ?',
      whereArgs: ['loan-ravi'],
    );
    await pumpPawn(tester);

    // #06J: the cloud badge must actually render, with the state it claims.
    final synced = find.byKey(const ValueKey('pawn-sync-loan-ravi'));
    final waiting = find.byKey(const ValueKey('pawn-sync-loan-suresh'));
    expect(synced, findsOneWidget);
    expect(waiting, findsOneWidget);
    expect(
        find.descendant(
            of: synced, matching: find.byIcon(Icons.cloud_done_outlined)),
        findsOneWidget);
    expect(
        find.descendant(
            of: waiting, matching: find.byIcon(Icons.cloud_upload_outlined)),
        findsOneWidget,
        reason: 'a pledge the server has not named is a pending upload');

    // #06J: the caller menu needs a visible icon, not only a long-press.
    expect(find.byKey(const ValueKey('pawn-menu-loan-ravi')), findsOneWidget);
    expect(find.byKey(const ValueKey('pawn-menu-loan-suresh')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pawn-menu-loan-ravi')));
    await tester.pumpAndSettle();

    for (final action in const [
      'Call',
      'SMS',
      'WhatsApp',
      'Move to another pawn profile',
      'Edit',
    ]) {
      expect(find.text(action), findsOneWidget,
          reason: 'the tile menu must offer $action');
    }
  });

  testWidgets('moving a pledge asks the pawn-move password (#06A)',
      (tester) async {
    await seedPawnLoans();
    await state.setPawnMovePassword('move-1234');
    await pumpPawn(tester);

    Future<Object?> categoryOf(String uuid) async {
      final rows = await local.db.query('pawn_loans',
          columns: ['category'], where: 'client_uuid = ?', whereArgs: [uuid]);
      return rows.single['category'];
    }

    Future<void> chooseMove() async {
      await tester.tap(find.byKey(const ValueKey('pawn-menu-loan-ravi')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to another pawn profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pawn_Removed'));
      await tester.pumpAndSettle();
    }

    // The move does not happen on a tap alone: the secret is asked first, and
    // a wrong secret leaves the pledge where it was.
    await chooseMove();
    expect(find.text('Type pawn-move password'), findsOneWidget,
        reason: '#06A: moving a pledge must ask the pawn-move password');
    expect(await categoryOf('loan-ravi'), isNull);

    await tester.enterText(find.byType(TextField).last, 'wrong-secret');
    await tester.tap(find.text('Move'));
    await settleWithDb(tester);
    expect(await categoryOf('loan-ravi'), isNull,
        reason: 'a wrong password must never move a pledge');

    // The right secret moves it, and the tile says so.
    await chooseMove();
    await tester.enterText(find.byType(TextField).last, 'move-1234');
    await tester.tap(find.text('Move'));
    await settleWithDb(tester);
    expect(await categoryOf('loan-ravi'), 'Pawn_Removed');
    expect(find.text('Moved to Pawn_Removed.'), findsOneWidget);
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
    // #069 named the promised date explicitly and added the actual due date,
    // so the old bare 'Due Date' label must not come back.
    for (final label in const [
      'Principal',
      'Interest Rate',
      'Loan Date',
      'Due Date (Promised)',
      'Actual Due Date',
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

  testWidgets('returning from the + KYC form fills the visible customer name',
      (tester) async {
    await seedPawnLoans();
    await pumpLoanForm(tester);

    await tester.tap(find.byTooltip('Add new customer (Full KYC form)'));
    await tester.pumpAndSettle();
    expect(find.text('New Customer'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Customer name *'), 'Test Drag');
    await tester.tap(find.text('SAVE'));
    await settleWithDb(tester);
    // Let the CustomerForm route finish popping before looking at the loan
    // form; until then both forms are in the tree.
    await tester.pumpAndSettle();

    // Back on the loan form: the name must be in the visible Autocomplete box,
    // not only in the hidden value used by Save (#06H).
    expect(find.text('New Pawn Loan'), findsOneWidget);
    final nameField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Customer * (Type name or search)'));
    expect(nameField.controller?.text, 'Test Drag');
    final idField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Customer ID'));
    expect(idField.controller?.text, 'A03',
        reason: 'the new customer is the third book number after A01/A02');
  });
}
