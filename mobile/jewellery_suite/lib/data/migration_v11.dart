import 'package:sqflite/sqflite.dart';

/// Schema version 11 — payment types.
///
/// Adds the two columns that make Monthly Interest-Only loans possible:
///
/// * `khatabook_loans.payment_type` — `INSTALLMENT` (default) or
///   `INTEREST_ONLY`. Nothing else is valid; unknown values read as
///   `INSTALLMENT`.
/// * `khatabook_loans.current_interest` — the per-period interest currently in
///   force. For installment loans it is unused. For interest-only loans it is
///   the amount each period bills, editable at any time: changing it affects
///   only periods billed afterwards, never history.
/// * `khatabook_collections.interest_period` — nullable. Set only when a
///   collection explicitly prepays a *future* interest period, so a later
///   delete/edit can put that period back to unpaid instead of guessing.
///
/// Additive and idempotent like every migration before it.
class MigrationV11 {
  const MigrationV11._();

  static const version = 11;

  static const installment = 'INSTALLMENT';
  static const interestOnly = 'INTEREST_ONLY';

  static Future<void> addSchema(Database db) async {
    await _addColumn(db, 'khatabook_loans', 'payment_type', 'TEXT');
    await _addColumn(db, 'khatabook_loans', 'current_interest', 'REAL');
    await _addColumn(db, 'khatabook_collections', 'interest_period', 'INTEGER');
  }

  /// Existing loans predate payment types: every one of them is an installment
  /// loan, and its per-period interest is its stored interest figure.
  static Future<int> backfill(Database db) async {
    final loans = await db.query('khatabook_loans',
        where: 'payment_type IS NULL OR payment_type = ?', whereArgs: ['']);
    for (final l in loans) {
      await db.update(
        'khatabook_loans',
        {
          'payment_type': installment,
          'current_interest': (l['interest_amount'] as num?)?.toDouble() ?? 0,
        },
        where: 'client_uuid = ?',
        whereArgs: [l['client_uuid']],
      );
    }
    return loans.length;
  }

  static Future<void> _addColumn(
      Database db, String table, String column, String type) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((c) => '${c['name']}' == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }

  /// The effective payment type of a loan row. Unknown and missing values read
  /// as installment loans, so pre-v11 rows behave exactly as before.
  static String paymentTypeOf(Map<String, Object?> loan) {
    final raw = '${loan['payment_type'] ?? ''}'.toUpperCase();
    return raw == interestOnly ? interestOnly : installment;
  }

  static bool isInterestOnly(Map<String, Object?> loan) =>
      paymentTypeOf(loan) == interestOnly;
}
