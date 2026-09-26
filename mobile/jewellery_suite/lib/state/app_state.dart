import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../data/api_client.dart';
import '../data/local_db.dart';
import '../data/sync_service.dart';
import '../util/format.dart';

/// Single source of truth for the UI: session, local data helpers and sync.
class AppState extends ChangeNotifier {
  final LocalDb db;
  ApiClient? api;

  bool loggedIn = false;
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
    await backfillCustomerIds();
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

  Future<void> login(String url, String usr, String pwd) async {
    final client = ApiClient(baseUrl: url);
    await client.login(usr, pwd);
    api = client;
    _user = usr;
    loggedIn = true;
    await db.setSetting('server_url', url);
    await db.setSetting('sid', client.sid);
    await db.setSetting('user', usr);
    notifyListeners();
  }

  Future<void> logout() async {
    api = null;
    _user = null;
    loggedIn = false;
    await db.setSetting('sid', null);
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

  Future<List<Map<String, Object?>>> itemsFor(String loanUuid) {
    return db.query('pawn_items',
        where: 'loan_uuid = ?', whereArgs: [loanUuid], orderBy: 'id asc');
  }

  // --------------------------------------------------------------- dashboard
  Future<Map<String, Object?>> dashboard() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return {
      'customers': await db.count('customers'),
      'active_pawn': await db.count('pawn_loans',
          where: 'status = ? OR status IS NULL', whereArgs: ['Active']),
      'pawn_out': await db.sum('pawn_loans', 'loan_amount',
          where: 'status = ? OR status IS NULL', whereArgs: ['Active']),
      'pawn_payable': await db.sum('pawn_loans', 'total_payable',
          where: 'status = ? OR status IS NULL', whereArgs: ['Active']),
      'pawn_paid': await db.sum('pawn_loans', 'amount_paid',
          where: 'status = ? OR status IS NULL', whereArgs: ['Active']),
      'khatabook_active': await db.count('khatabook_loans',
          where: 'status = ? OR status IS NULL', whereArgs: ['Active']),
      'khatabook_principal': await db.sum('khatabook_loans', 'principal_amount',
          where: 'status = ? OR status IS NULL', whereArgs: ['Active']),
      'khatabook_outstanding': await db.sum('khatabook_loans', 'outstanding',
          where: 'status = ? OR status IS NULL', whereArgs: ['Active']),
      'collected_today': await db.sum('khatabook_collections', 'amount',
          where: 'collection_date = ?', whereArgs: [today]),
    };
  }

  // ---------------------------------------------------------- customer IDs
  /// Next customer ID. Order of preference:
  /// 1. freed pool (deleted customer IDs are reused first),
  /// 2. the user-seeded "book" number (`customer_id_next`, set when the user
  ///    typed a start like 5102 — every following customer auto-continues 5103…),
  /// 3. largest numeric ID in use + 1 (keeps counting when no seed is given).
  Future<String> nextCustomerId() async {
    final pool = await db.query('customer_id_pool', orderBy: 'id asc');
    if (pool.isNotEmpty) {
      final id = pool.first['id']!.toString();
      await db
          .deleteWhere('customer_id_pool', 'id = ?', [id]);
      return id;
    }
    final seed = await db.getSetting('customer_id_next');
    if (seed != null) {
      final n = int.tryParse(seed.trim()) ?? 0;
      if (n > 0) {
        await db.setSetting('customer_id_next', '${n + 1}');
        return n.toString();
      }
    }
    final rows = await db.query('customers', columns: ['customer_id']);
    var maxN = 0;
    for (final r in rows) {
      final id = r['customer_id']?.toString() ?? '';
      final n = int.tryParse(RegExp(r'\d+').firstMatch(id)?.group(0) ?? '');
      if (n != null && n > maxN) maxN = n;
    }
    return '${maxN + 1}';
  }

  /// New-customer ID entry. Blank [input] → auto sequence ([nextCustomerId]).
  /// A typed start (e.g. "5102") is used as-is and seeds `customer_id_next` so
  /// the following customers continue (5103…). Throws [StateError] if a typed
  /// ID already belongs to another customer.
  Future<String> claimCustomerId(String? input, {String? excludeUuid}) async {
    final raw = (input ?? '').trim();
    if (raw.isEmpty) return nextCustomerId();
    final rows = await db.query('customers', columns: ['client_uuid', 'customer_id']);
    for (final r in rows) {
      if (r['client_uuid'] == excludeUuid) continue;
      if (r['customer_id']?.toString() == raw) {
        throw StateError('Customer ID $raw is already used by another customer');
      }
    }
    final pool = await db.query('customer_id_pool',
        where: 'id = ?', whereArgs: [raw]);
    if (pool.isNotEmpty) {
      await db.deleteWhere('customer_id_pool', 'id = ?', [raw]);
    }
    final n = int.tryParse(raw);
    if (n != null && n > 0) {
      await db.setSetting('customer_id_next', '${n + 1}');
    }
    return raw;
  }

  /// Puts a customer's ID back into the freed pool (called on delete) so the
  /// next new customer reuses it.
  Future<void> freeCustomerId(String? id) async {
    if (id == null || id.trim().isEmpty) return;
    await db.upsert('customer_id_pool', {
      'id': id.trim(),
      'freed_at': DateTime.now().toIso8601String(),
    });
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

  // ---------------------------------------------------------------- history
  /// Records an activity/deletion event for the History screen.
  Future<void> logEvent(String module, String kind, String title,
      {double amount = 0, String? village, String? ref}) async {
    try {
      await db.upsert('history_log', {
        'module': module,
        'kind': kind,
        'title': title,
        'amount': Num.money(amount),
        'village': village,
        'loan_ref': ref,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (error) {
      debugPrint('history log failed: $error');
    }
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
