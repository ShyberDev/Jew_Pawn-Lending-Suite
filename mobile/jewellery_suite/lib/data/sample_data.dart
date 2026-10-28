import 'package:flutter/foundation.dart';

import 'local_db.dart';

/// One row identified as development/sample data.
class SampleRecord {
  final String table;

  /// The value used to delete this row: its primary key in [table]. Some
  /// tables are keyed by an integer `id` rather than `client_uuid`, so this is
  /// never assumed.
  final String uuid;
  final String label;

  const SampleRecord(this.table, this.uuid, this.label);

  @override
  String toString() => '$table · $label';
}

/// The result of inspecting the database for development/sample rows.
///
/// Nothing is deleted by [SampleDataService.inspect] — it only reports. When
/// [blocked] is not empty the removal is refused, because one of the checks
/// below could not prove that deleting would be safe.
class SampleDataReport {
  /// Sample rows grouped by table, in a stable order.
  final Map<String, List<SampleRecord>> byTable;

  /// Demo villages that will be kept because real customers still use them.
  final List<String> keptVillages;

  /// Reasons it would be unsafe to remove. Non-empty blocks removal.
  final List<String> blocked;

  /// Tables a real record was found pointing into the sample set.
  final List<String> realDataTouched;

  const SampleDataReport({
    required this.byTable,
    required this.keptVillages,
    required this.blocked,
    required this.realDataTouched,
  });

  int get totalRows =>
      byTable.values.fold<int>(0, (s, rows) => s + rows.length);

  int countFor(String table) => byTable[table]?.length ?? 0;

  bool get isEmpty => totalRows == 0;

  bool get safeToRemove => blocked.isEmpty && !isEmpty;
}

/// Finds and removes the development/sample records that earlier builds wrote
/// into the real database (`c-demo-*`, `v-demo-*` and the ten "Sample …"
/// members), so they never become part of the shop's customer database.
///
/// The rules, in order:
///
/// 1. **Identify by marker, not by resemblance.** A row is sample data only if
///    its uuid carries a demo marker (`c-demo-…`, `v-demo-…`, `v-sample-…`)
///    or its name/phone is one the sample generators actually use. Nothing is
///    matched merely because it "looks like" sample data.
/// 2. **Follow the real relationships.** Child rows are reached through the
///    uuid each table actually stores. Several tables store a *name* rather
///    than a uuid — those are only followed when that name belongs to exactly
///    one customer in the whole database, otherwise the removal is blocked
///    rather than guessed.
/// 3. **Refuse to touch real data.** A demo village that still has real
///    customers is kept. A real record pointing into the sample set is
///    reported in [SampleDataReport.realDataTouched] and blocks removal.
/// 4. **Explicit only.** [inspect] reads. [remove] deletes, and refuses unless
///    the report is clean and the caller passes [confirmedByUser] after showing
///    it.
class SampleDataService {
  SampleDataService(this.db);

  final LocalDb db;

  static const demoUuidPrefixes = <String>['c-demo-', 'v-demo-', 'v-sample-'];

  /// Names produced by AppState.addSampleMembers.
  ///
  /// v1.0.21: every sample is named after the condition it demonstrates
  /// (`Sample_DueToday`, `Sample_Overdue_Arrears`, `Sample_Refinanced`, ...),
  /// so the list says what it is for. The prefix match also covers the older
  /// `Sample Monthly 1` shape, which means a shop that seeded v1.0.20 data can
  /// still remove all of it in one go.
  static final sampleNamePattern =
      RegExp(r'^Sample[_ ]', caseSensitive: false);

  /// Phone numbers produced by AppState.addSampleMembers (9000000001…10).
  static final samplePhonePattern =
      RegExp(r'^900000000(1|2|3|4|5|6|7|8|9|10)$');

  static const _customers = 'customers';
  static const _villages = 'villages';

