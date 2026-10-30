import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/util/otp_gateway.dart';

/// #044 / #045 / #065.
///
/// * A hand-typed cashbook row can be corrected in place.
/// * A row created by Khatabook / Pawn / Jewellery is refused, because its
///   module owns the cash it produced.
/// * Month / all-time / custom ranges filter the list AND the totals.
/// * The OTP gateway reports itself unconfigured until a URL is saved.
void main() {
  late LocalDb local;
  late AppState state;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_cashbook_edit_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'cashbook.db'));
    state = AppState(local);
    await state.load();
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<List<Map<String, Object?>>> rows() => local.query('cashbook_entries');

  test('a manual entry can be corrected in place', () async {
    await state.addCashbookEntry(
      type: 'OUT',
      amount: 500,
      category: 'TEA_FOOD',
      mode: 'CASH',
      date: DateTime(2026, 10, 15),
      partyName: 'Ravi',
      notes: 'tea',
    );
    final row = (await rows()).single;
    final ok = await state.updateCashbookEntry(
      uuid: row['client_uuid'] as String,
      amount: 750,
      category: 'SHOP_EXPENSE',
      mode: 'upi',
      date: DateTime(2026, 10, 16),
      partyName: 'Ravi',
      notes: 'tea + snacks',
    );

    expect(ok, isTrue);
    final updated = (await rows()).single;
    expect(updated['amount'], 750);
    expect(updated['category'], 'SHOP_EXPENSE');
    expect(updated['payment_mode'], 'UPI');
    expect(updated['entry_date'], '2026-10-16');
    expect(updated['entry_type'], 'OUT', reason: 'an edit never flips IN/OUT');
    expect(updated['notes'], 'tea + snacks');
    expect(updated['dirty'], 1, reason: 'the change must reach the server');
  });

  test('a module-owned row is refused and left untouched', () async {
    await local.addCashbookEntry({
      'client_uuid': 'cash-khata',
      'entry_date': '2026-10-20',
      'entry_time': '10:00:00',
      'entry_type': 'IN',
      'amount': 1000.0,
      'payment_mode': 'CASH',
      'category': 'KHATA_COLLECTION',
      'reference_id': 'collection-1',
      'party_name': 'Ravi',
      'notes': '',
      'created_at': '2026-10-20T10:00:00',
      'dirty': 1,
    });

    final ok = await state.updateCashbookEntry(
      uuid: 'cash-khata',
      amount: 2000,
      category: 'OTHER_INCOME',
      mode: 'CASH',
    );

    expect(ok, isFalse);
    expect((await rows()).single['amount'], 1000.0);
  });

  test('a month / custom range filters the list and the totals', () async {
    for (final (day, amount) in [(1, 100.0), (15, 200.0), (31, 300.0)]) {
      await state.addCashbookEntry(
        type: 'IN',
        amount: amount,
        category: 'CUSTOMER_PAYMENT',
        mode: 'CASH',
        date: DateTime(2026, 10, day),
      );
    }
    await state.addCashbookEntry(
      type: 'IN',
      amount: 999,
      category: 'CUSTOMER_PAYMENT',
      mode: 'UPI',
      date: DateTime(2026, 11, 2),
    );

    final october = await state.getCashbookEntries(
        from: '2026-10-01', to: '2026-10-31');
    expect(october, hasLength(3));

    final octoberTotals = await state.getCashbookDailySummary(null,
        from: '2026-10-01', to: '2026-10-31');
    expect(octoberTotals['total_in'], 600.0);

    expect(await state.getCashbookEntries(), hasLength(4));
    expect((await state.getCashbookDailySummary(null))['total_in'], 1599.0);

    final oneDay =
        await state.getCashbookEntries(date: '2026-10-15');
    expect(oneDay, hasLength(1));
    expect(oneDay.single['amount'], 200.0);
  });

  test('the OTP gateway is unconfigured until a URL is saved', () async {
    expect(await OtpGateway.isConfigured(local), isFalse);
    expect(await OtpGateway.send(
          db: local,
          to: '9000000001',
          code: '123456',
          purpose: 'login',
        ),
        isFalse,
        reason: 'no gateway means the code must fall back to on-phone');

    await OtpGateway.configure(local,
        url: 'https://example.test/send', channel: 'email');
    expect(await OtpGateway.isConfigured(local), isTrue);
    expect(await OtpGateway.channel(local), 'email');

    await OtpGateway.clear(local);
    expect(await OtpGateway.isConfigured(local), isFalse);
    expect(await OtpGateway.channel(local), 'sms');
  });
}
