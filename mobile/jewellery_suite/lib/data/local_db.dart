import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migration_v10.dart';
import 'migration_v11.dart';
import 'migration_v12.dart';
import 'migration_v13.dart';
import 'migration_v14.dart';
import 'migration_v15.dart';
import 'migration_v9.dart';

/// Local, offline-first store. Every entity carries a `client_uuid` so it can be
/// pushed to the server idempotently, plus `server_name` once the server has it
/// and `dirty` while it still needs pushing.
///
/// Column names mirror the server DocType field names so pull/push is a simple
/// field copy (see `sync_service.dart`).
class LocalDb {
  Database? _db;

  Database get db => _db!;

  /// Absolute path of the open SQLite file, or null before [init] completes.
  /// Exposed so BackupService can take a verified snapshot of *this* database
  /// instead of re-deriving the file name (which would silently back up
  /// nothing if the name ever changed).
  String? path;

  /// Opens the database. [pathOverride] exists so tests can open a scratch
  /// file instead of the real one; production never passes it.
  Future<void> init({String? pathOverride}) async {
    // Web (wasm SQLite) has no path concept — open by plain filename.
    final file = pathOverride ??
        (kIsWeb
            ? 'jewellery_suite.db'
            : p.join(await getDatabasesPath(), 'jewellery_suite.db'));
    path = file;
    await _open(file);
  }

  Future<void> _open(String file) async {
    _db = await openDatabase(
      file,
      version: MigrationV15.version,
      onCreate: _create,
      onUpgrade: _upgrade,
    );
  }

  /// Closes the connection before a restore replaces the file. Screens keep
  /// the same [LocalDb] instance; [reopen] brings it back on the new bytes.
  Future<void> close() async {
    final open = _db;
    _db = null;
    await open?.close();
  }

