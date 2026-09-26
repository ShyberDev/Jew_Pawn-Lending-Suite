import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local, offline-first store. Every entity carries a `client_uuid` so it can be
/// pushed to the server idempotently, plus `server_name` once the server has it
/// and `dirty` while it still needs pushing.
///
/// Column names mirror the server DocType field names so pull/push is a simple
/// field copy (see `sync_service.dart`).
class LocalDb {
  Database? _db;

  Database get db => _db!;

  Future<void> init() async {
    // Web (wasm SQLite) has no path concept — open by plain filename.
    final file = kIsWeb
        ? 'jewellery_suite.db'
        : p.join(await getDatabasesPath(), 'jewellery_suite.db');
    _db = await openDatabase(
      file,
      version: 7,
      onCreate: _create,
      onUpgrade: _upgrade,
    );
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Khata type for village groups (Village / Personal / Business).
      try {
        await db
            .execute('ALTER TABLE villages ADD COLUMN khata_type TEXT');
      } catch (_) {/* column already present */}
    }
    if (oldVersion < 3) {
      // v3: google-pin location on villages, ID photo front/back on customers,
      // and the "You Gave" extra-amount ledger table (fees / late interest).
      try {
        await db.execute('ALTER TABLE villages ADD COLUMN latitude REAL');
      } catch (_) {/* column already present */}
      try {
        await db.execute('ALTER TABLE villages ADD COLUMN longitude REAL');
      } catch (_) {/* column already present */}
      try {
        await db
            .execute('ALTER TABLE customers ADD COLUMN id_photo_front TEXT');
      } catch (_) {/* column already present */}
      try {
        await db
            .execute('ALTER TABLE customers ADD COLUMN id_photo_back TEXT');
      } catch (_) {/* column already present */}
      await db.execute('''
        CREATE TABLE IF NOT EXISTS khatabook_given (
          client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
          customer TEXT, customer_name TEXT, village TEXT, khatabook_loan TEXT,
          given_date TEXT, amount REAL, note TEXT, updated_at TEXT
        )
      ''');
    }
    if (oldVersion < 4) {
      // v4: collection reminder date on customers + "You Gave" type
      // (principal / late_fee / interest) so reports can distinguish them.
      try {
        await db.execute('ALTER TABLE customers ADD COLUMN reminder_date TEXT');
      } catch (_) {/* column already present */}
      try {
        await db.execute('ALTER TABLE khatabook_given ADD COLUMN given_type TEXT');
      } catch (_) {/* column already present */}
    }
    if (oldVersion < 5) {
      // v5: refinance records (already in _create for fresh installs) and the
      // activity history log (deletions + recent transactions, with retention).
      await db.execute('''
        CREATE TABLE IF NOT EXISTS khatabook_refinances (
          client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
          khatabook_loan TEXT, customer TEXT, refinance_date TEXT,
          old_outstanding REAL, new_principal REAL, new_interest_amount REAL,
          new_installment_count INTEGER, new_interest_note TEXT, new_loan TEXT,
          remarks TEXT, updated_at TEXT
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_refinances_loan '
          'ON khatabook_refinances(khatabook_loan)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS history_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT, module TEXT, kind TEXT,
          title TEXT, amount REAL, village TEXT, loan_ref TEXT, created_at TEXT
        )
      ''');
    }
    if (oldVersion < 6) {
      // v6: khata customer IDs (order-wise A-01…A-99 → B-01… → Z-99 →
      // A-001…), a pool of freed IDs (deleted customers reuse them), and a
      // pawn transaction ledger (Amount Paying / Amount Requesting /
      // Interest Paid / Release with dual dates).
      try {
        await db
            .execute('ALTER TABLE customers ADD COLUMN customer_id TEXT');
      } catch (_) {/* column already present */}
      await db.execute('''
        CREATE TABLE IF NOT EXISTS customer_id_pool (
          id TEXT PRIMARY KEY, freed_at TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pawn_transactions (
          client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
          pawn_loan TEXT, customer TEXT, customer_name TEXT,
          tx_date TEXT, effective_date TEXT, tx_type TEXT,
          amount REAL, principal_part REAL, interest_part REAL,
          notes TEXT, updated_at TEXT
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pawn_tx_loan '
          'ON pawn_transactions(pawn_loan)');
    }
    if (oldVersion < 7) {
      // v7: bank / UPI QR codes for the shop (add from gallery, swipe between).
      await db.execute('''
        CREATE TABLE IF NOT EXISTS qr_codes (
          id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT, path TEXT,
          created_at TEXT
        )
      ''');
    }
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');

    await db.execute('''
      CREATE TABLE qr_codes (
        id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT, path TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE villages (
        client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
        village_name TEXT, khata_type TEXT, district TEXT, state TEXT,
        pincode TEXT, collector TEXT, notes TEXT, updated_at TEXT,
        latitude REAL, longitude REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
        customer_name TEXT, phone TEXT, customer_type TEXT, village TEXT,
        address TEXT, status TEXT, id_proof_type TEXT, id_proof_number TEXT,
        rating TEXT, gold_interest_rate REAL, silver_interest_rate REAL,
        khatabook_interest_rate REAL, notes TEXT, photo_path TEXT, updated_at TEXT,
        id_photo_front TEXT, id_photo_back TEXT, reminder_date TEXT,
        customer_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE pawn_loans (
        client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
        customer TEXT, customer_name TEXT, phone TEXT, village TEXT,
        business TEXT, status TEXT, loan_date TEXT, interest_basis TEXT,
        loan_amount REAL, interest_rate REAL, due_date TEXT,
        total_gross_weight REAL, total_net_weight REAL, hallmarked_weight REAL,
        non_hallmarked_weight REAL, total_market_value REAL, ltv REAL,
        interest_accrued REAL, total_payable REAL, amount_paid REAL,
        balance REAL, last_interest_date TEXT, release_date TEXT, remarks TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE pawn_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT, loan_uuid TEXT,
        item_description TEXT, metal_type TEXT, purity TEXT, quantity INTEGER,
        gross_weight REAL, net_weight REAL, hallmarked INTEGER,
        valuation_rate REAL, market_value REAL, approved_amount REAL,
        remarks TEXT, photo_path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE khatabook_loans (
        client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
        customer TEXT, customer_name TEXT, phone TEXT, village TEXT,
        business TEXT, status TEXT, loan_date TEXT, principal_amount REAL,
        interest_amount REAL, total_payable REAL, installment_count INTEGER,
        installment_amount REAL, collection_frequency TEXT, start_date TEXT,
        end_date TEXT, customer_rating TEXT, refinanced_from TEXT,
        total_collected REAL, paid_installments INTEGER, outstanding REAL,
        remarks TEXT, updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE khatabook_collections (
        client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
        khatabook_loan TEXT, customer TEXT, village TEXT, collection_date TEXT,
        amount REAL, payment_mode TEXT, is_irregular INTEGER DEFAULT 0,
        remarks TEXT, updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE khatabook_given (
        client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
        customer TEXT, customer_name TEXT, village TEXT, khatabook_loan TEXT,
        given_date TEXT, amount REAL, note TEXT, updated_at TEXT,
        given_type TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE pawn_releases (
        client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
        pawn_loan TEXT, customer TEXT, release_date TEXT, payment_mode TEXT,
        principal_paid REAL, interest_paid REAL, other_charges REAL,
        total_paid REAL, remarks TEXT, updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE pawn_transactions (
        client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
        pawn_loan TEXT, customer TEXT, customer_name TEXT,
        tx_date TEXT, effective_date TEXT, tx_type TEXT,
        amount REAL, principal_part REAL, interest_part REAL,
        notes TEXT, updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE khatabook_refinances (
        client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
        khatabook_loan TEXT, customer TEXT, refinance_date TEXT,
        old_outstanding REAL, new_principal REAL, new_interest_amount REAL,
        new_installment_count INTEGER, new_interest_note TEXT, new_loan TEXT,
        remarks TEXT, updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE history_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT, module TEXT, kind TEXT,
        title TEXT, amount REAL, village TEXT, loan_ref TEXT, created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT, op TEXT, doctype TEXT,
        client_uuid TEXT, data TEXT, created_at TEXT, status TEXT, error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE photo_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT, client_uuid TEXT, doctype TEXT,
        local_path TEXT, uploaded INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE customer_id_pool (
        id TEXT PRIMARY KEY, freed_at TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_pawn_items_loan ON pawn_items(loan_uuid)');
    await db.execute(
        'CREATE INDEX idx_pawn_tx_loan ON pawn_transactions(pawn_loan)');
  }

  // ---------------------------------------------------------------- settings
  Future<String?> getSetting(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ------------------------------------------------------------------ generic
  Future<List<Map<String, Object?>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
    List<String>? columns,
  }) {
    return db.query(table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        columns: columns);
  }

  Future<Map<String, Object?>?> byUuid(String table, String uuid) async {
    final rows =
        await db.query(table, where: 'client_uuid = ?', whereArgs: [uuid]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> byServerName(String table, String name) async {
    final rows =
        await db.query(table, where: 'server_name = ?', whereArgs: [name]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsert(String table, Map<String, Object?> row) async {
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteWhere(String table, String where, List<Object?> args) async {
    await db.delete(table, where: where, whereArgs: args);
  }

  /// Deletes rows (optionally filtered) from a table — mirrors sqflite's
  /// delete so screens can call `db.delete(table, where: …)`.
  Future<void> delete(String table,
      {String? where, List<Object?>? whereArgs}) async {
    await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<int> count(String table,
      {String? where, List<Object?>? whereArgs}) async {
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM $table${where != null ? ' WHERE $where' : ''}',
        whereArgs);
    return (r.first['c'] as int?) ?? 0;
  }

  Future<double> sum(String table, String column,
      {String? where, List<Object?>? whereArgs}) async {
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM($column),0) AS s FROM $table'
        '${where != null ? ' WHERE $where' : ''}',
        whereArgs);
    return (r.first['s'] as num?)?.toDouble() ?? 0;
  }

  // ------------------------------------------------------------------- outbox
  /// Column names of a table (used to copy server docs field-by-field).
  Future<Set<String>> columns(String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'] as String).toSet();
  }

  Future<void> enqueue({
    required String op,
    required String doctype,
    required String clientUuid,
    required Map<String, Object?> data,
  }) async {
    // Collapse repeated offline edits into a single pending mutation (LWW).
    await db.delete('outbox',
        where: 'client_uuid = ? AND doctype = ? AND status = ?',
        whereArgs: [clientUuid, doctype, 'pending']);
    await db.insert('outbox', {
      'op': op,
      'doctype': doctype,
      'client_uuid': clientUuid,
      'data': jsonEncode(data),
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending',
    });
  }

  Future<List<Map<String, Object?>>> pendingMutations() {
    return db.query('outbox',
        where: 'status = ?', whereArgs: ['pending'], orderBy: 'id asc');
  }

  Future<void> markMutation(int id,
      {required String status, String? error}) async {
    await db.update('outbox', {'status': status, 'error': error},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> pendingCount() =>
      count('outbox', where: 'status = ?', whereArgs: ['pending']);

  Future<int> failedCount() =>
      count('outbox', where: 'status = ?', whereArgs: ['error']);

  /// Re-queue mutations that previously failed (e.g. a link target had not
  /// synced yet), so the next sync retries them.
  Future<void> retryFailed() async {
    await db.update('outbox', {'status': 'pending', 'error': null},
        where: 'status = ?', whereArgs: ['error']);
  }

  // ------------------------------------------------------------------- photos
  Future<void> enqueuePhoto(
      String clientUuid, String doctype, String path) async {
    await db.insert('photo_queue', {
      'client_uuid': clientUuid,
      'doctype': doctype,
      'local_path': path,
      'uploaded': 0,
    });
  }

  Future<List<Map<String, Object?>>> pendingPhotos() {
    return db.query('photo_queue', where: 'uploaded = ?', whereArgs: [0]);
  }

  Future<void> markPhotoUploaded(int id) async {
    await db
        .update('photo_queue', {'uploaded': 1}, where: 'id = ?', whereArgs: [id]);
  }
}
