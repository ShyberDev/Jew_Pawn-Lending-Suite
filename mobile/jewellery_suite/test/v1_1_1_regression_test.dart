import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/data/migration_v15.dart';
import 'package:jewellery_suite/state/app_state.dart';

/// Regressions fixed for v1.1.1 after on-device testing:
///
/// * New Pawn Loan "SAVE" did nothing for a new customer — the form hard-coded
///   customer ID `A01` (usually already taken), then wrote customer photo
///   columns that do not exist (`id_front` / `id_back`).
/// * Customer Profile "You Gave" could not add late fee / interest / principal
///   after the first loan — `khatabook_given` had no `payment_mode` column while
///   every write sent one.
/// * Cashbook could only filter by payment mode, not by the module that created
///   the entry.
void main() {
  late LocalDb local;
  late AppState state;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_v111_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'v111.db'));
    state = AppState(local);
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('You Gave storage', () {
    test('khatabook_given accepts payment_mode on a fresh install', () async {
      await local.upsert('khatabook_given', {
        'client_uuid': 'g1',
        'customer_name': 'Ravi',
        'customer_uuid': 'c1',
        'khatabook_loan': 'l1',
        'given_date': '2026-10-28',
        'amount': 500,
        'given_type': 'late_fee',
        'payment_mode': 'UPI',
        'note': 'Late fee',
      });
      final row = (await local.byUuid('khatabook_given', 'g1'))!;
      expect(row['payment_mode'], 'UPI');
    });

    test('saveEntity writes the row and its cashbook OUT hook', () async {
      await state.saveEntity(
        table: 'khatabook_given',
        doctype: 'Khatabook Given',
        uuid: 'g2',
        data: {
          'customer': 'Ravi',
          'customer_name': 'Ravi',
          'customer_uuid': 'c1',
          'village': 'V',
          'khatabook_loan': 'l1',
          'given_date': '2026-10-28',
          'amount': 750.0,
          'given_type': 'interest',
          'payment_mode': 'BANK',
          'note': 'Interest',
        },
      );

      final given = (await local.byUuid('khatabook_given', 'g2'))!;
      expect(given['amount'], 750.0);
      expect(given['payment_mode'], 'BANK');

      final cash = await local.getCashbookEntries(date: '2026-10-28');
      expect(cash, hasLength(1));
      expect(cash.first['category'], 'KHATA_DISBURSE');
      expect(cash.first['payment_mode'], 'BANK');
      expect(cash.first['entry_type'], 'OUT');
    });
  });

  group('New Pawn Loan save', () {
    test('a brand-new customer + loan is written in full', () async {
      // Exactly what the form now sends: next free book ID when the field is
      // blank, and the real customer photo columns.
      final customerId = await state.claimCustomerId('');
      await state.saveEntity(
        table: 'customers',
        doctype: 'Pawn Customer',
        uuid: 'pc1',
        data: {
          'customer_name': 'New Pawn Customer',
          'customer_id': customerId,
          'phone': '9000000001',
          'village': 'Pallipatti',
          'id_proof_type': 'Aadhaar',
          'id_proof_number': '1234',
          'id_photo_front': '/photos/front.jpg',
          'id_photo_back': '/photos/back.jpg',
          'customer_type': 'General',
        },
      );

      await state.savePawnLoan(
        uuid: 'pl1',
        data: {
          'customer': 'New Pawn Customer',
          'customer_name': 'New Pawn Customer',
          'customer_uuid': 'pc1',
          'village': 'Pallipatti',
          'status': 'Active',
          'loan_date': '2026-10-28',
          'interest_basis': 'Gold',
          'loan_amount': 5000.0,
          'interest_rate': 3.0,
          'due_date': '2027-01-26',
          'total_gross_weight': 10.0,
          'total_net_weight': 9.5,
          'hallmarked_weight': 9.5,
          'non_hallmarked_weight': 0.0,
          'total_market_value': 60000.0,
          'ltv': 8.33,
          'interest_accrued': 450.0,
          'last_interest_date': '2027-01-26',
          'total_payable': 5450.0,
          'amount_paid': 0.0,
          'balance': 5450.0,
          'phone': '9000000001',
          'id_proof_type': 'Aadhaar',
          'id_proof_number': '1234',
          'id_front': '/photos/front.jpg',
          'id_back': '/photos/back.jpg',
        },
        items: [
          {
            'item_description': 'Gold chain',
            'metal_type': 'Gold',
            'purity': '22K',
            'quantity': 1,
            'gross_weight': 10.0,
            'net_weight': 9.5,
            'hallmarked': 1,
            'valuation_rate': 6300.0,
            'market_value': 59850.0,
            'photo_path': null,
          }
        ],
      );

      final customer = (await local.byUuid('customers', 'pc1'))!;
      expect(customer['customer_id'], customerId);
      expect(customer['id_photo_front'], '/photos/front.jpg');

      final loan = (await local.byUuid('pawn_loans', 'pl1'))!;
      expect(loan['loan_amount'], 5000.0);
      expect(loan['customer_uuid'], 'pc1');

      final items = await local
          .query('pawn_items', where: 'loan_uuid = ?', whereArgs: ['pl1']);
      expect(items, hasLength(1));
      expect(items.first['item_description'], 'Gold chain');

      final cash = await local.getCashbookEntries(date: '2026-10-28');
      expect(cash, hasLength(1));
      expect(cash.first['category'], 'PAWN_DISBURSE');
      expect(cash.first['entry_type'], 'OUT');
    });

    test('a blank customer ID never reuses A01', () async {
      final first = await state.claimCustomerId('');
      final second = await state.claimCustomerId('');
      expect(first, 'A01');
      expect(second, 'A02');
      expect(first == second, isFalse);
    });
  });

  group('cashbook source filter', () {
    Future<void> seed() async {
      const day = '2026-10-28';
      await local.addCashbookEntry({
        'client_uuid': 'e1',
        'entry_date': day,
        'entry_time': '09:00:00',
        'entry_type': 'IN',
        'amount': 1000.0,
        'payment_mode': 'CASH',
        'category': 'KHATA_COLLECTION',
        'created_at': day,
      });
      await local.addCashbookEntry({
        'client_uuid': 'e2',
        'entry_date': day,
        'entry_time': '10:00:00',
        'entry_type': 'OUT',
        'amount': 500.0,
        'payment_mode': 'UPI',
        'category': 'PAWN_DISBURSE',
        'created_at': day,
      });
      await local.addCashbookEntry({
        'client_uuid': 'e3',
        'entry_date': day,
        'entry_time': '11:00:00',
        'entry_type': 'IN',
        'amount': 2500.0,
        'payment_mode': 'BANK',
        'category': 'JEWELLERY_SALE',
        'created_at': day,
      });
      await local.addCashbookEntry({
        'client_uuid': 'e4',
        'entry_date': day,
        'entry_time': '12:00:00',
        'entry_type': 'OUT',
        'amount': 200.0,
        'payment_mode': 'CASH',
        'category': 'SHOP_EXPENSE',
        'created_at': day,
      });
    }

    test('each module returns only its own rows', () async {
      await seed();
      const day = '2026-10-28';

      final khata = await local.getCashbookEntries(date: day, source: 'KHATA');
      expect(khata.map((e) => e['client_uuid']), ['e1']);

      final pawn = await local.getCashbookEntries(date: day, source: 'PAWN');
      expect(pawn.map((e) => e['client_uuid']), ['e2']);

      final jewellery =
          await local.getCashbookEntries(date: day, source: 'JEWELLERY');
      expect(jewellery.map((e) => e['client_uuid']), ['e3']);

      final manual =
          await local.getCashbookEntries(date: day, source: 'MANUAL');
      expect(manual.map((e) => e['client_uuid']), ['e4']);
    });

    test('source and payment mode combine', () async {
      await seed();
      const day = '2026-10-28';
      final rows = await local.getCashbookEntries(
          date: day, source: 'KHATA', mode: 'CASH');
      expect(rows, hasLength(1));
      expect(rows.first['client_uuid'], 'e1');

      final none = await local.getCashbookEntries(
          date: day, source: 'PAWN', mode: 'CASH');
      expect(none, isEmpty);
    });

    test('the daily tally follows the active filters', () async {
      await seed();
      const day = '2026-10-28';

      final all = await local.getCashbookDailySummary(day);
      expect(all['total_in'], 3500.0);
      expect(all['total_out'], 700.0);
      expect(all['net'], 2800.0);

      final pawn = await local.getCashbookDailySummary(day, source: 'PAWN');
      expect(pawn['total_in'], 0.0);
      expect(pawn['total_out'], 500.0);
      expect(pawn['net'], -500.0);
    });
  });

  group('migration v15', () {
    test('adds payment_mode and is safe to run twice', () async {
      final file = p.join(dir.path, 'raw15.db');
      final raw = await openDatabase(
        file,
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
              'CREATE TABLE khatabook_given (client_uuid TEXT PRIMARY KEY)');
        },
      );
      await MigrationV15.addSchema(raw);
      await MigrationV15.addSchema(raw);
      final cols = await raw.rawQuery('PRAGMA table_info(khatabook_given)');
      expect(cols.any((c) => c['name'] == 'payment_mode'), isTrue);
      await raw.close();
    });
  });
}
