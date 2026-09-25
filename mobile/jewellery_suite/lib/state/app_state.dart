import 'package:flutter/foundation.dart';

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
    await refreshCounts();
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
}
