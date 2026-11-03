import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/jewellery_store.dart';
import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/util/format.dart';
import 'package:jewellery_suite/util/jewellery_math.dart';

/// Jewellery operations: old-metal register, customer orders, worker ledgers,
/// linked returns, reports and the cash direction of every money movement.
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
        p.join(Directory.systemTemp.path, 'jewellery_suite_operations_test.db');
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
    double estimatedCost = 0,
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
        estimatedCost: estimatedCost,
      );

  group('wastage in metal weight', () {
    test('percentage making is shown as wastage grams', () {
      final line = JewelleryMath.line(
        weight: 10,
        purityPct: 92,
        pureRate: 15000,
        makingMode: MakingMode.percentage,
        makingValue: 6,
      );
      expect(line.wastageWeight, closeTo(0.6, 0.0005));
      expect(line.totalEquivalentWeight, closeTo(9.8, 0.0005));
      expect(line.metalValue + line.makingAmount, closeTo(147000, 0.01));
    });

    test('fixed weight making is the wastage weight itself', () {
      final line = JewelleryMath.line(
        weight: 10,
        purityPct: 92,
        pureRate: 15000,
        makingMode: MakingMode.weight,
        makingValue: 0.5,
      );
      expect(line.wastageWeight, closeTo(0.5, 0.0005));
      expect(line.totalEquivalentWeight, closeTo(9.7, 0.0005));
    });

    test('a flat rupee making charge becomes equivalent grams', () {
      final line = JewelleryMath.line(
        weight: 10,
        purityPct: 92,
        pureRate: 15000,
        makingMode: MakingMode.amount,
        makingValue: 1500,
      );
      expect(line.wastageWeight, closeTo(0.1, 0.0005));
      expect(line.totalEquivalentWeight, closeTo(9.3, 0.0005));
      expect(line.total, closeTo(139500, 0.01));
    });
  });

  group('old metal register', () {
    test('voucher, grams and accepted value are listed once', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        oldMetal: const OldMetalInput(
          metal: JewelleryStore.gold,
          grossWeight: 2,
          purity: 92,
          rate: 15000,
        ),
      );
      final invoice = (await store.invoice(uuid))!;
      expect(Num.toDouble(invoice['old_metal_value']), closeTo(27600, 0.01));
      expect(Num.toDouble(invoice['total']), closeTo(119400, 0.01));

      final totals = await store.oldMetalTotals();
      expect(totals.vouchers, 1);
      expect(totals.goldGrams, closeTo(1.84, 0.0005));
      expect(totals.acceptedValue, closeTo(27600, 0.01));

      final vouchers = await store.oldMetalVouchers();
      expect(vouchers, hasLength(1));
      expect(vouchers.single['customer'], 'Ravi');
      expect(vouchers.single['invoice_doc_no'], invoice['doc_no']);

      final searched = await store.oldMetalVouchers(search: 'rav');
      expect(searched, hasLength(1));
    });
  });

  group('customer orders', () {
    test('an order does not move stock until delivery', () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.orderDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        amountPaid: 20000,
        promisedDate: DateTime(2026, 11, 12),
        mobile: '9999999999',
        address: 'Main road',
        status: 'Pending',
      );
      final order = (await store.invoice(uuid))!;
      expect(order['promised_date'], '2026-11-12');
      expect(order['mobile'], '9999999999');
      expect(order['status'], 'Pending');
      expect(await store.stockTotals(), isEmpty);

      expect(await store.orders(), hasLength(1));
      expect((await store.orderStatusSummary())['Pending'], 1);

      await store.updateOrderStatus(uuid, 'Ready');
      expect((await store.orderStatusSummary())['Ready'], 1);
      expect(
        () => store.updateOrderStatus(uuid, 'Delivered'),
        throwsA(isA<FormatException>()),
      );
    });

    test('delivery records actual weights, money and one stock movement',
        () async {
      final uuid = await store.saveInvoice(
        docType: JewelleryStore.orderDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        amountPaid: 20000,
        status: 'Pending',
      );
      final result = await store.deliverOrder(
        uuid: uuid,
        date: DateTime(2026, 11, 5),
        deliveredGrossWeight: 10.5,
        stoneWeight: 0.5,
        extraAmount: 1000,
      );
      expect(result.extra, 1000);

      final order = (await store.invoice(uuid))!;
      expect(order['status'], 'Delivered');
      expect(Num.toDouble(order['delivered_net_weight']), closeTo(10, 0.0005));
      expect(Num.toDouble(order['difference_weight']), closeTo(0, 0.0005));
      expect(Num.toDouble(order['total']), closeTo(148000, 0.01));
      expect(Num.toDouble(order['amount_paid']), closeTo(21000, 0.01));
      expect(Num.toDouble(order['outstanding']), closeTo(127000, 0.01));

      final stock = await store.stockTotals();
      expect(stock['GOLD_FINISHED'], closeTo(-10, 0.0005));

      expect(
        () => store.deliverOrder(
          uuid: uuid,
          date: DateTime(2026, 11, 6),
          deliveredGrossWeight: 10,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('worker ledger', () {
    test('cash and metal are signed assets, never a loss', () async {
      await store.saveWorkerTransaction(
        workerName: 'Ramesh',
        date: DateTime(2026, 11, 2),
        type: 'CASH',
        cashAmount: 5000,
      );
      await store.saveWorkerTransaction(
        workerName: 'Ramesh',
        date: DateTime(2026, 11, 2),
        type: 'GOLD',
        goldWeight: 10,
        purity: 100,
      );
      await store.saveWorkerTransaction(
        workerName: 'Ramesh',
        date: DateTime(2026, 11, 3),
        type: 'GOLD',
        goldWeight: -4,
        purity: 100,
      );
      await store.saveWorkerTransaction(
        workerName: 'Ramesh',
        date: DateTime(2026, 11, 3),
        type: 'CASH',
        cashAmount: -2000,
      );

      final positions = await store.workerPositions();
      expect(positions, hasLength(1));
      expect(positions.single.name, 'Ramesh');
      expect(positions.single.cashReserve, closeTo(3000, 0.01));
      expect(positions.single.goldReserve, closeTo(6, 0.0005));
      expect(positions.single.fineGoldReserve, closeTo(6, 0.0005));
      expect(positions.single.txnCount, 4);

      final stock = await store.stockTotals();
      expect(stock['GOLD_RAW'], closeTo(-6, 0.0005));
      expect(await store.workerTransactions('Ramesh'), hasLength(4));
    });

    test('deleting a movement reverses its stock effect', () async {
      final uuid = await store.saveWorkerTransaction(
        workerName: 'Ramesh',
        date: DateTime(2026, 11, 2),
        type: 'GOLD',
        goldWeight: 10,
        purity: 100,
      );
      expect((await store.stockTotals())['GOLD_RAW'], closeTo(-10, 0.0005));
      await store.deleteWorkerTransaction(uuid);
      expect(await store.stockTotals(), isEmpty);
      expect(await store.workerTransactions('Ramesh'), isEmpty);
    });

    test('a worker order receives finished stock on delivery', () async {
      final uuid = await store.saveWorkerOrder(
        workerName: 'Ramesh',
        date: DateTime(2026, 11, 2),
        expectedDate: DateTime(2026, 11, 10),
        description: 'Necklace',
        orderedWeight: 10,
        makingMode: MakingMode.percentage,
        makingValue: 8,
      );
      expect((await store.workerOrders(workerName: 'Ramesh')), hasLength(1));

      await store.deliverWorkerOrder(
        uuid: uuid,
        date: DateTime(2026, 11, 9),
        deliveredGrossWeight: 9.5,
        stoneWeight: 0.5,
      );
      final order = (await store.workerOrders(workerName: 'Ramesh')).single;
      expect(order['status'], 'Delivered');
      expect(Num.toDouble(order['delivered_net_weight']), closeTo(9, 0.0005));
      expect((await store.stockTotals())['GOLD_FINISHED'], closeTo(9, 0.0005));
    });
  });

  group('returns', () {
    Future<String> seedSale({double paid = 100000}) => store.saveInvoice(
          docType: JewelleryStore.saleDoc,
          partyName: 'Ravi',
          date: DateTime(2026, 11, 2),
          metal: JewelleryStore.gold,
          items: [goldItem(makingMode: MakingMode.none, makingValue: 0)],
          amountPaid: paid,
        );

    test('a return is a linked credit and the sale stays unchanged', () async {
      final uuid = await seedSale();
      final returnUuid = await store.saveReturn(
        sourceInvoiceUuid: uuid,
        date: DateTime(2026, 11, 3),
        items: const [
          JewelleryReturnItemInput(
            description: 'Gold chain',
            metal: JewelleryStore.gold,
            grossWeight: 2,
            netWeight: 2,
            purity: 92,
            rate: 15000,
          ),
        ],
      );
      final invoice = (await store.invoice(uuid))!;
      expect(Num.toDouble(invoice['total']), closeTo(138000, 0.01));
      expect(Num.toDouble(invoice['outstanding']), closeTo(38000, 0.01));

      expect(await store.returnsForInvoice(uuid), closeTo(27600, 0.01));
      expect(await store.returnedWeightForInvoice(uuid), closeTo(2, 0.0005));

      final customer = (await store.creditCustomers()).single;
      expect(customer.outstanding, closeTo(10400, 0.01));

      final open = await store.openInvoicesForCustomer('Ravi');
      expect(open, hasLength(1));
      expect(Num.toDouble(open.single['outstanding']), closeTo(10400, 0.01));

      final ledger = await store.ledgerForCustomer('Ravi');
      expect(ledger.first.type, 'RETURN');
      expect(ledger.first.credit, closeTo(27600, 0.01));
      expect(ledger.first.balance, closeTo(10400, 0.01));

      final stock = await store.stockTotals();
      expect(stock['GOLD_FINISHED'], closeTo(-8, 0.0005));

      final rows = await store.returns();
      expect(rows, hasLength(1));
      expect(rows.single['return_no'], startsWith('RET-'));
      expect(await store.returnItems(returnUuid), hasLength(1));

      // A receipt can only cover the balance left after the return credit.
      expect(
        () => store.addPayment(
          invoiceUuid: uuid,
          amount: 10401,
          date: DateTime(2026, 11, 4),
        ),
        throwsA(isA<FormatException>()),
      );
      await store.addPayment(
        invoiceUuid: uuid,
        amount: 10400,
        date: DateTime(2026, 11, 4),
      );
    });

    test('deleting a return reverses stock and credit', () async {
      final uuid = await seedSale();
      final returnUuid = await store.saveReturn(
        sourceInvoiceUuid: uuid,
        date: DateTime(2026, 11, 3),
        items: const [
          JewelleryReturnItemInput(
            description: 'Gold chain',
            metal: JewelleryStore.gold,
            grossWeight: 2,
            netWeight: 2,
            purity: 92,
            rate: 15000,
          ),
        ],
      );
      await store.deleteReturn(returnUuid);
      expect(await store.returnsForInvoice(uuid), 0);
      expect((await store.creditCustomers()).single.outstanding,
          closeTo(38000, 0.01));
      expect(
          (await store.stockTotals())['GOLD_FINISHED'], closeTo(-10, 0.0005));
    });
  });

  group('reports', () {
    test('date range, returns and profit read the same documents', () async {
      final sale = await store.saveInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 1),
        metal: JewelleryStore.gold,
        items: [goldItem(estimatedCost: 100000)],
        amountPaid: 100000,
      );
      await store.saveInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Supplier',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
      );
      await store.saveReturn(
        sourceInvoiceUuid: sale,
        date: DateTime(2026, 11, 3),
        items: const [
          JewelleryReturnItemInput(
            description: 'Gold chain',
            metal: JewelleryStore.gold,
            grossWeight: 2,
            netWeight: 2,
            purity: 92,
            rate: 15000,
          ),
        ],
        refundAmount: 5000,
      );

      final totals = await store.reportTotals(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 3),
      );
      expect(totals.sales, closeTo(147000, 0.01));
      expect(totals.purchases, closeTo(147000, 0.01));
      expect(totals.collections, closeTo(100000, 0.01));
      expect(totals.returns, closeTo(27600, 0.01));
      expect(totals.refunds, closeTo(5000, 0.01));
      expect(totals.outstandingSales, closeTo(24400, 0.01));
      expect(totals.outstandingPurchases, closeTo(147000, 0.01));
      expect(totals.saleCount, 1);
      expect(totals.purchaseCount, 1);

      final profit = await store.profitSummary(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 3),
      );
      expect(profit.cost, closeTo(100000, 0.01));
      expect(profit.estimated, closeTo(24400, 0.01));
      expect(profit.finalProfit, closeTo(24400, 0.01));

      final outside = await store.reportTotals(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
      );
      expect(outside.sales, 0);
      expect(outside.purchases, 0);
    });
  });

  group('cash direction', () {
    late LocalDb local;
    late AppState state;
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('js_jewellery_ops_cash_');
      local = LocalDb();
      await local.init(pathOverride: p.join(dir.path, 'cash.db'));
      state = AppState(local);
    });

    tearDown(() async {
      await local.db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('purchase advance is OUT and order advance is IN', () async {
      await state.saveJewelleryInvoice(
        docType: JewelleryStore.purchaseDoc,
        partyName: 'Supplier',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        amountPaid: 5000,
      );
      await state.saveJewelleryInvoice(
        docType: JewelleryStore.orderDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        amountPaid: 20000,
      );

      final rows = await local.query('cashbook_entries');
      expect(rows, hasLength(2));
      final purchase =
          rows.firstWhere((r) => r['category'] == 'JEWELLERY_PURCHASE');
      expect(purchase['entry_type'], 'OUT');
      expect(purchase['amount'], 5000.0);
      final order = rows.firstWhere((r) => r['category'] == 'JEWELLERY_ORDER');
      expect(order['entry_type'], 'IN');
      expect(order['amount'], 20000.0);
    });

    test('order delivery extra is IN, refund is OUT', () async {
      final orderUuid = await state.saveJewelleryInvoice(
        docType: JewelleryStore.orderDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        amountPaid: 20000,
      );
      await state.deliverJewelleryOrder(
        orderUuid: orderUuid,
        date: DateTime(2026, 11, 5),
        deliveredGrossWeight: 10,
        extraAmount: 1000,
        refundAmount: 500,
      );
      final rows = await local.query('cashbook_entries');
      final extra = rows.where((r) => r['amount'] == 1000.0).single;
      expect(extra['entry_type'], 'IN');
      final refund = rows.where((r) => r['amount'] == 500.0).single;
      expect(refund['entry_type'], 'OUT');
      expect(refund['category'], 'JEWELLERY_RETURN');
    });

    test('return refund is OUT and worker cash follows its sign', () async {
      final saleUuid = await state.saveJewelleryInvoice(
        docType: JewelleryStore.saleDoc,
        partyName: 'Ravi',
        date: DateTime(2026, 11, 2),
        metal: JewelleryStore.gold,
        items: [goldItem()],
        amountPaid: 100000,
      );
      await state.saveJewelleryReturn(
        sourceInvoiceUuid: saleUuid,
        date: DateTime(2026, 11, 3),
        items: const [
          JewelleryReturnItemInput(
            description: 'Gold chain',
            metal: JewelleryStore.gold,
            grossWeight: 2,
            netWeight: 2,
            purity: 92,
            rate: 15000,
          ),
        ],
        refundAmount: 5000,
      );
      await state.saveJewelleryWorkerTransaction(
        workerName: 'Ramesh',
        date: DateTime(2026, 11, 3),
        type: 'CASH',
        cashAmount: 5000,
      );
      await state.saveJewelleryWorkerTransaction(
        workerName: 'Ramesh',
        date: DateTime(2026, 11, 4),
        type: 'CASH',
        cashAmount: -2000,
      );

      final rows = await local.query('cashbook_entries');
      final refund = rows.firstWhere(
          (r) => r['category'] == 'JEWELLERY_RETURN' && r['amount'] == 5000.0);
      expect(refund['entry_type'], 'OUT');
      final paid = rows.firstWhere(
          (r) => r['category'] == 'JEWELLERY_WORKER' && r['amount'] == 5000.0);
      expect(paid['entry_type'], 'OUT');
      final returned = rows.firstWhere(
          (r) => r['category'] == 'JEWELLERY_WORKER' && r['amount'] == 2000.0);
      expect(returned['entry_type'], 'IN');
    });
  });
}
