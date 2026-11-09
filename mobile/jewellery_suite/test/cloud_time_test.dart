import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/features/authentication/cloud/cloud_time.dart';

/// P5 — the sync boundary speaks UTC, the phone keeps its local wall clock.
void main() {
  test('a boundary stamp is UTC and is the same instant as the local value',
      () {
    final local = DateTime(2026, 11, 9, 11, 30, 15);
    final boundary = CloudTime.toBoundary(local.toIso8601String());
    expect(boundary, isNotNull);
    expect(boundary!.endsWith('Z'), isTrue,
        reason: 'Firestore documents must carry an unambiguous instant');
    expect(DateTime.parse(boundary).isAtSameMomentAs(local), isTrue);
  });

  test('a pulled stamp comes back as local wall clock with no zone', () {
    final stored = CloudTime.toLocalStamp('2026-11-09T06:00:00.000Z');
    expect(stored, isNotNull);
    expect(stored!.endsWith('Z'), isFalse,
        reason: 'the column mixes with DateTime.now().toIso8601String() rows');
    expect(DateTime.parse(stored).isAtSameMomentAs(
        DateTime.parse('2026-11-09T06:00:00.000Z')), isTrue);
  });

  test('the local and UTC forms of one instant are not "newer" than each other',
      () {
    final local = DateTime(2026, 11, 9, 11, 30);
    final utc = local.toUtc().toIso8601String();
    expect(CloudTime.isNewer(local.toIso8601String(), utc), isFalse);
    expect(CloudTime.isNewer(utc, local.toIso8601String()), isFalse);
    expect(
        CloudTime.isNewer(
            local.toIso8601String(), local.add(const Duration(milliseconds: 1)).toUtc().toIso8601String()),
        isTrue);
    expect(
        CloudTime.isNewer(
            utc, local.subtract(const Duration(milliseconds: 1)).toIso8601String()),
        isFalse);
  });

  test('an offset stamp is compared as an instant, not as text', () {
    // 11:30 in IST is 06:00 UTC.
    const ist = '2026-11-09T11:30:00.000+05:30';
    expect(CloudTime.isNewer('2026-11-09T06:00:00.000Z', ist), isFalse);
    expect(CloudTime.isNewer('2026-11-09T05:59:59.999Z', ist), isTrue);
    expect(CloudTime.isNewer(ist, '2026-11-09T06:00:00.001Z'), isTrue);
  });

  test('missing stamps keep the safer side', () {
    expect(CloudTime.isNewer(null, '2026-11-09T06:00:00.000Z'), isTrue);
    expect(CloudTime.isNewer('', '2026-11-09T06:00:00.000Z'), isTrue);
    expect(CloudTime.isNewer('2026-11-09T06:00:00.000Z', null), isFalse);
    expect(CloudTime.isNewer('2026-11-09T06:00:00.000Z', ''), isFalse);
    expect(CloudTime.isNewer('2026-11-09T06:00:00.000Z', 'not a date'), isFalse);
    expect(CloudTime.isNewer('not a date', '2026-11-09T06:00:00.000Z'), isTrue,
        reason: 'an unreadable local stamp loses to a real remote one');
  });

  test('only instants are normalised, business dates are left alone', () {
    expect(CloudTime.isStamp('created_at'), isTrue);
    expect(CloudTime.isStamp('updated_at'), isTrue);
    expect(CloudTime.isStamp('movement_date'), isFalse);
    expect(CloudTime.isStamp('order_date'), isFalse);
  });
}