  /// Reads the database and reports what is sample data. Never writes.
  Future<SampleDataReport> inspect() async {
    final blocked = <String>[];
    final keptVillages = <String>[];
    final touched = <String>[];
    final byTable = <String, List<SampleRecord>>{};

    final customers = await db.query(_customers);
    final villages = await db.query(_villages);

    // ---- 1. demo customers -------------------------------------------------
    final demoCustomerUuids = <String>{};
    final demoCustomerNames = <String>{};
    for (final c in customers) {
      final uuid = '${c['client_uuid'] ?? ''}';
      final name = '${c['customer_name'] ?? ''}'.trim();
      final phone = '${c['phone'] ?? ''}'.trim();
      final byUuid = demoUuidPrefixes.any(uuid.startsWith);
      final byName = sampleNamePattern.hasMatch(name);
      final byPhone = samplePhonePattern.hasMatch(phone);
      if (!(byUuid || byName || byPhone)) continue;
      demoCustomerUuids.add(uuid);
      demoCustomerNames.add(name);
      _add(
          byTable,
          _customers,
          SampleRecord(
              _customers, uuid, '$name · ${c['customer_id'] ?? 'no ID'}'));
    }

    // Names that more than one customer shares. Any table that stores a name
    // instead of a uuid cannot be resolved for these, so we refuse rather than
    // delete somebody's real loan.
    final nameCounts = <String, int>{};
    for (final c in customers) {
      final name = '${c['customer_name'] ?? ''}'.trim();
      if (name.isNotEmpty) nameCounts[name] = (nameCounts[name] ?? 0) + 1;
    }
    final ambiguousNames =
        nameCounts.entries.where((e) => e.value > 1).map((e) => e.key).toSet();
    for (final name in ambiguousNames) {
      if (demoCustomerNames.contains(name)) {
        blocked.add(
            'More than one customer is called "$name", so rows that store only '
            'the name cannot be told apart. Rename one before removing.');
      }
    }

    // ---- 2. demo villages --------------------------------------------------
    final demoVillageUuids = <String>{};
    for (final v in villages) {
      final uuid = '${v['client_uuid'] ?? ''}';
      if (!demoUuidPrefixes.any(uuid.startsWith)) continue;
      demoVillageUuids.add(uuid);
      final name = '${v['village_name'] ?? ''}';
      // A village is only sample data if nothing real still uses it.
      final realUsers = customers.where((c) =>
          '${c['village'] ?? ''}'.trim().toLowerCase() ==
              name.trim().toLowerCase() &&
          !demoCustomerUuids.contains('${c['client_uuid'] ?? ''}'));
      if (realUsers.isNotEmpty) {
        keptVillages.add(name);
        continue;
      }
      _add(byTable, _villages,
          SampleRecord(_villages, uuid, name.isEmpty ? '(unnamed)' : name));
    }

    // ---- 3. loans reached through the uuid they actually store --------------
    final demoLoans = <String, String>{}; // loan uuid -> owning customer uuid
    for (final table in const ['pawn_loans', 'khatabook_loans']) {
      final rows = await db.query(table);
      for (final r in rows) {
        final owner = '${r['customer'] ?? ''}';
        if (!demoCustomerUuids.contains(owner)) continue;
        final uuid = '${r['client_uuid'] ?? ''}';
        demoLoans[uuid] = table;
        final amount = r['loan_amount'] ?? r['principal_amount'];
        _add(
            byTable,
            table,
            SampleRecord(table, uuid,
                '${r['customer_name'] ?? ''} · ${amount ?? 0} · ${r['loan_date'] ?? ''}'));
      }
    }

    // ---- 4. children of demo loans (uuid-linked) ---------------------------
    for (final table in const ['pawn_items', 'pawn_transactions']) {
      final rows = await db.query(table);
      for (final r in rows) {
        if (!demoLoans
            .containsKey('${r['loan_uuid'] ?? r['pawn_loan'] ?? ''}')) {
          continue;
        }
        _add(
            byTable,
            table,
            SampleRecord(
                table,
                '${r['client_uuid'] ?? r['id'] ?? ''}',
                '${r['metal_type'] ?? r['tx_type'] ?? ''} ${r['amount'] ?? ''}'
                    .trim()));
      }
    }
    for (final table in const [
      'khatabook_collections',
      'khatabook_given',
      'khatabook_refinances'
    ]) {
      final rows = await db.query(table);
      for (final r in rows) {
        if (!demoLoans.containsKey('${r['khatabook_loan'] ?? ''}')) continue;
        _add(
            byTable,
            table,
            SampleRecord(
                table,
                '${r['client_uuid'] ?? ''}',
                '${r['amount'] ?? r['new_principal'] ?? ''} · ${r['collection_date'] ?? r['given_date'] ?? r['refinance_date'] ?? ''}'
                    .trim()));
      }
    }

    // ---- 5. tables that store a customer NAME -----------------------------
    for (final table in const ['pawn_releases', 'khatabook_collections']) {
      final rows = await db.query(table);
      for (final r in rows) {
        final name = '${r['customer'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        if (!demoCustomerNames.contains(name)) {
          continue; // someone else's record
        }
        if (ambiguousNames.contains(name)) continue; // blocked above
        final already =
            byTable[table]?.any((s) => s.uuid == '${r['client_uuid'] ?? ''}') ??
                false;
        if (already) continue;
        _add(
            byTable,
            table,
            SampleRecord(table, '${r['client_uuid'] ?? ''}',
                'name-linked: $name · ${r['amount'] ?? r['total_paid'] ?? ''}'));
      }
    }

    // ---- 6. prove no real record points into the sample set ----------------
    for (final entry in byTable.entries) {
      if (entry.key == _customers || entry.key == _villages) continue;
      final uuids = entry.value.map((r) => r.uuid).toSet();
      if (await _hasUnmarkedChild(entry.key, uuids)) {
        touched.add(entry.key);
      }
    }
    if (touched.isNotEmpty) {
      blocked.add(
          'These tables contain records that belong to the sample set but are '
          'not marked as sample data, so removal would be unsafe: '
          '${touched.join(', ')}.');
    }

