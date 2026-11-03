import 'package:sqflite/sqflite.dart';

/// Schema version 20 — retail sale pricing.
///
/// A sale line now stores **how it was priced**, separately from the purity
/// used for cost:
///
/// * `billing_basis` — `raw` (old purchase-style lines), `kdm` (net + wastage)
///   or `nonKdm` (net weight only).
/// * `wastage_pct` — the KDM wastage percentage.
/// * `making_charge` — the flat rupee making charge used by retail lines.
/// * `fine_weight` — net × actual purity, the metal content used for cost and
///   profit. It never changes the retail selling price.
///
/// Existing rows default to `raw`, so their historical totals keep using the
/// old purity-based formula and are never recalculated.
class MigrationV20 {
  const MigrationV20._();

  static const version = 20;

  static Future<void> addSchema(Database db) async {
    for (final sql in const [
      "ALTER TABLE jewellery_invoice_items ADD COLUMN billing_basis TEXT DEFAULT 'raw'",
      'ALTER TABLE jewellery_invoice_items ADD COLUMN wastage_pct REAL DEFAULT 0',
      'ALTER TABLE jewellery_invoice_items ADD COLUMN making_charge REAL DEFAULT 0',
      'ALTER TABLE jewellery_invoice_items ADD COLUMN fine_weight REAL DEFAULT 0',
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {
        // Column already present on a fresh install or a repeated migration.
      }
    }
  }
}
