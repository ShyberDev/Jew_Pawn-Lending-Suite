import 'dart:convert';

import '../util/ids.dart';
import 'api_client.dart';
import 'local_db.dart';

class SyncSummary {
  int pushed = 0;
  int failed = 0;
  int pulled = 0;
  int photos = 0;

  bool get ok => failed == 0;

  @override
  String toString() =>
      'pushed $pushed, failed $failed, pulled $pulled, photos $photos';
}

/// Orchestrates offline-first sync against `pawn_shop.api.sync`.
///
/// Push is idempotent (server keys on `client_uuid`), pull is a modified-since
/// delta. Photos are uploaded after their parent document exists on the server.
class SyncService {
  final LocalDb db;
  final ApiClient api;

  SyncService(this.db, this.api);

  /// Server DocType -> local table.
  static const Map<String, String> tableFor = {
    'Village': 'villages',
    'Pawn Customer': 'customers',
    'Pawn Loan': 'pawn_loans',
    'Pawn Release': 'pawn_releases',
    'Khatabook Loan': 'khatabook_loans',
    'Khatabook Collection': 'khatabook_collections',
    'Khatabook Refinance': 'khatabook_refinances',
  };

  static const Set<String> _submit = {
    'Pawn Release',
    'Khatabook Collection',
    'Khatabook Refinance',
  };

  static const List<String> itemFields = [
    'item_description',
    'metal_type',
    'purity',
    'quantity',
    'gross_weight',
    'net_weight',
    'hallmarked',
    'valuation_rate',
    'market_value',
    'approved_amount',
    'remarks',
  ];

  Future<SyncSummary> sync() async {
    final summary = SyncSummary();

    var device = await db.getSetting('device');
    if (device == null || device.isEmpty) {
      final name = await db.getSetting('device_name') ?? 'Android Phone';
      final registered = await api.registerDevice(name);
      device = registered['device'] as String?;
      if (device != null) await db.setSetting('device', device);
    }

    await _push(summary, device);
    await _uploadPhotos(summary);
    await _pull(summary);
    return summary;
  }

  // --------------------------------------------------------------------- push
  Future<void> _push(SyncSummary summary, String? device) async {
    final pending = await db.pendingMutations();
    if (pending.isEmpty) return;

    final mutations = <Map<String, dynamic>>[];
    for (final row in pending) {
      mutations.add(await _toMutation(row));
    }
    final resp = await api.push(mutations, device: device);
    final results = (resp['results'] as List?) ?? const [];
    final byUuid = <String, Map>{
      for (final r in results.cast<Map>())
        if (r['client_uuid'] != null) r['client_uuid'].toString(): r,
    };

    for (final row in pending) {
      final uuid = row['client_uuid'] as String;
      final result = byUuid[uuid];
      final id = row['id'] as int;
      if (result == null) continue;
      if (result['status'] == 'error') {
        await db.markMutation(id,
            status: 'error', error: result['error']?.toString());
        summary.failed++;
        continue;
      }
      await db.markMutation(id, status: 'done');
      summary.pushed++;

      final serverName = result['server_name'] as String?;
      final table = tableFor[row['doctype']];
      if (serverName != null && table != null) {
        final local = await db.byUuid(table, uuid);
        if (local != null) {
          await db.upsert(table, {
            ...local,
            'server_name': serverName,
            'dirty': 0,
          });
        }
      }
    }
  }

  /// Link fields that may hold a local `client_uuid` and must be resolved to the
  /// linked document's server name before pushing.
  static const Map<String, Map<String, String>> _linkFields = {
    'Pawn Release': {'pawn_loan': 'pawn_loans'},
    'Khatabook Collection': {'khatabook_loan': 'khatabook_loans'},
    'Khatabook Refinance': {'khatabook_loan': 'khatabook_loans'},
  };

  Future<Map<String, dynamic>> _toMutation(Map<String, Object?> row) async {
    final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
    final doctype = row['doctype'] as String;

    final links = _linkFields[doctype];
    if (links != null) {
      for (final entry in links.entries) {
        final value = data[entry.key];
        if (value is String && value.isNotEmpty) {
          final local = await db.byUuid(entry.value, value);
          final serverName = local?['server_name'] as String?;
          if (serverName != null) data[entry.key] = serverName;
        }
      }
    }

    return {
      'op': row['op'],
      'doctype': doctype,
      'client_uuid': row['client_uuid'],
      'submit': _submit.contains(doctype),
      'data': data,
    };
  }

  // ------------------------------------------------------------------- photos
  Future<void> _uploadPhotos(SyncSummary summary) async {
    final photos = await db.pendingPhotos();
    for (final photo in photos) {
      final id = photo['id'] as int;
      final doctype = photo['doctype'] as String;
      final table = tableFor[doctype];
      if (table == null) {
        await db.markPhotoUploaded(id);
        continue;
      }
      final local = await db.byUuid(table, photo['client_uuid'] as String);
      final serverName = local?['server_name'] as String?;
      if (serverName == null) continue; // parent not synced yet
      try {
        final path = photo['local_path'] as String;
        await api.uploadFile(
          filePath: path,
          filename: path.split('/').last,
          doctype: doctype,
          docname: serverName,
        );
        await db.markPhotoUploaded(id);
        summary.photos++;
      } catch (_) {
        // leave queued for the next sync
      }
    }
  }

  // --------------------------------------------------------------------- pull
  Future<void> _pull(SyncSummary summary) async {
    final since = await db.getSetting('last_pull');
    final resp = await api.pull(
      since: (since == null || since.isEmpty) ? null : since,
      doctypes: tableFor.keys.toList(),
    );

    final docs = (resp['docs'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final entry in docs.entries) {
      final table = tableFor[entry.key];
      if (table == null) continue;
      final columns = await db.columns(table);
      final list = (entry.value as List?) ?? const [];
      for (final raw in list) {
        final doc = (raw as Map).cast<String, dynamic>();
        final name = doc['name'] as String?;
        if (name == null) continue;
        final local = await db.byServerName(table, name);
        final row = <String, Object?>{};
        for (final key in doc.keys) {
          if (columns.contains(key)) row[key] = _normalize(doc[key]);
        }
        row['server_name'] = name;
        row['dirty'] = 0;
        row['client_uuid'] = local?['client_uuid'] ?? newUuid();
        await db.upsert(table, row);

        if (entry.key == 'Pawn Loan' && doc['items'] is List) {
          await _replaceItems(row['client_uuid'] as String, doc['items'] as List);
        }
      }
      summary.pulled += list.length;
    }

    final serverTime = resp['server_time'] as String?;
    if (serverTime != null) await db.setSetting('last_pull', serverTime);
  }

  Future<void> _replaceItems(String loanUuid, List rawItems) async {
    await db.deleteWhere('pawn_items', 'loan_uuid = ?', [loanUuid]);
    for (final raw in rawItems) {
      final item = (raw as Map).cast<String, dynamic>();
      final row = <String, Object?>{'loan_uuid': loanUuid};
      for (final field in itemFields) {
        if (item.containsKey(field)) row[field] = _normalize(item[field]);
      }
      await db.upsert('pawn_items', row);
    }
  }

  Object? _normalize(Object? value) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is num || value is String) return value;
    return null;
  }
}
