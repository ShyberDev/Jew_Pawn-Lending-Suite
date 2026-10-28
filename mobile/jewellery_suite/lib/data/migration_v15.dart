import 'package:sqflite/sqflite.dart';

/// Schema version 15 — payment mode on "You Gave" entries.
///
/// The You Gave dialog has offered Cash / UPI / Bank since v1.0.23 and the
/// cashbook auto-hook reads `payment_mode` from the row. The table itself never
/// got the column, so every You Gave save after the first loan failed with
/// "table khatabook_given has no column named payment_mode" — and because the
/// save is async and unguarded, the screen simply did nothing.
///
/// Additive and idempotent, like every migration.
class MigrationV15 {
  const MigrationV15._();

  static const version = 15;

  static Future<void> addSchema(Database db) async {
    const table = 'khatabook_given';
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (!cols.any((c) => '${c['name']}' == 'payment_mode')) {
      await db.execute('ALTER TABLE $table ADD COLUMN payment_mode TEXT');
    }
  }
}
