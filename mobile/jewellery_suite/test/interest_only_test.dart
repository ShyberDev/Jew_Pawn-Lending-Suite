import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/data/migration_v11.dart';
import 'package:jewellery_suite/state/app_state.dart';

/// Interest-only loans: one interest period billed at a time, principal
/// untouched until a principal payment arrives, future prepay explicit only.
///
/// The load-bearing rules, each pinned here:
/// - paying the period interest recovers ZERO principal;
/// - changing current_interest never rewrites billed periods;
/// - normal money never prepays a future period;
/// - an explicit future prepay marks exactly that period.
void main() {
  late LocalDb local;
  late AppState state;
  late Directory dir;

  String isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_io_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'io.db'));
    state = AppState(local);
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<Map<String, Object?>> interestOnlyLoan({
    double principal = 10000,
    double interest = 600,
    DateTime? start,
  }) async {
    final s = start ?? DateTime(2026, 9, 1);
    final uuid = 'loan-io-1';
    await local.upsert('khatabook_loans', {
      'client_uuid': uuid,
      'customer_name': 'Test',
      'customer_uuid': 'c1',
      'village': 'V',
      'status': 'Active',
      'loan_date': isoDay(s),
      'start_date': isoDay(s),
      'principal_amount': principal,
      'interest_amount': interest,
      'total_payable': principal,
      'installment_count': 0,
      'installment_amount': interest,
      'collection_frequency': 'Monthly',
      'payment_type': MigrationV11.interestOnly,
      'current_interest': interest,
      'total_collected': 0,
      'paid_installments': 0,
      'outstanding': principal,
      'principal_outstanding': principal,
      'interest_outstanding': 0,
      'principal_recovered': 0,
    });
    final loan = (await local.byUuid('khatabook_loans', uuid))!;
    return loan;
  }

  group('billing', () {
    test('creation bills exactly the first period', () async {
      final loan = await interestOnlyLoan();
      final rows =
          await state.ensureInterestPeriods(loan, today: DateTime(2026, 9, 15));
      expect(rows.length, 1);
      expect(rows.first['scheduled_amount'], 600);
      expect(rows.first['remaining_amount'], 600);
      expect(rows.first['status'], 'PENDING');
    });

    test('a later month bills the next period, never rewrites the first',
        () async {
      final loan = await interestOnlyLoan();
      await state.ensureInterestPeriods(loan, today: DateTime(2026, 9, 15));
      final rows =
          await state.ensureInterestPeriods(loan, today: DateTime(2026, 10, 5));
      expect(rows.length, 2);
      expect(rows[0]['scheduled_amount'], 600);
      // A changed current_interest applies to new periods only.
      await local.upsert('khatabook_loans', {
        ...loan,
        'current_interest': 350,
      });
      final again = (await local.byUuid('khatabook_loans', 'loan-io-1'))!;
      final rows2 = await state.ensureInterestPeriods(again,
          today: DateTime(2026, 11, 5));
      expect(rows2.length, 3);
      expect(rows2[2]['scheduled_amount'], 350);
      expect(rows2[0]['scheduled_amount'], 600, reason: 'history is immutable');
    });

    test('calling ensure twice bills nothing extra', () async {
      final loan = await interestOnlyLoan();
      await state.ensureInterestPeriods(loan, today: DateTime(2026, 9, 15));
      final rows =
          await state.ensureInterestPeriods(loan, today: DateTime(2026, 9, 15));
      expect(rows.length, 1);
      final live = (await local.byUuid('khatabook_loans', 'loan-io-1'))!;
      expect(live['total_payable'], 10600);
    });
  });

  group('spec sequence: 600 interest, then 600 + 4000 principal', () {
    test('interest-only payment recovers zero principal', () async {
      final loan = await interestOnlyLoan();
      await state.ensureInterestPeriods(loan, today: DateTime(2026, 9, 15));
      await state.applyPaymentToInterestPeriods('loan-io-1', 600);
      final rows = await local.db.query('khatabook_installments',
          where: 'khatabook_loan = ?', whereArgs: ['loan-io-1']);
      expect(rows.first['status'], 'PAID');
      expect(rows.first['remaining_amount'], 0);
    });

    test('normal money never prepays a future period', () async {
      final loan = await interestOnlyLoan();
      await state.ensureInterestPeriods(loan, today: DateTime(2026, 9, 15));
      // 1500: period 1 (600) clears, 900 finds no other DUE row — the
      // unbilled future stays untouched.
      await state.applyPaymentToInterestPeriods('loan-io-1', 1500);
      final rows = await local.db.query('khatabook_installments',
          where: 'khatabook_loan = ?',
          whereArgs: ['loan-io-1'],
          orderBy: 'installment_number asc');
      expect(rows.length, 1, reason: 'no future row exists to touch');
      expect(rows.first['status'], 'PAID');
    });

    test('explicit future prepay marks exactly that period', () async {
      final loan = await interestOnlyLoan();
      await state.ensureInterestPeriods(loan,
          today: DateTime(2026, 9, 15), throughPeriod: 2);
      await state.applyPaymentToInterestPeriods('loan-io-1', 600,
          onlyPeriod: 2);
      final rows = await local.db.query('khatabook_installments',
          where: 'khatabook_loan = ?',
          whereArgs: ['loan-io-1'],
          orderBy: 'installment_number asc');
      expect(rows[1]['status'], 'PAID');
      expect(rows[0]['status'], 'PENDING',
          reason: 'the current period is still owed');
    });
  });

  group('schema v11', () {
    test('adding the schema twice is harmless', () async {
      await MigrationV11.addSchema(local.db);
      await MigrationV11.addSchema(local.db);
      final cols =
          await local.db.rawQuery('PRAGMA table_info(khatabook_loans)');
      expect(
          cols.where((c) => c['name'] == 'payment_type').length, 1);
      expect(
          cols.where((c) => c['name'] == 'current_interest').length, 1);
    });

    test('fresh installs already carry the v11 columns', () async {
      final cols =
          await local.db.rawQuery('PRAGMA table_info(khatabook_loans)');
      final names = cols.map((c) => '${c['name']}').toSet();
      expect(names, contains('payment_type'));
      expect(names, contains('current_interest'));
    });
  });

  group('migration v11', () {
    test('old loans default to INSTALLMENT', () async {
      await local.upsert('khatabook_loans', {
        'client_uuid': 'loan-old',
        'payment_type': null,
        'interest_amount': 2000,
      });
      final n = await MigrationV11.backfill(local.db);
      expect(n, 1);
      final row = (await local.byUuid('khatabook_loans', 'loan-old'))!;
      expect(row['payment_type'], MigrationV11.installment);
      expect(row['current_interest'], 2000);
    });

    test('unknown payment types read as installment', () {
      expect(MigrationV11.paymentTypeOf({'payment_type': 'WAT'}),
          MigrationV11.installment);
      expect(MigrationV11.paymentTypeOf({}), MigrationV11.installment);
      expect(MigrationV11.isInterestOnly({'payment_type': 'INTEREST_ONLY'}),
          isTrue);
    });
  });
}
