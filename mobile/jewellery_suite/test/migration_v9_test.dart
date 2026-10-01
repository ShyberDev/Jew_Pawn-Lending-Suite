import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/data/migration_v9.dart';

/// The bug this migration exists to fix was real on the shop's own data: three
/// separate customers named "Ravi" in one village, and a 12,000 loan that could
/// not say which Ravi owned it, so it was filed under the wrong village.
///
/// These tests therefore care most about the case where a name is AMBIGUOUS.
/// The rule is: never guess. An ambiguous reference is left alone and reported,
/// because guessing wrong moves one person's money to another person.
void main() {
  late Database db;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> openFresh() async {
    dir = await Directory.systemTemp.createTemp('js_v9_');
    final d = LocalDb();
    await d.init(pathOverride: p.join(dir.path, 'v9.db'));
    return d.db;
  }

  setUp(() async {
    db = await openFresh();
  });

  tearDown(() async {
    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> addCustomer(String uuid, String name, {String? village}) =>
      db.insert('customers', {
        'client_uuid': uuid,
        'customer_name': name,
        if (village != null) 'village': village,
      });

  Future<void> addLoan(String uuid, {String? customer, String? customerName}) =>
      db.insert('khatabook_loans', {
        'client_uuid': uuid,
        if (customer != null) 'customer': customer,
        if (customerName != null) 'customer_name': customerName,
        'total_payable': 12000.0,
      });

  group('schema', () {
    test('a fresh install already has customer_uuid on every table', () async {
      for (final t in MigrationV9.targets) {
        final cols = await db.rawQuery('PRAGMA table_info(${t.table})');
        expect(cols.map((c) => c['name']), contains('customer_uuid'),
            reason: '${t.table} must carry customer_uuid from the start');
      }
    });

    test('the lookup index exists on every customer-referencing table',
        () async {
      for (final t in MigrationV9.targets) {
        final idx = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name=? AND sql LIKE '%customer_uuid%'",
            [t.table]);
        expect(idx, isNotEmpty, reason: '${t.table} needs its uuid index');
      }
    });

    test('search columns are indexed', () async {
      final names = (await db
              .rawQuery("SELECT name FROM sqlite_master WHERE type='index'"))
          .map((r) => '${r['name']}')
          .toList();
      expect(names, contains('idx_customers_name'));
      expect(names, contains('idx_customers_id'));
      expect(names, contains('idx_customers_village'));
    });

    test('adding the schema twice is harmless', () async {
      await MigrationV9.addSchema(db);
      await MigrationV9.addSchema(db);
      final cols = await db.rawQuery('PRAGMA table_info(khatabook_loans)');
      final n = cols.where((c) => c['name'] == 'customer_uuid').length;
      expect(n, 1, reason: 'the column must not be duplicated');
    });
  });

  group('backfill — unambiguous references', () {
    test('a stored uuid links directly', () async {
      await addCustomer('c1', 'Sunitha Rani');
      await addLoan('l1', customer: 'c1');
      final report = await MigrationV9.backfill(db);
      expect(report.linkedByUuid, 1);
      final row = (await db.query('khatabook_loans')).first;
      expect(row['customer_uuid'], 'c1');
    });

    test('a name only one customer answers to links', () async {
      await addCustomer('c1', 'Krishna', village: 'Pallipatti');
      await addLoan('l1', customerName: 'Krishna');
      final report = await MigrationV9.backfill(db);
      expect(report.linkedByUniqueName, 1);
      expect(report.isClean, isTrue);
      expect((await db.query('khatabook_loans')).first['customer_uuid'], 'c1');
    });

    test('case and extra spaces still match the same person', () async {
      await addCustomer('c1', 'Krishna');
      await addLoan('l1', customerName: '  krishna ');
      final report = await MigrationV9.backfill(db);
      expect(report.linkedByUniqueName, 1);
      expect((await db.query('khatabook_loans')).first['customer_uuid'], 'c1');
    });

    test('all seven tables are processed', () async {
      await addCustomer('c1', 'Krishna');
      await db.insert('pawn_loans', {'client_uuid': 'p1', 'customer': 'c1'});
      await db.insert('pawn_transactions',
          {'client_uuid': 't1', 'customer_name': 'Krishna'});
      await db.insert('pawn_releases', {'client_uuid': 'r1', 'customer': 'c1'});
      await db
          .insert('khatabook_loans', {'client_uuid': 'l1', 'customer': 'c1'});
      await db.insert(
          'khatabook_collections', {'client_uuid': 'co1', 'customer': 'c1'});
      await db.insert(
          'khatabook_given', {'client_uuid': 'g1', 'customer_name': 'Krishna'});
      await db.insert(
          'khatabook_refinances', {'client_uuid': 'f1', 'customer': 'c1'});

      final report = await MigrationV9.backfill(db);
      expect(report.isClean, isTrue);
      for (final t in [
        'pawn_loans',
        'pawn_transactions',
        'pawn_releases',
        'khatabook_loans',
        'khatabook_collections',
        'khatabook_given',
        'khatabook_refinances'
      ]) {
        final rows = await db.query(t);
        expect(rows.first['customer_uuid'], 'c1', reason: t);
      }
    });
  });

  group('backfill — ambiguous, the bug from the shop', () {
    test('three Ravis: the loan is NOT guessed, it is reported', () async {
      await addCustomer('c1', 'ravi', village: 'Uppalapadu');
      await addCustomer('c2', 'Ravi', village: 'Uppalapadu');
      await addCustomer('c3', 'Ravi', village: 'Uppalapadu');
      await addLoan('l1', customer: 'ravi');

      final report = await MigrationV9.backfill(db);
      expect(report.linkedByUuid, 0);
      expect(report.linkedByUniqueName, 0);
      expect(report.unresolved.length, 1);
      expect(report.unresolved.first.reason, contains('3 customers'));
      // The row keeps its old value and gains no uuid — no money moved.
      expect(
          (await db.query('khatabook_loans')).first['customer_uuid'], isNull);
    });

    test('two customers sharing a name block each other', () async {
      await addCustomer('c1', 'sampoo');
      await addCustomer('c2', 'sampoo');
      await addLoan('l1', customerName: 'sampoo');
      final report = await MigrationV9.backfill(db);
      expect(report.unresolved.length, 1);
    });

    test('a name nobody answers to is reported, not invented', () async {
      await addCustomer('c1', 'Krishna');
      await addLoan('l1', customerName: 'Ghost Customer');
      final report = await MigrationV9.backfill(db);
      expect(report.unresolved.first.reason, contains('no customer matches'));
      expect(
          (await db.query('khatabook_loans')).first['customer_uuid'], isNull);
    });

    test('an empty reference is reported', () async {
      await db.insert('khatabook_loans', {'client_uuid': 'l1'});
      final report = await MigrationV9.backfill(db);
      expect(report.unresolved.first.reason, contains('no reference'));
    });

    test('a uuid always wins even when the name is ambiguous', () async {
      await addCustomer('c1', 'ravi');
      await addCustomer('c2', 'ravi');
      await addLoan('l1', customer: 'c2', customerName: 'ravi');
      final report = await MigrationV9.backfill(db);
      expect(report.linkedByUuid, 1);
      expect(report.isClean, isTrue);
      expect((await db.query('khatabook_loans')).first['customer_uuid'], 'c2');
    });
  });

  group('safety', () {
    test('re-running changes nothing', () async {
      await addCustomer('c1', 'Krishna');
      await addCustomer('c2', 'ravi');
      await addCustomer('c3', 'Ravi'); // ambiguous — needs review
      await addLoan('l1', customerName: 'Krishna');
      await addLoan('l2', customer: 'ravi');

      final first = await MigrationV9.backfill(db);
      expect(first.linkedByUniqueName, 1, reason: 'only Krishna is unique');
      expect(first.unresolved.length, 1, reason: 'ravi is ambiguous');

      final second = await MigrationV9.backfill(db);
      expect(second.linkedByUniqueName, 0, reason: 'already done');
      expect(second.alreadyLinked, 1);
      expect(second.unresolved.length, first.unresolved.length);
    });

    test('an already-linked row keeps its uuid', () async {
      await addCustomer('c1', 'Krishna');
      await addCustomer('c2', 'Krishna'); // ambiguous
      await db.insert('khatabook_loans', {
        'client_uuid': 'l1',
        'customer': 'Krishna',
        'customer_uuid': 'c1',
      });
      final report = await MigrationV9.backfill(db);
      expect(report.alreadyLinked, 1);
      expect((await db.query('khatabook_loans')).first['customer_uuid'], 'c1');
    });

    test('the log records what happened', () async {
      await addCustomer('c1', 'Krishna');
      await addCustomer('c2', 'ravi');
      await addCustomer('c3', 'Ravi'); // ambiguous — the review case
      await addLoan('l1', customerName: 'Krishna');
      await addLoan('l2', customer: 'ravi');
      final report = await MigrationV9.backfill(db);
      await MigrationV9.writeLog(db, report);

      final rows = await db.query('migration_log');
      expect(rows.length, 1);
      final log = rows.first;
      expect(log['version'], MigrationV9.version);
      expect(log['linked_by_unique_name'], 1);
      expect(log['needs_review'], 1);
      expect('${log['detail']}', contains('ravi'),
          reason: 'the unresolved row is written down, not guessed');
    });
  });
}
