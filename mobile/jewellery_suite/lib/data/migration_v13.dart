import 'package:sqflite/sqflite.dart';

/// Schema version 13 — activity timestamp.
///
/// The member row shows how recently real money moved ("12 min ago",
/// "2 days ago"). The generic `updated_at` cannot drive this: it changes on
/// every save, including edits that move no money. So money actions stamp
/// their own field instead:
///
/// * `customers.last_activity_at TEXT` — nullable, written only by Collect,
///   You Gave (any type), Unpaid/Unavailable marking, interest changes,
///   refinance, and collection/given edits and deletes.
///
/// A fresh install starts with NULL (no recency shown); the first money
/// action starts the clock. Additive and idempotent like every migration.
class MigrationV13 {
  const MigrationV13._();

  static const version = 13;

  static Future<void> addSchema(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(customers)');
    if (!cols.any((c) => '${c['name']}' == 'last_activity_at')) {
      await db.execute(
          'ALTER TABLE customers ADD COLUMN last_activity_at TEXT');
    }
  }
}
