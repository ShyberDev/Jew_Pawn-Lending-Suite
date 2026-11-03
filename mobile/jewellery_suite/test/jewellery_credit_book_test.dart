import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/jewellery_store.dart';
import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/util/jewellery_math.dart';

/// The jewellery customer credit book and the cash direction of invoice
/// payments. Sales are customer receivables; purchases are supplier payables
/// and must never leak into the customer book.
void main() {
  late LocalDb db;
  late JewelleryStore store;
  late String file;

  Future<void> wipe() async {
    final f = File(file);
    if (f.existsSync()) f.deleteSync();
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    file = p.join(
        Directory.systemTemp.path, 'jewellery_suite_credit_book_test.db');
  });

  setUp(() async {
    await wipe();
    db = LocalDb();
    await db.init(pathOverride: file);
    store = JewelleryStore(db);
  });

  tearDown(() async {
    await db.db.close();
    await wipe();
  });

  tearDownAll(wipe);

  JewelleryItemInput goldItem({
    double weight = 10,
    double purity = 92,
    double rate = 15000,
    MakingMode makingMode = MakingMode.percentage,
    double makingValue = 6,
  }) =>
      JewelleryItemInput(
        description: 'Gold chain',
        metal: JewelleryStore.gold,
        grossWeight: weight,
        netWeight: weight,
        purity: purity,
        rate: rate,
        makingMode: makingMode,
        makingValue: makingValue,
      );

  Future<void> seedCreditBook() async {
    // Ravi: two sales, one part payment, one unpaid. The second sale uses a
    // different case on purpose so the book groups the name.
    await store.saveInvoice(
      docType: JewelleryStore.saleDoc,
      partyName: 'Ravi',
      date: DateTime(2026, 11, 1),
      metal: JewelleryStore.gold,
      items: [goldItem()],
      amountPaid: 47000,
    );
    await store.saveInvoice(
      docType: JewelleryStore.saleDoc,
      partyName: 'ravi',
      date: DateTime(2026, 11, 2),
      metal: JewelleryStore.gold,
      items: [goldItem(weight: 2, makingValue: 0)],
    );
    // Sita: fully settled.
    await store.saveInvoice(
      docType: JewelleryStore.saleDoc,
      partyName: 'Sita',
      date: DateTime(2026, 11, 2),
      metal: JewelleryStore.gold,
      items: [goldItem(weight: 5, makingValue: 0)],
      amountPaid: 69000,
    );
    // A purchase must stay out of the customer book.
    await store.saveInvoice(
      docType: JewelleryStore.purchaseDoc,
      partyName: 'Supplier',
      date: DateTime(2026, 11, 2),
      metal: JewelleryStore.gold,
      items: [goldItem()],
    );
  }

  group('credit customers', () {
    test('groups names, excludes purchases and totals the money', () async {
      await seedCreditBook();
      final customers = await store.creditCustomers();

      expect(customers.map((c) => c.name), ['Ravi', 'Sita']);
      final ravi = customers.first;
      expect(ravi.invoiceCount, 2);
      expect(ravi.billed, closeTo(174600, 0.01));
      expect(ravi.received, closeTo(47000, 0.01));
      expect(ravi.outstanding, closeTo(127600, 0.01));
      expect(ravi.lastDate, '2026-11-02');

      final sita = customers.last;
      expect(sita.invoiceCount, 1);
      expect(sita.billed, closeTo(69000, 0.01));
      expect(sita.received, closeTo(69000, 0.01));
      expect(sita.outstanding, closeTo(0, 0.01));

      expect(customers.map((c) => c.name), isNot(contains('Supplier')));
    });

    test('search matches a name case-insensitively', () async {
      await seedCreditBook();
      final found = await store.creditCustomers(search: 'SIT');
      expect(found, hasLength(1));
      expect(found.single.name, 'Sita');
    });

    test('credit book totals count only customers with dues', () async {
      await seedCreditBook();
      final totals = await store.creditBookTotals();
      expect(totals.outstanding, closeTo(127600, 0.01));
      expect(totals.customers, 1);
    });
  });

  group('customer ledger', () {
    test('sale debits, receipts credit and the balance runs forward', () async {
      await seedCreditBook();
      final rows = await store.ledgerForCustomer('RAVI');

      // Newest first.
      expect(rows, hasLength(3));
      expect(rows[0].isSale, isTrue);
      expect(rows[0].date, '2026-11-02');
      expect(rows[0].debit, closeTo(27600, 0.01));
      expect(rows[0].balance, closeTo(127600, 0.01));

      expect(rows[1].isSale, isFalse);
      expect(rows[1].credit, closeTo(47000, 0.01));
      expect(rows[1].balance, closeTo(100000, 0.01));

      expect(rows[2].isSale, isTrue);
      expect(rows[2].debit, closeTo(147000, 0.01));
      expect(rows[2].balance, closeTo(147000, 0.01));
      expect(rows[2].reference, 'SAL-20261101-0001');
    });

    test('old metal is a note on the sale, never a second credit', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        oldMetal: const OldMetalInput(
          metal: JewelleryStore.gold,
          grossWeight: 2,
          purity: 63,
          rate: 12500,
        ),
      );
      final invoice = (await store.invoice(uuid))!;
      final rows = await store.ledgerForCustomer('Ravi');
      expect(rows, hasLength(1));
      expect(rows.single.oldMetalValue, closeTo(15750, 0.01));
      expect(rows.single.debit, closeTo((invoice['total'] as num).toDouble(), 0.01));
      expect(rows.single.credit, 0);
    });

    test('open invoices are oldest first and settled ones are excluded',
        () async {
      await seedCreditBook();
      final ravi = await store.openInvoicesForCustomer('Ravi');
      expect(ravi, hasLength(2));
      expect(ravi.first['doc_no'], 'SAL-20261101-0001');
      expect(ravi.last['doc_no'], 'SAL-20261102-0001');

      final sita = await store.openInvoicesForCustomer('Sita');
      expect(sita, isEmpty);
    });
  });

  group('payment cash direction', () {
    late LocalDb local;
    late AppState state;
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('js_jewellery_cash_');
      local = LocalDb();
      await local.init(pathOverride: p.join(dir.path, 'cash.db'));
      state = AppState(local);
    });

    tearDown(() async {
      await local.db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('a supplier payment against a purchase is cash OUT', () async {
      final invoiceUuid = await state.saveJewelleryInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Supplier',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
      );
      await state.addJewelleryPayment(
        invoiceUuid: invoiceUuid,
        partyName: 'Supplier',
        amount: 5000,
        date: DateTime(2026, 11, 2),
        isPurchase: true,
      );

      final rows = await local.query('cashbook_entries');
      expect(rows, hasLength(1));
      expect(rows.single['category'], 'JEWELLERY_PURCHASE');
      expect(rows.single['entry_type'], 'OUT');
      expect(rows.single['amount'], 5000.0);
      expect(rows.single['party_name'], 'Supplier');
    });

    test('a customer receipt against a sale is cash IN', () async {
      final invoiceUuid = await state.saveJewelleryInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
      );
      await state.addJewelleryPayment(
        invoiceUuid: invoiceUuid,
        partyName: 'Ravi',
        amount: 5000,
        date: DateTime(2026, 11, 2),
      );

      final rows = await local.query('cashbook_entries');
      expect(rows, hasLength(1));
      expect(rows.single['category'], 'JEWELLERY_COLLECT');
      expect(rows.single['entry_type'], 'IN');
      expect(rows.single['amount'], 5000.0);
    });
  });
}
