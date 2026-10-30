import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../data/api_client.dart';
import '../data/local_db.dart';
import '../data/migration_v12.dart';
import '../data/sync_service.dart';
import '../util/format.dart';
import '../util/ids.dart';
import '../util/khata_alloc.dart';
import '../util/khata_loan_state.dart';
import '../util/khata_math.dart';
import '../util/khata_schedule.dart';
import '../util/pawn_math.dart';

/// Single source of truth for the UI: session, local data helpers and sync.
class AppState extends ChangeNotifier {
  final LocalDb db;
  ApiClient? api;

  bool loggedIn = false;

  /// Set when the shop chose to work without a server. The database is still
  /// the source of truth; only sync is unavailable. Cleared by a real login.
  static const offlineKey = 'offline_mode';
  bool syncing = false;
  int pending = 0;
  SyncSummary? lastSync;
  String? lastError;

  // ------------------------------------------------------------- app settings
  /// Dark / light appearance (app-wide, persisted).
  bool darkMode = false;

  /// In-app zoom 0.8×–1.5× (applies a text-scaler cap so large phone font /
  /// display settings never overflow the screens). Persisted.
  double fontScale = 1.0;

  /// Admin-password confirmation for delete / release actions (Home menu →
  /// Admin). Users who find it annoying can turn it off — it never blocks
  /// normal use, only destructive actions.
  bool adminConfirm = true;

  /// Shopkeeper user profile (photo shown on the home button, phone/email on
  /// the User Details panel).
  String userPhoto = '';
  String userPhone = '';
  String userEmail = '';
  String userName = '';

  AppState(this.db);

  String get serverUrl => api?.baseUrl ?? '';
  String get user => _user ?? '';
  String? _user;

  Future<void> load() async {
    final url = await db.getSetting('server_url');
    final sid = await db.getSetting('sid');
    final savedUser = await db.getSetting('user');
    if (url != null && sid != null && savedUser != null) {
      api = ApiClient(baseUrl: url, sid: sid);
      _user = savedUser;
      loggedIn = true;
    } else if (await db.getSetting(offlineKey) == '1') {
      // A shop with no server (or a phone restored from one) still opens its
      // own data. Sync stays unavailable until a server login is added.
      loggedIn = true;
    }
    darkMode = await db.getSetting('dark_mode') == '1';
    final fs = double.tryParse(await db.getSetting('font_scale') ?? '');
    fontScale = (fs == null || fs <= 0) ? 1.0 : fs.clamp(0.8, 1.5);
    adminConfirm = await db.getSetting('admin_confirm') != '0';
    userPhoto = await db.getSetting('user_photo') ?? '';
    userPhone = await db.getSetting('user_phone') ?? '';
    userEmail = await db.getSetting('user_email') ?? '';
    userName = await db.getSetting('user_name') ?? '';
    await refreshCounts();
    await migrateCustomerIdScheme();
    await normalizeCustomerIds();
    await backfillCustomerIds();
    await ensureLossKhata();
  }

  /// Guarantees the reserved Loss Khata exists. A village already named Loss
  /// (any casing) is adopted as-is rather than duplicated; otherwise the
  /// reserved row is created. Idempotent.
  Future<void> ensureLossKhata() async {
    final villages = await db.query('villages');
    for (final v in villages) {
      if (MigrationV12.isLossVillageName(v['village_name']?.toString())) {
        return;
      }
    }
    await db.upsert('villages', {
      'client_uuid': MigrationV12.lossVillageUuid,
      'village_name': MigrationV12.lossVillageName,
      'khata_type': 'Loss',
      'notes': 'Reserved: customers moved here are treated as loss. '
          'This khata cannot be deleted.',
      'updated_at': DateTime.now().toIso8601String(),
      'dirty': 1,
    });
  }

  /// Moves a customer to the Loss Khata. Only the village changes (origin
  /// remembered in `previous_village`); loans, collections, IDs and history
  /// are untouched, and normal collection keeps working there.
  Future<void> moveCustomerToLoss(Map<String, Object?> customer) async {
    final uuid = customer['client_uuid']?.toString() ?? '';
    if (uuid.isEmpty) return;
    final full = await db.byUuid('customers', uuid);
    if (full == null) return;
    await ensureLossKhata();
    await db.upsert('customers', {
      ...full,
      'previous_village': full['village'],
      'village': MigrationV12.lossVillageName,
      'updated_at': DateTime.now().toIso8601String(),
      'dirty': 1,
    });
    await logEvent(
        'khata', 'move_loss', 'Moved to Loss — ${full['customer_name']}',
        village: full['village']?.toString());
    notifyListeners();
  }

  /// Moves a customer out of Loss back into [village] (or General when null).
  Future<void> moveCustomerFromLoss(
      Map<String, Object?> customer, String? village) async {
    final uuid = customer['client_uuid']?.toString() ?? '';
    if (uuid.isEmpty) return;
    final full = await db.byUuid('customers', uuid);
    if (full == null) return;
    await db.upsert('customers', {
      ...full,
      'previous_village': null,
      'village': village,
      'updated_at': DateTime.now().toIso8601String(),
      'dirty': 1,
    });
    await logEvent(
        'khata', 'move_back', 'Moved back from Loss — ${full['customer_name']}',
        village: village);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    await db.setSetting('dark_mode', value ? '1' : '0');
    notifyListeners();
  }

  Future<void> setFontScale(double value) async {
    fontScale = value.clamp(0.8, 1.5);
    await db.setSetting('font_scale', fontScale.toString());
    notifyListeners();
  }

  /// Opens the shop without a server.
  ///
  /// This app is offline-first: the SQLite file is the shop's real ledger.
  /// Requiring a server login on a fresh install (or after restoring a backup
  /// made on a phone that never synced) would lock the shop out of its own
  /// data. Sync simply stays unavailable until a real login is added; Logout
  /// brings the login form back.
  Future<void> continueOffline() async {
    api = null;
    _user = null;
    loggedIn = true;
    await db.setSetting(offlineKey, '1');
    notifyListeners();
  }

  Future<void> login(String url, String usr, String pwd) async {
    final client = ApiClient(baseUrl: url);
    await client.login(usr, pwd);
    api = client;
    _user = usr;
    loggedIn = true;
    await db.setSetting('server_url', url);
    await db.setSetting('sid', client.sid);
    await db.setSetting('user', usr);
    await db.setSetting(offlineKey, null);
    notifyListeners();
  }

  Future<void> logout() async {
    api = null;
    _user = null;
    loggedIn = false;
    await db.setSetting('sid', null);
    await db.setSetting(offlineKey, null);
    notifyListeners();
  }

  Future<void> refreshCounts() async {
    pending = await db.pendingCount();
    notifyListeners();
  }

  Future<void> retryFailed() async {
    await db.retryFailed();
    await refreshCounts();
  }

