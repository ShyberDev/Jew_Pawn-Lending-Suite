import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

/// v17: pawn loan due dates (promised vs actual) and the pawn-move password.
///
/// The shop asked for two related things:
/// - a **Due Date (promised)** on the pawn loan form, already present, now also
///   shown on the profile next to a separate **Actual Due Date**;
/// - an **Outstanding** that always refers to the actual due date, recalculated
///   when the shop updates the dates.
///
/// The profile currently falls back to the promised due date when the actual
/// column is null, so existing loans still show a useful figure before the
/// first recalc. The schema adds two nullable columns so both can be stored
/// independently; the migration copies nothing by default so a loan's existing
/// dates are left exactly as they were until the shop edits them.
///
/// v17 later gained the pawn loan categories feature too, because a fresh
/// install needs those seeded rows from the same first-launch migration. For
/// upgrades the category column comes from MigrationV16; this class only adds
/// the category table + seed when it is missing so upgrades are not blocked.
class MigrationV17 {
  static const version = 17;

  static Future<void> addSchema(Database db) async {
    // Fresh installs get these columns from the CREATE TABLE; upgrades use the
    // ALTER. A duplicate-column error is harmless either way.
    for (final sql in [
      'ALTER TABLE pawn_loans ADD COLUMN pawn_due_promised TEXT',
      'ALTER TABLE pawn_loans ADD COLUMN pawn_due_actual TEXT',
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {/* column already present */}
    }

    // The pawn-move password is the same admin secret the app already stores,
    // just registered under its own toggle id so it can be set to the admin
    // password or a dedicated move secret from Password Settings. The actual
    // value is still the salted hash in settings — nothing stored here.
  }

  /// Seeded pawn categories. The loan list already reads the category from
  /// pawn_loans; this only keeps the category table itself present so a fresh
  /// install does not end up with a category filter that can never be filled.
  ///
  /// v16 owns the pawn_loans.category column; v17 owns this table only when a
  /// fresh install skips the v16 upgrade path.
  static Future<void> ensureCategories(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pawn_categories (
        name TEXT PRIMARY KEY, sort_order INTEGER, created_at TEXT
      )
    ''');

    final count = await db.rawQuery('SELECT COUNT(*) AS c FROM pawn_categories');
    if (((count.first['c'] as int?) ?? 0) > 0) return;

    final now = DateTime.now().toIso8601String();
    final seed = <String>['Forgot_Slip_List', 'Pawn_Removed'];
    for (var i = 0; i < seed.length; i++) {
      await db.insert(
        'pawn_categories',
        {'name': seed[i], 'sort_order': i, 'created_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    debugPrint('[db] v17: pawn categories seeded ($seed).');
  }
}
