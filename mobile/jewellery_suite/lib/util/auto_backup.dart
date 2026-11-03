import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/backup_service.dart';
import '../data/local_db.dart';

/// #048 — one **verified** backup a day, without the shop having to remember.
///
/// The rules this file enforces:
///
/// * Nothing runs until the shop turns it on. Silent disk use on a phone is
///   not a favour.
/// * At most one automatic copy per calendar day, tracked by
///   [AutoBackupPolicy.lastKey]. Opening the app ten times in a morning must
///   not produce ten archives.
/// * Only files this feature created (`auto_jewellery_suite_*.zip`) are ever
///   deleted, and only once more than [AutoBackupPolicy.defaultKeep] are
///   kept. A manual backup is never pruned — it may be the copy the shop is
///   about to hand over.
/// * A failed or unverified backup does not update the "last" marker, so the
///   next start tries again instead of pretending the day was covered.
class AutoBackupPolicy {
  static const enabledKey = 'auto_backup_enabled';
  static const lastKey = 'auto_backup_last';
  static const keepKey = 'auto_backup_keep';

  /// Prefix the archive name gets, so pruning can tell automatic copies from
  /// the shop's own.
  static const filePrefix = 'auto';

  static const defaultKeep = 7;
  static const minKeep = 1;
  static const maxKeep = 30;

  /// True when [now] is a day with no automatic backup yet.
  static bool isDue({
    required bool enabled,
    String? lastRunIso,
    required DateTime now,
  }) {
    if (!enabled) return false;
    final last = lastRunIso == null ? null : DateTime.tryParse(lastRunIso);
    if (last == null) return true;
    return !(last.year == now.year &&
        last.month == now.month &&
        last.day == now.day);
  }

  /// How many automatic copies to keep, clamped to a sane range. A bad setting
  /// must never mean "keep none".
  static int keepFrom(String? raw) {
    final n = int.tryParse(raw ?? '');
    if (n == null) return defaultKeep;
    return n.clamp(minKeep, maxKeep);
  }
}

/// What one run did, for the Settings line and the tests.
class AutoBackupResult {
  final bool created;
  final bool skipped;
  final String? fileName;

  /// Automatic copies removed because the retention count was exceeded.
  final int removed;

  /// Set when a backup was attempted but could not be verified.
  final String? problem;

  const AutoBackupResult({
    required this.created,
    required this.skipped,
    this.fileName,
    this.removed = 0,
    this.problem,
  });
}

/// Creates today's automatic backup when it is due, then prunes old copies.
///
/// [root] and [now] exist for tests; production passes neither.
Future<AutoBackupResult> runAutoBackup(
  LocalDb db, {
  DateTime? now,
  Directory? root,
}) async {
  final at = now ?? DateTime.now();
  final enabled = await db.getSetting(AutoBackupPolicy.enabledKey) == '1';
  final last = await db.getSetting(AutoBackupPolicy.lastKey);
  if (!AutoBackupPolicy.isDue(enabled: enabled, lastRunIso: last, now: at)) {
    return const AutoBackupResult(created: false, skipped: true);
  }

  final service = BackupService(db, root: root);
  final result =
      await service.createBackup(prefix: AutoBackupPolicy.filePrefix);
  if (!result.verified) {
    return AutoBackupResult(
      created: false,
      skipped: false,
      problem: result.problem ?? 'The automatic backup could not be verified.',
    );
  }

  // Only a verified archive counts as "today is covered".
  await db.setSetting(AutoBackupPolicy.lastKey, at.toIso8601String());
  final keep = AutoBackupPolicy.keepFrom(
      await db.getSetting(AutoBackupPolicy.keepKey));
  final removed = await _prune(service, keep);
  return AutoBackupResult(
    created: true,
    skipped: false,
    fileName: result.info.fileName,
    removed: removed,
  );
}

/// Deletes the oldest automatic copies beyond [keep]. Manual backups and
/// files the shop copied in from Downloads are left alone.
Future<int> _prune(BackupService service, int keep) async {
  final all = await service.listBackups();
  final automatic = all
      .where((b) =>
          p.basename(b.fileName).startsWith('${AutoBackupPolicy.filePrefix}_'))
      .toList();
  var removed = 0;
  for (var i = keep; i < automatic.length; i++) {
    if (await service.deleteBackup(automatic[i].path)) removed++;
  }
  return removed;
}
