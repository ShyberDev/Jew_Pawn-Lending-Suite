import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/jewellery_store.dart';
import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/util/format.dart';
import 'package:jewellery_suite/util/jewellery_math.dart';

/// The jewellery supplier payable book: purchases create the payable, purchase
/// payments reduce it, and customer sales never leak into it.
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
    file =
        p.join(Directory.systemTemp.path, 'jewellery_suite_supplier_test.db');
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

  Future<String> seedSupplierBook() async {
    final first = await store.saveInvoice(
      docType: JewelleryStore.purchaseDoc,
      partyName: 'Supplier A',
      date: DateTime(2026, 11, 1),
      metal: JewelleryStore.gold,
      items: [goldItem()],
      amountPaid: 47000,
    );
    await store.saveInvoice(
      docType: JewelleryStore.purchaseDoc,
      partyName: 'supplier a',
      date: DateTime(2026, 11, 2),
      metal: JewelleryStore.gold,
      items: [goldItem(weight: 2, makingValue: 0)],
    );
    await store.saveInvoice(
      docType: JewelleryStore.purchaseDoc,
      partyName: 'Supplier B',
      date: DateTime(2026, 11, 2),
      metal: JewelleryStore.gold,
      items: [goldItem(weight: 5, makingValue: 0)],
      amountPaid: 69000,
    );
    // A customer sale must stay out of the supplier book.
    await store.saveInvoice(
      docType: JewelleryStore.saleDoc,
      partyName: 'Ravi',
      date: DateTime(2026, 11, 2),
      metal: JewelleryStore.gold,
      items: [goldItem()],
    );
    await store.addPayment(
      invoiceUuid: first,
      amount: 50000,
      date: DateTime(2026, 11, 3),
    );
    return first;
  }

  group('supplier payables', () {
    test('groups names, excludes sales and totals the money', () async {
      await seedSupplierBook();
      final suppliers = await store.supplierPayables();

      expect(suppliers.map((s) => s.name), ['Supplier A', 'Supplier B']);
      final a = suppliers.first;
      expect(a.invoiceCount, 2);
      expect(a.billed, closeTo(174600, 0.01));
      expect(a.paid, closeTo(97000, 0.01));
      expect(a.outstanding, closeTo(77600, 0.01));
      expect(a.lastDate, '2026-11-02');

      final b = suppliers.last;
      expect(b.invoiceCount, 1);
      expect(b.billed, closeTo(69000, 0.01));
      expect(b.paid, closeTo(69000, 0.01));
      expect(b.outstanding, closeTo(0, 0.01));

      expect(suppliers.map((s) => s.name), isNot(contains('Ravi')));
    });

    test('search matches a supplier name case-insensitively', () async {
      await seedSupplierBook();
      final found = await store.supplierPayables(search: 'SUPPLIER A');
      expect(found, hasLength(1));
      expect(found.single.name, 'Supplier A');
    });

    test('totals count only suppliers with dues', () async {
      await seedSupplierBook();
      final totals = await store.supplierBookTotals();
      expect(totals.outstanding, closeTo(77600, 0.01));
      expect(totals.suppliers, 1);
    });

    test('open purchase invoices are oldest first', () async {
      await seedSupplierBook();
      final open = await store.openPurchaseInvoicesForSupplier('supplier a');
      expect(open, hasLength(2));
      expect(open.first['doc_no'], 'PUR-20261101-0001');
      expect(Num.toDouble(open.first['outstanding']), closeTo(50000, 0.01));
      expect(open.last['doc_no'], 'PUR-20261102-0001');
      expect(Num.toDouble(open.last['outstanding']), closeTo(27600, 0.01));
    });
  });

  group('supplier ledger', () {
    test('purchases credit, payments debit and the payable runs forward',
        () async {
      await seedSupplierBook();
      final rows = await store.ledgerForSupplier('SUPPLIER A');

      // Newest first.
      expect(rows, hasLength(4));
      expect(rows[0].isPurchase, isFalse);
      expect(rows[0].date, '2026-11-03');
      expect(rows[0].debit, closeTo(50000, 0.01));
      expect(rows[0].balance, closeTo(77600, 0.01));

      expect(rows[1].isPurchase, isTrue);
      expect(rows[1].credit, closeTo(27600, 0.01));
      expect(rows[1].balance, closeTo(127600, 0.01));

      expect(rows[2].isPurchase, isFalse);
      expect(rows[2].debit, closeTo(47000, 0.01));
      expect(rows[2].balance, closeTo(100000, 0.01));

      expect(rows[3].isPurchase, isTrue);
      expect(rows[3].credit, closeTo(147000, 0.01));
      expect(rows[3].balance, closeTo(147000, 0.01));
      expect(rows[3].reference, 'PUR-20261101-0001');
    });

    test('a settled supplier has a zero payable', () async {
      await seedSupplierBook();
      final rows = await store.ledgerForSupplier('Supplier B');
      expect(rows, hasLength(2));
      expect(rows[0].isPurchase, isFalse);
      expect(rows[0].debit, closeTo(69000, 0.01));
      expect(rows[0].balance, closeTo(0, 0.01));
      expect(rows[1].isPurchase, isTrue);
      expect(rows[1].balance, closeTo(69000, 0.01));
    });
  });
}
