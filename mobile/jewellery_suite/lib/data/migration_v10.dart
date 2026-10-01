import 'package:sqflite/sqflite.dart';

/// Schema version 10 — the canonical khatabook financial model.
///
/// Builds on v9 (customer identity). Adds the three things the specification
/// requires and the app did not have:
///
/// 1. **`khatabook_installments`** — the schedule as real rows with their own
///    due date, scheduled amount, paid amount, remaining amount and status.
///    Previously installments were recomputed on the fly, so a payment could
///    never be tied to the installment it settled.
/// 2. **Component columns on `khatabook_loans`** — principal recovered,
///    principal outstanding, interest outstanding, fee balances and unapplied
///    credit. Without these, `Investment` (capital deployed) cannot be
///    answered at all, because the app only stored one `total_payable`.
/// 3. **`khatabook_allocations`** — the permanent allocation ledger. Every
///    payment records exactly where each rupee went: which installment, which
///    component, how much. This is what makes a balance auditable rather than
///    merely correct today.
///
/// Additive and idempotent: nothing is dropped or renamed, and every step is
/// safe to re-run.
class MigrationV10 {
  const MigrationV10._();

  static const version = 10;

  /// Component balances carried on the loan itself, with their declared type.
  ///
  /// SQLite is dynamically typed, so adding a `REAL` column to an existing table
  /// is safe — the declared type is advisory, and declaring the numeric columns
  /// as REAL keeps values reading as numbers rather than as text.
  static const loanColumns = <String, String>{
    'original_principal': 'REAL',
    'expected_interest': 'REAL',
    'expected_repayment': 'REAL',
    'principal_recovered': 'REAL',
    'principal_outstanding': 'REAL',
    'interest_outstanding': 'REAL',
    'late_fee_outstanding': 'REAL',
    'other_charge_outstanding': 'REAL',
    'unapplied_credit': 'REAL',
    'closure_type': 'TEXT',
    'closed_at': 'TEXT',
  };

  static Future<void> addSchema(Database db) async {
    for (final entry in loanColumns.entries) {
      await _addColumn(db, 'khatabook_loans', entry.key, entry.value);
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS khatabook_installments (
        client_uuid TEXT PRIMARY KEY,
        khatabook_loan TEXT NOT NULL,
        customer_uuid TEXT,
        installment_number INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        scheduled_amount REAL NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0,
        remaining_amount REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        interest_component REAL NOT NULL DEFAULT 0,
        late_fee REAL NOT NULL DEFAULT 0,
        other_charge REAL NOT NULL DEFAULT 0,
        created_at TEXT, updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS khatabook_allocations (
        client_uuid TEXT PRIMARY KEY,
        khatabook_loan TEXT NOT NULL,
        installment_number INTEGER,
        khatabook_collection TEXT,
        component TEXT NOT NULL,
        amount REAL NOT NULL,
        allocation_order INTEGER NOT NULL,
        allocated_at TEXT NOT NULL,
        note TEXT
      )
    ''');

    for (final sql in [
      'CREATE INDEX IF NOT EXISTS idx_khata_inst_loan ON khatabook_installments(khatabook_loan)',
      'CREATE INDEX IF NOT EXISTS idx_khata_inst_due ON khatabook_installments(due_date)',
      'CREATE INDEX IF NOT EXISTS idx_khata_inst_status ON khatabook_installments(status)',
      'CREATE INDEX IF NOT EXISTS idx_khata_inst_customer ON khatabook_installments(customer_uuid)',
      'CREATE INDEX IF NOT EXISTS idx_khata_alloc_loan ON khatabook_allocations(khatabook_loan)',
      'CREATE INDEX IF NOT EXISTS idx_khata_alloc_collection ON khatabook_allocations(khatabook_collection)',
    ]) {
      await db.execute(sql);
    }
  }

  static Future<void> _addColumn(
      Database db, String table, String column, String type) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((c) => '${c['name']}' == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }

  /// Seeds the component balances on existing loans from the two figures the
  /// app already had, so the new columns are never NULL.
  ///
  /// With no allocation history there is no way to know how much of the
  /// collected money was principal, so principal recovery starts at **zero** —
  /// the conservative choice. Money is never assumed recovered when it is not
  /// provable, which keeps `Investment` an upper bound rather than a guess.
  static Future<int> seedComponents(Database db) async {
    final loans =
        await db.query('khatabook_loans', where: 'principal_outstanding IS NULL');
    for (final l in loans) {
      final principal = (l['principal_amount'] as num?)?.toDouble() ?? 0;
      final collected = (l['total_collected'] as num?)?.toDouble() ?? 0;
      final payable = (l['total_payable'] as num?)?.toDouble() ?? 0;
      await db.update('khatabook_loans', {
        'original_principal': principal,
        'expected_interest': payable - principal,
        'expected_repayment': payable,
        'principal_recovered': 0,
        'principal_outstanding': principal,
        'interest_outstanding': payable - principal,
        'late_fee_outstanding': 0,
        'other_charge_outstanding': 0,
        'unapplied_credit': 0,
        'status': LoanStatusWire.of(l['status'], payable, collected),
      }, where: 'client_uuid = ?', whereArgs: [l['client_uuid']]);
    }
    return loans.length;
  }
}

/// Maps the legacy two-value status onto the seven-state machine, so an old
/// "Closed" row keeps its meaning instead of silently becoming ACTIVE.
class LoanStatusWire {
  const LoanStatusWire._();

  static String of(Object? raw, double payable, double collected) {
    final s = '${raw ?? ''}'.toUpperCase();
    // A v10 state is already canonical; leave it alone.
    const canonical = {
      'ACTIVE',
      'COMPLETED',
      'SETTLED',
      'REFINANCED',
      'WRITTEN_OFF',
      'DEFAULTED',
      'CANCELLED',
    };
    if (canonical.contains(s)) return s;
    if (s == 'CLOSED') {
      return collected >= payable && payable > 0 ? 'COMPLETED' : 'ACTIVE';
    }
    return 'ACTIVE';
  }
}
