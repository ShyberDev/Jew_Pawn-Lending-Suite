import 'package:sqflite/sqflite.dart';

/// Schema version 21 — draft purchases, shared expenses and late fees.
///
/// * `jewellery_invoices.shared_expense` — one amount for the whole document
///   (freight, hallmarking, stones for the lot). It is split across the lines
///   by net weight when the document is saved, so the lines still add up.
/// * `jewellery_invoices.late_fee_total` — the sum of manual late fees. The
///   item total and recorded cost are never rewritten; only `outstanding` grows.
/// * `jewellery_charges` — one row per manual fee, kept as the audit trail the
///   ledger reads. Nothing here is generated automatically.
class MigrationV21 {
  const MigrationV21._();

  static const version = 21;

  static Future<void> addSchema(Database db) async {
    for (final sql in const [
      'ALTER TABLE jewellery_invoices ADD COLUMN shared_expense REAL DEFAULT 0',
      'ALTER TABLE jewellery_invoices ADD COLUMN late_fee_total REAL DEFAULT 0',
      '''CREATE TABLE IF NOT EXISTS jewellery_charges (
        client_uuid TEXT PRIMARY KEY,
        invoice_uuid TEXT NOT NULL,
        party TEXT,
        charge_date TEXT,
        amount REAL DEFAULT 0,
        note TEXT,
        dirty INTEGER DEFAULT 1,
        updated_at TEXT
      )''',
      'CREATE INDEX IF NOT EXISTS idx_jewellery_charges_party '
          'ON jewellery_charges(party)',
      'CREATE INDEX IF NOT EXISTS idx_jewellery_charges_invoice '
          'ON jewellery_charges(invoice_uuid)',
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {
        // Column or table already present on a fresh install or a repeated run.
      }
    }
  }
}
