import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/features/authentication/cloud/cloud_sync.dart';

/// P1/P4/P5 regression tests, run against the real v21 schema rather than a
/// hand-written mock — the schema mismatch that broke the pull was invisible to
/// a mock.
Future<List<Map<String, Object?>>> batch(
  LocalDb db,
  CloudMirror mirror,
  String stamp,
  String uuid, {
  required bool hasDirty,
  int limit = CloudSync.pushBatchSize,
}) {
  final filter = CloudSync.pushWhere(mirror, stamp, uuid, hasDirty: hasDirty);
  return db.query(
    mirror.table,
    where: filter.where,
    whereArgs: filter.args,
    orderBy: '${mirror.stamp} asc, client_uuid asc',
    limit: limit,
  );
}

void main() {
  late LocalDb db;
  late String file;

  final movements = CloudSync.mirrors
      .firstWhere((m) => m.table == 'jewellery_stock_movements');
  final txns = CloudSync.mirrors
      .firstWhere((m) => m.table == 'jewellery_worker_txns');

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    file = p.join(
      Directory.systemTemp.path,
      'jewellery_suite_cloud_sync_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    db = LocalDb();
    await db.init(pathOverride: file);
  });

  tearDown(() async {
    await db.close();
    final f = File(file);
    if (f.existsSync()) f.deleteSync();
  });

  Map<String, dynamic> firestoreMovement(String id,
          {double weight = 12.5, String stamp = '2026-11-09T06:00:00.000Z'}) =>
      <String, dynamic>{
        'client_uuid': id,
        'metal': 'GOLD',
        'movement_date': '2026-11-09',
        'movement_type': 'SALE',
        'stock_kind': 'FINISHED',
        'weight': weight,
        'purity': 91.6,
        'fine_weight': 11.45,
        'notes': 'sale',
        'created_at': stamp,
        // Both of these exist only in Firestore: the rules require updated_at,
        // and older clients sent dirty. Neither is a column locally.
        'updated_at': stamp,
        'dirty': 0,
      };

  group('P1 — pull against the real schema', () {
    test('the v21 movement ledger has no updated_at and no dirty column',
        () async {
      final columns = await db.columns('jewellery_stock_movements');
      expect(columns, containsAll(<String>['client_uuid', 'created_at', 'weight']));
      expect(columns.contains('updated_at'), isFalse,
          reason: 'this is exactly why the pull used to throw');
      expect(columns.contains('dirty'), isFalse);
    });

    test('a Firestore-shaped movement is stored without its extra fields',
        () async {
      final applied = await CloudSync.instance
          .applyRemote(db, movements, 'mov-1', firestoreMovement('mov-1'));
      expect(applied, isTrue);

      final row = await db.byUuid('jewellery_stock_movements', 'mov-1');
      expect(row, isNotNull);
      expect(row!['weight'], 12.5);
      expect(row['movement_date'], '2026-11-09');
      expect(
        DateTime.parse(row['created_at'] as String).isAtSameMomentAs(
            DateTime.parse('2026-11-09T06:00:00.000Z')),
        isTrue,
        reason: 'the instant survives, in the local storage format',
      );
    });

    test('the same movement never overwrites itself', () async {
      await CloudSync.instance
          .applyRemote(db, movements, 'mov-2', firestoreMovement('mov-2'));
      final again = await CloudSync.instance.applyRemote(
          db, movements, 'mov-2', firestoreMovement('mov-2', weight: 99));
      expect(again, isFalse);
      final row = await db.byUuid('jewellery_stock_movements', 'mov-2');
      expect(row!['weight'], 12.5);
    });

    test('a record with a nested map does not crash the pull', () async {
      final applied = await CloudSync.instance.applyRemote(
          db, movements, 'mov-3', {...firestoreMovement('mov-3'), 'meta': {'a': 1}});
      expect(applied, isTrue);
    });
  });

  group('P1/P5 — worker rows merge on the UTC stamp', () {
    test('a pulled worker row is stored clean and only a later instant wins',
        () async {
      await CloudSync.instance.applyRemote(db, txns, 'txn-1', {
        'client_uuid': 'txn-1',
        'worker_name': 'Ravi',
        'txn_type': 'CASH_PAID',
        'cash_amount': 500.0,
        'updated_at': '2026-11-09T06:00:00.000Z',
      });
      var row = await db.byUuid('jewellery_worker_txns', 'txn-1');
      expect(row!['dirty'], 0, reason: 'a pulled row must not upload again');

      final older = await CloudSync.instance.applyRemote(db, txns, 'txn-1', {
        'client_uuid': 'txn-1',
        'cash_amount': 1.0,
        'updated_at': '2026-11-09T05:59:59.999Z',
      });
      expect(older, isFalse);

      final newer = await CloudSync.instance.applyRemote(db, txns, 'txn-1', {
        'client_uuid': 'txn-1',
        'cash_amount': 750.0,
        'updated_at': '2026-11-09T06:00:00.001Z',
      });
      expect(newer, isTrue);
      row = await db.byUuid('jewellery_worker_txns', 'txn-1');
      expect(row!['cash_amount'], 750.0);
      expect(row['worker_name'], 'Ravi',
          reason: 'a partial document must not erase untouched columns');
    });

    test('a local wall-clock stamp ties with its UTC form', () async {
      final local = DateTime(2026, 11, 9, 11, 30);
      await CloudSync.instance.applyRemote(db, txns, 'txn-2', {
        'client_uuid': 'txn-2',
        'cash_amount': 10.0,
        'updated_at': local.toIso8601String(),
      });
      final sameInstant = await CloudSync.instance.applyRemote(db, txns, 'txn-2', {
        'client_uuid': 'txn-2',
        'cash_amount': 20.0,
        'updated_at': local.toUtc().toIso8601String(),
      });
      expect(sameInstant, isFalse,
          reason: 'the same instant is not a newer edit');
    });
  });

  group('P4 — watermark cannot skip an equal stamp', () {
    test('two batches cover rows that share one timestamp', () async {
      const stamp = '2026-11-09T10:00:00.000';
      for (final id in ['a', 'b', 'c']) {
        await db.db.insert('jewellery_stock_movements', {
          'client_uuid': id,
          'metal': 'GOLD',
          'movement_date': '2026-11-09',
          'movement_type': 'SALE',
          'stock_kind': 'FINISHED',
          'weight': 1.0,
          'purity': 91.6,
          'fine_weight': 0.916,
          'created_at': stamp,
        });
      }

      final first =
          await batch(db, movements, '', '', hasDirty: false, limit: 2);
      expect(first.map((r) => r['client_uuid']), ['a', 'b']);

      final watermark = first.last['created_at'] as String;
      final watermarkId = first.last['client_uuid'] as String;
      final second = await batch(db, movements, watermark, watermarkId,
          hasDirty: false, limit: 2);
      expect(second.map((r) => r['client_uuid']), ['c'],
          reason: 'the row after the batch boundary must still be sent');
    });

    test('a pulled worker row is not selected for upload again', () async {
      await CloudSync.instance.applyRemote(db, txns, 'txn-3', {
        'client_uuid': 'txn-3',
        'worker_name': 'Ravi',
        'cash_amount': 100.0,
        'updated_at': '2026-11-09T06:00:00.000Z',
      });
      final rows = await batch(db, txns, '2026-11-09T11:30:00.000', 'zzz',
          hasDirty: true);
      expect(rows, isEmpty);
    });

    test('a local edit behind the watermark still uploads while dirty',
        () async {
      await db.db.insert('jewellery_worker_txns', {
        'client_uuid': 'txn-4',
        'worker_name': 'Ravi',
        'cash_amount': 50.0,
        'dirty': 1,
        'updated_at': '2026-11-09T05:00:00.000',
      });
      final rows = await batch(db, txns, '2026-11-09T11:30:00.000', 'zzz',
          hasDirty: true);
      expect(rows.map((r) => r['client_uuid']), ['txn-4']);
    });

    test('the watermark keeps stamp and uuid apart', () {
      expect(CloudSync.watermarkKey('jewellery_worker_txns'),
          'cloud_wm_jewellery_worker_txns');
      expect(CloudSync.watermarkIdKey('jewellery_worker_txns'),
          'cloud_wm_jewellery_worker_txns_id');
    });
  });
}