  /// Re-opens the database at the path already recorded by [init]. On an
  /// upgrade, SQLite runs the same migrations as a normal launch.
  Future<void> reopen() async {
    final file = path;
    if (file == null) {
      await init();
      return;
    }
    await _open(file);
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Khata type for village groups (Village / Personal / Business).
      try {
        await db.execute('ALTER TABLE villages ADD COLUMN khata_type TEXT');
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
        await db.execute('ALTER TABLE customers ADD COLUMN id_photo_back TEXT');
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
        await db
            .execute('ALTER TABLE khatabook_given ADD COLUMN given_type TEXT');
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
        await db.execute('ALTER TABLE customers ADD COLUMN customer_id TEXT');
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
    if (oldVersion < 8) {
      // v8: ID proof captured on the pawn loan itself (type, number, front and
      // back images), so the slip's proof travels with the pledge.
      for (final sql in [
        'ALTER TABLE pawn_loans ADD COLUMN id_proof_type TEXT',
        'ALTER TABLE pawn_loans ADD COLUMN id_proof_number TEXT',
        'ALTER TABLE pawn_loans ADD COLUMN id_front TEXT',
        'ALTER TABLE pawn_loans ADD COLUMN id_back TEXT',
        'ALTER TABLE pawn_loans ADD COLUMN rate_per_gram REAL',
      ]) {
        try {
          await db.execute(sql);
        } catch (_) {/* column already present */}
      }
    }
    if (oldVersion < 9) {
      // v9: CUSTOMER IDENTITY. Pawn loans, khata loans, collections, releases
      // and transactions used to identify their customer by storing the
      // customer's NAME, which cannot say which of two people called "Ravi"
      // owns a loan — one Ravi's 12,000 was filed under another village
      // because the name alone could not resolve. Identity is now the
      // customer's uuid; the name stays as a display cache.
      //
      // The backfill links only what is unambiguous and reports the rest for a
      // human, so no money is ever silently moved between people. See
      // lib/data/migration_v9.dart.
      await MigrationV9.addSchema(db);
      final report = await MigrationV9.backfill(db);
      await MigrationV9.writeLog(db, report);
      if (report.unresolved.isNotEmpty) {
        debugPrint('[db] migration v9 needs manual review: '
            '${report.unresolved.length} row(s)');
      }
    }
    if (oldVersion < 10) {
      // v10: the canonical khatabook model. Installments become real rows,
      // the loan carries per-component balances so 'Investment' (capital
      // deployed) can be answered, and every payment records exactly where
      // each rupee went. See docs/MIGRATION_V10.md.
      await MigrationV10.addSchema(db);
      final seeded = await MigrationV10.seedComponents(db);
      debugPrint('[db] migration v10: schema added, $seeded loan(s) seeded');
    }
    if (oldVersion < 14) {
      // v14: cashbook module (daily in/out entries and auto-hooks).
      // See lib/data/migration_v14.dart.
      await MigrationV14.addSchema(db);
    }
    if (oldVersion < 15) {
      // v15: payment mode on "You Gave" rows. Without it every You Gave save
      // aborted on an unknown column. See lib/data/migration_v15.dart.
      await MigrationV15.addSchema(db);
    }
    if (oldVersion < 13) {
      // v13: activity timestamp for the member-row recency display.
      // See lib/data/migration_v13.dart.
      await MigrationV13.addSchema(db);
    }
    if (oldVersion < 12) {
      // v12: Loss Khata origin tracking — one nullable column, nothing else.
      // See lib/data/migration_v12.dart.
      await MigrationV12.addSchema(db);
    }
    if (oldVersion < 11) {
      // v11: payment types. Interest-only loans bill one interest period at a
      // time instead of amortising a fixed total. See
      // lib/data/migration_v11.dart.
      await MigrationV11.addSchema(db);
      final filled = await MigrationV11.backfill(db);
      debugPrint('[db] migration v11: schema added, $filled loan(s) defaulted');
    }
  }

  Future<void> _create(Database db, int version) async {
    await db
        .execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');

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
        id_proof_type TEXT, id_proof_number TEXT, id_front TEXT, id_back TEXT,
        rate_per_gram REAL, updated_at TEXT
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

    // Fresh installs never run the v9 upgrade, so create its audit table here
    // too. Backups track it and must see a real (possibly empty) table.
    await db.execute('''
      CREATE TABLE migration_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        version INTEGER, ran_at TEXT, linked_by_uuid INTEGER,
        linked_by_unique_name INTEGER, already_linked INTEGER,
        needs_review INTEGER, detail TEXT
      )
    ''');

    await db
        .execute('CREATE INDEX idx_pawn_items_loan ON pawn_items(loan_uuid)');
    await db.execute(
        'CREATE INDEX idx_pawn_tx_loan ON pawn_transactions(pawn_loan)');

    // v9–v13 are part of the fresh-install schema too, so a new phone
    // starts with customer identity, the canonical khatabook model, payment
    // types, loss tracking and the activity timestamp already in place.
    await MigrationV9.addSchema(db);
    await MigrationV10.addSchema(db);
    await MigrationV11.addSchema(db);
    await MigrationV12.addSchema(db);
    await MigrationV13.addSchema(db);
    await MigrationV14.addSchema(db);
    await MigrationV15.addSchema(db);
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

  /// The table's declared primary-key column, read from the schema itself
  /// (never hard-coded) and cached for the lifetime of the app.
  final Map<String, String> _pkCache = {};

  Future<String?> _primaryKey(String table) async {
    final cached = _pkCache[table];
    if (cached != null) return cached;
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    for (final r in rows) {
      if ((r['pk'] as int?) == 1) {
        final name = r['name'] as String;
        _pkCache[table] = name;
        return name;
      }
    }
    return null;
  }

  /// Writes [row] into [table], matched on the table's primary key.
  ///
  /// MERGE semantics, deliberately NOT `INSERT OR REPLACE`: REPLACE is a
  /// delete + insert, so every column missing from [row] silently reverts to
  /// its default (NULL). Callers only ever write the fields they own, so that
  /// behaviour wiped a customer's book ID, reminder date, interest-rate
  /// overrides, rating and ID photos the moment anyone edited their name —
  /// a routine action destroying data the form does not even display.
  ///
  /// A column is cleared only when the caller passes an explicit `null`.
  Future<void> upsert(String table, Map<String, Object?> row) async {
    final pk = await _primaryKey(table);
    final key = pk == null ? null : row[pk];
    if (key != null) {
      final changed = await db.update(table, row,
          where: '$pk = ?',
          whereArgs: [key],
          conflictAlgorithm: ConflictAlgorithm.replace);
      if (changed > 0) return;
    }
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteWhere(
      String table, String where, List<Object?> args) async {
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
    await db.update('photo_queue', {'uploaded': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------ cashbook
  Future<void> addCashbookEntry(Map<String, Object?> entry) async {
    await db.insert('cashbook_entries', entry,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> getCashbookEntries({
    String? date,
    String? mode,
    String? type,
    String? source,
  }) async {
    final (where, args) = _cashbookWhere(
      date: date,
      mode: mode,
      type: type,
      source: source,
    );
    return db.query(
      'cashbook_entries',
      where: where,
      whereArgs: args,
      orderBy: 'entry_date DESC, entry_time DESC',
    );
  }

  /// Builds the WHERE clause shared by the list and the daily tally, so the
  /// totals always describe exactly the rows on screen.
  (String?, List<Object?>) _cashbookWhere({
    String? date,
    String? mode,
    String? type,
    String? source,
  }) {
    final whereClauses = <String>[];
    final args = <Object?>[];

    if (date != null && date.isNotEmpty) {
      whereClauses.add('entry_date = ?');
      args.add(date);
    }
    if (mode != null && mode != 'ALL') {
      whereClauses.add('payment_mode = ?');
      args.add(mode);
    }
    if (type != null && type != 'ALL') {
      whereClauses.add('entry_type = ?');
      args.add(type);
    }
    if (source != null && source != 'ALL') {
      if (source == 'MANUAL') {
        // Everything the shopkeeper typed by hand. Source modules always use
        // a `<MODULE>_` category prefix (KHATA_, PAWN_, JEWELLERY_).
        whereClauses.add("category NOT LIKE 'KHATA%' "
            "AND category NOT LIKE 'PAWN%' "
            "AND category NOT LIKE 'JEWELLERY%'");
      } else {
        whereClauses.add('category LIKE ?');
        args.add('${source.toUpperCase()}_%');
      }
    }

    return (
      whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      args,
    );
  }

  Future<Map<String, double>> getCashbookDailySummary(
    String date, {
    String? mode,
    String? type,
    String? source,
  }) async {
    final (filter, args) = _cashbookWhere(
      date: date,
      mode: mode,
      type: type,
      source: source,
    );
    final rows = await db.rawQuery('''
      SELECT 
        SUM(CASE WHEN entry_type = 'IN' THEN amount ELSE 0 END) as total_in,
        SUM(CASE WHEN entry_type = 'OUT' THEN amount ELSE 0 END) as total_out
      FROM cashbook_entries
      WHERE ${filter ?? '1 = 1'}
    ''', args);

    if (rows.isEmpty) return {'total_in': 0.0, 'total_out': 0.0, 'net': 0.0};
    final totalIn = (rows.first['total_in'] as num?)?.toDouble() ?? 0.0;
    final totalOut = (rows.first['total_out'] as num?)?.toDouble() ?? 0.0;
    return {
      'total_in': totalIn,
      'total_out': totalOut,
      'net': totalIn - totalOut,
    };
  }

  Future<void> deleteCashbookEntry(String uuid) async {
    await db.delete('cashbook_entries',
        where: 'client_uuid = ?', whereArgs: [uuid]);
  }

  /// Cash entries created by one source row (a loan, collection, release…).
  ///
  /// `reference_id` is not globally unique across modules by accident: every
  /// automated entry stores the uuid of the row that caused it. The optional
  /// [category] narrows this to one module when a source can have more than
  /// one entry (for example a refinance writes only the fresh-cash OUT).
  Future<List<Map<String, Object?>>> cashbookForReference(
    String referenceId, {
    String? category,
  }) {
    return db.query(
      'cashbook_entries',
      where: category == null
          ? 'reference_id = ?'
          : 'reference_id = ? AND category = ?',
      whereArgs: category == null
          ? [referenceId]
          : [referenceId, category],
      orderBy: 'entry_date asc, entry_time asc',
    );
  }

  /// Removes every automated entry that points at one of [references].
  ///
  /// Used by the delete hooks. Manual entries are never touched because they
  /// have no source reference.
  Future<void> deleteCashbookForReferences(Iterable<String> references) async {
    final refs = references
        .map((r) => r.trim())
        .where((r) => r.isNotEmpty)
        .toSet()
        .toList();
    if (refs.isEmpty) return;
    final placeholders = List.filled(refs.length, '?').join(', ');
    await db.delete('cashbook_entries',
        where: 'reference_id IN ($placeholders)', whereArgs: refs);
  }

  /// Removes a legacy automated entry identified by its category, reference,
  /// amount and business date.
  ///
  /// Before v1.1.2 a collection hook stored the *loan* uuid in `reference_id`;
  /// the row can still be found without guessing because amount + date + loan
  /// are all known from the collection being deleted.
  Future<void> deleteCashbookMatching({
    required String category,
    required String referenceId,
    required double amount,
    required String date,
  }) async {
    await db.delete(
      'cashbook_entries',
      where: 'category = ? AND reference_id = ? AND amount = ? '
          'AND entry_date = ?',
      whereArgs: [category, referenceId, amount, date],
    );
  }
}
