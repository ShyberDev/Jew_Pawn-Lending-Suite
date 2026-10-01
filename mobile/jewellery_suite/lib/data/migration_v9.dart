import 'package:sqflite/sqflite.dart';

/// Schema version 9 — the **customer identity** migration.
///
/// ## Why
///
/// Pawn loans, khata loans, collections, releases, transactions and "You Gave"
/// rows all identified their customer by storing the customer's **name** in a
/// `customer` column. Two people may legitimately share a name, and on a real
/// shop's book they did: three different "Ravi" records, one of whom owned a
/// ₹12,000 loan that the app filed under the wrong village because the name
/// alone could not say which Ravi it was.
///
/// So identity moves to `customer_uuid`, which is unique by construction.
/// `customer_name` stays as a display cache that the UI always refreshes from
/// the customer record, so renaming someone fixes every screen at once.
///
/// ## What this migration guarantees
///
/// * **It never merges customers.** One customer row in, one customer row out.
/// * **It never guesses from a name alone.** A loan is linked only when the
///   stored reference resolves to exactly one customer. When several customers
///   share the name, the row is left unresolved and reported for manual review
///   (see [MigrationReport.unresolved]) — guessing would silently move one
///   person's money to another person's account.
/// * **It is idempotent.** Rows already carrying a `customer_uuid` are left
///   alone, and every step is safe to re-run.
/// * **It is additive.** No column is dropped or renamed and no data is
///   deleted, so a downgrade loses nothing.
/// * **It writes a migration log**, so exactly what happened is knowable later.
/// Rows the migration could not resolve safely, for manual review.
class Unresolved {
  final String table;
  final String rowUuid;
  final String reference;
  final String reason;

  const Unresolved(this.table, this.rowUuid, this.reference, this.reason);

  @override
  String toString() => '$table.$rowUuid -> "$reference" ($reason)';
}

class MigrationReport {
  /// Rows linked because the stored reference was already a uuid.
  final int linkedByUuid;

  /// Rows linked because exactly one customer had that name.
  final int linkedByUniqueName;

  /// Rows already carrying a uuid — nothing to do.
  final int alreadyLinked;

  /// Rows left alone for a human to decide.
  final List<Unresolved> unresolved;

  /// True when nothing is waiting for review.
  bool get isClean => unresolved.isEmpty;

  const MigrationReport({
    required this.linkedByUuid,
    required this.linkedByUniqueName,
    required this.alreadyLinked,
    required this.unresolved,
  });

  @override
  String toString() => 'MigrationV9: linked(uuid)=$linkedByUuid, '
      'linked(unique name)=$linkedByUniqueName, '
      'already=$alreadyLinked, needs review=${unresolved.length}';
}

class MigrationV9 {
  const MigrationV9._();

  static const version = 9;

  /// Tables that point at a customer, and the columns that may hold the old
  /// free-text reference.
  ///
  /// BOTH `customer` and `customer_name` are tried, because the app has never
  /// been consistent about which one holds the reference: the pawn form writes
  /// a uuid into `customer`, the khata form writes a *name* into `customer`,
  /// and the sample seeder writes a uuid. Relying on one column would silently
  /// fail to link rows written through the other.
  static const targets = <({String table, List<String> legacyColumns})>[
    (table: 'pawn_loans', legacyColumns: ['customer', 'customer_name']),
    (table: 'pawn_transactions', legacyColumns: ['customer_name', 'customer']),
    (table: 'pawn_releases', legacyColumns: ['customer', 'customer_name']),
    (table: 'khatabook_loans', legacyColumns: ['customer_name', 'customer']),
    (
      table: 'khatabook_collections',
      legacyColumns: ['customer', 'customer_name']
    ),
    (table: 'khatabook_given', legacyColumns: ['customer_name', 'customer']),
    (
      table: 'khatabook_refinances',
      legacyColumns: ['customer', 'customer_name']
    ),
  ];

