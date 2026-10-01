// `reason: '$name'` is correct and intentional (expect's reason is a String),
// but the linter flags `${ident}` as an unnecessary interpolation.
// ignore_for_file: unnecessary_string_interpolations

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/data/sample_data.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/util/format.dart';
import 'package:jewellery_suite/util/khata_loan_state.dart';

/// v1.0.21 — the sample seeder used to write `outstanding` by hand and leave
/// every v10 component column empty, so a sample loan's Investment and
/// Outstanding disagreed with what the real screens compute. These tests run
/// the seeder against a real database and assert the money is coherent.
void main() {
  late LocalDb db;
  late AppState state;
  late String file;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    file = p.join(Directory.systemTemp.path, 'jewellery_suite_khata_sample.db');
  });

  setUp(() async {
    final f = File(file);
    if (f.existsSync()) f.deleteSync();
    db = LocalDb();
    await db.init(pathOverride: file);
    state = AppState(db);
    await state.load();
  });

  tearDown(() async {
    await db.db.close();
    final f = File(file);
    if (f.existsSync()) f.deleteSync();
  });

  Future<List<Map<String, Object?>>> loansOf(String name) async =>
      db.query('khatabook_loans', where: 'customer_name = ?', whereArgs: [name]);

  test('seeder creates one member per condition', () async {
    final added = await state.addSampleMembers();
    expect(added, 11, reason: 'all eleven sample members should be new');

    final names = (await db.query('customers', columns: ['customer_name']))
        .map((c) => '${c['customer_name']}')
        .toList();
    for (final expected in const [
      'Sample_DueToday',
      'Sample_Overdue_4Days',
      'Sample_Overdue_Arrears',
      'Sample_Upcoming',
      'Sample_PartPaid',
      'Sample_LateFee',
      'Sample_FullyPaid',
      'Sample_InterestOnly',
      'Sample_Refinanced',
      'Sample_Overdue_NoReminder',
      'Sample_InLoss',
    ]) {
      expect(names, contains(expected));
    }
  });

  test('every seeded loan is internally consistent', () async {
    await state.addSampleMembers();
    final loans = await db.query('khatabook_loans');
    expect(loans, isNotEmpty);

    for (final l in loans) {
      final st = KhataLoanState.fromRow(l);
      final name = '${l['customer_name']}';
      final principal = Num.toDouble(l['principal_amount']);

      // The v10 columns must actually be written, not left null. This is the
      // exact regression the old seeder had.
      expect(l['principal_outstanding'], isNotNull, reason: '$name');
      expect(l['principal_recovered'], isNotNull, reason: '$name');
      expect(l['interest_outstanding'], isNotNull, reason: '$name');

      // Principal outstanding must never exceed the original principal.
      expect(st.investment, lessThanOrEqualTo(principal + 0.001),
          reason: '$name recovered more than was lent');

      // Recovery + outstanding must add back up to the original principal.
      expect(st.principalRecovered + st.investment,
          closeTo(principal, 0.01),
          reason: '$name principal does not reconcile');

      // No negative balance anywhere.
      expect(st.investment, greaterThanOrEqualTo(0), reason: '$name');
      expect(st.interestOutstanding, greaterThanOrEqualTo(0), reason: '$name');
      expect(st.lateFeeOutstanding, greaterThanOrEqualTo(0), reason: '$name');
      expect(st.unappliedCredit, greaterThanOrEqualTo(0), reason: '$name');

      // Collected can never exceed the payable amount.
      expect(Num.toDouble(l['total_collected']),
          lessThanOrEqualTo(Num.toDouble(l['total_payable']) + 0.01),
          reason: '$name');
    }
  });

  test('the fully-paid member really owes nothing', () async {
    await state.addSampleMembers();
    final loans = await loansOf('Sample_FullyPaid');
    final st = KhataLoanState.fromRow(loans.first);
    // v1.0.21 seeded 2 of 4 installments here, so it still showed a red DUE
    // chip despite being called "FullyPaid".
    expect(st.investment, 0, reason: 'principal must be fully recovered');
    expect(st.interestOutstanding, 0);
    expect(st.outstandingBalance, 0);
  });

  test('reminders only go on members already due in the future', () async {
    await state.addSampleMembers();
    final rows =
        await db.query('customers', columns: ['customer_name', 'reminder_date']);
    final with_ = rows
        .where((c) => c['reminder_date'] != null)
        .map((c) => '${c['customer_name']}')
        .toSet();
    // A reminder overrides the schedule, so giving one to an overdue member
    // would repaint its red chip blue and hide the arrears.
    expect(with_, {
      'Sample_Upcoming',
      'Sample_PartPaid',
      'Sample_InterestOnly',
      'Sample_Refinanced',
    });
  });

  test('every sample has a real frequency — never a blank one', () async {
    await state.addSampleMembers();
    // _frequencyName('') silently falls back to Weekly, and the loan form can
    // never produce a blank, so a seeded one is an impossible state.
    final loans = await db.query('khatabook_loans');
    for (final l in loans) {
      expect('${l['collection_frequency']}'.trim(), isNotEmpty,
          reason: '${l['customer_name']} has a blank frequency');
    }
  });

  test('the loss member lives in the Loss khata', () async {
    await state.addSampleMembers();
    final rows = await db.query('customers',
        where: 'customer_name = ?', whereArgs: ['Sample_InLoss']);
    expect(rows, hasLength(1));
    expect('${rows.first['village']}'.toLowerCase(), contains('loss'));
  });

  test('the late fee is recorded once, as a dated You Gave row', () async {
    await state.addSampleMembers();
    // The fee arrives as a dated charge, and the loan ends up carrying it ONCE.
    // 600 here would mean the seeder wrote it and then charged it again.
    final loans = await loansOf('Sample_LateFee');
    expect(Num.toDouble(loans.first['late_fee_outstanding']), 300);
    // It arrives through the "you gave" ledger instead.
    final given = await db.query('khatabook_given',
        columns: ['given_type', 'amount', 'given_date', 'note']);
    final fees = given.where((g) => '${g['given_type']}' == 'late_fee');
    expect(fees, hasLength(1), reason: 'exactly one late-fee charge');
    expect(Num.toDouble(fees.first['amount']), 300);
    expect('${fees.first['given_date']}', isNotEmpty);
  });

  test('every seeded member has a dated transaction history', () async {
    await state.addSampleMembers();
    // A shopkeeper types the loan out on the start date, so each member who has
    // money should have at least one dated line on each side.
    final given = await db.query('khatabook_given', columns: ['given_date']);
    final cols = await db.query('khatabook_collections', columns: ['collection_date']);
    expect(given, isNotEmpty);
    expect(cols, isNotEmpty);
    for (final r in given) {
      expect('${r['given_date']}'.trim(), isNotEmpty);
    }
    for (final r in cols) {
      expect('${r['collection_date']}'.trim(), isNotEmpty);
    }
  });

  test('every rupee collected has an allocation row', () async {
    await state.addSampleMembers();
    final collections = await db.query('khatabook_collections');
    expect(collections, isNotEmpty, reason: 'the matrix includes payments');

    for (final c in collections) {
      final allocs = await db.query('khatabook_allocations',
          where: 'khatabook_collection = ?', whereArgs: [c['client_uuid']]);
      final sum = allocs
          .map((a) => Num.toDouble(a['amount']))
          .fold<double>(0, (a, b) => a + b);
      expect(sum, closeTo(Num.toDouble(c['amount']), 0.01),
          reason: 'collection ${c['client_uuid']} does not fully allocate');
    }
  });

  test('the due-today member really is due today', () async {
    await state.addSampleMembers();
    final loans = await loansOf('Sample_DueToday');
    expect(loans, hasLength(1));
    final start = DateTime.parse(loans.first['start_date']! as String);
    final firstDue = start.add(const Duration(days: 7));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    expect(DateTime(firstDue.year, firstDue.month, firstDue.day), today,
        reason: 'the red DUE TODAY chip depends on this');
  });

  test('the upcoming member is not due yet', () async {
    await state.addSampleMembers();
    final loans = await loansOf('Sample_Upcoming');
    final start = DateTime.parse(loans.first['start_date']! as String);
    final firstDue = start.add(const Duration(days: 7));
    final now = DateTime.now();
    expect(firstDue.isAfter(DateTime(now.year, now.month, now.day)), isTrue,
        reason: 'a future due date is what makes the chip blue');
  });

  test('the refinance freezes the old loan and opens a new one', () async {
    await state.addSampleMembers();
    final all = await loansOf('Sample_Refinanced');
    expect(all.length, greaterThanOrEqualTo(2),
        reason: 'refinance keeps the old loan and adds the new one');

    final frozen =
        all.where((l) => '${l['status']}'.toUpperCase() == 'REFINANCED');
    expect(frozen, isNotEmpty, reason: 'the old loan must be marked REFINANCED');

    final refs = await db.query('khatabook_refinances',
        where: 'customer = ?', whereArgs: [all.first['customer']]);
    expect(refs, isNotEmpty, reason: 'the two sides must be linked');
  });

  test('sample data is still recognised as removable', () async {
    await state.addSampleMembers();
    final svc = SampleDataService(db);
    final report = await svc.inspect();
    expect(report.byTable['customers'], isNotEmpty);
    // Nothing real is touched: the report must not claim a real record is at
    // risk when the database holds only samples.
    expect(report.realDataTouched, isEmpty);
  });

  test('running the seeder twice adds nothing and changes nothing', () async {
    await state.addSampleMembers();
    final first = await db.query('khatabook_loans');
    final second = await state.addSampleMembers();
    expect(second, 0);
    final after = await db.query('khatabook_loans');
    expect(after.length, first.length);
  });
}
