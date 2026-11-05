import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/jewellery_store.dart';
import 'package:jewellery_suite/data/local_db.dart';

/// The three workflow boxes that used to be open in
/// `Calculations_and_Test_Cases.md` §2:
///
/// * a draft purchase must post **no** stock, and confirming must post it once;
/// * a shared expense is split by weight and stated once;
/// * a late fee is a separate charge that never rewrites the sale value.
void main() {
  late LocalDb db;
  late JewelleryStore store;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_draft_');
    db = LocalDb();
    await db.init(pathOverride: p.join(dir.path, 'draft.db'));
    store = JewelleryStore(db);
  });

  tearDown(() async {
    await db.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  JewelleryItemInput rawItem({double weight = 10, double additional = 0}) =>
      JewelleryItemInput(
        description: 'Raw gold',
        metal: JewelleryStore.gold,
        grossWeight: weight,
        netWeight: weight,
        purity: 92,
        rate: 15000,
        additionalCost: additional,
      );

  Future<List<Map<String, Object?>>> movements() =>
      db.db.query('jewellery_stock_movements');

  group('draft purchases', () {
    test('a draft posts no stock and no payment', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Ravi Bullion',
        date: DateTime(2026, 11, 5),
        metal: JewelleryStore.gold,
        items: [rawItem()],
        amountPaid: 5000,
        status: JewelleryStore.draftStatus,
      );

      expect(await movements(), isEmpty,
          reason: 'a draft must never move stock');
      expect(await db.db.query('jewellery_payments'), isEmpty,
          reason: 'a draft must not record a payment');
      final invoice = await store.invoice(uuid);
      expect(invoice!['status'], JewelleryStore.draftStatus);
      expect(invoice['amount_paid'], 0);
      expect(invoice['outstanding'], invoice['total']);
    });

    test('confirming posts stock exactly once', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Ravi Bullion',
        date: DateTime(2026, 11, 5),
        metal: JewelleryStore.gold,
        items: [rawItem()],
        status: JewelleryStore.draftStatus,
      );

      await store.confirmInvoice(uuid);
      final first = await movements();
      expect(first, hasLength(1));
      expect(first.single['movement_type'], 'PURCHASE_IN');
      expect((first.single['weight'] as num?)?.toDouble(), closeTo(10, 0.001));

      await expectLater(
        store.confirmInvoice(uuid),
        throwsA(isA<FormatException>()),
        reason: 'a confirmed document is no longer a draft',
      );
      expect(await movements(), hasLength(1),
          reason: 'confirm must never post the stock twice');
      expect((await store.invoice(uuid))!['status'], 'Active');
    });

    test('a draft stays out of supplier payables until confirmed', () async {
      await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Ravi Bullion',
        date: DateTime(2026, 11, 5),
        metal: JewelleryStore.gold,
        items: [rawItem()],
        status: JewelleryStore.draftStatus,
      );
      expect(await store.supplierPayables(), isEmpty);
    });
  });

  group('shared expense', () {
    test('is split by net weight and charged once', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Ravi Bullion',
        date: DateTime(2026, 11, 5),
        metal: JewelleryStore.gold,
        items: [rawItem(weight: 10), rawItem(weight: 5)],
        sharedExpense: 300,
      );

      final invoice = await store.invoice(uuid);
      expect(
          (invoice!['shared_expense'] as num?)?.toDouble(), closeTo(300, 0.01));
      final items = await store.itemsFor(uuid);
      expect((items[0]['additional_cost'] as num?)?.toDouble(),
          closeTo(200, 0.01));
      expect((items[1]['additional_cost'] as num?)?.toDouble(),
          closeTo(100, 0.01));
      expect(
          (invoice['additional_total'] as num?)?.toDouble(), closeTo(300, 0.01),
          reason: 'the shared expense must be stated once, not per line twice');

      final lineSum = items.fold<double>(
          0, (sum, item) => sum + (item['line_total'] as num).toDouble());
      expect((invoice['total'] as num?)?.toDouble(), closeTo(lineSum, 1.0),
          reason: 'the invoice total is still the sum of its lines');
    });

    test('no shared expense leaves the lines alone', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Ravi Bullion',
        date: DateTime(2026, 11, 5),
        metal: JewelleryStore.gold,
        items: [rawItem()],
      );
      final items = await store.itemsFor(uuid);
      expect((items.single['additional_cost'] as num?)?.toDouble(), 0);
    });
  });

  group('late fee', () {
    test('raises the balance without touching the sale value', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Shyam',
        date: DateTime(2026, 11, 1),
        metal: JewelleryStore.gold,
        items: [rawItem()],
      );
      final before = await store.invoice(uuid);
      final total = (before!['total'] as num).toDouble();
      final outstanding = (before['outstanding'] as num).toDouble();

      await store.addLateFee(
        invoiceUuid: uuid,
        amount: 500,
        date: DateTime(2026, 11, 5),
        note: 'Late',
      );

      final after = await store.invoice(uuid);
      expect((after!['total'] as num).toDouble(), closeTo(total, 0.01),
          reason: 'a fee must never rewrite what was sold');
      expect((after['late_fee_total'] as num).toDouble(), closeTo(500, 0.01));
      expect((after['outstanding'] as num).toDouble(),
          closeTo(outstanding + 500, 0.01));

      final ledger = await store.ledgerForCustomer('Shyam');
      final fee = ledger.firstWhere((e) => e.type == 'LATE_FEE');
      expect(fee.debit, closeTo(500, 0.01));
      expect(fee.description, 'Late fee');

      final dues = await store.creditCustomers();
      expect(dues.single.outstanding, closeTo(outstanding + 500, 0.01));
    });

    test('deleting the sale removes its fees', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Shyam',
        date: DateTime(2026, 11, 1),
        metal: JewelleryStore.gold,
        items: [rawItem()],
      );
      await store.addLateFee(
          invoiceUuid: uuid, amount: 200, date: DateTime(2026, 11, 5));
      await store.deleteInvoice(uuid);
      expect(await db.db.query('jewellery_charges'), isEmpty);
    });
  });
}
