import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/data/sample_data.dart';

/// Sample data must be removable without ever putting a real record at risk.
/// These tests use deliberately awkward data — real customers living in a demo
/// village, two people sharing a name, a real loan pointing at a demo customer —
/// because those are the cases where a careless deletion does damage.
void main() {
  late LocalDb db;
  late SampleDataService svc;
  late String file;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    file = p.join(Directory.systemTemp.path, 'jewellery_suite_sample_test.db');
  });

  setUp(() async {
    final f = File(file);
    if (f.existsSync()) f.deleteSync();
    db = LocalDb();
    await db.init(pathOverride: file);
    svc = SampleDataService(db);
  });

  tearDown(() async {
    await db.db.close();
    final f = File(file);
    if (f.existsSync()) f.deleteSync();
  });

  Future<void> seedDemo() async {
    await db.upsert(
        'villages', {'client_uuid': 'v-demo-1', 'village_name': 'Pallipatti'});
    await db.upsert('customers', {
      'client_uuid': 'c-demo-1',
      'customer_name': 'Lakshmi Bai',
      'village': 'Pallipatti',
    });
    await db.upsert('khatabook_loans', {
      'client_uuid': 'l-demo-1',
      'customer': 'c-demo-1',
      'customer_name': 'Lakshmi Bai',
      'village': 'Pallipatti',
      'principal_amount': 5000.0,
      'total_payable': 6500.0,
    });
    await db.upsert('khatabook_collections', {
      'client_uuid': 'col-demo-1',
      'khatabook_loan': 'l-demo-1',
      'customer': 'Lakshmi Bai',
      'amount': 1000.0,
      'collection_date': '2026-09-01',
    });
  }

  Future<void> seedReal() async {
    await db.upsert('customers', {
      'client_uuid': 'c-real-1',
      'customer_name': 'Ravi Kumar',
      'village': 'Pallipatti',
    });
    await db.upsert('customers', {
      'client_uuid': 'c-real-2',
      'customer_name': 'Sunitha Rani',
      'village': 'Uppalapadu',
    });
  }

  group('identification', () {
    test('finds demo rows and leaves real ones out', () async {
      await seedDemo();
      // Put the real customers in a village of their own, so the demo village
      // is genuinely unused and removable.
      await db.upsert('customers', {
        'client_uuid': 'c-real-1',
        'customer_name': 'Ravi Kumar',
        'village': 'Uppalapadu',
      });
      await db.upsert('customers', {
        'client_uuid': 'c-real-2',
        'customer_name': 'Sunitha Rani',
        'village': 'Uppalapadu',
      });
      final r = await svc.inspect();

      expect(r.countFor('customers'), 1);
      expect(r.countFor('villages'), 1);
      expect(r.countFor('khatabook_loans'), 1);
      expect(r.countFor('khatabook_collections'), 1);
      expect(r.totalRows, 4);
      expect(r.keptVillages, isEmpty);
      expect(r.safeToRemove, isTrue);
    });

    test('an empty database reports nothing to do', () async {
      final r = await svc.inspect();
      expect(r.isEmpty, isTrue);
      expect(r.safeToRemove, isFalse,
          reason: 'nothing to remove is not safe to do');
    });

    test('finds the ten "Sample …" members by name and phone', () async {
      await db.upsert(
          'villages', {'client_uuid': 'v-x', 'village_name': 'Pallipatti'});
      await db.upsert('customers', {
        'client_uuid': 'random-uuid',
        'customer_name': 'Sample Weekly 1', // uuid is NOT a demo marker
        'phone': '9000000005',
      });
      await db.upsert('customers', {
        'client_uuid': 'real',
        'customer_name': 'Ravi Kumar',
        'phone': '9876543210',
      });
      final r = await svc.inspect();
      expect(r.countFor('customers'), 1);
      expect(r.byTable['customers']!.first.label, contains('Sample Weekly 1'));
      // `v-x` is a real village, so it must not be treated as sample data.
      expect(r.countFor('villages'), 0);
    });

    test('keeps a demo village that real customers still live in', () async {
      await seedDemo();
      await seedReal(); // Ravi Kumar is a real customer in Pallipatti
      final r = await svc.inspect();

      expect(r.keptVillages, contains('Pallipatti'));
      expect(r.countFor('villages'), 0,
          reason: 'deleting it would strand a real customer');
    });

    test('blocks when two customers share a name that a table stores',
        () async {
      // khatabook_collections.customer holds a NAME, so a shared name means
      // real rows cannot be told apart from demo rows.
      await seedDemo();
      await db.upsert('customers', {
        'client_uuid': 'c-real-same-name',
        'customer_name': 'Lakshmi Bai', // different person, same name
        'village': 'Uppalapadu',
      });
      final r = await svc.inspect();
      expect(r.blocked, isNotEmpty);
      expect(r.safeToRemove, isFalse);
      expect(r.blocked.first, contains('Lakshmi Bai'));
    });
  });

  group('removal', () {
    test('removes demo rows and leaves every real row', () async {
      await seedDemo();
      await seedReal();
      final before = await svc.inspect();
      expect(before.safeToRemove, isTrue);

      final after = await svc.remove(confirmedByUser: true);
      expect(after.totalRows, 0, reason: 'no sample rows may remain');

      expect((await db.query('customers')).length, 2,
          reason: 'both real customers must survive');
      expect((await db.query('khatabook_loans')).length, 0);
      expect((await db.query('khatabook_collections')).length, 0);
      // The village was kept because a real customer lives there.
      expect((await db.query('villages')).length, 1);
    });

    test('deletes demo children before their loan', () async {
      await seedDemo();
      await db.upsert('pawn_items', {
        'loan_uuid': 'pdemo',
        'metal_type': 'Gold',
        'net_weight': 10.0,
      });
      await db.upsert('pawn_transactions', {
        'client_uuid': 'tx-demo-1',
        'pawn_loan': 'pdemo',
        'tx_type': 'Interest Paid',
        'amount': 100.0,
      });
      await db.upsert('pawn_loans', {
        'client_uuid': 'pdemo',
        'customer': 'c-demo-1',
        'customer_name': 'Lakshmi Bai',
        'loan_amount': 20000.0,
      });

      final after = await svc.remove(confirmedByUser: true);
      expect(after.totalRows, 0);
      expect((await db.query('pawn_items')).length, 0);
      expect((await db.query('pawn_transactions')).length, 0);
      expect((await db.query('pawn_loans')).length, 0);
    });

    test('refuses when the user has not confirmed', () async {
      await seedDemo();
      final result = await svc.remove(confirmedByUser: false);
      expect(result.blocked, contains('Removal was not confirmed.'));
      expect((await db.query('customers')).length, 1,
          reason: 'nothing may be deleted without confirmation');
    });

    test('refuses when the report is blocked, changing nothing', () async {
      await seedDemo();
      await db.upsert('customers', {
        'client_uuid': 'c-real-same-name',
        'customer_name': 'Lakshmi Bai',
        'village': 'Uppalapadu',
      });
      final result = await svc.remove(confirmedByUser: true);
      expect(result.safeToRemove, isFalse);
      expect((await db.query('customers')).length, 2);
      expect((await db.query('khatabook_loans')).length, 1,
          reason: 'a blocked removal must leave the loan alone');
    });

    test('is safe to run twice', () async {
      await seedDemo();
      await svc.remove(confirmedByUser: true);
      final second = await svc.remove(confirmedByUser: true);
      expect(second.isEmpty, isTrue);
      expect((await db.query('customers')).length, 0);
    });
  });

  test('describeSafely reports counts without customer names', () async {
    await seedDemo();
    final r = await svc.inspect();
    final text = svc.describeSafely(r);
    expect(text, contains('customers=1'));
    expect(text, isNot(contains('Lakshmi')));
  });
}
