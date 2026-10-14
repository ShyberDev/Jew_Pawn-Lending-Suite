import 'package:sqflite/sqflite.dart';

/// Schema version 14 — Cashbook module.
///
/// Adds daily Cash IN / Cash OUT ledger (`cashbook_entries`) tracking:
/// - Daily income/expense transactions
/// - Automatic hooks from Khatabook collections & Pawn disbursements/repayments
/// - Payment mode (Cash, UPI, Bank) and category tracking.
class MigrationV14 {
  const MigrationV14._();

  static const version = 14;

  static Future<void> addSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cashbook_entries (
        client_uuid TEXT PRIMARY KEY,
        server_name TEXT,
        dirty INTEGER DEFAULT 1,
        entry_date TEXT NOT NULL,
        entry_time TEXT NOT NULL,
        entry_type TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_mode TEXT NOT NULL,
        category TEXT NOT NULL,
        reference_id TEXT,
        party_name TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cashbook_date ON cashbook_entries(entry_date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cashbook_category ON cashbook_entries(category)');
  }
}
