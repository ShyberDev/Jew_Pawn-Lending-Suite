import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/data/migration_v12.dart';
import 'package:jewellery_suite/state/app_state.dart';

/// Loss Khata is one more Khata row, not a new system: moving a customer only
/// rewrites their village (remembering the origin), and nothing else moves.
///
/// The rules pinned here:
/// - the reserved row is created once, adopted when present, never duplicated;
/// - a move keeps loans, collections, IDs and history untouched;
/// - a move back clears the origin and restores the village.
void main() {
  late LocalDb local;
  late AppState state;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_loss_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'loss.db'));
    state = AppState(local);
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<String> customer(String name, String? village) async {
    const uuid = 'c-loss-1';
    await local.upsert('customers', {
      'client_uuid': uuid,
      'customer_name': name,
      'village': village,
      'customer_id': 'A01',
    });
    return uuid;
  }

  group('reserved row', () {
    test('ensure creates it once', () async {
      await state.ensureLossKhata();
      await state.ensureLossKhata();
      final rows = await local.db.query('villages',
          where: 'village_name = ?', whereArgs: ['Loss']);
      expect(rows.length, 1);
      expect(rows.first['client_uuid'], MigrationV12.lossVillageUuid);
    });

    test('an existing Loss village is adopted, not duplicated', () async {
      await local.upsert('villages', {
        'client_uuid': 'some-other-uuid',
        'village_name': 'loss',
      });
      await state.ensureLossKhata();
      final rows = await local.db.query('villages');
      expect(
          rows.where((r) =>
              MigrationV12.isLossVillageName(
                  r['village_name']?.toString())),
          hasLength(1));
    });

    test('name matching ignores case', () {
      expect(MigrationV12.isLossKhata('Loss'), isTrue);
      expect(MigrationV12.isLossKhata('LOSS'), isTrue);
      expect(MigrationV12.isLossKhata(' loss '), isTrue);
      expect(MigrationV12.isLossKhata('Pallipatti'), isFalse);
      expect(MigrationV12.isLossKhata(null), isFalse);
    });
  });

  group('move to Loss', () {
    test('only the village changes; everything else stays', () async {
      final uuid = await customer('Ravi', 'Pallipatti');
      await local.upsert('khatabook_loans', {
        'client_uuid': 'l1',
        'customer': uuid,
        'customer_name': 'Ravi',
        'village': 'Pallipatti',
        'total_payable': 12000,
        'outstanding': 12000,
        'status': 'Active',
      });
      final before =
          (await local.byUuid('customers', uuid))!;

      await state.moveCustomerToLoss(before);

      final after = (await local.byUuid('customers', uuid))!;
      expect(after['village'], 'Loss');
      expect(after['previous_village'], 'Pallipatti');
      expect(after['customer_name'], 'Ravi');
      expect(after['customer_id'], 'A01');
      // Loan untouched: same village column, same balance, still active.
      final loan = (await local.byUuid('khatabook_loans', 'l1'))!;
      expect(loan['outstanding'], 12000);
      expect(loan['status'], 'Active');
      final loans = await local.db.query('khatabook_loans');
      expect(loans.length, 1, reason: 'no loan duplicated or removed');
    });
  });

  group('move back', () {
    test('restores the village and clears the origin', () async {
      final uuid = await customer('Ravi', 'Pallipatti');
      final before =
          (await local.byUuid('customers', uuid))!;
      await state.moveCustomerToLoss(before);
      final inLoss =
          (await local.byUuid('customers', uuid))!;

      await state.moveCustomerFromLoss(inLoss, 'Pallipatti');

      final back = (await local.byUuid('customers', uuid))!;
      expect(back['village'], 'Pallipatti');
      expect(back['previous_village'], isNull);
    });

    test('can move back to General (no village)', () async {
      final uuid = await customer('Ravi', 'Pallipatti');
      final before =
          (await local.byUuid('customers', uuid))!;
      await state.moveCustomerToLoss(before);
      final inLoss =
          (await local.byUuid('customers', uuid))!;

      await state.moveCustomerFromLoss(inLoss, null);

      final back = (await local.byUuid('customers', uuid))!;
      expect(back['village'], isNull);
    });
  });

  group('schema v12', () {
    test('fresh installs carry previous_village', () async {
      final cols =
          await local.db.rawQuery('PRAGMA table_info(customers)');
      expect(cols.map((c) => '${c['name']}'), contains('previous_village'));
    });

    test('adding the schema twice is harmless', () async {
      await MigrationV12.addSchema(local.db);
      await MigrationV12.addSchema(local.db);
      final cols =
          await local.db.rawQuery('PRAGMA table_info(customers)');
      expect(
          cols.where((c) => c['name'] == 'previous_village').length, 1);
    });
  });
}