    // ---- 7. also collect what the "real customers" check protected ----------
    // Sample members that were created against a village that is real are fine:
    // deleting the member does not touch the village.

    return SampleDataReport(
      byTable:
          Map.fromEntries(byTable.entries.map((e) => MapEntry(e.key, e.value))),
      keptVillages: keptVillages,
      blocked: blocked,
      realDataTouched: touched,
    );
  }

  /// Deletes the sample rows reported by [inspect].
  ///
  /// Refuses unless [confirmedByUser] is true (the UI must show the report and
  /// the user must confirm) and the report is clean. Deletion runs children
  /// first, and only for rows whose uuid was in the inspected set — the set is
  /// re-read inside the delete so a concurrent change cannot widen it.
  Future<SampleDataReport> remove({required bool confirmedByUser}) async {
    final report = await inspect();
    if (!confirmedByUser) {
      return SampleDataReport(
        byTable: report.byTable,
        keptVillages: report.keptVillages,
        blocked: [...report.blocked, 'Removal was not confirmed.'],
        realDataTouched: report.realDataTouched,
      );
    }
    if (!report.safeToRemove) return report;

    // Children before parents, so no half-deleted loan is ever visible.
    const order = [
      'khatabook_refinances',
      'khatabook_given',
      'khatabook_collections',
      'pawn_transactions',
      'pawn_releases',
      'pawn_items',
      'khatabook_loans',
      'pawn_loans',
      'villages',
      'customers',
    ];
    // Every source row that can own a Cashbook entry. Collect the references
    // BEFORE deleting so the automated cash rows go with their source: a
    // sample loan's disbursement, its collections and a refinance's fresh
    // cash must not survive in the shop's real cashbook.
    final cashRefs = <String>{
      for (final rows in report.byTable.values)
        for (final r in rows)
          if (r.uuid.isNotEmpty) r.uuid,
    };

    for (final table in order) {
      final rows = report.byTable[table];
      if (rows == null || rows.isEmpty) continue;
      // A table whose rows are listed with an empty key (pawn_items) is not
      // deleted row by row: its rows are removed with the loan they belong to.
      if (rows.every((r) => r.uuid.isEmpty)) continue;
      final pk = await _primaryKeyColumn(table);
      if (pk == null) continue;
      for (final r in rows) {
        if (r.uuid.isEmpty) continue;
        final value =
            pk == 'id' && int.tryParse(r.uuid) == null ? r.uuid : r.uuid;
        await db.deleteWhere(table, '$pk = ?', [value]);
      }
    }

    await db.deleteCashbookForReferences(cashRefs);
    // A final read proves nothing is left behind.
    return inspect();
  }

  /// The table's declared primary-key column, read from the schema so this
  /// never has to guess between `client_uuid` and `id`.
  Future<String?> _primaryKeyColumn(String table) async {
    try {
      final rows = await db.db.rawQuery('PRAGMA table_info($table)');
      for (final r in rows) {
        if ((r['pk'] as int?) == 1) return r['name'] as String;
      }
    } catch (_) {/* table absent on this install */}
    return null;
  }

  /// True when a row in [table] references one of [uuids] but was not itself
  /// identified as sample data — i.e. real data pointing into the sample set.
  Future<bool> _hasUnmarkedChild(String table, Set<String> uuids) async {
    if (uuids.isEmpty) return false;
    final column = switch (table) {
      'pawn_items' => 'loan_uuid',
      'pawn_transactions' => 'pawn_loan',
      'pawn_releases' => 'pawn_loan',
      'khatabook_collections' ||
      'khatabook_given' ||
      'khatabook_refinances' =>
        'khatabook_loan',
      _ => 'client_uuid',
    };
    try {
      final marks = List.filled(uuids.length, '?').join(',');
      final rows = await db.db.rawQuery(
          'SELECT client_uuid FROM $table '
          'WHERE $column IN ($marks)',
          uuids.toList());
      // Every hit must itself be one of the sample rows.
      final allowed = uuids.toSet();
      for (final r in rows) {
        if (!allowed.contains('${r['client_uuid'] ?? ''}')) return true;
      }
    } catch (_) {
      return false; // column/table absent on this install
    }
    return false;
  }

  void _add(
      Map<String, List<SampleRecord>> into, String table, SampleRecord r) {
    into.putIfAbsent(table, () => <SampleRecord>[]).add(r);
  }

  /// Log-safe summary: counts only, never names, phones or amounts.
  String describeSafely(SampleDataReport report) {
    final parts = report.byTable.entries
        .map((e) => '${e.key}=${e.value.length}')
        .join(' ');
    debugPrint('[sample-data] total=${report.totalRows} $parts '
        'keptVillages=${report.keptVillages.length} '
        'blocked=${report.blocked.length}');
    return parts;
  }
}
