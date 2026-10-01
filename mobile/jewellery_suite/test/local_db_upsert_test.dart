import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';

/// LocalDb.upsert must MERGE, never REPLACE.
///
/// Regression cover for the largest data-loss vector in the app: upsert used
/// to be `INSERT OR REPLACE`, which is delete + insert, so every column the
/// caller did not mention reverted to NULL. Editing a customer name — a
/// routine action from a form that only shows 10 of the 22 columns — silently
/// erased the book ID, the promised collection date, the interest-rate
/// overrides, the rating and the ID photos.
///
/// These run against the real schema built by LocalDb._create.
void main() {
  late LocalDb db;
  late String file;

  Future<void> wipe() async {
    final f = File(file);
    if (f.existsSync()) f.deleteSync();
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // A scratch file on the test host — never the phone's real database.
    // Passing the path explicitly keeps the wipe below honest.
    file = p.join(Directory.systemTemp.path, 'jewellery_suite_upsert_test.db');
  });

  setUp(() async {
    await wipe(); // a clean file every run, so onCreate builds the schema
    db = LocalDb();
    await db.init(pathOverride: file);
  });

  // The handle must be released: an open sqflite_common_ffi database keeps the
  // test isolate alive, so leaking one connection per case hangs the run.
  tearDown(() async {
    await db.db.close();
    await wipe();
  });

  tearDownAll(wipe);

  Map<String, Object?> customer({
    String name = 'Ravi Kumar',
    String? id = 'A-01',
    String? phone = '9000000001',
    String? rating = 'Good',
    double? gold = 2.5,
    double? silver = 3.5,
    String? reminder = '2099-01-01',
    String? front = '/photos/front.jpg',
    String? back = '/photos/back.jpg',
    String? notes = 'prefers evening calls',
  }) =>
      {
        'client_uuid': 'c1',
        'customer_name': name,
        if (id != null) 'customer_id': id,
        if (phone != null) 'phone': phone,
        if (rating != null) 'rating': rating,
        if (gold != null) 'gold_interest_rate': gold,
        if (silver != null) 'silver_interest_rate': silver,
        if (reminder != null) 'reminder_date': reminder,
        if (front != null) 'id_photo_front': front,
        if (back != null) 'id_photo_back': back,
        if (notes != null) 'notes': notes,
      };

  group('upsert merge semantics', () {
    test('a full row inserts', () async {
      await db.upsert('customers', customer());
      final row = await db.byUuid('customers', 'c1');
      expect(row, isNotNull);
      expect(row!['customer_name'], 'Ravi Kumar');
      expect(row['customer_id'], 'A-01');
    });

    test('a partial update keeps every column it does not mention', () async {
      await db.upsert('customers', customer());

      // Exactly what CustomerForm._save sends — only the form's own fields.
      await db.upsert('customers', {
        'client_uuid': 'c1',
        'customer_name': 'Ravi Kumar (shop)',
        'phone': '9000000001',
        'village': 'Pallipatti',
        'customer_type': 'General',
        'status': 'Active',
      });

      final row = (await db.byUuid('customers', 'c1'))!;
      expect(row['customer_name'], 'Ravi Kumar (shop)');
      expect(row['village'], 'Pallipatti');
      // The fields the form never shows must survive an ordinary edit.
      expect(row['customer_id'], 'A-01', reason: 'book ID must survive');
      expect(row['rating'], 'Good', reason: 'rating must survive');
      expect(row['gold_interest_rate'], 2.5,
          reason: 'pawn rate override must survive');
      expect(row['silver_interest_rate'], 3.5);
      expect(row['reminder_date'], '2099-01-01',
          reason: 'promised collection date must survive');
      expect(row['id_photo_front'], '/photos/front.jpg');
      expect(row['id_photo_back'], '/photos/back.jpg');
      expect(row['notes'], 'prefers evening calls');
    });

    test('an explicit null still clears a column', () async {
      await db.upsert('customers', customer());
      await db.upsert('customers', {
        'client_uuid': 'c1',
        'customer_name': 'Ravi Kumar',
        'reminder_date': null,
      });
      final row = (await db.byUuid('customers', 'c1'))!;
      expect(row['reminder_date'], isNull, reason: 'explicit null clears');
      expect(row['customer_id'], 'A-01',
          reason: 'a column left out is untouched, not cleared');
      expect(row['id_photo_front'], '/photos/front.jpg');
    });

    test('re-upserting the same key updates in place, never duplicates',
        () async {
      for (final n in ['v0', 'v1', 'v2']) {
        await db.upsert(
            'customers', {'client_uuid': 'c1', 'customer_name': 'Name $n'});
      }
      final rows = await db.query('customers');
      expect(rows.length, 1);
      expect(rows.first['customer_name'], 'Name v2');
    });

    test('distinct keys stay distinct (two people, one name)', () async {
      await db.upsert('customers', customer());
      await db.upsert('customers', {
        'client_uuid': 'c2',
        'customer_name': 'Ravi Kumar', // same name, different person
        'customer_id': 'A-02',
        'phone': '9000000002',
      });
      final rows = await db.query('customers', orderBy: 'customer_id asc');
      expect(rows.length, 2);
      expect(rows.map((r) => r['customer_id']).toList(), ['A-01', 'A-02']);
    });

    test('an unknown column is still rejected (schema guard)', () async {
      // Merge semantics must not turn a schema mismatch into a silent write.
      // This is the exact failure that made "Add sample members" add nothing.
      await expectLater(
        db.upsert('customers', {
          'client_uuid': 'c1',
          'customer_name': 'Ravi Kumar',
          'business': 'Tailor', // no such column on customers
        }),
        throwsA(anything),
      );
    });
  });

  group('primary key discovery (no hard-coded table knowledge)', () {
    test('TEXT primary key drives matching', () async {
      await db.upsert('customer_id_pool', {'id': 'A-01'});
      await db.upsert('customer_id_pool',
          {'id': 'A-01', 'freed_at': '2026-09-28T10:00:00'});
      final rows = await db.query('customer_id_pool');
      expect(rows.length, 1);
      expect(rows.first['freed_at'], '2026-09-28T10:00:00',
          reason: 're-freeing updates the row, it does not duplicate it');
    });

    test('INTEGER autoincrement key inserts when no id is given', () async {
      await db.upsert('history_log', {'module': 'Pawn', 'kind': 'Loan'});
      await db.upsert('history_log', {'module': 'Pawn', 'kind': 'Collect'});
      final rows = await db.query('history_log', orderBy: 'id asc');
      expect(rows.length, 2);
      expect(rows.map((r) => r['kind']).toList(), ['Loan', 'Collect']);
    });

    test('a missing table still raises rather than writing nowhere', () async {
      await expectLater(
        db.upsert('no_such_table', {'client_uuid': 'x'}),
        throwsA(anything),
      );
    });
  });
}
