import 'dart:convert';

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
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'jewellery_suite.db'),
      version: 1,
      onCreate: _create,
    );
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');

    await db.execute('''
      CREATE TABLE villages (
        client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
        village_name TEXT, district TEXT, state TEXT, pincode TEXT,
        collector TEXT, notes TEXT, updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
        customer_name TEXT, phone TEXT, customer_type TEXT, village TEXT,
        address TEXT, status TEXT, id_proof_type TEXT, id_proof_number TEXT,
        rating TEXT, gold_interest_rate REAL, silver_interest_rate REAL,
        khatabook_interest_rate REAL, notes TEXT, photo_path TEXT, updated_at TEXT
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
      CREATE TABLE pawn_releases (
        client_uuid TEXT PRIMARY KEY, server_name TEXT, dirty INTEGER DEFAULT 1,
        pawn_loan TEXT, customer TEXT, release_date TEXT, payment_mode TEXT,
        principal_paid REAL, interest_paid REAL, other_charges REAL,
        total_paid REAL, remarks TEXT, updated_at TEXT
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

    await db.execute('CREATE INDEX idx_pawn_items_loan ON pawn_items(loan_uuid)');
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
  }) {
    return db.query(table,
        where: where, whereArgs: whereArgs, orderBy: orderBy, limit: limit);
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
