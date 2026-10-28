import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/data/sample_data.dart';
import 'package:jewellery_suite/state/app_state.dart';

/// Cashbook linkage regressions for v1.1.2 (#030–#032).
///
/// The Cashbook is a mirror of money that actually moved. Before this batch it
/// only received entries on CREATE: editing a loan or collection left the old
/// amount behind, deleting the source left its cash, and a refinance wrote
/// nothing for the fresh cash. These tests pin the mirror to the source row.
void main() {
  late LocalDb local;
  late AppState state;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_cashbook_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'cashbook.db'));
    state = AppState(local);
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<List<Map<String, Object?>>> cash() => local.query('cashbook_entries');

  Map<String, Object?> pawnData(double amount, {String date = '2026-10-20'}) => {
        'customer': 'c1',
        'customer_name': 'Ravi',
        'customer_uuid': 'c1',
        'loan_date': date,
        'loan_amount': amount,
        'status': 'Active',
      };

  group('pawn loan cash follows edits', () {
    test('create writes one OUT; editing updates it instead of duplicating',
        () async {
      await state.savePawnLoan(
          uuid: 'pl1', data: pawnData(10000), items: const []);
      var rows = await cash();
      expect(rows, hasLength(1));
      expect(rows.single['category'], 'PAWN_DISBURSE');
      expect(rows.single['amount'], 10000.0);
      expect(rows.single['client_uuid'], isNotEmpty);

      final cashUuid = rows.single['client_uuid'];

      await state.savePawnLoan(
          uuid: 'pl1', data: pawnData(12500.5), items: const []);
      rows = await cash();
      expect(rows, hasLength(1), reason: 'an edit must not add a second entry');
      expect(rows.single['client_uuid'], cashUuid,
          reason: 'the same cash movement keeps its identity');
      expect(rows.single['amount'], 12500.0,
          reason: 'pawn cash truncates to whole rupees like the rest of pawn');
    });

    test('editing the principal to zero removes the entry', () async {
      await state.savePawnLoan(
          uuid: 'pl1', data: pawnData(10000), items: const []);
      await state.savePawnLoan(
          uuid: 'pl1', data: pawnData(0), items: const []);
      expect(await cash(), isEmpty);
    });

    test('deleting the loan removes its cash', () async {
      await state.savePawnLoan(
          uuid: 'pl1', data: pawnData(10000), items: const []);
      await state.deleteCashbookFor(['pl1']);
      expect(await cash(), isEmpty);
    });
  });

  group('khata collection cash follows edits', () {
    Map<String, Object?> collection(double amount,
            {String date = '2026-10-21', String mode = 'CASH'}) =>
        {
          'khatabook_loan': 'k1',
          'customer': 'Ravi',
          'customer_uuid': 'c1',
          'village': 'V',
          'collection_date': date,
          'amount': amount,
          'payment_mode': mode,
        };

    test('create, edit and zero keep exactly one entry in step', () async {
      await state.saveEntity(
          table: 'khatabook_collections',
          doctype: 'Khatabook Collection',
          uuid: 'col1',
          data: collection(1000));
      var rows = await cash();
      expect(rows, hasLength(1));
      expect(rows.single['reference_id'], 'col1',
          reason: 'the collection row must be the cash reference');
      expect(rows.single['entry_type'], 'IN');

      await state.saveEntity(
          table: 'khatabook_collections',
          doctype: 'Khatabook Collection',
          uuid: 'col1',
          data: collection(1500, mode: 'UPI'));
      rows = await cash();
      expect(rows, hasLength(1));
      expect(rows.single['amount'], 1500.0);
      expect(rows.single['payment_mode'], 'UPI');

      await state.saveEntity(
          table: 'khatabook_collections',
          doctype: 'Khatabook Collection',
          uuid: 'col1',
          data: collection(0));
      expect(await cash(), isEmpty);
    });

    test('a legacy entry keyed by the loan is migrated, not duplicated',
        () async {
      // Simulate a row written by v1.1.1: the collection existed, but the cash
      // entry pointed at the loan and carried the old amount.
      await local.upsert('khatabook_collections', {
        'client_uuid': 'col1',
        'khatabook_loan': 'k1',
        'customer': 'Ravi',
        'collection_date': '2026-10-21',
        'amount': 1000.0,
      });
      await local.addCashbookEntry({
        'client_uuid': 'legacy-cash',
        'entry_date': '2026-10-21',
        'entry_time': '09:00:00',
        'entry_type': 'IN',
        'amount': 1000.0,
        'payment_mode': 'CASH',
        'category': 'KHATA_COLLECTION',
        'reference_id': 'k1',
        'party_name': 'Ravi',
        'created_at': '2026-10-21T09:00:00',
      });

      await state.saveEntity(
          table: 'khatabook_collections',
          doctype: 'Khatabook Collection',
          uuid: 'col1',
          data: collection(1000));

      final rows = await cash();
      expect(rows, hasLength(1), reason: 'the legacy copy must be replaced');
      expect(rows.single['reference_id'], 'col1');
      expect(rows.single['amount'], 1000.0);
    });

    test('deleteCashbookForLoan removes disbursement and every collection',
        () async {
      await local.upsert('khatabook_loans', {
        'client_uuid': 'k1',
        'customer': 'c1',
        'customer_name': 'Ravi',
        'principal_amount': 10000.0,
        'total_payable': 12000.0,
      });
      await local.addCashbookEntry({
        'client_uuid': 'disb',
        'entry_date': '2026-10-20',
        'entry_time': '09:00:00',
        'entry_type': 'OUT',
        'amount': 10000.0,
        'payment_mode': 'CASH',
        'category': 'KHATA_DISBURSE',
        'reference_id': 'k1',
        'created_at': '2026-10-20T09:00:00',
      });
      await local.addCashbookEntry({
        'client_uuid': 'colcash',
        'entry_date': '2026-10-21',
        'entry_time': '09:00:00',
        'entry_type': 'IN',
        'amount': 1000.0,
        'payment_mode': 'CASH',
        'category': 'KHATA_COLLECTION',
        'reference_id': 'col1',
        'created_at': '2026-10-21T09:00:00',
      });
      await local.upsert('khatabook_collections', {
        'client_uuid': 'col1',
        'khatabook_loan': 'k1',
        'customer': 'c1',
        'collection_date': '2026-10-21',
        'amount': 1000.0,
      });

      await state.deleteCashbookForLoan({'k1'});
      expect(await cash(), isEmpty);
    });
  });

  group('refinance cash', () {
    test('writes only the fresh cash, never the rolled balance', () async {
      await local.upsert('khatabook_loans', {
        'client_uuid': 'old',
        'customer': 'c1',
        'customer_name': 'Ravi',
        'customer_uuid': 'c1',
        'village': 'V',
        'status': 'Active',
        'loan_date': '2026-09-01',
        'start_date': '2026-09-01',
        'principal_amount': 10000.0,
        'interest_amount': 2000.0,
        'total_payable': 12000.0,
        'installment_count': 12,
        'collection_frequency': 'Weekly',
        'payment_type': 'INSTALLMENT',
        'current_interest': 2000.0,
        'total_collected': 6000.0,
        'outstanding': 6000.0,
        'principal_outstanding': 4000.0,
        'interest_outstanding': 2000.0,
      });
      final old = (await local.byUuid('khatabook_loans', 'old'))!;

      await state.executeRefinance(
        oldLoan: old,
        fresh: 2500,
        interest: 900,
        paymentType: 'INSTALLMENT',
        frequency: 'Weekly',
        count: 12,
        collectionAmount: 500,
      );

      final rows = await cash();
      expect(rows, hasLength(1));
      expect(rows.single['category'], 'KHATA_REFINANCE');
      expect(rows.single['entry_type'], 'OUT');
      expect(rows.single['amount'], 2500.0,
          reason: 'the rolled ₹6,000 is a transfer, not cash');
    });
  });

  group('sample data removal (#032)', () {
    late SampleDataService samples;

    setUp(() {
      samples = SampleDataService(local);
    });

    test('deletes cash for demo rows and keeps real cash', () async {
      await local.upsert('villages',
          {'client_uuid': 'v-demo-1', 'village_name': 'Pallipatti'});
      await local.upsert('villages',
          {'client_uuid': 'v-real', 'village_name': 'Uppalapadu'});
      await local.upsert('customers', {
        'client_uuid': 'c-demo-1',
        'customer_name': 'Lakshmi Bai',
        'village': 'Pallipatti',
      });
      await local.upsert('customers', {
        'client_uuid': 'c-real',
        'customer_name': 'Ravi Kumar',
        'village': 'Uppalapadu',
      });
      await local.upsert('khatabook_loans', {
        'client_uuid': 'l-demo',
        'customer': 'c-demo-1',
        'customer_name': 'Lakshmi Bai',
        'village': 'Pallipatti',
        'principal_amount': 5000.0,
        'total_payable': 6500.0,
      });
      await local.upsert('khatabook_loans', {
        'client_uuid': 'l-real',
        'customer': 'c-real',
        'customer_name': 'Ravi Kumar',
        'village': 'Uppalapadu',
        'principal_amount': 7000.0,
        'total_payable': 8000.0,
      });
      for (final ref in ['l-demo', 'l-real']) {
        await local.addCashbookEntry({
          'client_uuid': 'cash-$ref',
          'entry_date': '2026-10-20',
          'entry_time': '09:00:00',
          'entry_type': 'OUT',
          'amount': 1000.0,
          'payment_mode': 'CASH',
          'category': 'KHATA_DISBURSE',
          'reference_id': ref,
          'created_at': '2026-10-20T09:00:00',
        });
      }

      final report = await samples.inspect();
      expect(report.safeToRemove, isTrue, reason: report.blocked.join('; '));
      await samples.remove(confirmedByUser: true);

      final rows = await cash();
      expect(rows, hasLength(1));
      expect(rows.single['reference_id'], 'l-real',
          reason: 'only the demo loan\'s cash may be removed');
    });
  });
}
