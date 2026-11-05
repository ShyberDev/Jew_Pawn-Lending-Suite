import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/jewellery_store.dart';
import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/util/jewellery_math.dart';

/// Guards that keep money and stock from posting twice:
///
/// * an order that is already delivered cannot be delivered again;
/// * a delivered order cannot be reopened and delivered again;
/// * a credit note cannot return more metal than the sale still has.
void main() {
  late LocalDb db;
  late JewelleryStore store;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_order_guard_');
    db = LocalDb();
    await db.init(pathOverride: p.join(dir.path, 'guards.db'));
    store = JewelleryStore(db);
  });

  tearDown(() async {
    await db.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  JewelleryItemInput item({double weight = 10}) => JewelleryItemInput(
        description: 'Ring',
        metal: JewelleryStore.gold,
        grossWeight: weight,
        netWeight: weight,
        purity: 92,
        rate: 15000,
        makingMode: MakingMode.amount,
        makingValue: 0,
      );

  Future<String> readyOrder() async {
    final uuid = await store.saveInvoice(
      docType: JewelleryStore.orderDoc,
      partyName: 'Asha',
      date: DateTime(2026, 11, 1),
      metal: JewelleryStore.gold,
      items: [item()],
    );
    await store.updateOrderStatus(uuid, 'Ready');
    return uuid;
  }

  Future<double> deliveredWeight() async {
    final rows = await db.db.query('jewellery_stock_movements',
        where: 'movement_type = ?', whereArgs: ['ORDER_DELIVERY_OUT']);
    return rows.fold<double>(
        0, (sum, r) => sum + ((r['weight'] as num?)?.toDouble() ?? 0));
  }

  group('order delivery', () {
    test('a delivered order cannot be delivered twice', () async {
      final uuid = await readyOrder();
      await store.deliverOrder(
          uuid: uuid, date: DateTime(2026, 11, 5), deliveredGrossWeight: 10);
      expect(await deliveredWeight(), closeTo(-10, 0.001));

      await expectLater(
        store.deliverOrder(
            uuid: uuid, date: DateTime(2026, 11, 6), deliveredGrossWeight: 10),
        throwsA(isA<FormatException>()),
      );
      expect(await deliveredWeight(), closeTo(-10, 0.001),
          reason: 'the second delivery must not move stock again');
      final invoice = await store.invoice(uuid);
      expect(invoice!['status'], 'Delivered');
      expect(invoice['delivery_date'], '2026-11-05',
          reason: 'the original delivery date must be kept');
    });

    test('a delivered order cannot be reopened', () async {
      final uuid = await readyOrder();
      await store.deliverOrder(
          uuid: uuid, date: DateTime(2026, 11, 5), deliveredGrossWeight: 10);

      await expectLater(store.updateOrderStatus(uuid, 'Ready'),
          throwsA(isA<FormatException>()));
      expect((await store.invoice(uuid))!['status'], 'Delivered');
    });
  });

  group('return guard', () {
    Future<String> sale() => store.saveInvoice(
          docType: JewelleryStore.saleDoc,
          partyName: 'Asha',
          date: DateTime(2026, 11, 1),
          metal: JewelleryStore.gold,
          items: [item()],
        );

    JewelleryReturnItemInput back(double weight) => JewelleryReturnItemInput(
          description: 'Ring',
          metal: JewelleryStore.gold,
          grossWeight: weight,
          netWeight: weight,
          purity: 92,
          rate: 15000,
          restock: true,
        );

    test('cannot return more metal than the sale holds', () async {
      final uuid = await sale();
      await store.saveReturn(
        sourceInvoiceUuid: uuid,
        date: DateTime(2026, 11, 5),
        items: [back(6)],
      );
      await expectLater(
        store.saveReturn(
          sourceInvoiceUuid: uuid,
          date: DateTime(2026, 11, 6),
          items: [back(6)],
        ),
        throwsA(isA<FormatException>()),
      );
      expect(await store.returnedWeightForInvoice(uuid), closeTo(6, 0.001));
    });

    test('a return within the remaining weight is accepted', () async {
      final uuid = await sale();
      await store.saveReturn(
        sourceInvoiceUuid: uuid,
        date: DateTime(2026, 11, 5),
        items: [back(4)],
      );
      final second = await store.saveReturn(
        sourceInvoiceUuid: uuid,
        date: DateTime(2026, 11, 6),
        items: [back(6)],
      );
      expect(second, isNotEmpty);
      expect(await store.returnedWeightForInvoice(uuid), closeTo(10, 0.001));
    });
  });
}
