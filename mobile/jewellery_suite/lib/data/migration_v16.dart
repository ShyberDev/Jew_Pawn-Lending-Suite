import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

/// v16: pawn loan categories.
///
/// The shop asked for a third way to group pledges beside Active / Released
/// and Villages: free-form categories such as **Forgot_Slip_List** and
/// **Pawn_Removed**, plus any custom ones the shop adds later. A loan carries
/// one nullable `category` name; the names themselves live in
/// `pawn_categories` so they can be renamed without touching every loan.
class MigrationV16 {
  static const version = 16;

  /// Categories every shop starts with. They are ordinary rows, so the shop
  /// can rename or delete them later.
  static const defaultCategories = <String>[
    'Forgot_Slip_List',
    'Pawn_Removed',
  ];

  static Future<void> addSchema(Database db) async {
    // Fresh installs get this column from the CREATE TABLE, upgrades from the
    // ALTER. Either way a duplicate-column error is harmless.
    try {
      await db.execute('ALTER TABLE pawn_loans ADD COLUMN category TEXT');
    } catch (_) {/* column already present */}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pawn_categories (
        name TEXT PRIMARY KEY, sort_order INTEGER, created_at TEXT
      )
    ''');

    // Seed only on an empty table, so deleting a default category is not
    // undone on the next launch.
    final count = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM pawn_categories');
    if (((count.first['c'] as int?) ?? 0) > 0) return;
    final now = DateTime.now().toIso8601String();
    for (var i = 0; i < defaultCategories.length; i++) {
      await db.insert(
        'pawn_categories',
        {'name': defaultCategories[i], 'sort_order': i, 'created_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    debugPrint('[db] migration v16: pawn categories seeded '
        '(${defaultCategories.length})');
  }
}
