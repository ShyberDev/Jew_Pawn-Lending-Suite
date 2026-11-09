import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/features/authentication/cloud/cloud_sync.dart';

/// The merge rule is the only part of cloud sync that can silently lose or
/// duplicate a shop's stock, so it is pinned here without needing Firebase.
void main() {
  test('a remote row wins only when its stamp is newer', () {
    expect(CloudSync.remoteIsNewer('2026-11-01T10:00:00.000', '2026-11-01T10:00:01.000'), isTrue);
    expect(CloudSync.remoteIsNewer('2026-11-01T10:00:01.000', '2026-11-01T10:00:00.000'), isFalse);
    expect(CloudSync.remoteIsNewer('2026-11-01T10:00:00.000', '2026-11-01T10:00:00.000'), isFalse,
        reason: 'an equal stamp must not overwrite the local edit');
  });

  test('a row with no local stamp is always accepted', () {
    expect(CloudSync.remoteIsNewer(null, '2026-11-01T10:00:00.000'), isTrue);
    expect(CloudSync.remoteIsNewer('', '2026-11-01T10:00:00.000'), isTrue);
  });

  test('a remote row with no stamp never overwrites local data', () {
    expect(CloudSync.remoteIsNewer('2026-11-01T10:00:00.000', null), isFalse);
    expect(CloudSync.remoteIsNewer('2026-11-01T10:00:00.000', ''), isFalse);
  });

  test('every stock / worker row gets a firestore-safe UTC updated_at', () {
    final doc = CloudSync.docFor({
      'client_uuid': 'abc',
      'weight': 12.5,
      'created_at': '2026-11-01T10:00:00.000',
      'notes': null,
    });
    final stamp = doc['updated_at'] as String;
    expect(stamp.endsWith('Z'), isTrue,
        reason: 'the boundary is UTC, so two phones agree on "later"');
    expect(DateTime.parse(stamp).isAtSameMomentAs(
            DateTime.parse('2026-11-01T10:00:00.000')),
        isTrue);
    expect(doc['weight'], 12.5);
    expect(doc.containsKey('notes'), isTrue);
    expect(doc['created_at'], stamp,
        reason: 'instants are normalised at the boundary too');
  });

  test('a movement is never replaced, but a worker row can be', () {
    final movement = CloudSync.mirrors
        .firstWhere((m) => m.table == 'jewellery_stock_movements');
    expect(movement.immutable, isTrue);
    final worker =
        CloudSync.mirrors.firstWhere((m) => m.table == 'jewellery_worker_txns');
    expect(worker.immutable, isFalse);
  });

  test('the shop id is the signed-in account', () {
    expect(CloudSync.shopIdFor('uid-123'), 'uid-123');
  });
}
