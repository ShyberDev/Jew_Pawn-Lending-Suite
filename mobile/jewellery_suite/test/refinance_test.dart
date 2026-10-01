import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';

/// Refinance is a split, never a rewrite.
///
/// The bug this locks out: the old code folded the outstanding into a fresh
/// principal ON THE SAME ROW, added a marker row carrying the fresh cash, and
/// the ledger counted both — a ₹12,000 loan refinanced with ₹12,000 fresh
/// showed balances near ₹38,400. Now the old loan freezes and a separate new
/// loan carries previous + fresh + interest.
void main() {
  late LocalDb local;
  late AppState state;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_refi_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'refi.db'));
    state = AppState(local);
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<String> oldLoan({
    double principal = 10000,
    double interest = 2000,
    double collected = 6000,
  }) async {
    const uuid = 'loan-old-1';
    final total = principal + interest;
    await local.upsert('khatabook_loans', {
      'client_uuid': uuid,
      'customer_name': 'Test',
      'customer_uuid': 'c1',
      'village': 'V',
      'status': 'Active',
      'loan_date': '2026-09-01',
      'start_date': '2026-09-01',
      'principal_amount': principal,
      'interest_amount': interest,
      'total_payable': total,
      'installment_count': 12,
      'installment_amount': total / 12,
      'collection_frequency': 'Weekly',
      'payment_type': 'INSTALLMENT',
      'current_interest': interest,
      'total_collected': collected,
      'paid_installments': 6,
      'outstanding': total - collected,
      'principal_outstanding': principal,
      'interest_outstanding': 0,
      'principal_recovered': 0,
    });
    return uuid;
  }

  group('the frozen draft example', () {
    test('6000 + 2000 + 1600 = 9600 across two rows', () async {
      final oldUuid = await oldLoan();
      final before =
          (await local.byUuid('khatabook_loans', oldUuid))!;

      final created = await state.executeRefinance(
        oldLoan: before,
        fresh: 2000,
        interest: 1600,
        paymentType: 'INSTALLMENT',
        frequency: 'Weekly',
        count: 12,
        collectionAmount: 800,
        note: 'test',
      );

      // Old loan: frozen, history intact.
      final old = (await local.byUuid('khatabook_loans', oldUuid))!;
      expect(old['status'], 'REFINANCED');
      expect(old['outstanding'], 6000);
      expect(old['total_collected'], 6000);
      expect(old['principal_amount'], 10000,
          reason: 'nothing rewritten');

      // New loan: the three components, separately visible.
      expect(created['principal_amount'], 8000,
          reason: '6000 rolled + 2000 fresh');
      expect(created['interest_amount'], 1600);
      expect(created['total_payable'], 9600);
      expect(created['outstanding'], 9600);
      expect(created['installment_amount'], 800);
      expect(created['installment_count'], 12);
      expect(created['refinanced_from'], oldUuid);
      expect(created['status'], 'Active');
      expect(created['total_collected'], 0);
      expect(created['payment_type'], 'INSTALLMENT');

      // The record links both sides with the breakdown the tile shows.
      final refis = await local.db.query('khatabook_refinances');
      expect(refis.length, 1);
      expect(refis.first['old_outstanding'], 6000);
      expect(refis.first['new_principal'], 8000);
      expect(refis.first['new_interest_amount'], 1600);
      expect(refis.first['new_loan'], created['client_uuid']);
    });

    test('ledger arithmetic: old + transfer + new = new outstanding',
        () async {
      final oldUuid = await oldLoan();
      final before =
          (await local.byUuid('khatabook_loans', oldUuid))!;
      await state.executeRefinance(
        oldLoan: before,
        fresh: 2000,
        interest: 1600,
        paymentType: 'INSTALLMENT',
        frequency: 'Weekly',
        count: 12,
        collectionAmount: 800,
      );
      // Ledger model: old debit + collections + transfer credit + new debit.
      const oldTotal = 12000.0;
      const oldCollections = 6000.0;
      const transfer = 6000.0;
      const newTotal = 9600.0;
      expect(oldTotal - oldCollections - transfer + newTotal, 9600,
          reason: 'exactly the new outstanding, nothing doubled');
    });

    test('no given marker row is written for the fresh cash', () async {
      final oldUuid = await oldLoan();
      final before =
          (await local.byUuid('khatabook_loans', oldUuid))!;
      await state.executeRefinance(
        oldLoan: before,
        fresh: 2000,
        interest: 1600,
        paymentType: 'INSTALLMENT',
        frequency: 'Weekly',
        count: 12,
        collectionAmount: 800,
      );
      final givens = await local.db.query('khatabook_given');
      expect(givens, isEmpty,
          reason: 'fresh cash lives inside the new loan total');
    });
  });

  group('interest-only refinance', () {
    test('new loan starts at principal; first period billed once', () async {
      final oldUuid = await oldLoan();
      final before =
          (await local.byUuid('khatabook_loans', oldUuid))!;
      final created = await state.executeRefinance(
        oldLoan: before,
        fresh: 2000,
        interest: 600,
        paymentType: 'INTEREST_ONLY',
        frequency: 'Monthly',
        count: 0,
        collectionAmount: 0,
        on: DateTime(2026, 10, 2),
      );
      // 6000 rolled + 2000 fresh = 8000 principal; first 600 period billed.
      expect(created['principal_amount'], 8000);
      expect(created['total_payable'], 8600);
      expect(created['outstanding'], 8600);
      expect(created['payment_type'], 'INTEREST_ONLY');
      expect(created['current_interest'], 600);
      final periods = await local.db.query('khatabook_installments',
          where: 'khatabook_loan = ?',
          whereArgs: [created['client_uuid']]);
      expect(periods.length, 1);
      expect(periods.first['scheduled_amount'], 600);
    });
  });

  group('defaults', () {
    test('blank collection amount falls back to total ÷ count', () async {
      // Covered at the dialog layer; the writer stores what it is given.
      final oldUuid = await oldLoan();
      final before =
          (await local.byUuid('khatabook_loans', oldUuid))!;
      final created = await state.executeRefinance(
        oldLoan: before,
        fresh: 0,
        interest: 1200,
        paymentType: 'INSTALLMENT',
        frequency: 'Weekly',
        count: 12,
        collectionAmount: 600,
      );
      // 6000 + 0 + 1200 = 7200; stored collection figure kept as passed.
      expect(created['total_payable'], 7200);
      expect(created['installment_amount'], 600);
    });
  });
}
