import 'package:sqflite/sqflite.dart';

/// Schema version 18 — the Jewellery core.
///
/// The module is deliberately split into documents (invoices), their lines,
/// money movements and stock movements instead of one wide table:
///
/// * `jewellery_rates` — one saved pure-metal rate per metal per day. History
///   is never rewritten: a line stores the rate it used.
/// * `jewellery_invoices` — sale / purchase / order header. Every document has
///   an immutable internal uuid and a readable document number.
/// * `jewellery_invoice_items` — each line keeps the weight, purity, making
///   mode/value and rate **as entered**, plus its calculated equivalents.
/// * `jewellery_payments` — one row per receipt/payment, never a silent edit of
///   the invoice total.
/// * `jewellery_old_metal` — the exchange voucher. It is the single owner of the
///   old-metal credit and of the separate old-metal stock receipt.
/// * `jewellery_stock_movements` — the only place stock changes. A movement
///   always links back to the document that caused it.
class MigrationV18 {
  const MigrationV18._();

  static const version = 18;

  static Future<void> addSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS jewellery_rates (
        metal TEXT NOT NULL,
        rate_date TEXT NOT NULL,
        pure_rate REAL NOT NULL,
        updated_at TEXT,
        PRIMARY KEY (metal, rate_date)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS jewellery_invoices (
        client_uuid TEXT PRIMARY KEY,
        server_name TEXT,
        dirty INTEGER DEFAULT 1,
        doc_no TEXT,
        doc_type TEXT NOT NULL,
        metal TEXT,
        party TEXT,
        party_name TEXT,
        invoice_date TEXT,
        making_mode TEXT,
        subtotal REAL,
        additional_total REAL,
        discount REAL,
        old_metal_value REAL,
        round_off REAL,
        total REAL,
        amount_paid REAL,
        outstanding REAL,
        cost_total REAL DEFAULT 0,
        status TEXT DEFAULT 'Active',
        notes TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_jewellery_doc_no '
        'ON jewellery_invoices(doc_no)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_jewellery_invoice_date '
        'ON jewellery_invoices(invoice_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_jewellery_party '
        'ON jewellery_invoices(party_name)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS jewellery_invoice_items (
        client_uuid TEXT PRIMARY KEY,
        invoice_uuid TEXT NOT NULL,
        description TEXT,
        metal TEXT,
        purity REAL,
        gross_weight REAL,
        net_weight REAL,
        rate_per_gram REAL,
        making_mode TEXT,
        making_value REAL,
        effective_pct REAL,
        equivalent_weight REAL,
        metal_value REAL,
        making_amount REAL,
        additional_cost REAL,
        discount REAL,
        line_total REAL,
        estimated_cost REAL DEFAULT 0,
        actual_cost REAL DEFAULT 0,
        sort_order INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_jewellery_items_invoice '
        'ON jewellery_invoice_items(invoice_uuid)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS jewellery_payments (
        client_uuid TEXT PRIMARY KEY,
        server_name TEXT,
        dirty INTEGER DEFAULT 1,
        invoice_uuid TEXT NOT NULL,
        party TEXT,
        pay_date TEXT,
        amount REAL,
        payment_mode TEXT,
        reference_no TEXT,
        notes TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_jewellery_payments_invoice '
        'ON jewellery_payments(invoice_uuid)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS jewellery_old_metal (
        client_uuid TEXT PRIMARY KEY,
        server_name TEXT,
        dirty INTEGER DEFAULT 1,
        invoice_uuid TEXT,
        customer TEXT,
        voucher_no TEXT,
        metal TEXT,
        gross_weight REAL,
        purity REAL,
        equivalent_weight REAL,
        rate_per_gram REAL,
        accepted_value REAL,
        received_date TEXT,
        notes TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_jewellery_old_invoice '
        'ON jewellery_old_metal(invoice_uuid)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS jewellery_stock_movements (
        client_uuid TEXT PRIMARY KEY,
        metal TEXT,
        movement_date TEXT,
        movement_type TEXT,
        stock_kind TEXT,
        weight REAL,
        purity REAL,
        fine_weight REAL,
        source_uuid TEXT,
        source_type TEXT,
        notes TEXT,
        created_at TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_jewellery_stock_kind '
        'ON jewellery_stock_movements(stock_kind, metal)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_jewellery_stock_source '
        'ON jewellery_stock_movements(source_uuid)');
  }
}