  Future<SyncSummary> sync() async {
    final client = api;
    if (client == null) throw ApiException('Not logged in');
    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      final summary = await SyncService(db, client).sync();
      lastSync = summary;
      return summary;
    } catch (error) {
      lastError = error.toString();
      rethrow;
    } finally {
      syncing = false;
      await refreshCounts();
    }
  }

  // ------------------------------------------------------------------- writes
  Future<String> saveEntity({
    required String table,
    required String doctype,
    required String uuid,
    required Map<String, Object?> data,
  }) async {
    final existing = await db.byUuid(table, uuid);
    final serverName = existing?['server_name'] as String?;
    await db.upsert(table, {
      ...data,
      'client_uuid': uuid,
      'server_name': serverName,
      'dirty': 1,
      'updated_at': DateTime.now().toIso8601String(),
    });
    await db.enqueue(
      op: serverName == null ? 'create' : 'update',
      doctype: doctype,
      clientUuid: uuid,
      data: {...data, if (serverName != null) 'name': serverName},
    );

    // Auto-hooks follow their source row: CREATE writes the entry, EDIT
    // updates the same entry (same uuid), and setting the amount to zero
    // removes it. v1.1.1 only handled CREATE, so an edited collection or a
    // deleted source left cash that never happened in the Cashbook.
    final now = DateTime.now();
    if (table == 'pawn_releases') {
      await _syncCashbookEntry(
        category: 'PAWN_REPAYMENT',
        referenceId: uuid,
        entryType: 'IN',
        amount: Num.toDouble(data['total_paid']),
        date: businessDay(data['release_date'], now),
        paymentMode:
            (data['payment_mode']?.toString() ?? 'CASH').toUpperCase(),
        partyName: data['customer']?.toString() ?? '',
        notes: 'Pawn loan release settlement',
      );
    }

    if (table == 'khatabook_loans') {
      // A refinanced loan is not fresh cash: only its `fresh` slice moved and
      // executeRefinance writes that as KHATA_REFINANCE. Writing a full
      // KHATA_DISBURSE here would double-count the rolled balance.
      final isRefinance = (data['refinanced_from']?.toString() ?? '').isNotEmpty;
      await _syncCashbookEntry(
        category: 'KHATA_DISBURSE',
        referenceId: uuid,
        entryType: 'OUT',
        amount: isRefinance ? 0 : Num.toDouble(data['principal_amount']),
        date: businessDay(data['loan_date'], now),
        paymentMode: 'CASH',
        partyName: data['customer_name']?.toString() ?? '',
        notes: 'Khata loan disbursed',
      );
    }

    if (table == 'khatabook_collections') {
      await _syncCashbookEntry(
        category: 'KHATA_COLLECTION',
        referenceId: uuid,
        entryType: 'IN',
        amount: Num.toDouble(data['amount']),
        date: businessDay(data['collection_date'], now),
        paymentMode:
            (data['payment_mode']?.toString() ?? 'CASH').toUpperCase(),
        partyName: data['customer']?.toString() ??
            data['customer_name']?.toString() ??
            '',
        notes: 'Khata collection payment',
        // Rows written before v1.1.2 referenced the loan, not the collection.
        legacyReferenceId: existing?['khatabook_loan']?.toString(),
        legacyAmount: existing == null ? null : Num.toDouble(existing['amount']),
        legacyDate:
            existing == null ? null : businessDay(existing['collection_date'], now),
      );
    }

    if (table == 'khatabook_given') {
      await _syncCashbookEntry(
        category: 'KHATA_DISBURSE',
        referenceId: uuid,
        entryType: 'OUT',
        amount: Num.toDouble(data['amount']),
        date: businessDay(data['given_date'], now),
        paymentMode:
            (data['payment_mode']?.toString() ?? 'CASH').toUpperCase(),
        partyName: data['customer_name']?.toString() ?? '',
        notes: data['note']?.toString() ?? 'Khata You-Gave extra',
      );
    }

    await refreshCounts();
    return uuid;
  }

  Future<String> savePawnLoan({
    required String uuid,
    required Map<String, Object?> data,
    required List<Map<String, Object?>> items,
  }) async {
    final existing = await db.byUuid('pawn_loans', uuid);
    final serverName = existing?['server_name'] as String?;
    await db.upsert('pawn_loans', {
      ...data,
      'client_uuid': uuid,
      'server_name': serverName,
      'dirty': 1,
      'updated_at': DateTime.now().toIso8601String(),
    });
    await db.deleteWhere('pawn_items', 'loan_uuid = ?', [uuid]);
    for (final item in items) {
      await db.upsert('pawn_items', {...item, 'loan_uuid': uuid});
    }
    await db.enqueue(
      op: serverName == null ? 'create' : 'update',
      doctype: 'Pawn Loan',
      clientUuid: uuid,
      data: {
        ...data,
        'items': items,
        if (serverName != null) 'name': serverName,
      },
    );

    // Auto-hook: Pawn Loan -> Cash OUT (Disbursed). Follows edits and removes
    // the entry if the principal is edited down to zero.
    final now = DateTime.now();
    await _syncCashbookEntry(
      category: 'PAWN_DISBURSE',
      referenceId: uuid,
      entryType: 'OUT',
      amount: Num.toDouble(data['loan_amount']),
      date: businessDay(data['loan_date'], now),
      paymentMode: 'CASH',
      partyName: data['customer_name']?.toString() ?? '',
      notes: 'Pawn loan principal disbursed',
    );

    await refreshCounts();
    return uuid;
  }

  /// Stores a photo path on a record and queues it for upload once the record
  /// exists on the server. [column] defaults to `photo_path` (customer photo) —
  /// pass `id_photo_front` / `id_photo_back` for ID-proof photos.
  Future<void> savePhoto({
    required String table,
    required String doctype,
    required String uuid,
    required String path,
    String column = 'photo_path',
  }) async {
    final existing = await db.byUuid(table, uuid);
    if (existing != null) {
      await db.upsert(table, {...existing, column: path});
    }
    await db.enqueuePhoto(uuid, doctype, path);
  }

  /// Capital currently deployed on active khatabook loans — the sum of
  /// principal still owed, so it **falls** as principal is recovered.
  ///
  /// This is what makes "Khata investment" mean the money still in the street.
  /// Summing `principal_amount` (the original principal) could only ever rise.
  ///
  /// A row written before v10 has no `principal_outstanding`; its principal is
  /// the only figure available, so it is used as a safe upper bound rather than
  /// guessing at recovery. Pure, so the KPI can be tested directly.
  static double _khataInvestmentValue(List<Map<String, Object?>> loans) {
    var total = 0.0;
    for (final l in loans) {
      total += l['principal_outstanding'] != null
          ? Num.toDouble(l['principal_outstanding'])
          : Num.toDouble(l['principal_amount']);
    }
    return Num.rupees(total);
  }

  /// Public seam for [khataInvestmentForTest] so the Home KPI's definition can
  /// be tested directly rather than inferred through a widget.
  @visibleForTesting
  static double khataInvestmentForTest(List<Map<String, Object?>> loans) =>
      _khataInvestmentValue(loans);

  /// Writes the permanent allocation ledger for one payment.
  ///
  /// The specification requires that every payment record exactly where each
  /// rupee went — installment, component, amount. Without this a balance is
  /// merely correct *today* and cannot be explained afterwards.
  ///
  /// One row per component with an explicit order, so the allocation can be
  /// replayed in the sequence it was applied.
  Future<void> recordAllocations({
    required String loanUuid,
    required String collectionUuid,
    required Allocation allocation,
    int? installmentNumber,
  }) async {
    final now = DateTime.now().toIso8601String();
    var order = 0;
    final parts = <(String, double)>[
      ('INTEREST', allocation.interest),
      ('LATE_FEE', allocation.lateFee),
      ('OTHER_CHARGE', allocation.otherCharge),
      ('PRINCIPAL', allocation.principal),
    ];
    for (final (component, amount) in parts) {
      if (amount <= 0) continue;
      await db.upsert('khatabook_allocations', {
        'client_uuid': newUuid(),
        'khatabook_loan': loanUuid,
        'installment_number': installmentNumber,
        'khatabook_collection': collectionUuid,
        'component': component,
        'amount': Num.rupees(amount),
        'allocation_order': order++,
        'allocated_at': now,
      });
    }
    // Surplus is recorded too, so held credit is never invisible.
    if (allocation.unapplied > 0) {
      await db.upsert('khatabook_allocations', {
        'client_uuid': newUuid(),
        'khatabook_loan': loanUuid,
        'installment_number': installmentNumber,
        'khatabook_collection': collectionUuid,
        'component': 'UNAPPLIED_CREDIT',
        'amount': Num.rupees(allocation.unapplied),
        'allocation_order': order,
        'allocated_at': now,
        'note': 'Held as credit; not applied to any obligation',
      });
    }
  }

  /// Principal recovered on a loan, taken from the ledger when it exists.
  ///
  /// The ledger is authoritative because it records what actually happened.
  /// Older rows have no ledger, so the stored column is used — and recovery is
  /// never assumed, because inventing it would understate the shop's capital.
  Future<double> principalRecoveredFor(String loanUuid) async {
    try {
      final rows = await db.query('khatabook_allocations',
          where: 'khatabook_loan = ? AND component = ?',
          whereArgs: [loanUuid, 'PRINCIPAL']);
      if (rows.isNotEmpty) {
        return Num.rupees(
            rows.fold<double>(0, (s, r) => s + Num.toDouble(r['amount'])));
      }
    } catch (_) {/* the table is absent before v10 */}
    final loan = await db.byUuid('khatabook_loans', loanUuid);
    return Num.toDouble(loan?['principal_recovered']);
  }

  /// Interest-only period rows for a loan, oldest first.
  ///
  /// Billing happens here and only here: generating a period adds its interest
  /// to the loan's `interest_outstanding` / `total_payable` / `outstanding`.
  /// Calling this when nothing is missing changes nothing, so it is safe to
  /// call from every screen that shows dues.
  ///
  /// Period n is due one full interval after the previous: period 1 falls
  /// `start + 1 step`, never on the start day itself. All fully elapsed
  /// periods plus the current one are billed; anything after that does not
  /// exist yet. A future period can still be billed early by passing
  /// [throughPeriod] (the Future Interest option), which generates and bills
  /// every period up to and including it.
  Future<List<Map<String, Object?>>> ensureInterestPeriods(
    Map<String, Object?> loan, {
    int? throughPeriod,
    DateTime? today,
  }) async {
    final now = today ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final uuid = loan['client_uuid']?.toString() ?? '';
    if (uuid.isEmpty) return const [];
    final start = parseIso(loan['start_date'] ?? loan['loan_date']);
    if (start == null) return const [];
    final frequency = loan['collection_frequency']?.toString() ?? 'Monthly';
    final stepDays = KhataSchedule.intervalDays(frequency);

    var rows = await db.query('khatabook_installments',
        where: 'khatabook_loan = ?',
        whereArgs: [uuid],
        orderBy: 'installment_number asc');
    var billed = rows.length;

    int periodsElapsed() {
      var n = 0;
      while (!_addSteps(start, (n + 1) * stepDays, frequency).isAfter(day)) {
        n++;
      }
      // The period containing today is always billable.
      return n + 1;
    }

    var target = periodsElapsed();
    if (throughPeriod != null && throughPeriod > target) target = throughPeriod;
    if (target < 1) target = 1;

    final currentInterest =
        Num.toDouble(loan['current_interest'] ?? loan['interest_amount']);
    var billedInterest = 0.0;
    final stamp = DateTime.now().toIso8601String();
    for (var n = billed + 1; n <= target; n++) {
      final due = _addSteps(start, n * stepDays, frequency);
      await db.upsert('khatabook_installments', {
        'client_uuid': newUuid(),
        'khatabook_loan': uuid,
        'customer_uuid': loan['customer_uuid'],
        'installment_number': n,
        'due_date': _isoDay(due),
        'scheduled_amount': Num.rupees(currentInterest),
        'paid_amount': 0,
        'remaining_amount': Num.rupees(currentInterest),
        'status': 'PENDING',
        'interest_component': Num.rupees(currentInterest),
        'created_at': stamp,
        'updated_at': stamp,
      });
      billedInterest = Num.rupees(billedInterest + currentInterest);
    }
    if (billedInterest > 0) {
      final fresh = await db.byUuid('khatabook_loans', uuid) ?? loan;
      await db.upsert('khatabook_loans', {
        ...fresh,
        'interest_outstanding': Num.rupees(
            Num.toDouble(fresh['interest_outstanding']) + billedInterest),
        'total_payable':
            Num.rupees(Num.toDouble(fresh['total_payable']) + billedInterest),
        'outstanding':
            Num.rupees(Num.toDouble(fresh['outstanding']) + billedInterest),
        'installment_count': target,
        'dirty': 1,
      });
    }
    rows = await db.query('khatabook_installments',
        where: 'khatabook_loan = ?',
        whereArgs: [uuid],
        orderBy: 'installment_number asc');
    return rows;
  }

  /// Re-marks interest-period rows from the remaining INTEREST allocation
  /// slices, oldest first. Used after a collection is edited or deleted so no
  /// row keeps a paid state its money no longer supports. Future-prepaid
  /// periods keep their explicit link (`interest_period` on the collection).
  Future<void> rebuildInterestPeriods(String loanUuid) async {
    final rows = await db.query('khatabook_installments',
        where: 'khatabook_loan = ?',
        whereArgs: [loanUuid],
        orderBy: 'installment_number asc');
    if (rows.isEmpty) return;
    for (final r in rows) {
      await db.upsert('khatabook_installments', {
        ...r,
        'paid_amount': 0,
        'remaining_amount': r['scheduled_amount'],
        'status': 'PENDING',
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
    // Replay the INTEREST allocation slices — never full collection amounts,
    // because one payment can split across interest and principal and only
    // the interest share belongs on these rows.
    List<Map<String, Object?>> slices;
    try {
      slices = await db.query('khatabook_allocations',
          where: 'khatabook_loan = ? AND component = ?',
          whereArgs: [loanUuid, 'INTEREST'],
          orderBy: 'allocated_at asc, allocation_order asc');
    } catch (_) {
      return; // table absent before v10
    }
    for (final s in slices) {
      var left = Num.toDouble(s['amount']);
      if (left <= 0) continue;
      int? pinned;
      try {
        final coll = await db.query('khatabook_collections',
            where: 'client_uuid = ?', whereArgs: [s['khatabook_collection']]);
        if (coll.isNotEmpty) {
          pinned = (coll.first['interest_period'] as num?)?.toInt();
        }
      } catch (_) {/* collections table always exists; ignore */}
      final targets = pinned != null
          ? rows
              .where(
                  (r) => (r['installment_number'] as num?)?.toInt() == pinned)
              .toList()
          : rows;
      for (final t in targets) {
        if (left <= 0) break;
        final current = await db.query('khatabook_installments',
            where: 'client_uuid = ?', whereArgs: [t['client_uuid']]);
        if (current.isEmpty) continue;
        final row = current.first;
        final remaining = Num.toDouble(row['remaining_amount']);
        if (remaining <= 0) continue;
        final take = left < remaining ? left : remaining;
        final paid = Num.rupees(Num.toDouble(row['paid_amount']) + take);
        final leftRow =
            Num.rupees(Num.toDouble(row['scheduled_amount']) - paid);
        await db.upsert('khatabook_installments', {
          ...row,
          'paid_amount': paid,
          'remaining_amount': leftRow < 0 ? 0 : leftRow,
          'status': leftRow <= 0 ? 'PAID' : 'PARTIALLY_PAID',
          'updated_at': DateTime.now().toIso8601String(),
        });
        left = Num.rupees(left - take);
      }
    }
    await _recountInterestPeriods(loanUuid);
  }

  /// Applies a payment's interest share to interest-period rows, oldest first.
  ///
  /// Normal money never prepays the future: only due rows (date arrived) take
  /// money here. Pass [onlyPeriod] for an explicit Future Interest payment,
  /// which marks that specific period instead. Returns the rupees that landed
  /// on rows; anything left over already went to principal via the allocation
  /// engine.
  Future<double> applyPaymentToInterestPeriods(
    String loanUuid,
    double amount, {
    int? onlyPeriod,
  }) async {
    var rows = await db.query('khatabook_installments',
        where: 'khatabook_loan = ?',
        whereArgs: [loanUuid],
        orderBy: 'installment_number asc');
    if (rows.isEmpty) return 0;
    final day = DateTime.now();
    final today = DateTime(day.year, day.month, day.day);
    Iterable<Map<String, Object?>> targets = rows;
    if (onlyPeriod != null) {
      targets = rows.where(
          (r) => (r['installment_number'] as num?)?.toInt() == onlyPeriod);
    } else {
      targets = rows.where((r) {
        final due = parseIso(r['due_date']);
        return due != null &&
            !DateTime(due.year, due.month, due.day).isAfter(today);
      });
    }
    var left = amount;
    var applied = 0.0;
    for (final t in targets) {
      if (left <= 0) break;
      final current = await db.query('khatabook_installments',
          where: 'client_uuid = ?', whereArgs: [t['client_uuid']]);
      if (current.isEmpty) continue;
      final row = current.first;
      final remaining = Num.toDouble(row['remaining_amount']);
      if (remaining <= 0) continue;
      final take = left < remaining ? left : remaining;
      final paid = Num.rupees(Num.toDouble(row['paid_amount']) + take);
      final leftRow = Num.rupees(Num.toDouble(row['scheduled_amount']) - paid);
      await db.upsert('khatabook_installments', {
        ...row,
        'paid_amount': paid,
        'remaining_amount': leftRow < 0 ? 0 : leftRow,
        'status': leftRow <= 0 ? 'PAID' : 'PARTIALLY_PAID',
        'updated_at': DateTime.now().toIso8601String(),
      });
      left = Num.rupees(left - take);
      applied = Num.rupees(applied + take);
    }
    await _recountInterestPeriods(loanUuid);
    return applied;
  }

  /// `paid_installments` / `installment_count` mirror the period rows so every
  /// existing counter display keeps working: paid = oldest-consecutive fully
  /// paid periods, count = billed periods.
  Future<void> _recountInterestPeriods(String loanUuid) async {
    final rows = await db.query('khatabook_installments',
        where: 'khatabook_loan = ?',
        whereArgs: [loanUuid],
        orderBy: 'installment_number asc');
    var consecutive = 0;
    for (final r in rows) {
      if (Num.toDouble(r['remaining_amount']) <= 0) {
        consecutive++;
      } else {
        break;
      }
    }
    final loan = await db.byUuid('khatabook_loans', loanUuid);
    if (loan == null) return;
    await db.upsert('khatabook_loans', {
      ...loan,
      'paid_installments': consecutive,
      'installment_count': rows.length,
      'dirty': 1,
    });
  }

  /// Due date `totalDays` after [start]: flat days, except Monthly which
  /// steps whole calendar months (10th stays 10th, 31-01 lands on Feb 28/29).
  static DateTime _addSteps(DateTime start, int totalDays, String frequency) {
    if (frequency.toLowerCase().contains('month')) {
      final months = totalDays ~/ 30;
      return KhataSchedule.dueDate(start, 'Monthly', months);
    }
    return start.add(Duration(days: totalDays));
  }

  static String _isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Refinances a loan: the single writer for every refinance in the app.
  ///
  /// The old loan is FROZEN — status to REFINANCED, every balance and row
  /// untouched — and a separate new loan carries the fresh arrangement. Fresh
  /// cash is physical money handed over now; it is never the old outstanding.
  ///
  /// New obligation = previous outstanding + fresh cash + new interest.
  /// Returns the new loan row.
  Future<Map<String, Object?>> executeRefinance({
    required Map<String, Object?> oldLoan,
    required double fresh,
    required double interest,
    required String paymentType,
    required String frequency,
    required int count,
    required double collectionAmount,
    String? note,
    DateTime? on,
  }) async {
    final day = on ?? DateTime.now();
    final dayIso = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final stamp = day.toIso8601String();
    final oldUuid = oldLoan['client_uuid']?.toString() ?? '';
    final prevOut = Num.rupees(Num.toDouble(oldLoan['outstanding']));
    final freshMoney = Num.rupees(fresh);
    final newInterest = Num.rupees(interest);
    final newPrincipal = Num.rupees(prevOut + freshMoney);
    final isIO = paymentType == 'INTEREST_ONLY';
    // Interest-only loans start at principal only; the first period is billed
    // by ensureInterestPeriods below (pre-adding it here would bill twice —
    // the same trap as loan creation).
    final newTotal =
        Num.rupees(isIO ? newPrincipal : newPrincipal + newInterest);
    final newLoanUuid = newUuid();
    final ref = (oldLoan['server_name'] as String?) ?? oldUuid;

    // 1. Freeze the old loan. Nothing from its history is rewritten.
    await db.upsert('khatabook_loans', {
      ...oldLoan,
      'status': 'REFINANCED',
      'dirty': 1,
    });

    // 2. The new loan, with its own terms and its own schedule.
    final n = isIO ? 0 : (count <= 0 ? 12 : count);
    final per = collectionAmount > 0
        ? collectionAmount
        : Num.rupees(isIO ? newInterest : newTotal / n);
    final newLoan = <String, Object?>{
      'client_uuid': newLoanUuid,
      'server_name': null,
      'dirty': 1,
      'customer': oldLoan['customer'],
      'customer_name': oldLoan['customer_name'],
      'customer_uuid': oldLoan['customer_uuid'],
      'phone': oldLoan['phone'],
      'village': oldLoan['village'],
      'business': oldLoan['business'],
      'status': 'Active',
      'loan_date': dayIso,
      'principal_amount': newPrincipal,
      'interest_amount': newInterest,
      'total_payable': newTotal,
      'installment_count': n,
      'installment_amount': per,
      'collection_frequency': frequency,
      'start_date': dayIso,
      'end_date': _isoDay(_addSteps(DateTime(day.year, day.month, day.day),
          (isIO ? 1 : n) * KhataSchedule.intervalDays(frequency), frequency)),
      'customer_rating': oldLoan['customer_rating'],
      'refinanced_from': oldUuid,
      'total_collected': 0,
      'paid_installments': 0,
      'outstanding': newTotal,
      'original_principal': newPrincipal,
      'expected_interest': newInterest,
      'expected_repayment': newTotal,
      'principal_recovered': 0,
      'principal_outstanding': newPrincipal,
      'interest_outstanding': isIO ? 0 : newInterest,
      'late_fee_outstanding': 0,
      'other_charge_outstanding': 0,
      'unapplied_credit': 0,
      'payment_type': paymentType,
      'current_interest': newInterest,
      'updated_at': stamp,
    };
    await db.upsert('khatabook_loans', newLoan);

    // 2b. Fresh cash physically leaves the till now. The rolled-over
    // outstanding is an accounting transfer, not cash, so only `fresh` is
    // written to the Cashbook. v1.1.1 wrote no entry at all.
    await _syncCashbookEntry(
      category: 'KHATA_REFINANCE',
      referenceId: newLoanUuid,
      entryType: 'OUT',
      amount: freshMoney,
      date: dayIso,
      paymentMode: 'CASH',
      partyName: oldLoan['customer_name']?.toString() ?? '',
      notes: 'Refinance — fresh cash handed over',
    );

    // 3. The refinance record links both sides and carries the breakdown the
    // tile shows: previous + fresh + interest = new obligation.
    await db.upsert('khatabook_refinances', {
      'client_uuid': newUuid(),
      'server_name': null,
      'dirty': 1,
      'khatabook_loan': ref,
      'customer': oldLoan['customer'],
      'refinance_date': stamp,
      'old_outstanding': prevOut,
      'new_principal': newPrincipal,
      'new_interest_amount': newInterest,
      'new_installment_count': n,
      'new_interest_note': note,
      'new_loan': newLoanUuid,
      'remarks': note,
      'updated_at': stamp,
    });

    // 4. First interest period for interest-only new loans.
    if (isIO) {
      final created =
          await db.byUuid('khatabook_loans', newLoanUuid) ?? newLoan;
      await ensureInterestPeriods(created, today: day);
    }

    await touchActivity(oldLoan['customer_uuid']?.toString());
    await logEvent('khata', 'refinance', 'Refinance',
        amount: newTotal, village: oldLoan['village']?.toString(), ref: ref);
    notifyListeners();
    return (await db.byUuid('khatabook_loans', newLoanUuid)) ?? newLoan;
  }

  /// Stamps a customer's money-activity clock. Called ONLY by actions that
  /// move money or mark non-payment (collect, You Gave, Unpaid/Unavailable,
  /// interest changes, refinance, collection/given edits and deletes) — never
  /// by visits or plain edits, so the member row's recency display stays
  /// truthful. Failures are swallowed: a missing clock must never block money.
  Future<void> touchActivity(String? customerUuid) async {
    final uuid = customerUuid?.toString() ?? '';
    if (uuid.isEmpty) return;
    try {
      final row = await db.byUuid('customers', uuid);
      if (row == null) return;
      await db.upsert('customers', {
        ...row,
        'last_activity_at': DateTime.now().toIso8601String(),
        'dirty': 1,
      });
    } catch (_) {/* clock is advisory, money comes first */}
  }

  Future<List<Map<String, Object?>>> itemsFor(String loanUuid) {
    return db.query('pawn_items',
        where: 'loan_uuid = ?', whereArgs: [loanUuid], orderBy: 'id asc');
  }

  // --------------------------------------------------------------- dashboard
  /// Home dashboard figures. Every pawn number comes from [PawnMath] so the
  /// Home KPI, the Pawn screen, the Pawn dashboard and Reports always agree.
  Future<Map<String, Object?>> dashboard() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final activePawns = await db.query('pawn_loans',
        where: 'status = ? OR status IS NULL', whereArgs: ['Active']);
    final pawn = PawnMath.totals(activePawns);
    // Both vocabularies count: legacy 'Active' and v10 'ACTIVE'.
    // (Pawn queries elsewhere intentionally keep their own 'Active'.)
    final khata = await db.query('khatabook_loans',
        where: 'status IN (?, ?) OR status IS NULL',
        whereArgs: ['Active', 'ACTIVE']);
    return {
      'customers': await db.count('customers'),
      'active_pawn': pawn.count,
      // "Pawn outstanding" = what the shop can still collect (principal +
      // interest due − received). Identical to the Pawn screen and dashboard.
      'pawn_out': pawn.outstanding,
      'pawn_investment': pawn.investment,
      'pawn_interest': pawn.interest,
      'khatabook_active': await db.count('khatabook_loans',
          where: 'status IN (?, ?) OR status IS NULL',
          whereArgs: ['Active', 'ACTIVE']),
      // v10: "Khata investment" is the CAPITAL DEPLOYED, i.e. principal
      // outstanding, not the original principal. It falls as principal is
      // recovered, which is the whole point — summing `principal_amount` could
      // only ever rise and never meant the money still in the street. Rows
      // written before v10 have no principal_outstanding, so they fall back to
      // their principal, keeping the figure an upper bound rather than a guess.
      'khatabook_principal': _khataInvestmentValue(khata),
      'khatabook_recovered': Num.rupees(khata.fold<double>(
          0, (s, l) => s + Num.toDouble(l['principal_recovered']))),
      'khatabook_outstanding': await db.sum('khatabook_loans', 'outstanding',
          where: 'status IN (?, ?) OR status IS NULL',
          whereArgs: ['Active', 'ACTIVE']),
      'collected_today': await db.sum('khatabook_collections', 'amount',
          where: 'collection_date = ?', whereArgs: [today]),
      'cashbook_in':
          (await db.getCashbookDailySummary(today))['total_in'] ?? 0.0,
      'cashbook_out':
          (await db.getCashbookDailySummary(today))['total_out'] ?? 0.0,
      'cashbook_net': (await db.getCashbookDailySummary(today))['net'] ?? 0.0,
    };
  }

  // ------------------------------------------------------------------ cashbook
  Future<void> addCashbookEntry({
    required String type, // 'IN' or 'OUT'
    required double amount,
    required String category,
    required String mode,
    DateTime? date,
    String? partyName,
    String? notes,
    String? referenceId,
  }) async {
    final now = DateTime.now();
    final d = date ?? now;
    final uuid = newUuid();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    await db.addCashbookEntry({
      'client_uuid': uuid,
      'entry_date': _isoDay(d),
      'entry_time': timeStr,
      'entry_type': type,
      'amount': Num.rupees(amount),
      'payment_mode': mode.toUpperCase(),
      'category': category,
      'reference_id': referenceId,
      'party_name': partyName ?? '',
      'notes': notes ?? '',
      'created_at': now.toIso8601String(),
      'dirty': 1,
    });
    notifyListeners();
  }

  Future<void> deleteCashbookEntry(String uuid) async {
    await db.deleteCashbookEntry(uuid);
    notifyListeners();
  }

  /// Removes the automated entries that belong to deleted source rows.
  ///
  /// Screens call this with the loan / collection / release uuid BEFORE they
  /// delete the source row, so a delete can never leave cash behind.
  Future<void> deleteCashbookFor(Iterable<String> references) async {
    await db.deleteCashbookForReferences(references);
    notifyListeners();
  }

  /// Deletes a whole khata loan's cash traces: the disbursement, every
  /// collection (including legacy rows whose reference was the loan uuid),
  /// every You-Gave row and every refinance fresh-cash entry.
  ///
  /// Callers pass both the uuid and server name because old rows may use one
  /// or the other.
  Future<void> deleteCashbookForLoan(Set<String> loanRefs) async {
    final refs = {...loanRefs};
    final loans = <Map<String, Object?>>[];
    for (final r in loanRefs) {
      if (r.isEmpty) continue;
      loans.addAll(await db.query('khatabook_loans',
          where: 'client_uuid = ? OR server_name = ?', whereArgs: [r, r]));
    }
    final uuids = loans
        .map((l) => l['client_uuid']?.toString() ?? '')
        .where((u) => u.isNotEmpty)
        .toSet();
    final all = {...refs, ...uuids};
    if (all.isEmpty) return;
    final placeholders = List.filled(all.length, '?').join(', ');
    final collections = await db.query('khatabook_collections',
        where: 'khatabook_loan IN ($placeholders)', whereArgs: all.toList());
    final givens = await db.query('khatabook_given',
        where: 'khatabook_loan IN ($placeholders)', whereArgs: all.toList());
    for (final row in [...collections, ...givens]) {
      final uuid = row['client_uuid']?.toString() ?? '';
      if (uuid.isNotEmpty) all.add(uuid);
    }
    await db.deleteCashbookForReferences(all);
  }

  /// A safe `yyyy-MM-dd` from a possibly malformed stored value.
  static String businessDay(Object? value, DateTime fallback) {
    final s = value?.toString().trim() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : _isoDay(fallback);
  }

  /// Creates or updates the one automated cash entry for a source row.
  ///
  /// The entry keeps its original uuid and clock time, so an edit changes the
  /// amount/date/mode in place instead of writing a second movement. When the
  /// amount becomes zero the entry is removed.
  ///
  /// [legacyReferenceId] handles collection entries written before v1.1.2,
  /// which stored the loan uuid instead of the collection uuid.
  Future<void> _syncCashbookEntry({
    required String category,
    required String referenceId,
    required String entryType,
    required double amount,
    required String date,
    required String paymentMode,
    required String partyName,
    required String notes,
    String? legacyReferenceId,
    double? legacyAmount,
    String? legacyDate,
  }) async {
    var existing =
        await db.cashbookForReference(referenceId, category: category);
    Map<String, Object?>? legacy;
    if (existing.isEmpty &&
        legacyReferenceId != null &&
        legacyReferenceId.isNotEmpty &&
        legacyReferenceId != referenceId &&
        legacyAmount != null &&
        legacyDate != null) {
      final rows = await db.db.query(
        'cashbook_entries',
        where: 'category = ? AND reference_id = ? AND amount = ? '
            'AND entry_date = ?',
        whereArgs: [category, legacyReferenceId, legacyAmount, legacyDate],
      );
      if (rows.isNotEmpty) legacy = rows.first;
    }

    if (amount <= 0) {
      final ids = <String>{
        ...existing.map((r) => r['client_uuid']?.toString() ?? ''),
        if (legacy != null) legacy['client_uuid']?.toString() ?? '',
      }..removeWhere((id) => id.isEmpty);
      for (final id in ids) {
        await db.deleteCashbookEntry(id);
      }
      return;
    }

    final found = existing.isNotEmpty ? existing.first : legacy;
    final now = DateTime.now();
    final newUuidValue = found?['client_uuid']?.toString() ?? newUuid();
    await db.addCashbookEntry({
      'client_uuid': newUuidValue,
      'server_name': found?['server_name'],
      'dirty': 1,
      'entry_date': date,
      'entry_time': found?['entry_time']?.toString() ??
          '${now.hour.toString().padLeft(2, '0')}:'
              '${now.minute.toString().padLeft(2, '0')}:'
              '${now.second.toString().padLeft(2, '0')}',
      'entry_type': entryType,
      'amount': Num.rupees(amount),
      'payment_mode': paymentMode,
      'category': category,
      'reference_id': referenceId,
      'party_name': partyName,
      'notes': notes,
      'created_at': found?['created_at']?.toString() ?? now.toIso8601String(),
    });

    // A migrated legacy row must not survive next to its new copy.
    if (legacy != null &&
        (legacy['client_uuid']?.toString() ?? '') != newUuidValue) {
      await db.deleteCashbookEntry(legacy['client_uuid']?.toString() ?? '');
    }
  }

  Future<List<Map<String, Object?>>> getCashbookEntries({
    String? date,
    String? mode,
    String? type,
    String? source,
  }) =>
      db.getCashbookEntries(date: date, mode: mode, type: type, source: source);

  Future<Map<String, double>> getCashbookDailySummary(
    String? date, {
    String? mode,
    String? type,
    String? source,
  }) {
    final d = date ?? _isoDay(DateTime.now());
    return db.getCashbookDailySummary(d,
        mode: mode, type: type, source: source);
  }

  // ---------------------------------------------------------- customer IDs
  // Book-style IDs: a letter + at least two digits, NO hyphen (mobile typing) —
  //   A01, A02 … A99, B01 … B99, … Z99,
  //   then A001 … Z999, and A0001 … when a letter runs out again.
  // Older rows may still hold hyphenated IDs (A-01); the regex accepts both
  // and everything is normalised to the hyphen-free form on read/write.
  // The number is the searchable book number shown wherever a customer is
  // listed (khata card, pawn loan, profile, search results).

  static final _bookIdRe = RegExp(r'^([A-Za-z])\s*-?\s*(\d+)$');

  /// "B07" (or legacy "B-07") -> (width 2, letter index 1, number 7).
  /// Null when not a book ID.
  static (int, int, int)? _parseBookId(String raw) {
    final m = _bookIdRe.firstMatch(raw.trim());
    if (m == null) return null;
    final letter = m.group(1)!.toUpperCase().codeUnitAt(0) - 65; // A = 0
    if (letter < 0 || letter > 25) return null;
    final digits = m.group(2)!;
    final n = int.tryParse(digits) ?? 0;
    if (n <= 0) return null;
    return (digits.length, letter, n);
  }

  static String _formatBookId(int width, int letter, int n) =>
      '${String.fromCharCode(65 + letter)}${n.toString().padLeft(width, '0')}';

  /// Hyphen-free canonical form: "a-03" -> "A03". Returns the trimmed input
  /// unchanged when it is not a book ID.
  static String normalizeBookId(String raw) {
    final p = _parseBookId(raw);
    if (p == null) return raw.trim();
    return _formatBookId(p.$1, p.$2, p.$3);
  }

  /// The ID that follows (width, letter, number) in the book sequence.
  static (int, int, int) _bookSuccessor(int width, int letter, int n) {
    final max = (math.pow(10, width) - 1).toInt(); // 99, 999, 9999…
    if (n < max) return (width, letter, n + 1);
    if (letter < 25) return (width, letter + 1, 1);
    return (width + 1, 0, 1); // Z-99 -> A-001
  }

  static bool _bookGt((int, int, int) a, (int, int, int) b) {
    if (a.$1 != b.$1) return a.$1 > b.$1;
    if (a.$2 != b.$2) return a.$2 > b.$2;
    return a.$3 > b.$3;
  }

  /// Highest book ID in use, in book order (Z-99 beats A-5000's neighbours).
  static (int, int, int)? _highestBookId(Iterable<String> ids) {
    (int, int, int)? best;
    for (final raw in ids) {
      final p = _parseBookId(raw);
      if (p == null) continue;
      if (best == null || _bookGt(p, best)) best = p;
    }
    return best;
  }

  /// Next customer ID. Order of preference:
  /// 1. freed pool (IDs of deleted customers are reused first),
  /// 2. continue after the last ID handed out (`customer_id_next`),
  /// 3. continue after the highest ID currently in use.
  Future<String> nextCustomerId() async {
    final pool = await db.query('customer_id_pool', orderBy: 'id asc');
    if (pool.isNotEmpty) {
      final id = pool.first['id']!.toString();
      await db.deleteWhere('customer_id_pool', 'id = ?', [id]);
      return id;
    }
    final seed = await db.getSetting('customer_id_next');
    (int, int, int) last;
    final seedParts = (seed == null) ? null : _parseBookId(seed);
    if (seedParts != null) {
      last = seedParts;
    } else {
      final rows = await db.query('customers', columns: ['customer_id']);
      last =
          _highestBookId(rows.map((r) => r['customer_id']?.toString() ?? '')) ??
              (2, 0, 0);
    }
    final next = _bookSuccessor(last.$1, last.$2, last.$3);
    final id = _formatBookId(next.$1, next.$2, next.$3);
    await db.setSetting('customer_id_next', id);
    return id;
  }

  /// New-customer ID entry. Blank [input] -> auto sequence ([nextCustomerId]).
  /// A typed ID (e.g. "C07", "c7", "B 12", legacy "C-07") is normalised to
  /// "C07" / "B12" and the sequence continues from it. Throws [StateError] if
  /// the ID already belongs to another customer or is not letter + digits.
  Future<String> claimCustomerId(String? input, {String? excludeUuid}) async {
    final raw = (input ?? '').trim();
    if (raw.isEmpty) return nextCustomerId();
    final m = _bookIdRe.firstMatch(raw);
    String normalized;
    if (m != null) {
      final letter = m.group(1)!.toUpperCase();
      final digits = m.group(2)!;
      final width = digits.length < 2 ? 2 : digits.length;
      normalized = '$letter${digits.padLeft(width, '0')}';
    } else {
      final n = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
      if (n == null || n <= 0) {
        throw StateError('Customer ID must be a letter + digits (e.g. A01)');
      }
      // Digits only: keep the letter the sequence is currently on.
      final seed = await db.getSetting('customer_id_next');
      final letter = _parseBookId(seed ?? '')?.$2 ?? 0;
      normalized = _formatBookId(2, letter, n);
    }
    final rows =
        await db.query('customers', columns: ['client_uuid', 'customer_id']);
    for (final r in rows) {
      if (r['client_uuid'] == excludeUuid) continue;
      final existing = normalizeBookId(r['customer_id']?.toString() ?? '');
      if (existing.toUpperCase() == normalized.toUpperCase()) {
        throw StateError(
            'Customer ID $normalized is already used by another customer');
      }
    }
    final pool = await db
        .query('customer_id_pool', where: 'id = ?', whereArgs: [normalized]);
    if (pool.isNotEmpty) {
      await db.deleteWhere('customer_id_pool', 'id = ?', [normalized]);
    }
    // Legacy hyphenated pool entries (A-01) equal the normalized ID.
    final legacyHyphen =
        '${normalized.substring(0, 1)}-${normalized.substring(1)}';
    await db.deleteWhere('customer_id_pool', 'id = ?', [legacyHyphen]);
    await db.setSetting('customer_id_next', normalized);
    return normalized;
  }

  /// Puts a customer's ID back into the freed pool (called on delete) so the
  /// next new customer reuses it.
  Future<void> freeCustomerId(String? id) async {
    if (id == null || id.trim().isEmpty) return;
    await db.upsert('customer_id_pool', {
      'id': normalizeBookId(id),
      'freed_at': DateTime.now().toIso8601String(),
    });
  }

  /// One-time normalisation: rewrite hyphenated IDs (A-01) to hyphen-free
  /// (A01) across customers, the freed pool and the sequence setting.
  Future<void> normalizeCustomerIds() async {
    try {
      final rows =
          await db.query('customers', columns: ['client_uuid', 'customer_id']);
      for (final r in rows) {
        final raw = r['customer_id']?.toString() ?? '';
        if (raw.contains('-')) {
          final norm = normalizeBookId(raw);
          if (norm != raw) {
            final full = await db.byUuid(
                'customers', r['client_uuid']?.toString() ?? '');
            if (full != null) {
              await db.upsert(
                  'customers', {...full, 'customer_id': norm, 'dirty': 1});
            }
          }
        }
      }
      final pool = await db.query('customer_id_pool');
      for (final p in pool) {
        final raw = p['id']?.toString() ?? '';
        if (raw.contains('-')) {
          final norm = normalizeBookId(raw);
          if (norm != raw) {
            await db.deleteWhere('customer_id_pool', 'id = ?', [raw]);
            await db.upsert('customer_id_pool', {
              'id': norm,
              'freed_at': DateTime.now().toIso8601String(),
            });
          }
        }
      }
      final next = await db.getSetting('customer_id_next');
      if (next != null && next.contains('-')) {
        await db.setSetting('customer_id_next', normalizeBookId(next));
      }
    } catch (error) {
      debugPrint('normalize customer ids failed: $error');
    }
  }

  /// Assigns IDs to any customers still missing one (legacy / demo rows), in
  /// row order, reusing freed IDs first. Safe to run at every start-up.
  Future<void> backfillCustomerIds() async {
    try {
      final missing = await db.query('customers',
          where: 'customer_id IS NULL OR customer_id = ?', whereArgs: ['']);
      if (missing.isEmpty) return;
      for (final c in missing) {
        final id = await nextCustomerId();
        await db.upsert('customers', {...c, 'customer_id': id, 'dirty': 1});
      }
    } catch (error) {
      debugPrint('backfill customer ids failed: $error');
    }
  }

  /// v1.0.9: IDs used to be plain numbers (1, 2, 3 …). The shop's book scheme
  /// is A01 … Z99 → A001 …, so any legacy numeric ID is re-issued once, in
  /// customer order. A no-op on every start-up after the first run.
  Future<void> migrateCustomerIdScheme() async {
    try {
      if (await db.getSetting('customer_id_scheme') == 'book') return;
      // Full rows: upsert() replaces, so a partial row would wipe the customer.
      final rows = await db.query('customers', orderBy: 'updated_at asc');
      final legacy = rows
          .where(
              (r) => _parseBookId(r['customer_id']?.toString() ?? '') == null)
          .toList();
      if (legacy.isEmpty) {
        await db.setSetting('customer_id_scheme', 'book');
        return;
      }
      final used = <String>{
        for (final r in rows)
          if (_parseBookId(r['customer_id']?.toString() ?? '') != null)
            normalizeBookId(r['customer_id']?.toString() ?? '').toUpperCase()
      };
      var cursor = _highestBookId(used) ?? (2, 0, 0);
      for (final c in legacy) {
        var next = _bookSuccessor(cursor.$1, cursor.$2, cursor.$3);
        var id = _formatBookId(next.$1, next.$2, next.$3);
        while (used.contains(id)) {
          next = _bookSuccessor(next.$1, next.$2, next.$3);
          id = _formatBookId(next.$1, next.$2, next.$3);
        }
        cursor = next;
        used.add(id);
        await db.upsert('customers', {...c, 'customer_id': id, 'dirty': 1});
      }
      await db.setSetting(
          'customer_id_next', _formatBookId(cursor.$1, cursor.$2, cursor.$3));
      await db.setSetting('customer_id_scheme', 'book');
    } catch (error) {
      debugPrint('customer id scheme migration failed: $error');
    }
  }

  // ---------------------------------------------------------------- history
  /// Records an activity/deletion event for the History screen.
  Future<void> logEvent(String module, String kind, String title,
      {double amount = 0, String? village, String? ref}) async {
    try {
      await db.upsert('history_log', {
        'module': module,
        'kind': kind,
        'title': title,
        'amount': Num.rupees(amount),
        'village': village,
        'loan_ref': ref,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (error) {
      debugPrint('history log failed: $error');
    }
  }

  // ------------------------------------------------------- sample data
  /// The single canonical writer for a khata collection.
  ///
  /// Every rupee that comes in goes through here: the Collect dialog on the
  /// profile, the one on the loan sheet, and the sample seeder. Money is
  /// allocated by [KhataAlloc] (interest -> late fee -> other -> principal),
  /// the resulting component balances are written back, and the per-rupee
  /// allocation rows are recorded so the ledger can always be explained.
  ///
  /// Sample data MUST go through this rather than a hand-written shortcut:
  /// v1.0.20's seeder wrote `outstanding` by hand and left the v10 component
  /// columns empty, so every sample balance disagreed with the real engine.
  Future<void> applyCollection({
    required Map<String, Object?> loan,
    required double amount,
    required DateTime receivedOn,
    String mode = 'Cash',
  }) async {
    if (amount <= 0) return;
    final loanUuid = '${loan['client_uuid'] ?? ''}';
    if (loanUuid.isEmpty) return;

    final collectionUuid = newUuid();
    await db.upsert('khatabook_collections', {
      'client_uuid': collectionUuid,
      'dirty': 1,
      'khatabook_loan': loanUuid,
      'customer': loan['customer'],
      // khatabook_collections has NO customer_name column (the name lives on
      // the loan and is reached through customer_uuid). Writing one aborted
      // the insert, so a seeded payment silently vanished.
      'customer_uuid': loan['customer_uuid'] ?? loan['customer'],
      'village': loan['village'],
      'collection_date': _isoDay(receivedOn),
      'amount': Num.rupees(amount),
      'payment_mode': mode,
      'is_irregular': 0,
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Auto-hook: Khata Collection -> Cash IN
    final now = DateTime.now();
    await db.addCashbookEntry({
      'client_uuid': newUuid(),
      'entry_date': _isoDay(receivedOn),
      'entry_time':
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
      'entry_type': 'IN',
      'amount': Num.rupees(amount),
      'payment_mode': mode.toUpperCase(),
      'category': 'KHATA_COLLECTION',
      // The collection row is the source, so deleting/editing that row can
      // find its cash entry. Older builds stored the loan uuid here.
      'reference_id': collectionUuid,
      'party_name': loan['customer_name']?.toString() ?? '',
      'notes': 'Khata collection payment',
      'created_at': now.toIso8601String(),
      'dirty': 1,
    });

    // Re-read the loan: an earlier sample payment may have moved it on.
    final fresh = await db.byUuid('khatabook_loans', loanUuid) ?? loan;
    final before = KhataLoanState.fromRow(fresh);
    final allocation = KhataAlloc.allocate(
      payment: amount,
      interestDue: before.interestOutstanding,
      lateFeeDue: before.lateFeeOutstanding,
      otherChargeDue: before.otherChargeOutstanding,
      principalDue: before.investment,
    );
    final after = KhataLoanState.apply(before, allocation);
    final collected = KhataMath.addToCollected(
      already: Num.toDouble(fresh['total_collected']),
      payment: amount,
      totalPayable: Num.toDouble(fresh['total_payable']),
    );
    await db.upsert('khatabook_loans', {
      ...fresh,
      ...after.toRow(),
      'total_collected': collected,
      'paid_installments': KhataMath.paidInstallments(
        collected: collected,
        totalPayable: Num.toDouble(fresh['total_payable']),
        count: (fresh['installment_count'] as num?)?.toInt() ?? 0,
      ),
      'dirty': 1,
    });
    await recordAllocations(
      loanUuid: loanUuid,
      collectionUuid: collectionUuid,
      allocation: allocation,
    );
  }

  /// Records a "You Gave" charge against a loan (a fresh principal top-up, a
  /// late fee, another charge) exactly as the You Gave dialog does: a dated
  /// `khatabook_collections`-style row on the given side, the component added
  /// to the loan, and the running balances kept true.
  Future<void> _addGiven({
    required Map<String, Object?> loan,
    required double amount,
    required String kind,
    String note = '',
    DateTime? on,
  }) async {
    if (amount <= 0) return;
    final loanUuid = '${loan['client_uuid'] ?? ''}';
    if (loanUuid.isEmpty) return;
    final day = on ?? DateTime.now();
    await db.upsert('khatabook_given', {
      'client_uuid': newUuid(),
      'dirty': 1,
      'khatabook_loan': loanUuid,
      'customer': loan['customer'],
      'customer_uuid': loan['customer_uuid'] ?? loan['customer'],
      'customer_name': loan['customer_name'],
      'given_date': _isoDay(day),
      'amount': Num.rupees(amount),
      'given_type': kind,
      'note': note,
      'updated_at': DateTime.now().toIso8601String(),
    });
    final before = KhataLoanState.fromRow(loan);
    final after = switch (kind) {
      'principal' => KhataLoanState(
          originalPrincipal: Num.rupees(before.originalPrincipal + amount),
          principalRecovered: before.principalRecovered,
          interestOutstanding: before.interestOutstanding,
          lateFeeOutstanding: before.lateFeeOutstanding,
          otherChargeOutstanding: before.otherChargeOutstanding,
          unappliedCredit: before.unappliedCredit,
          status: before.status),
      'late_fee' => before.copyWith(
          lateFeeOutstanding: Num.rupees(before.lateFeeOutstanding + amount)),
      _ => before.copyWith(
          otherChargeOutstanding:
              Num.rupees(before.otherChargeOutstanding + amount)),
    };
    final totalPayable =
        Num.rupees(Num.toDouble(loan['total_payable']) + amount);
    await db.upsert('khatabook_loans', {
      ...loan,
      ...after.toRow(),
      'principal_amount': kind == 'principal'
          ? Num.rupees(Num.toDouble(loan['principal_amount']) + amount)
          : loan['principal_amount'],
      'total_payable': totalPayable,
      'outstanding': Num.rupees(after.outstandingBalance),
      'dirty': 1,
    });
  }

  /// v1.0.21: a full KHATABOOK test matrix, one member per visible condition,
  /// named after that condition so the list explains itself:
  ///
  ///   Sample_DueToday         red chip - an installment falls due today
  ///   Sample_Overdue_4Days    red chip - four days late
  ///   Sample_Overdue_Arrears  red chip - three installments missed at once
  ///   Sample_Upcoming         blue chip - next due is in the future
  ///   Sample_OnTime           green ON TIME - nothing due
  ///   Sample_FullyPaid        closed loan, nothing outstanding
  ///   Sample_PartPaid         one paid, next due still ahead
  ///   Sample_LateFee          a late fee outstanding alongside the schedule
  ///   Sample_InterestOnly     interest-only loan with billed periods
  ///   Sample_Refinanced       refinanced: old frozen, new loan split in three
  ///   Sample_NoDueDate        no schedule at all (No Due Date filter)
  ///
  /// Every balance is produced by [applyCollection] and [KhataLoanState], the
  /// same engine the real screens use, so nothing here can drift from the app.
  /// Safe to run twice: existing sample names are skipped.
  Future<int> addSampleMembers() async {
    var added = 0;
    try {
      final today = DateTime.now();

      // Members must live in a khata that exists, or they cannot be opened
      // from anywhere in Khatabook. Reuse the shop's Pallipatti khata when it
      // is there, otherwise create one for the sample set.
      const sampleVillage = 'Pallipatti';
      final villageRows = await db.query('villages', columns: ['village_name']);
      final villageName = villageRows
          .map((v) => (v['village_name']?.toString() ?? '').trim())
          .firstWhere((v) => v.toLowerCase() == sampleVillage.toLowerCase(),
              orElse: () => '');
      if (villageName.isEmpty) {
        await db.upsert('villages', {
          'client_uuid': 'v-sample-members',
          'village_name': sampleVillage,
          'notes': 'Created by "Add sample data" — safe to delete',
          'updated_at': DateTime.now().toIso8601String(),
          'dirty': 1,
        });
      }
      final village = villageName.isEmpty ? sampleVillage : villageName;

      final existing = await db.query('customers', columns: ['customer_name']);
      final have = existing
          .map((c) => (c['customer_name']?.toString() ?? '').toLowerCase())
          .toSet();

      // (name, phone, business, principal, interest, count, frequency,
      //  daysAgoStart, lateFee, interestOnly, noDueDate, refinance,
      //  payments: (amount, daysAgoReceived))
      final specs = <(
        String,
        String,
        String,
        double,
        double,
        int,
        String,
        int,
        double,
        bool,
        bool,
        bool,
        List<(double, int)>
      )>[
        // start 7 days back, weekly -> first due is TODAY, unpaid = red.
        (
          'Sample_DueToday',
          '9000000001',
          'Grocer',
          12000,
          2400,
          12,
          'Weekly',
          7,
          0,
          false,
          false,
          false,
          <(double, int)>[]
        ),
        // start 11 days back -> first due 4 days ago, unpaid = red + late.
        (
          'Sample_Overdue_4Days',
          '9000000002',
          'Tailor',
          8000,
          1600,
          10,
          'Weekly',
          11,
          0,
          false,
          false,
          false,
          <(double, int)>[]
        ),
        // start 30 days back, weekly -> dues 23/16/9 days ago all missed.
        (
          'Sample_Overdue_Arrears',
          '9000000003',
          'Business',
          12000,
          2400,
          12,
          'Weekly',
          30,
          0,
          false,
          false,
          false,
          <(double, int)>[]
        ),
        // start 2 days back -> first due 5 days ahead = blue.
        (
          'Sample_Upcoming',
          '9000000004',
          'Shop',
          10000,
          2000,
          10,
          'Weekly',
          2,
          0,
          false,
          false,
          false,
          <(double, int)>[]
        ),
        // start 20 days back, biweekly -> dues 6 days ago and 8 days ahead.
        // Pay the first in full, so what is left sits in the future = blue.
        (
          'Sample_PartPaid',
          '9000000005',
          'Tailor',
          15000,
          3000,
          8,
          'Biweekly',
          20,
          0,
          false,
          false,
          false,
          <(double, int)>[(4500, 18)]
        ),
        // Two monthly dues behind, nothing paid since = red arrears.
        (
          'Sample_LateFee',
          '9000000006',
          'Business',
          9000,
          1800,
          6,
          'Monthly',
          75,
          300,
          false,
          false,
          false,
          <(double, int)>[(1800, 40)]
        ),
        // Fully settled: nothing left to collect = green ON TIME.
        // 4 x 1800 = 7200 = the whole obligation, so this one is genuinely
        // settled and shows the green ON TIME chip. v1.0.21 first shipped this
        // with only 2 of 4 paid, which still showed a red DUE chip.
        (
          'Sample_FullyPaid',
          '9000000007',
          'Grocer',
          6000,
          1200,
          4,
          'Monthly',
          150,
          0,
          false,
          false,
          false,
          <(double, int)>[(1800, 130), (1800, 100), (1800, 70), (1800, 40)]
        ),
        // Interest-only: one fixed monthly interest, billed per period.
        (
          'Sample_InterestOnly',
          '9000000008',
          'Landlord',
          20000,
          2000,
          12,
          'Monthly',
          70,
          0,
          true,
          false,
          false,
          <(double, int)>[(2000, 60), (2000, 30)]
        ),
        // Old loan frozen as REFINANCED, new loan = previous outstanding +
        // fresh cash + new interest, linked by khatabook_refinances.
        (
          'Sample_Refinanced',
          '9000000009',
          'Business',
          30000,
          6000,
          12,
          'Monthly',
          90,
          0,
          false,
          false,
          true,
          <(double, int)>[(3000, 60)]
        ),
        // Overdue AND carrying no reminder date. v1.0.21 shipped this as
        // "Sample_NoReminder" with a BLANK frequency, which _frequencyName
        // silently reads as Weekly — so the row showed "DUE 3 DAYS AGO" under a
        // name that said it had no due date. An empty frequency is also
        // impossible in the real loan form (it always defaults to Weekly), so
        // it was a made-up state. Now it is honestly named and honestly
        // overdue.
        (
          'Sample_Overdue_NoReminder',
          '9000000010',
          'Shop',
          5000,
          500,
          10,
          'Weekly',
          10,
          0,
          false,
          true,
          false,
          <(double, int)>[]
        ),
        // Already living in the Loss Khata (village = Loss) so that screen has
        // something in it. A real move is a village change only; loans,
        // collections and history all stay with the member.
        (
          'Sample_InLoss',
          '9000000011',
          'Uncollected',
          8000,
          1600,
          10,
          'Weekly',
          80,
          0,
          false,
          false,
          false,
          <(double, int)>[]
        ),
      ];

      for (final s in specs) {
        if (have.contains(s.$1.toLowerCase())) continue;
        final cu = newUuid();
        final start = today.subtract(Duration(days: s.$8));
        final total = Num.rupees(s.$4 + s.$5);

        // The Loss member must sit in the reserved Loss khata, which is just a
        // village named 'Loss' (MigrationV12). Moving a customer there is a
        // village change; everything else about them stays.
        final memberVillage =
            s.$1 == 'Sample_InLoss' ? MigrationV12.lossVillageName : village;
        await db.upsert('customers', {
          'client_uuid': cu,
          'customer_name': s.$1,
          'phone': s.$2,
          'village': memberVillage,
          'previous_village': s.$1 == 'Sample_InLoss' ? village : null,
          'customer_type': 'Khatabook',
          'status': 'Active',
          'customer_id': await nextCustomerId(),
          'updated_at': DateTime.now().toIso8601String(),
          'dirty': 1,
        });

        // No reminder_date is seeded on purpose. A reminder OVERRIDES the
        // loan schedule in the due display (the shopkeeper's word wins), so
        // seeding one turned every overdue sample blue and hid the very chips
        // the matrix exists to show. The schedule alone must produce red /
        // blue / green, which is the real rule worth testing.

        // A reminder date OVERRIDES the loan schedule in the due display — the
        // shopkeeper's word wins. So it is only seeded where the schedule
        // already points into the future; giving one to an overdue member would
        // repaint its red chip blue and hide the arrears the sample exists to
        // show. This also makes the "No Due Date" filter (which really means
        // "no reminder set") discriminate instead of listing everyone.
        const remindable = {
          'Sample_Upcoming',
          'Sample_PartPaid',
          'Sample_InterestOnly',
          'Sample_Refinanced',
        };
        if (remindable.contains(s.$1)) {
          await db.upsert('customers', {
            'client_uuid': cu,
            'reminder_date': _isoDay(today.add(const Duration(days: 4))),
            'dirty': 1,
          });
        }

        // The loan itself is the first "You Gave" row; _addGiven records it
        // the same way the dialog does, so the ledger reads exactly like one a
        // shopkeeper typed by hand: money out on the start date, then each
        // part-payment on its own dated line.
        final loanUuid = newUuid();
        await db.upsert('khatabook_loans', {
          'client_uuid': loanUuid,
          'dirty': 1,
          'customer': cu,
          'customer_uuid': cu,
          'customer_name': s.$1,
          'phone': s.$2,
          'village': memberVillage,
          'business': s.$3,
          'status': 'Active',
          'loan_date': _isoDay(start),
          'start_date': _isoDay(start),
          'end_date': s.$11
              ? null
              : _isoDay(_addSteps(DateTime(start.year, start.month, start.day),
                  s.$6 * KhataSchedule.intervalDays(s.$7), s.$7)),
          'principal_amount': s.$4,
          'interest_amount': s.$5,
          'total_payable': total,
          'installment_count': s.$6,
          'installment_amount': s.$6 == 0 ? 0 : Num.rupees(total / s.$6),
          'collection_frequency': s.$7,
          'paid_installments': 0,
          'total_collected': 0,
          'outstanding': total,
          // ---- v10 component balances. The old seeder left these empty,
          // which made every sample balance disagree with the real engine.
          'original_principal': s.$4,
          'expected_interest': s.$5,
          'expected_repayment': total,
          'principal_recovered': 0,
          'principal_outstanding': s.$4,
          'interest_outstanding': s.$10 ? 0 : s.$5,
          // Added later by _addGiven as a dated charge; must not be
          // seeded here as well or it would be counted twice.
          'late_fee_outstanding': 0,
          'other_charge_outstanding': 0,
          'unapplied_credit': 0,
          'payment_type': s.$10 ? 'INTEREST_ONLY' : 'INSTALLMENT',
          'current_interest': s.$5,
          'updated_at': DateTime.now().toIso8601String(),
        });

        // Payments, oldest first, each through the canonical engine.
        var loan = await db.byUuid('khatabook_loans', loanUuid);
        if (loan == null) continue;
        var current = loan;
        for (final p in s.$13) {
          await applyCollection(
            loan: current,
            amount: p.$1,
            receivedOn: today.subtract(Duration(days: p.$2)),
          );
          current = await db.byUuid('khatabook_loans', loanUuid) ?? current;
        }

        // Late fee as its own dated "You Gave" entry, so the arrears member
        // shows a charge line the way a real one would.
        if (s.$9 > 0) {
          await _addGiven(
            loan: current,
            amount: s.$9,
            kind: 'late_fee',
            note: 'Late fee',
            on: today.subtract(Duration(days: 5)),
          );
          current = await db.byUuid('khatabook_loans', loanUuid) ?? current;
        }

        // Interest-only loans bill one period at a time as the days pass.
        if (s.$10) {
          await ensureInterestPeriods(current, today: today);
          current = await db.byUuid('khatabook_loans', loanUuid) ?? current;
        }

        // Refinance: freeze this loan and open the new three-part loan.
        if (s.$12) {
          await executeRefinance(
            oldLoan: current,
            fresh: 25000,
            interest: 5000,
            paymentType: 'INSTALLMENT',
            frequency: 'Monthly',
            count: 12,
            collectionAmount: 0,
          );
        }
        added++;
      }
      await db.setSetting('sample_members_added', '1');
      await refreshCounts();
    } catch (error) {
      debugPrint('sample data failed: $error');
    }
    return added;
  }

  /// Deletes events older than [before] (retention-based auto-clear).
  Future<void> purgeHistory(DateTime before) async {
    await db.delete('history_log',
        where: 'created_at < ?', whereArgs: [before.toIso8601String()]);
  }

  /// "Clear Now" — wipes the whole history (admin-password guarded).
  Future<void> clearHistory() async {
    await db.delete('history_log');
  }

  // ---------------------------------------------------------------- QR codes
  /// Bank / UPI QR codes for the shop (gallery paths, swipe-between view).
  Future<List<Map<String, Object?>>> qrCodes() =>
      db.query('qr_codes', orderBy: 'id asc');

  Future<void> addQrCode(String label, String path) => db.upsert('qr_codes', {
        'label': label,
        'path': path,
        'created_at': DateTime.now().toIso8601String(),
      });

  Future<void> updateQrLabel(int id, String label) =>
      db.upsert('qr_codes', {'id': id, 'label': label});

  Future<void> deleteQrCode(int id) =>
      db.deleteWhere('qr_codes', 'id = ?', [id]);

  // ------------------------------------------------------- admin confirmation
  /// Whether the admin-password step guards delete / release actions.
  /// Off means destructive actions run on the drag/confirm alone.
  Future<void> setAdminConfirm(bool value) async {
    adminConfirm = value;
    await db.setSetting('admin_confirm', value ? '1' : '0');
    notifyListeners();
  }

  // --------------------------------------------------------- user profile
  Future<void> setUserField(String key, String value) async {
    await db.setSetting(key, value);
    switch (key) {
      case 'user_photo':
        userPhoto = value;
      case 'user_phone':
        userPhone = value;
      case 'user_email':
        userEmail = value;
      case 'user_name':
        userName = value;
    }
    notifyListeners();
  }

  /// Total bytes of the app's own data on the phone: the SQLite database(s)
  /// plus every stored photo / image. Used by the About App screen.
  Future<int> appDataBytes() async {
    var total = 0;
    try {
      final docs = await getApplicationDocumentsDirectory();
      total += await _dirSize(docs);
      final dbPath = await getDatabasesPath();
      total += await _dirSize(Directory(dbPath));
    } catch (_) {/* no path on web preview */}
    return total;
  }

  Future<int> _dirSize(Directory dir) async {
    var total = 0;
    try {
      await for (final f in dir.list(recursive: true, followLinks: false)) {
        if (f is File) {
          try {
            total += await f.length();
          } catch (_) {}
        }
      }
    } catch (_) {/* directory may not exist yet */}
    return total;
  }
}
