import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/jewellery_store.dart';
import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/util/jewellery_math.dart';

/// The jewellery core against the real v18 schema: rate history, document
/// totals, old metal counted once, stock movements and payment balances.
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
        p.join(Directory.systemTemp.path, 'jewellery_suite_jewellery_test.db');
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

  group('rates', () {
    test('a saved rate is kept per day and never rewritten', () async {
      final day1 = DateTime(2026, 11, 1);
      final day2 = DateTime(2026, 11, 2);
      await store.saveRate(JewelleryStore.gold, 15000, date: day1);
      await store.saveRate(JewelleryStore.gold, 16000, date: day2);

      expect(await store.rateOn(JewelleryStore.gold, day1), 15000);
      expect(await store.rateOn(JewelleryStore.gold, day2), 16000);
      expect(await store.latestRate(JewelleryStore.gold), 16000);
    });

    test('negative rates are refused', () async {
      expect(() => store.saveRate(JewelleryStore.gold, -1),
          throwsA(isA<FormatException>()));
    });
  });

  group('sale document', () {
    test('percentage-making total, cash paid and stock out', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        amountPaid: 100000,
      );
      final invoice = (await store.invoice(uuid))!;
      expect(invoice['total'], closeTo(147000, 0.01));
      expect(invoice['amount_paid'], closeTo(100000, 0.01));
      expect(invoice['outstanding'], closeTo(47000, 0.01));
      expect(invoice['doc_no'], 'SAL-20261102-0001');

      final stock = await store.stockTotals();
      expect(stock['GOLD_FINISHED'], closeTo(-10, 0.0001));

      final payments = await store.paymentsFor(uuid);
      expect(payments.length, 1);
      expect(payments.first['amount'], closeTo(100000, 0.01));
    });

    test('old metal is deducted exactly once and received into stock',
        () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        oldMetal: const OldMetalInput(
          metal: JewelleryStore.gold,
          grossWeight: 10,
          purity: 63,
          rate: 14000,
        ),
      );
      final invoice = (await store.invoice(uuid))!;
      expect(invoice['old_metal_value'], closeTo(88200, 0.01));
      expect(invoice['total'], closeTo(58800, 0.01));
      expect(invoice['outstanding'], closeTo(58800, 0.01));

      final old = (await store.oldMetalFor(uuid))!;
      expect(old['equivalent_weight'], closeTo(6.3, 0.0001));

      final stock = await store.stockTotals();
      expect(stock['GOLD_OLD'], closeTo(6.3, 0.0001));
    });

    test('the round-off is stored and reconciles', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.silver,
        items: [
          JewelleryItemInput(
            metal: JewelleryStore.silver,
            grossWeight: 15,
            netWeight: 15,
            purity: 100,
            rate: 250,
            makingMode: MakingMode.amount,
            makingValue: 500,
            discount: 500,
          ),
        ],
      );
      final invoice = (await store.invoice(uuid))!;
      expect(invoice['total'], 3750);
      expect(invoice['round_off'], closeTo(0, 0.0001));
    });

    test('documents on the same day get different sequences', () async {
      final day = DateTime(2026, 11, 2);
      for (var i = 0; i < 2; i++) {
        await store.saveInvoice(
          docType: JewelleryStore.saleDoc,
          partyName: 'Ravi',
          date: day,
          metal: JewelleryStore.gold,
          items: [goldItem()],
        );
      }
      final rows = await store.invoices(docType: JewelleryStore.saleDoc);
      final numbers = rows.map((r) => r['doc_no']).toSet();
      expect(numbers.length, 2);
      expect(numbers, containsAll(['SAL-20261102-0001', 'SAL-20261102-0002']));
    });
  });

  group('retail sale pricing', () {
    test('KDM bills net + wastage and stores purity for cost only', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [
          JewelleryItemInput(
            description: 'KDM chain',
            metal: JewelleryStore.gold,
            grossWeight: 10,
            netWeight: 10,
            purity: 80,
            rate: 15000,
            billingBasis: BillingBasis.kdm,
            wastagePct: 10,
            makingCharge: 1000,
            estimatedCost: 140000,
            actualCost: 140000,
          ),
        ],
      );
      final invoice = (await store.invoice(uuid))!;
      expect(invoice['total'], closeTo(166000, 0.01));
      expect(invoice['outstanding'], closeTo(166000, 0.01));

      final item = (await store.itemsFor(uuid)).single;
      expect(item['billing_basis'], 'kdm');
      expect(item['wastage_pct'], closeTo(10, 0.0001));
      expect(item['making_charge'], closeTo(1000, 0.01));
      expect(item['fine_weight'], closeTo(8, 0.0001));
      expect(item['line_total'], closeTo(166000, 0.01));

      // The customer bought 10 g of finished gold, so only 10 g leaves stock.
      final stock = await store.stockTotals();
      expect(stock['GOLD_FINISHED'], closeTo(-10, 0.0001));

      final profit = await store.profitSummary(
        from: DateTime(2026, 11, 2),
        to: DateTime(2026, 11, 2),
      );
      expect(profit.cost, closeTo(140000, 0.01));
      expect(profit.estimated, closeTo(26000, 0.01));
      expect(profit.finalProfit, closeTo(26000, 0.01));
    });

    test('old metal is an asset exchange, not a reduction in sale profit',
        () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [
          JewelleryItemInput(
            description: 'KDM chain',
            metal: JewelleryStore.gold,
            grossWeight: 10,
            netWeight: 10,
            purity: 80,
            rate: 15000,
            billingBasis: BillingBasis.kdm,
            wastagePct: 10,
            makingCharge: 1000,
            actualCost: 140000,
          ),
        ],
        oldMetal: const OldMetalInput(
          metal: JewelleryStore.gold,
          grossWeight: 10,
          purity: 63,
          rate: 14000,
        ),
      );
      final invoice = (await store.invoice(uuid))!;
      expect(invoice['old_metal_value'], closeTo(88200, 0.01));
      expect(invoice['total'], closeTo(77800, 0.01));

      final profit = await store.profitSummary(
        from: DateTime(2026, 11, 2),
        to: DateTime(2026, 11, 2),
      );
      expect(profit.cost, closeTo(140000, 0.01));
      expect(profit.estimated, closeTo(26000, 0.01));
      expect(profit.finalProfit, closeTo(26000, 0.01));
    });

    test('non-KDM price ignores actual purity at 60, 80 and 85 percent',
        () async {
      for (final purity in [60.0, 80.0, 85.0]) {
        final uuid = await store.saveInvoice(
          docType: JewelleryStore.saleDoc,
          partyName: 'Ravi',
          date: DateTime(2026, 11, 2),
          metal: JewelleryStore.gold,
          items: [
            JewelleryItemInput(
              description: 'Non-KDM chain',
              metal: JewelleryStore.gold,
              grossWeight: 10,
              netWeight: 10,
              purity: purity,
              rate: 15000,
              billingBasis: BillingBasis.nonKdm,
              makingCharge: 1000,
            ),
          ],
        );
        final invoice = (await store.invoice(uuid))!;
        expect(invoice['total'], closeTo(151000, 0.01),
            reason: 'purity $purity% must not change the sale price');

        final item = (await store.itemsFor(uuid)).single;
        expect(item['billing_basis'], 'nonKdm');
        expect(item['fine_weight'], closeTo(10 * purity / 100, 0.0001));
      }
    });
  });

  group('purchase document', () {
    test('adds raw stock and records the supplier payment', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Supplier',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.silver,
        items: [
          JewelleryItemInput(
            metal: JewelleryStore.silver,
            grossWeight: 15,
            netWeight: 15,
            purity: 60,
            rate: 250,
            makingMode: MakingMode.percentage,
            makingValue: 15,
          ),
        ],
        amountPaid: 1000,
      );
      final invoice = (await store.invoice(uuid))!;
      expect(invoice['total'], closeTo(2813, 0.01)); // 2812.50 → 2813
      expect(invoice['doc_no'], 'PUR-20261102-0001');

      final stock = await store.stockTotals();
      expect(stock['SILVER_RAW'], closeTo(15, 0.0001));
    });
  });

  group('stock valuation', () {
    test('values fine grams at the latest saved pure rate', () async {
      await store.saveRate(JewelleryStore.gold, 16000,
          date: DateTime(2026, 11, 1));
      await store.saveRate(JewelleryStore.silver, 250,
          date: DateTime(2026, 11, 1));

      await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Supplier',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
      );
      await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Supplier',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.silver,
        items: [
          JewelleryItemInput(
            metal: JewelleryStore.silver,
            grossWeight: 100,
            netWeight: 100,
            purity: 90,
            rate: 250,
            makingMode: MakingMode.amount,
            makingValue: 0,
          ),
        ],
      );
      await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [
          JewelleryItemInput(
            metal: JewelleryStore.gold,
            grossWeight: 1,
            netWeight: 1,
            purity: 100,
            rate: 15000,
            makingMode: MakingMode.amount,
            makingValue: 0,
          ),
        ],
        oldMetal: const OldMetalInput(
          metal: JewelleryStore.gold,
          grossWeight: 2,
          purity: 50,
          rate: 14000,
        ),
      );

      final valuation = await store.stockValuation();
      expect(valuation.goldRate, 16000);
      expect(valuation.silverRate, 250);
      expect(valuation.grams(JewelleryStore.gold, JewelleryStore.stockRaw),
          closeTo(10, 0.0001));
      expect(valuation.fineWeight(JewelleryStore.gold, JewelleryStore.stockRaw),
          closeTo(9.2, 0.0001));
      expect(valuation.valueFor(JewelleryStore.gold, JewelleryStore.stockRaw),
          closeTo(147200, 0.01));
      expect(
          valuation.fineWeight(
              JewelleryStore.gold, JewelleryStore.stockFinished),
          closeTo(-1, 0.0001));
      expect(
          valuation.valueFor(JewelleryStore.gold, JewelleryStore.stockFinished),
          closeTo(-16000, 0.01));
      expect(valuation.fineWeight(JewelleryStore.gold, JewelleryStore.stockOld),
          closeTo(1, 0.0001));
      expect(valuation.valueFor(JewelleryStore.gold, JewelleryStore.stockOld),
          closeTo(16000, 0.01));
      expect(
          valuation.fineWeight(JewelleryStore.silver, JewelleryStore.stockRaw),
          closeTo(90, 0.0001));
      expect(valuation.valueFor(JewelleryStore.silver, JewelleryStore.stockRaw),
          closeTo(22500, 0.01));

      expect(valuation.totalFineGold, closeTo(9.2, 0.0001));
      expect(valuation.totalFineSilver, closeTo(90, 0.0001));
      expect(valuation.totalValue, closeTo(169700, 0.01));
    });

    test('no saved rate leaves the fine grams but values them at zero',
        () async {
      await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Supplier',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
      );
      final valuation = await store.stockValuation();
      expect(valuation.goldRate, isNull);
      expect(valuation.silverRate, isNull);
      expect(valuation.totalFineGold, closeTo(9.2, 0.0001));
      expect(valuation.totalValue, 0);
    });
  });

  group('payments', () {
    test('paying more than the balance is refused, not hidden', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        amountPaid: 1000,
      );
      expect(
        () => store.addPayment(
          invoiceUuid: uuid,
          amount: 200000,
          date: DateTime(2026, 11, 3),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a part payment re-derives the outstanding without compounding',
        () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        amountPaid: 47000,
      );
      await store.addPayment(
        invoiceUuid: uuid,
        amount: 50000,
        date: DateTime(2026, 11, 3),
      );
      final invoice = (await store.invoice(uuid))!;
      expect(invoice['amount_paid'], closeTo(97000, 0.01));
      expect(invoice['outstanding'], closeTo(50000, 0.01));
    });
  });

  group('delete', () {
    test('removes the document, its items, payments and stock movement',
        () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        amountPaid: 1000,
      );
      final refs = await store.deleteInvoice(uuid);
      expect(refs, contains(uuid));
      expect(await store.invoice(uuid), isNull);
      expect(await store.itemsFor(uuid), isEmpty);
      expect(await store.paymentsFor(uuid), isEmpty);
      expect((await store.stockTotals())['GOLD_FINISHED'] ?? 0,
          closeTo(0, 0.0001));
    });
  });

  group('document filters', () {
    Future<void> seedDocuments() async {
      await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi Kumar',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        amountPaid: 147000,
        notes: 'Wedding set',
      );
      await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Supplier One',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem(weight: 2, makingValue: 0)],
        amountPaid: 10000,
      );
      await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Supplier Two',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.silver,
        items: [
          JewelleryItemInput(
            metal: JewelleryStore.silver,
            grossWeight: 15,
            netWeight: 15,
            purity: 60,
            rate: 250,
            makingMode: MakingMode.amount,
            makingValue: 0,
          ),
        ],
      );
      await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Meena',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.silver,
        items: [
          JewelleryItemInput(
            metal: JewelleryStore.silver,
            grossWeight: 15,
            netWeight: 15,
            purity: 100,
            rate: 250,
            makingMode: MakingMode.amount,
            makingValue: 0,
          ),
        ],
      );
    }

    test('searches doc number, party and notes case-insensitively', () async {
      await seedDocuments();
      expect(await store.invoices(search: 'ravi'), hasLength(1));
      expect(await store.invoices(search: 'wedding'), hasLength(1));
      expect(await store.invoices(search: 'pur-20261102'), hasLength(2));
    });

    test('filters by document type and metal together', () async {
      await seedDocuments();
      final purchases = await store.invoices(
          docType: JewelleryStore.purchaseDoc, metal: JewelleryStore.gold);
      expect(purchases, hasLength(1));
      expect(purchases.single['party_name'], 'Supplier One');

      final silver = await store.invoices(metal: JewelleryStore.silver);
      expect(silver, hasLength(2));
      expect(silver.map((r) => r['party_name']),
          containsAll(['Supplier Two', 'Meena']));
    });

    test('filters by payment status', () async {
      await seedDocuments();
      expect(await store.invoices(paymentStatus: 'settled'), hasLength(1));
      expect(await store.invoices(paymentStatus: 'partial'), hasLength(1));
      expect(await store.invoices(paymentStatus: 'unpaid'), hasLength(2));
      expect(await store.invoices(paymentStatus: 'open'), hasLength(3));

      final partialGoldPurchase = await store.invoices(
        docType: JewelleryStore.purchaseDoc,
        metal: JewelleryStore.gold,
        paymentStatus: 'partial',
      );
      expect(partialGoldPurchase, hasLength(1));
      expect(partialGoldPurchase.single['party_name'], 'Supplier One');
    });
  });

  group('monthly chart', () {
    Future<void> seedMonths() async {
      await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 9, 10),
        metal: JewelleryStore.gold,
        items: [goldItem()],
      );
      await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Supplier',
        date: DateTime(2026, 9, 15),
        metal: JewelleryStore.gold,
        items: [goldItem(weight: 2, makingValue: 0)],
      );
      await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 10, 5),
        metal: JewelleryStore.gold,
        items: [goldItem()],
      );
      await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Supplier',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem(weight: 2, makingValue: 0)],
      );
      await store.saveInvoice(
        docType: JewelleryStore.orderDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
      );
      await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 3),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        status: 'Cancelled',
      );
    }

    test('six months are filled oldest first and orders/cancelled are out',
        () async {
      await seedMonths();
      final months = await store.monthlyTotals(asOf: DateTime(2026, 11, 15));

      expect(months, hasLength(6));
      expect(months.map((m) => m.label),
          ['Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov']);
      expect(months[0].month, '2026-06');
      expect(months[0].sales, 0);
      expect(months[0].purchases, 0);

      expect(months[3].sales, closeTo(147000, 0.01));
      expect(months[3].purchases, closeTo(27600, 0.01));
      expect(months[4].sales, closeTo(147000, 0.01));
      expect(months[4].purchases, 0);
      expect(months[5].sales, 0,
          reason: 'the cancelled sale and the order must not chart');
      expect(months[5].purchases, closeTo(27600, 0.01));
    });

    test('a shorter window keeps only the newest months', () async {
      await seedMonths();
      final months =
          await store.monthlyTotals(months: 2, asOf: DateTime(2026, 11, 15));
      expect(months.map((m) => m.month), ['2026-10', '2026-11']);
      expect(await store.monthlyTotals(months: 0), isEmpty);
    });
  });

  group('recovery', () {
    test('a green recovery needs a recorded cost and real collections', () {
      final status = JewelleryStore.recoveryFor({
        'status': 'Active',
        'cost_total': 7000.0,
        'amount_paid': 8000.0,
      });
      expect(status, RecoveryStatus.green);
    });

    test('no recorded cost is grey, not a fake profit', () {
      expect(
        JewelleryStore.recoveryFor({
          'status': 'Active',
          'cost_total': 0,
          'amount_paid': 8000.0,
        }),
        RecoveryStatus.grey,
      );
    });
  });
}
