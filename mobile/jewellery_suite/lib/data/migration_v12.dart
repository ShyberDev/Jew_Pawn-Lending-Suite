import 'package:sqflite/sqflite.dart';

/// Schema version 12 — Loss Khata origin tracking.
///
/// Loss Khata is one more row in the existing Khata list, not a new system:
/// moving a customer to Loss only rewrites their `village`. This migration
/// adds the single column that remembers where they came from so the Loss
/// list can show it:
///
/// * `customers.previous_village TEXT` — nullable, set on move-to-Loss,
///   cleared on move-back. Nothing else reads or writes it.
///
/// Additive and idempotent like every migration before it.
class MigrationV12 {
  const MigrationV12._();

  static const version = 12;

  /// Reserved identity of the Loss Khata village row.
  static const lossVillageUuid = 'loss-khata';
  static const lossVillageName = 'Loss';

  static Future<void> addSchema(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(customers)');
    if (!cols.any((c) => '${c['name']}' == 'previous_village')) {
      await db.execute(
          'ALTER TABLE customers ADD COLUMN previous_village TEXT');
    }
  }

  static bool isLossVillageName(String? name) =>
      (name ?? '').trim().toLowerCase() == 'loss';

  static bool isLossKhata(String? khataName) =>
      isLossVillageName(khataName);
}
