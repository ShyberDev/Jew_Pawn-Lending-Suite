import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/jewellery_store.dart';
import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/util/jewellery_math.dart';

/// C13 in `Calculations_and_Test_Cases.md`: one receipt may be split across
/// several invoices, and anything the invoices do not need is **credit the
/// customer holds**, never a refusal and never a hidden zero balance.
void main() {
  late LocalDb db;
  late JewelleryStore store;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_receipt_');
    db = LocalDb();
    await db.init(pathOverride: p.join(dir.path, 'receipt.db'));
    store = JewelleryStore(db);
  });

  tearDown(() async {
    await db.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  JewelleryItemInput goldItem({double weight = 10, double makingValue = 6}) =>
      JewelleryItemInput(
        description: 'Gold chain',
        metal: JewelleryStore.gold,
        grossWeight: weight,
        netWeight: weight,
        purity: 92,
        rate: 15000,
        makingMode: MakingMode.percentage,
        makingValue: makingValue,
      );

  /// Ravi owes ₹1,47,000 on the first sale and ₹27,600 on the second.
  Future<List<String>> twoSales() async => [
        await store.saveInvoice(
          docType: JewelleryStore.saleDoc,
          partyName: 'Ravi',
          date: DateTime(2026, 11, 1),
          metal: JewelleryStore.gold,
          items: [goldItem()],
        ),
        await store.saveInvoice(
          docType: JewelleryStore.saleDoc,
          partyName: 'Ravi',
          date: DateTime(2026, 11, 2),
          metal: JewelleryStore.gold,
          items: [goldItem(weight: 2, makingValue: 0)],
        ),
      ];

  group('receipt allocation', () {
    test('spreads oldest first and keeps the excess as an advance', () async {
      await twoSales();
      final result = await store.receiveCustomerPayment(
        partyName: 'Ravi',
        amount: 200000,
        date: DateTime(2026, 11, 3),
      );

      expect(result.allocated.values.fold<double>(0, (a, b) => a + b),
          closeTo(174600, 0.01));
      expect(result.unallocated, closeTo(25400, 0.01));
      expect(result.payments, hasLength(3)); // two invoices + the advance
    });

    test('never takes more than an invoice owes', () async {
      await twoSales();
      final result = await store.receiveCustomerPayment(
        partyName: 'Ravi',
        amount: 5000,
        date: DateTime(2026, 11, 3),
      );
      expect(result.allocated.values.single, closeTo(5000, 0.01));
      expect(result.unallocated, 0);
    });

    test('a manual split decides which invoice the money belongs to',
        () async {
      final uuids = await twoSales();
      final result = await store.receiveCustomerPayment(
        partyName: 'Ravi',
        amount: 27600,
        date: DateTime(2026, 11, 3),
        allocations: {uuids[1]: 27600},
      );

      expect(result.allocated[uuids[1]], closeTo(27600, 0.01));
      expect(result.allocated.containsKey(uuids[0]), isFalse);
      final first = (await store.invoice(uuids[0]))!;
      final second = (await store.invoice(uuids[1]))!;
      expect((first['outstanding'] as num).toDouble(), closeTo(147000, 0.01));
      expect((second['outstanding'] as num).toDouble(), closeTo(0, 0.01));
    });

    test('the advance is customer credit, not a hidden zero balance', () async {
      await twoSales();
      await store.receiveCustomerPayment(
        partyName: 'Ravi',
        amount: 200000,
        date: DateTime(2026, 11, 3),
      );

      final customer = (await store.creditCustomers()).single;
      expect(customer.outstanding, 0);
      expect(customer.received, closeTo(200000, 0.01));

      final ledger = await store.ledgerForCustomer('Ravi');
      final advance = ledger.firstWhere((e) => e.type == 'ADVANCE');
      expect(advance.credit, closeTo(25400, 0.01));
      expect(advance.description, 'Advance received');
      expect(ledger.first.balance, 0);
    });

    test('a zero or negative receipt is refused', () async {
      await twoSales();
      expect(
        () => store.receiveCustomerPayment(
          partyName: 'Ravi',
          amount: 0,
          date: DateTime(2026, 11, 3),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('cashbook', () {
    late LocalDb local;
    late AppState state;

    setUp(() async {
      local = LocalDb();
      await local.init(pathOverride: p.join(dir.path, 'cash.db'));
      state = AppState(local);
    });

    test('every part of the receipt posts one IN row', () async {
      final sale = await state.saveJewelleryInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 1),
        metal: JewelleryStore.gold,
        items: [goldItem()],
      );
      await state.receiveJewelleryReceipt(
        partyName: 'Ravi',
        amount: 50000,
        date: DateTime(2026, 11, 3),
        allocations: {sale: 47000},
      );

      final rows = await local.query('cashbook_entries');
      expect(rows, hasLength(2));
      expect(rows.every((r) => r['category'] == 'JEWELLERY_COLLECT'), isTrue);
      expect(rows.every((r) => r['entry_type'] == 'IN'), isTrue);
      expect(
        rows.fold<double>(0, (sum, r) => sum + (r['amount'] as num).toDouble()),
        closeTo(50000, 0.01),
      );
      await local.db.close();
    });
  });
}
