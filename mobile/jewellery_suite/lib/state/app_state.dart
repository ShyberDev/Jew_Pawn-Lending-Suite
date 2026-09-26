import 'dart:io';
import 'dart:math' as math;

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
    await migrateCustomerIdScheme();
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
  // Book-style IDs: a letter + at least two digits —
  //   A-01, A-02 … A-99, B-01 … B-99, … Z-99,
  //   then A-001 … Z-999, and A-0001 … when a letter runs out again.
  // The number is the searchable book number shown wherever a customer is
  // listed (khata card, pawn loan, profile, search results).

  static final _bookIdRe = RegExp(r'^([A-Za-z])\s*-\s*(\d+)$');

  /// "B-07" -> (width 2, letter index 1, number 7). Null when not a book ID.
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
      '${String.fromCharCode(65 + letter)}-${n.toString().padLeft(width, '0')}';

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
      last = _highestBookId(rows.map((r) => r['customer_id']?.toString() ?? '')) ??
          (2, 0, 0);
    }
    final next = _bookSuccessor(last.$1, last.$2, last.$3);
    final id = _formatBookId(next.$1, next.$2, next.$3);
    await db.setSetting('customer_id_next', id);
    return id;
  }

  /// New-customer ID entry. Blank [input] -> auto sequence ([nextCustomerId]).
  /// A typed ID (e.g. "C-07", "c7", "B 12") is normalised to "C-07" / "B-12"
  /// and the sequence continues from it. Throws [StateError] if the ID already
  /// belongs to another customer or is not letter + digits.
  Future<String> claimCustomerId(String? input, {String? excludeUuid}) async {
    final raw = (input ?? '').trim();
    if (raw.isEmpty) return nextCustomerId();
    final m = _bookIdRe.firstMatch(raw);
    String normalized;
    if (m != null) {
      final letter = m.group(1)!.toUpperCase();
      final digits = m.group(2)!;
      final width = digits.length < 2 ? 2 : digits.length;
      normalized = '$letter-${digits.padLeft(width, '0')}';
    } else {
      final n = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
      if (n == null || n <= 0) {
        throw StateError('Customer ID must be a letter + digits (e.g. A-01)');
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
      final existing = r['customer_id']?.toString() ?? '';
      if (existing.toUpperCase() == normalized.toUpperCase()) {
        throw StateError(
            'Customer ID $normalized is already used by another customer');
      }
    }
    final pool =
        await db.query('customer_id_pool', where: 'id = ?', whereArgs: [normalized]);
    if (pool.isNotEmpty) {
      await db.deleteWhere('customer_id_pool', 'id = ?', [normalized]);
    }
    await db.setSetting('customer_id_next', normalized);
    return normalized;
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

  /// v1.0.9: IDs used to be plain numbers (1, 2, 3 …). The shop's book scheme
  /// is A-01 … Z-99 → A-001 …, so any legacy numeric ID is re-issued once, in
  /// customer order. A no-op on every start-up after the first run.
  Future<void> migrateCustomerIdScheme() async {
    try {
      if (await db.getSetting('customer_id_scheme') == 'book') return;
      // Full rows: upsert() replaces, so a partial row would wipe the customer.
      final rows =
          await db.query('customers', orderBy: 'updated_at asc');
      final legacy = rows
          .where((r) => _parseBookId(r['customer_id']?.toString() ?? '') == null)
          .toList();
      if (legacy.isEmpty) {
        await db.setSetting('customer_id_scheme', 'book');
        return;
      }
      final used = <String>{
        for (final r in rows)
          if (_parseBookId(r['customer_id']?.toString() ?? '') != null)
            (r['customer_id']?.toString() ?? '').toUpperCase()
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
        await db.upsert('customers',
            {...c, 'customer_id': id, 'dirty': 1});
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