  /// Adds the columns and indexes. Safe on a fresh install and on upgrade.
  static Future<void> addSchema(Database db) async {
    for (final t in targets) {
      await _addColumn(db, t.table, 'customer_uuid', 'TEXT');
    }
    // The uuid is now the lookup key for every screen that follows a customer's
    // loans, so it has to be indexed.
    for (final t in targets) {
      await db.execute('CREATE INDEX IF NOT EXISTS '
          'idx_${t.table}_customer ON ${t.table}(customer_uuid)');
    }
    // Search and grouping paths that were previously full table scans.
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(customer_name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_id ON customers(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_village ON customers(village)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_khata_loans_loan ON khatabook_collections(khatabook_loan)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_khata_given_loan ON khatabook_given(khatabook_loan)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pawn_loans_status ON pawn_loans(status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_outbox_status ON outbox(status)');
  }

  /// Adds a column only when it is missing, so the schema step is idempotent.
  /// [column] is the bare column name; the type is applied here.
  static Future<void> _addColumn(
      Database db, String table, String column, String type) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((c) => '${c['name']}' == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }

  /// Links every resolvable row to its customer uuid.
  ///
  /// Matching rules, in order — deliberately conservative:
  ///  1. the stored reference is already a `client_uuid` → link it;
  ///  2. the reference is a name that matches **exactly one** customer → link;
  ///  3. anything else (no match, or several customers share the name) → leave
  ///     it for [MigrationReport.unresolved] and a human decision.
  ///
  /// Name matching is case- and whitespace-insensitive, because the same person
  /// is typed "Ravi" and "ravi" from different screens.
  static Future<MigrationReport> backfill(Database db) async {
    final customers = await db.query('customers');
    final byUuid = <String, String>{};
    final byName = <String, List<String>>{};
    for (final c in customers) {
      final uuid = '${c['client_uuid'] ?? ''}'.trim();
      if (uuid.isEmpty) continue;
      byUuid[uuid.toLowerCase()] = uuid;
      final name = _norm(c['customer_name']);
      if (name.isEmpty) continue;
      byName.putIfAbsent(name, () => <String>[]).add(uuid);
    }

    var byUuidCount = 0, byNameCount = 0, already = 0;
    final unresolved = <Unresolved>[];

    for (final t in targets) {
      final rows = await db.query(t.table);
      for (final row in rows) {
        final rowUuid = '${row['client_uuid'] ?? row['id'] ?? ''}';
        final existing = '${row['customer_uuid'] ?? ''}'.trim();
        if (existing.isNotEmpty) {
          already++;
          continue;
        }
        // Try each candidate column: a uuid match is always safe and wins; a
        // name only counts when exactly one customer answers to it.
        var linked = false;
        String? blockedReason;
        String? blockedRef;

        for (final column in t.legacyColumns) {
          final reference = '${row[column] ?? ''}'.trim();
          if (reference.isEmpty) continue;

          final asUuid = byUuid[reference.toLowerCase()];
          if (asUuid != null) {
            await _set(db, t.table, rowUuid, asUuid);
            byUuidCount++;
            linked = true;
            break;
          }
          final candidates = byName[_norm(reference)] ?? const <String>[];
          if (candidates.length == 1) {
            await _set(db, t.table, rowUuid, candidates.first);
            byNameCount++;
            linked = true;
            break;
          }
          blockedRef ??= reference;
          blockedReason ??= candidates.length > 1
              ? '${candidates.length} customers share this name'
              : 'no customer matches';
        }

        if (linked) continue;
        unresolved.add(Unresolved(
          t.table,
          rowUuid,
          blockedRef ?? '',
          blockedReason ?? 'no reference stored',
        ));
      }
    }
    return MigrationReport(
      linkedByUuid: byUuidCount,
      linkedByUniqueName: byNameCount,
      alreadyLinked: already,
      unresolved: unresolved,
    );
  }

  static Future<void> _set(
      Database db, String table, String rowUuid, String customerUuid) async {
    final key = table == 'pawn_items' ? 'id' : 'client_uuid';
    await db.update(table, {'customer_uuid': customerUuid},
        where: '$key = ?', whereArgs: [rowUuid]);
  }

  /// Records what the migration did. Kept as a real table so the outcome can
  /// be inspected months later without trusting this file.
  static Future<void> writeLog(Database db, MigrationReport report) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS migration_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        version INTEGER, ran_at TEXT, linked_by_uuid INTEGER,
        linked_by_unique_name INTEGER, already_linked INTEGER,
        needs_review INTEGER, detail TEXT
      )
    ''');
    await db.insert('migration_log', {
      'version': version,
      'ran_at': DateTime.now().toIso8601String(),
      'linked_by_uuid': report.linkedByUuid,
      'linked_by_unique_name': report.linkedByUniqueName,
      'already_linked': report.alreadyLinked,
      'needs_review': report.unresolved.length,
      'detail': report.unresolved.map((u) => '$u').join('\n'),
    });
  }

  static String _norm(Object? v) =>
      '${v ?? ''}'.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
