import 'package:sqflite/sqflite.dart';

/// Schema version 19 — jewellery operations.
///
/// Adds the fields a customer order needs at delivery, plus three ledgers that
/// are deliberately separate from invoices:
///
/// * `jewellery_worker_orders` — work given to a worker, with ordered and
///   delivered weights. A worker order may link to a customer order.
/// * `jewellery_worker_txns` — signed cash/gold movements. Positive cash means
///   the shop paid the worker; positive gold means the shop issued metal.
/// * `jewellery_returns` / `jewellery_return_items` — a linked credit note.
///   The original sale invoice is never rewritten.
class MigrationV19 {
  const MigrationV19._();

  static const version = 19;

  static Future<void> addSchema(Database db) async {
    // Order/delivery fields on the existing document header. SQLite has no
    // `ADD COLUMN IF NOT EXISTS`, so each statement is guarded.
    for (final sql in const [
      'ALTER TABLE jewellery_invoices ADD COLUMN promised_date TEXT',
      'ALTER TABLE jewellery_invoices ADD COLUMN delivery_date TEXT',
      'ALTER TABLE jewellery_invoices ADD COLUMN delivered_gross_weight REAL',
      'ALTER TABLE jewellery_invoices ADD COLUMN stone_weight REAL',
      'ALTER TABLE jewellery_invoices ADD COLUMN delivered_net_weight REAL',
      'ALTER TABLE jewellery_invoices ADD COLUMN difference_weight REAL',
      'ALTER TABLE jewellery_invoices ADD COLUMN extra_amount REAL DEFAULT 0',
      'ALTER TABLE jewellery_invoices ADD COLUMN refund_amount REAL DEFAULT 0',
      'ALTER TABLE jewellery_invoices ADD COLUMN mobile TEXT',
      'ALTER TABLE jewellery_invoices ADD COLUMN address TEXT',
      'ALTER TABLE jewellery_invoices ADD COLUMN photo_path TEXT',
      'ALTER TABLE jewellery_invoices ADD COLUMN slip_photo_path TEXT',
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {
        // Column already present on a fresh install or a repeated migration.
      }
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS jewellery_worker_orders (
        client_uuid TEXT PRIMARY KEY,
        server_name TEXT,
        dirty INTEGER DEFAULT 1,
        worker_name TEXT,
        order_uuid TEXT,
        order_date TEXT,
        expected_date TEXT,
        delivered_date TEXT,
        metal TEXT,
        item_description TEXT,
        ordered_weight REAL,
        delivered_gross_weight REAL,
        stone_weight REAL,
        delivered_net_weight REAL,
        making_mode TEXT,
        making_value REAL,
        additional_cost REAL,
        cash_paid REAL DEFAULT 0,
        metal_paid REAL DEFAULT 0,
        status TEXT DEFAULT 'Pending',
        notes TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_jewellery_worker_order '
        'ON jewellery_worker_orders(worker_name, order_date)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS jewellery_worker_txns (
        client_uuid TEXT PRIMARY KEY,
        server_name TEXT,
        dirty INTEGER DEFAULT 1,
        worker_name TEXT,
        order_uuid TEXT,
        txn_date TEXT,
        txn_type TEXT,
        cash_amount REAL DEFAULT 0,
        gold_weight REAL DEFAULT 0,
        rate_per_gram REAL,
        purity REAL DEFAULT 100,
        notes TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_jewellery_worker_txn '
        'ON jewellery_worker_txns(worker_name, txn_date)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS jewellery_returns (
        client_uuid TEXT PRIMARY KEY,
        server_name TEXT,
        dirty INTEGER DEFAULT 1,
        return_no TEXT,
        source_invoice_uuid TEXT,
        party_name TEXT,
        return_date TEXT,
        metal TEXT,
        total REAL DEFAULT 0,
        refund_amount REAL DEFAULT 0,
        restock INTEGER DEFAULT 1,
        notes TEXT,
        updated_at TEXT
      )
    ''');
    await db
        .execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_jewellery_return_no '
            'ON jewellery_returns(return_no)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_jewellery_return_source '
        'ON jewellery_returns(source_invoice_uuid)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS jewellery_return_items (
        client_uuid TEXT PRIMARY KEY,
        return_uuid TEXT NOT NULL,
        description TEXT,
        metal TEXT,
        gross_weight REAL,
        net_weight REAL,
        purity REAL,
        rate_per_gram REAL,
        value REAL,
        restock INTEGER DEFAULT 1,
        sort_order INTEGER
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_jewellery_return_items '
        'ON jewellery_return_items(return_uuid)');
  }
}
