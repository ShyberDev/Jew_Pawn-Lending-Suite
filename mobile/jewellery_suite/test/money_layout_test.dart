import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/features/customers/screens/customer_profile_screen.dart';
import 'package:jewellery_suite/features/khata/screens/khata_screen.dart';
import 'package:jewellery_suite/ui/pawn_dashboard_screen.dart';

/// #021 / #024 / #034: money and weight formatting must stay readable on a
/// small phone, and large figures must scale down rather than overflow.
void main() {
  late LocalDb local;
  late AppState state;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_money_ui_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'money_ui.db'));
    state = AppState(local);
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> settleWithDb(WidgetTester tester, {int rounds = 25}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpSmall(
    WidgetTester tester,
    Widget screen,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await settleWithDb(tester);
  }

  Future<void> seedBigKhata() async {
    await local.upsert('villages', {
      'client_uuid': 'v1',
      'village_name': 'Alpha',
      'dirty': 0,
    });
    await local.upsert('customers', {
      'client_uuid': 'c1',
      'customer_name': 'Ravi Kumar',
      'customer_id': 'A01',
      'village': 'Alpha',
      'phone': '9000000001',
      'dirty': 0,
    });
    await local.upsert('khatabook_loans', {
      'client_uuid': 'k1',
      'customer': 'c1',
      'customer_name': 'Ravi Kumar',
      'customer_uuid': 'c1',
      'village': 'Alpha',
      'status': 'Active',
      'loan_date': '2026-09-01',
      'start_date': '2026-09-01',
      'principal_amount': 99999999.0,
      'interest_amount': 10000000.0,
      'total_payable': 109999999.0,
      'installment_count': 12,
      'installment_amount': 9166666.0,
      'collection_frequency': 'Weekly',
      'payment_type': 'INSTALLMENT',
      'total_collected': 0,
      'outstanding': 109999999.0,
      'principal_outstanding': 99999999.0,
      'interest_outstanding': 10000000.0,
      'dirty': 0,
    });
  }

  testWidgets('customer profile fits 320 dp at 2× text with a large balance',
      (tester) async {
    await seedBigKhata();
    final customer = (await local.byUuid('customers', 'c1'))!;

    await pumpSmall(
        tester, CustomerProfileScreen(customer: customer));

    // A RenderFlex overflow is reported as a FlutterError from the frame.
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomerProfileScreen), findsOneWidget);
  });

  testWidgets('khata dashboard fits 320 dp at 2× text with large totals',
      (tester) async {
    await seedBigKhata();

    await pumpSmall(tester, const KhataGroupsScreen());

    expect(tester.takeException(), isNull);
  });

  testWidgets('pawn dashboard groups money and shows 3-decimal weights',
      (tester) async {
    await local.upsert('customers', {
      'client_uuid': 'pc1',
      'customer_name': 'Ravi',
      'customer_id': 'A01',
      'dirty': 0,
    });
    await local.upsert('pawn_loans', {
      'client_uuid': 'pl1',
      'customer_uuid': 'pc1',
      'customer': 'pc1',
      'customer_name': 'Ravi',
      'status': 'Active',
      'loan_date': '2026-10-01',
      'interest_basis': 'Gold',
      'loan_amount': 1234567.0,
      'interest_rate': 2.0,
      'interest_accrued': 0,
      'amount_paid': 0,
      'dirty': 0,
    });
    await local.upsert('pawn_items', {
      'loan_uuid': 'pl1',
      'metal_type': 'Gold',
      'net_weight': 987.6543,
    });
    await local.upsert('pawn_items', {
      'loan_uuid': 'pl1',
      'metal_type': 'Silver',
      'net_weight': 12.5,
    });

    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: PawnDashboardScreen()),
      ),
    );
    await settleWithDb(tester);

    expect(find.text('₹12,34,567'), findsOneWidget,
        reason: 'Indian lakh grouping, no raw double');
    expect(find.text('987.654 g'), findsOneWidget,
        reason: 'weights round to three decimals');
    expect(find.text('12.500 g'), findsOneWidget);
  });
}
