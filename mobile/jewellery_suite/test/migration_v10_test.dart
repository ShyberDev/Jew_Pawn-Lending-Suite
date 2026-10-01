import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/data/migration_v10.dart';

/// The v10 schema: installments as real rows, component balances on the loan,
/// and the permanent allocation ledger.
///
/// The behaviour that matters most is that seeding a pre-v10 loan does **not**
/// invent principal recovery — money is never assumed recovered when it cannot
/// be proven, because that would understate the shop's capital.
void main() {
  late Database db;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_v10_');
    final d = LocalDb();
    await d.init(pathOverride: p.join(dir.path, 'v10.db'));
    db = d.db;
  });

  tearDown(() async {
    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('schema', () {
    test('a fresh install has both new tables', () async {
      for (final t in ['khatabook_installments', 'khatabook_allocations']) {
        final r = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?", [t]);
        expect(r, isNotEmpty, reason: '$t must exist');
      }
    });

    test('the loan carries every component column', () async {
      final cols = (await db.rawQuery('PRAGMA table_info(khatabook_loans)'))
          .map((c) => '${c['name']}')
          .toSet();
      for (final c in MigrationV10.loanColumns.keys) {
        expect(cols, contains(c));
      }
    });

    test('installments can be read by loan, due date and status', () async {
      final idx = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='index'"))
          .map((r) => '${r['name']}')
          .toSet();
      expect(idx, contains('idx_khata_inst_loan'));
      expect(idx, contains('idx_khata_inst_due'));
      expect(idx, contains('idx_khata_inst_status'));
      expect(idx, contains('idx_khata_alloc_loan'));
    });

    test('adding the schema twice is harmless', () async {
      await MigrationV10.addSchema(db);
      await MigrationV10.addSchema(db);
      final cols = await db.rawQuery('PRAGMA table_info(khatabook_loans)');
      expect(cols.where((c) => c['name'] == 'principal_recovered').length, 1);
    });
  });

  group('seeding existing loans', () {
    Future<void> legacyLoan(String uuid, String name, double principal,
        double collected) =>
        db.insert('khatabook_loans', {
          'client_uuid': uuid,
          'customer': name,
          'customer_name': name,
          'principal_amount': principal,
          'total_payable': principal,
          'total_collected': collected,
          'outstanding': principal - collected,
          'status': 'Active',
        });

    test('never invents principal recovery', () async {
      // ₹6,000 was collected but there is no allocation history, so we cannot
      // know how much was principal. Assuming zero recovery keeps Investment an
      // upper bound rather than a fabrication.
      await legacyLoan('l1', 'Krishna', 10000, 6000);
      final n = await MigrationV10.seedComponents(db);
      expect(n, 1);
      final row = (await db.query('khatabook_loans')).first;
      expect(row['principal_recovered'], 0.0);
      expect(row['principal_outstanding'], 10000.0);
      expect(row['unapplied_credit'], 0.0);
      expect(row['original_principal'], 10000.0);
    });

    test('keeps a pre-v10 "Closed" meaning COMPLETED', () async {
      await db.insert('khatabook_loans', {
        'client_uuid': 'l1',
        'principal_amount': 1000.0,
        'total_payable': 1000.0,
        'total_collected': 1000.0,
        'outstanding': 0.0,
        'status': 'Closed',
      });
      await MigrationV10.seedComponents(db);
      expect((await db.query('khatabook_loans')).first['status'], 'COMPLETED');
    });

    test('a "Closed" row with a balance left stays ACTIVE', () async {
      // Never claim a loan is complete while money is still owed.
      await db.insert('khatabook_loans', {
        'client_uuid': 'l1',
        'principal_amount': 1000.0,
        'total_payable': 1000.0,
        'total_collected': 100.0,
        'outstanding': 900.0,
        'status': 'Closed',
      });
      await MigrationV10.seedComponents(db);
      expect((await db.query('khatabook_loans')).first['status'], 'ACTIVE');
    });

    test('an already-v10 status is left alone', () async {
      await db.insert('khatabook_loans', {
        'client_uuid': 'l1',
        'principal_amount': 1000.0,
        'total_payable': 1000.0,
        'status': 'WRITTEN_OFF',
      });
      await MigrationV10.seedComponents(db);
      expect((await db.query('khatabook_loans')).first['status'], 'WRITTEN_OFF');
    });

    test('seeding twice touches nothing', () async {
      await legacyLoan('l1', 'Krishna', 10000, 0);
      await MigrationV10.seedComponents(db);
      final second = await MigrationV10.seedComponents(db);
      expect(second, 0, reason: 'already seeded');
    });
  });

  group('status mapping', () {
    test('canonical states pass through', () {
      for (final s in [
        'ACTIVE',
        'COMPLETED',
        'SETTLED',
        'REFINANCED',
        'WRITTEN_OFF',
        'DEFAULTED',
        'CANCELLED'
      ]) {
        expect(LoanStatusWire.of(s, 0, 0), s);
      }
    });

    test('legacy Closed maps by whether anything is owed', () {
      expect(LoanStatusWire.of('Closed', 1000, 1000), 'COMPLETED');
      expect(LoanStatusWire.of('Closed', 1000, 400), 'ACTIVE');
    });

    test('an unknown status becomes ACTIVE rather than being lost', () {
      expect(LoanStatusWire.of('WAT', 0, 0), 'ACTIVE');
      expect(LoanStatusWire.of(null, 0, 0), 'ACTIVE');
    });
  });
}
