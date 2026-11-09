import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../data/local_db.dart';
import 'cloud_time.dart';
import 'firebase_bootstrap.dart';

/// One local table mirrored to a Firestore sub-collection.
class CloudMirror {
  const CloudMirror({
    required this.table,
    required this.collection,
    required this.stamp,
    required this.immutable,
  });

  /// Local SQLite table.
  final String table;

  /// Firestore sub-collection under `shops/{shopId}/`.
  final String collection;

  /// Column used to order pushes (and, for mutable rows, to pick a winner).
  final String stamp;

  /// Movements are an append-only ledger: an existing row is never replaced.
  final bool immutable;
}

/// The shop's cloud status, shown on the Cloud account screen.
@immutable
class CloudSyncState {
  const CloudSyncState({
    this.busy = false,
    this.live = false,
    this.summary = 'Not synced yet.',
    this.error,
  });

  final bool busy;
  final bool live;
  final String summary;
  final String? error;

  CloudSyncState copyWith({
    bool? busy,
    bool? live,
    String? summary,
    String? error,
    bool clearError = false,
  }) =>
      CloudSyncState(
        busy: busy ?? this.busy,
        live: live ?? this.live,
        summary: summary ?? this.summary,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Keeps this phone's stock ledger and worker records in step with every other
/// phone signed in to the same Firebase account.
///
/// Scope, deliberately narrow:
/// * `jewellery_stock_movements` — the single stock ledger. Movements are
///   append-only and keyed by `client_uuid`, so two phones can never apply the
///   same movement twice.
/// * `jewellery_worker_orders` and `jewellery_worker_txns` — the shop's
///   workers (metal issued, returned, cash paid).
///
/// Deletions are not mirrored yet: a removed row stays on the other phone.
/// Invoice headers/payments are not mirrored yet either, so money totals still
/// reconcile through the existing server sync.
class CloudSync {
  CloudSync._();

  static final instance = CloudSync._();

  static const mirrors = <CloudMirror>[
    CloudMirror(
      table: 'jewellery_stock_movements',
      collection: 'stock_movements',
      stamp: 'created_at',
      immutable: true,
    ),
    CloudMirror(
      table: 'jewellery_worker_orders',
      collection: 'worker_orders',
      stamp: 'updated_at',
      immutable: false,
    ),
    CloudMirror(
      table: 'jewellery_worker_txns',
      collection: 'worker_txns',
      stamp: 'updated_at',
      immutable: false,
    ),
  ];

  /// Rows read per push round trip. Kept at 200 because that is what the shop
  /// already ran in the field; the watermark makes the boundary exact.
  static const pushBatchSize = 200;

  /// Upper bound on batches per [syncNow] so one huge backlog cannot hold the
  /// status card on "Syncing…" for ever; the next sync continues where this
  /// stopped.
  static const maxPushBatches = 20;

  /// Shop id used in Firestore paths.
  ///
  /// Phase 1 shops are personal: every phone signs in to the same Firebase
  /// account, so the account's uid *is* the shop. Sharing a shop between
  /// different accounts needs an invite flow and is not built yet.
  static String shopIdFor(String uid) => uid;

  /// Last stamp pushed for [table] (local storage format).
  static String watermarkKey(String table) => 'cloud_wm_$table';

  /// `client_uuid` of the last row pushed for [table].
  ///
  /// The stamp alone is not enough: two rows written in the same millisecond
  /// share it, so `stamp > watermark` skipped one of them — including at the
  /// 200-row batch boundary, where the next batch started on an equal stamp.
  static String watermarkIdKey(String table) => 'cloud_wm_${table}_id';

  final ValueNotifier<CloudSyncState> state =
      ValueNotifier(const CloudSyncState());

  LocalDb? _db;
  VoidCallback? _onChanged;
  String? _shopId;
  bool _busy = false;
  bool _listening = false;
  StreamSubscription<User?>? _authSub;
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs =
      [];

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Called once at startup with the open database.
  void attach(LocalDb db, {VoidCallback? onChanged}) {
    _db = db;
    _onChanged = onChanged;
  }

  /// Starts the live listener and catches up. Safe to call more than once.
  Future<void> start() async {
    if (!FirebaseBootstrap.ready) {
      state.value = const CloudSyncState(
          summary: 'Cloud sync is off — Firebase is not configured in this '
              'build. See docs/FIREBASE_SETUP.md.');
      return;
    }
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _stopListeners();
        state.value = const CloudSyncState(
            summary: 'Signed out. Local data is untouched.');
      } else {
        unawaited(syncNow());
      }
    });
    if (FirebaseAuth.instance.currentUser != null) await syncNow();
  }

  Future<void> stop() async {
    await _authSub?.cancel();
    _authSub = null;
    _stopListeners();
  }

  void _stopListeners() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _listening = false;
    state.value = state.value.copyWith(live: false);
  }

  /// Pushes local changes and (re)opens the live listeners.
  Future<void> syncNow() async {
    final db = _db;
    if (!FirebaseBootstrap.ready || db == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      state.value = const CloudSyncState(
          summary: 'Sign in to the cloud account to sync this phone.');
      return;
    }
    if (_busy) return;
    _busy = true;
    state.value = state.value.copyWith(
        busy: true, summary: 'Syncing…', clearError: true);
    try {
      _shopId = shopIdFor(user.uid);
      await _ensureShop(user);
      var pushed = 0;
      for (final mirror in mirrors) {
        pushed += await _push(db, _shopId!, mirror);
      }
      _listen(db, _shopId!);
      state.value = CloudSyncState(
        live: true,
        summary: pushed == 0
            ? 'Everything is already up to date.'
            : 'Sent $pushed change${pushed == 1 ? '' : 's'} to the cloud.',
      );
      if (pushed > 0) _onChanged?.call();
    } catch (e) {
      state.value = state.value
          .copyWith(busy: false, error: _readable(e), summary: 'Sync failed.');
    } finally {
      _busy = false;
      state.value = state.value.copyWith(busy: false);
    }
  }

  /// Creates the shop document on the first sync.
  ///
  /// The security rules allow an owner to *get* their own shop before it
  /// exists, so this is a plain "read, then create". The rules must agree with
  /// this order — `get` gated on `isMember()`, which itself needs the document
  /// to exist, denies the very first sync and the shop can never be created.
  ///
  /// If an older rules deployment is still live and refuses that read, the
  /// create is attempted anyway: `set(merge: true)` is idempotent, so the
  /// fallback cannot overwrite an existing shop.
  Future<void> _ensureShop(User user) async {
    final ref = _firestore.doc('shops/$_shopId');
    try {
      final snapshot = await ref.get();
      if (snapshot.exists) return;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      debugPrint('[cloud] shop read denied; trying the create anyway');
    }
    await ref.set({
      'owner': user.uid,
      'name': user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : 'Jewellery Suite',
      'members': {user.uid: true},
      'updated_at': CloudTime.nowUtcIso(),
    }, SetOptions(merge: true));
  }

  // --------------------------------------------------------------------- push
  /// The rows a push should send next.
  ///
  /// A row is sent when it has never been sent (the composite `(stamp, uuid)`
  /// is past the watermark) **or** when it is still flagged `dirty`. Tables
  /// without a `dirty` column (the append-only movement ledger) use the
  /// watermark alone.
  @visibleForTesting
  static ({String where, List<Object?> args}) pushWhere(
    CloudMirror mirror,
    String stamp,
    String uuid, {
    required bool hasDirty,
  }) {
    final after = '(${mirror.stamp} > ? '
        'OR (${mirror.stamp} = ? AND client_uuid > ?))';
    return (
      where: hasDirty ? '(dirty = 1 OR $after)' : after,
      args: <Object?>[stamp, stamp, uuid],
    );
  }

  Future<int> _push(LocalDb db, String shopId, CloudMirror mirror) async {
    final columns = await db.columns(mirror.table);
    final hasDirty = columns.contains('dirty');
    final collection =
        _firestore.collection('shops').doc(shopId).collection(mirror.collection);
    var stamp = await db.getSetting(watermarkKey(mirror.table)) ?? '';
    var uuid = await db.getSetting(watermarkIdKey(mirror.table)) ?? '';
    var pushed = 0;

    for (var batch = 0; batch < maxPushBatches; batch++) {
      final filter = pushWhere(mirror, stamp, uuid, hasDirty: hasDirty);
      final rows = await db.query(
        mirror.table,
        where: filter.where,
        whereArgs: filter.args,
        orderBy: '${mirror.stamp} asc, client_uuid asc',
        limit: pushBatchSize,
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        final id = row['client_uuid']?.toString() ?? '';
        if (id.isEmpty) continue;
        await collection.doc(id).set(docFor(row), SetOptions(merge: true));
        pushed++;
        // Now in the cloud: clearing `dirty` and moving the watermark is what
        // stops a record pulled from another phone from being uploaded again.
        if (hasDirty && row['dirty'] != 0) {
          await db.db.update(mirror.table, {'dirty': 0},
              where: 'client_uuid = ?', whereArgs: [id]);
        }
        final rowStamp = row[mirror.stamp]?.toString() ?? '';
        final advanced = rowStamp.compareTo(stamp) > 0 ||
            (rowStamp == stamp && id.compareTo(uuid) > 0);
        if (advanced) {
          stamp = rowStamp;
          uuid = id;
          await db.setSetting(watermarkKey(mirror.table), stamp);
          await db.setSetting(watermarkIdKey(mirror.table), uuid);
        }
      }
      if (rows.length < pushBatchSize) break;
    }
    return pushed;
  }

  /// Firestore document for a local row: every column plus `updated_at`
  /// (required by the security rules), with instants written in UTC.
  static Map<String, Object?> docFor(Map<String, Object?> row) => _docFor(row);

  static Map<String, Object?> _docFor(Map<String, Object?> row) {
    final out = <String, Object?>{};
    for (final entry in row.entries) {
      final value = entry.value;
      if (value == null || value is num || value is String || value is bool) {
        out[entry.key] = value is String && CloudTime.isStamp(entry.key)
            ? CloudTime.toBoundary(value) ?? value
            : value;
      } else {
        out[entry.key] = value.toString();
      }
    }
    out['updated_at'] =
        CloudTime.toBoundary(row['updated_at'] ?? row['created_at']) ??
            CloudTime.nowUtcIso();
    return out;
  }

  // --------------------------------------------------------------------- pull
  void _listen(LocalDb db, String shopId) {
    if (_listening && _subs.isNotEmpty) return;
    _listening = true;
    for (final mirror in mirrors) {
      final sub = _firestore
          .collection('shops')
          .doc(shopId)
          .collection(mirror.collection)
          .snapshots()
          .listen(
        // The callback must not be `async`: a rejection inside it became an
        // unhandled asynchronous error that killed the listener. Each record is
        // applied (and caught) in [_applySnapshot] instead.
        (snap) => unawaited(_applySnapshot(db, mirror, snap)),
        onError: (Object e) {
          state.value = state.value.copyWith(error: _readable(e));
        },
      );
      _subs.add(sub);
    }
  }

  Future<void> _applySnapshot(
    LocalDb db,
    CloudMirror mirror,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    var applied = 0;
    Object? rejected;
    for (final change in snap.docChanges) {
      if (change.type == DocumentChangeType.removed) continue;
      final data = change.doc.data();
      if (data == null) continue;
      try {
        if (await applyRemote(db, mirror, change.doc.id, data)) applied++;
      } catch (e, st) {
        // One bad record must never stop the other updates, and must never
        // escape as an unhandled error.
        rejected = e;
        debugPrint('[cloud] skipped ${mirror.collection}/${change.doc.id}: $e\n$st');
      }
    }
    if (applied > 0) {
      state.value = state.value.copyWith(
          live: true,
          summary: 'Received $applied update'
              '${applied == 1 ? '' : 's'} from another phone.');
      _onChanged?.call();
    }
    if (rejected != null) {
      state.value = state.value.copyWith(
          error: 'One ${mirror.collection} record could not be saved on this '
              'phone: ${_readable(rejected)}');
    }
  }

  /// Writes one remote document into its local table.
  ///
  /// Firestore documents carry fields the local table may not have — the
  /// security rules require `updated_at` even on the append-only movement
  /// ledger, which has no such column. Every field is checked against
  /// `PRAGMA table_info` first, so a schema difference can no longer fail the
  /// whole pull with `no such column: updated_at`.
  @visibleForTesting
  Future<bool> applyRemote(LocalDb db, CloudMirror mirror, String id,
      Map<String, dynamic> data) async {
    final columns = await db.columns(mirror.table);
    final row = <String, Object?>{};
    for (final entry in data.entries) {
      if (!columns.contains(entry.key)) continue;
      final value = entry.value;
      if (value is Map || value is List || value is Timestamp) continue;
      row[entry.key] = CloudTime.isStamp(entry.key)
          ? CloudTime.toLocalStamp(value) ?? value
          : value;
    }
    row['client_uuid'] = id;

    final existing = await db.byUuid(mirror.table, id);
    if (existing != null) {
      if (mirror.immutable) return false;
      final local = existing[mirror.stamp];
      final remote = row[mirror.stamp] ?? data[mirror.stamp];
      if (!CloudTime.isNewer(local, remote)) return false;
    }
    if (columns.contains('dirty')) row['dirty'] = 0;
    await db.upsert(mirror.table, row);
    return true;
  }

  /// Last-write-wins on an ISO-8601 stamp. A missing local stamp wins for the
  /// remote row; a missing remote stamp never overwrites anything.
  static bool remoteIsNewer(String? local, String? remote) =>
      CloudTime.isNewer(local, remote);

  static String _readable(Object e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'unavailable':
          return 'No internet connection — this phone keeps working offline.';
        case 'permission-denied':
          return 'The cloud refused this account. Deploy firestore.rules '
              '(docs/FIREBASE_SETUP.md) and sign in again.';
        case 'failed-precondition':
          return 'The Firestore database is not created yet.';
        default:
          return e.message ?? e.code;
      }
    }
    return e.toString();
  }
}
