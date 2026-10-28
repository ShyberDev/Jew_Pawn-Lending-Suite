import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'local_db.dart';
import 'migration_v15.dart';

/// One backup file on disk.
class BackupInfo {
  final String path;
  final String fileName;
  final DateTime createdAt;
  final int bytes;

  /// Size of the database inside the archive, when it could be read.
  final int? dbBytes;

  /// Number of photo files inside the archive.
  final int photoCount;

  const BackupInfo({
    required this.path,
    required this.fileName,
    required this.createdAt,
    required this.bytes,
    this.dbBytes,
    this.photoCount = 0,
  });
}

/// Outcome of [BackupService.createBackup].
///
/// [verified] is true only when the finished archive was read back, its
/// database passed SQLite's own integrity check, and every table's row count
/// matched the live database. Anything else comes back as false with a
/// readable [problem], so the shopkeeper sees words rather than a stack trace.
class BackupResult {
  final BackupInfo info;
  final bool verified;
  final Map<String, int> counts;
  final String? problem;

  const BackupResult({
    required this.info,
    required this.verified,
    required this.counts,
    this.problem,
  });
}

/// Outcome of [BackupService.restoreBackup].
class RestoreResult {
  final bool restored;
  final String? problem;

  /// The verified backup taken immediately before the live data was replaced.
  final BackupInfo? safetyBackup;

  /// Photo files copied out of the archive.
  final int restoredPhotos;

  const RestoreResult({
    required this.restored,
    this.problem,
    this.safetyBackup,
    this.restoredPhotos = 0,
  });
}

/// Creates restorable backups of the shop's data.
///
/// The rules this class exists to enforce:
///
/// * **The live database is never modified.** The snapshot is produced by
///   `VACUUM INTO`, which writes a new, defragmented file from a read-only
///   view. Where the device's SQLite is too old for that, the fallback
///   checkpoints the write-ahead log and copies the bytes — still without
///   writing to the database itself.
/// * **Nothing is reported as created until it is proven.** The snapshot and
///   then the finished archive are each opened read-only, run through
///   `PRAGMA integrity_check`, and their per-table row counts are compared
///   with the live database.
/// * **An existing backup is never overwritten.** Names carry a timestamp plus
///   a collision counter; [deleteBackup] is the only thing that removes a file.
/// * **No customer data is ever logged.** Only counts, sizes and file names
///   leave this class.
class BackupService {
  /// [root] overrides the app documents directory. Production leaves it null so
  /// backups land beside the photos; tests point it at a scratch directory.
  BackupService(this.db, {Directory? root}) : _root = root;

  final LocalDb db;
  final Directory? _root;

  static const folder = 'backups';
  static const dbEntry = 'db/jewellery_suite.db';
  static const manifestEntry = 'manifest.json';
  static const photoFolder = 'photos';
  static const formatVersion = 1;

  /// Tables whose row counts go into the manifest and are compared when a
  /// backup is verified. A missing table is recorded as -1 (absent), which is
  /// deliberately different from zero rows.
  static const trackedTables = <String>[
    'customers',
    'villages',
    'pawn_loans',
    'pawn_items',
    'pawn_transactions',
    'pawn_releases',
    'khatabook_loans',
    'khatabook_collections',
    'khatabook_given',
    'khatabook_refinances',
    'khatabook_allocations',
    'khatabook_installments',
    'cashbook_entries',
    'customer_id_pool',
    'history_log',
    'qr_codes',
    'settings',
    'outbox',
    'photo_queue',
    'migration_log',
  ];

  Future<Directory> backupDir() async {
    final docs = _root ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, folder));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Customer photos and ID copies, which live beside the database.
  Future<List<File>> photoFiles() async {
    try {
      final docs = _root ?? await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, photoFolder));
      if (!await dir.exists()) return const [];
      final out = <File>[];
      // A file reachable twice (symlink / hard link / repeated listing) must
      // still appear once in the archive. Duplicate photo entries made old
      // restores copy the same image over itself and inflated the backup.
      final seen = <String>{};
      await for (final f in dir.list(followLinks: false)) {
        if (f is! File) continue;
        final key = p.normalize(p.absolute(f.path));
        if (!seen.add(key)) continue;
        out.add(f);
      }
      out.sort((a, b) => a.path.compareTo(b.path)); // stable archive order
      return out;
    } catch (_) {
      return const []; // no documents directory (web preview)
    }
  }

  /// Creates a backup and verifies it.
  Future<BackupResult> createBackup({bool includePhotos = true}) async {
    final createdAt = DateTime.now();
    final counts = await liveCounts();

    try {
      final source = db.path;
      if (source == null || !await File(source).exists()) {
        return _failed('The database file could not be found.', counts);
      }

      final work = await Directory.systemTemp.createTemp('js_backup_');
      try {
        final snapshot = p.join(work.path, 'snapshot.db');

        // 1. A consistent copy, without writing to the live database.
        final copyProblem = await _snapshot(source, snapshot);
        if (copyProblem != null) return _failed(copyProblem, counts);

        // 2. Prove the copy is a usable database before packaging it.
        final snapshotProblem = await _checkDatabase(snapshot, counts);
        if (snapshotProblem != null) return _failed(snapshotProblem, counts);

        // 3. Build the archive in one pass: the snapshot, the photos and a
        //    manifest that describes both.
        final photos = includePhotos ? await photoFiles() : const <File>[];
        final dir = await backupDir();
        final target = await _uniquePath(dir, createdAt);
        final manifest = <String, Object?>{
          'format': 'jewellery-suite-backup',
          'format_version': formatVersion,
          'created_at': createdAt.toIso8601String(),
          'includes_photos': includePhotos,
          'photo_count': photos.length,
          'row_counts': counts,
          'note': 'To restore, replace the app database file with '
              '$dbEntry from this archive.',
        };

        final encoder = ZipFileEncoder();
        try {
          encoder.create(target, modified: createdAt);
          await encoder.addFile(File(snapshot), dbEntry);
          for (final photo in photos) {
            await encoder.addFile(
                photo, p.join(photoFolder, p.basename(photo.path)));
          }
          encoder.addArchiveFile(ArchiveFile.bytes(
              manifestEntry,
              utf8.encode(
                  const JsonEncoder.withIndent('  ').convert(manifest))));
        } finally {
          await _closeQuietly(encoder);
        }

        // 4. Verify what actually landed on disk, not what we intended.
        final archiveProblem = await validateArchive(target);

        final file = File(target);
        final info = BackupInfo(
          path: target,
          fileName: p.basename(target),
          createdAt: createdAt,
          bytes: await file.exists() ? await file.length() : 0,
          dbBytes: await _entrySize(target, dbEntry),
          photoCount: photos.length,
        );
        return BackupResult(
          info: info,
          verified: archiveProblem == null,
          counts: counts,
          problem: archiveProblem,
        );
      } finally {
        await _deleteQuietly(work);
      }
    } catch (_) {
      return _failed('The backup could not be completed.', counts);
    }
  }

  /// Restores a backup in place.
  ///
  /// Safety rules, in order:
  /// 1. the archive is validated against SQLite before anything is touched;
  /// 2. a fresh, verified safety backup of the CURRENT data is taken;
  /// 3. only then is the live database closed, replaced and reopened;
  /// 4. the archive schema may be older (migrations run on reopen) but never
  ///    newer than this app — a future schema would be silently corrupted.
  ///
  /// The caller is responsible for reloading [AppState] after a successful
  /// restore; [db] is already pointing at the restored file.
  Future<RestoreResult> restoreBackup(String zipPath) async {
    Directory? work;
    var closed = false;
    try {
      final problem =
          await validateArchive(zipPath, compareWithLive: false);
      if (problem != null) {
        return RestoreResult(restored: false, problem: problem);
      }
      final manifest = await readManifest(zipPath);
      if (manifest == null ||
          manifest['format'] != 'jewellery-suite-backup') {
        return const RestoreResult(
            restored: false, problem: 'This file is not a Jewellery Suite backup.');
      }
      final format = (manifest['format_version'] as num?)?.toInt() ?? 1;
      if (format > formatVersion) {
        return const RestoreResult(
            restored: false,
            problem: 'This backup was made by a newer app version.');
      }

      // A restore is destructive, so the current data gets its own verified
      // backup first. If that cannot be produced, nothing is replaced.
      final safety = await createBackup(includePhotos: true);
      if (!safety.verified) {
        return RestoreResult(
            restored: false,
            problem: 'Could not make a safety backup first: ${safety.problem}');
      }

      final archive = ZipDecoder()
          .decodeBytes(await File(zipPath).readAsBytes(), verify: true);
      final entry = archive.files.firstWhere((f) => f.name == dbEntry);
      final bytes = entry.readBytes();
      if (bytes == null || bytes.isEmpty) {
        return RestoreResult(
            restored: false,
            problem: 'The archived database is empty.',
            safetyBackup: safety.info);
      }

      work = await Directory.systemTemp.createTemp('js_restore_');
      final extracted = File(p.join(work.path, 'restore.db'))
        ..writeAsBytesSync(bytes, flush: true);

      // Prove the extracted file is a healthy database and not from the
      // future. This duplicates the archive check on purpose: the bytes that
      // will actually be written are the ones validated.
      Database? check;
      try {
        check = await openDatabase(extracted.path, readOnly: true);
        final verdictRows = await check.rawQuery('PRAGMA integrity_check');
        final verdict = verdictRows.isEmpty
            ? ''
            : '${verdictRows.first.values.first}';
        if (verdict.toLowerCase() != 'ok') {
          return RestoreResult(
              restored: false,
              problem: 'The backup failed SQLite\'s integrity check.',
              safetyBackup: safety.info);
        }
        final versionRows = await check.rawQuery('PRAGMA user_version');
        final version = versionRows.isEmpty
            ? 0
            : ((versionRows.first.values.first as num?)?.toInt() ?? 0);
        if (version > MigrationV15.version) {
          return RestoreResult(
              restored: false,
              problem: 'The backup database is newer than this app.',
              safetyBackup: safety.info);
        }
      } catch (_) {
        return RestoreResult(
            restored: false,
            problem: 'The backup database could not be opened.',
            safetyBackup: safety.info);
      } finally {
        await check?.close();
      }

      // Stage photos beside the validated database, with a traversal guard.
      final stagedPhotos = Directory(p.join(work.path, 'photos'));
      await stagedPhotos.create(recursive: true);
      var photoCount = 0;
      for (final f in archive.files) {
        if (!f.isFile || !f.name.startsWith('$photoFolder/')) continue;
        final rel = f.name.substring(photoFolder.length + 1);
        if (rel.isEmpty || p.isAbsolute(rel) || rel.contains('..')) continue;
        final data = f.readBytes();
        if (data == null) continue;
        final target = File(p.join(stagedPhotos.path, p.basename(rel)));
        await target.writeAsBytes(data, flush: true);
        photoCount++;
      }

      final livePath = db.path;
      if (livePath == null) {
        return RestoreResult(
            restored: false,
            problem: 'The live database path is unknown.',
            safetyBackup: safety.info);
      }

      await db.close();
      closed = true;
      try {
        await File(livePath).writeAsBytes(
            await extracted.readAsBytes(),
            flush: true);
        for (final suffix in const ['-wal', '-shm', '-journal']) {
          final side = File('$livePath$suffix');
          if (await side.exists()) await side.delete();
        }

        // Replace the photo folder only when the archive says it contains
        // photos (even zero), so a database-only backup never deletes images
        // that were not part of it.
        final includesPhotos = manifest['includes_photos'] == true;
        if (includesPhotos) {
          final docs = _root ?? await getApplicationDocumentsDirectory();
          final livePhotos = Directory(p.join(docs.path, photoFolder));
          if (await livePhotos.exists()) {
            await livePhotos.delete(recursive: true);
          }
          await livePhotos.create(recursive: true);
          await for (final f in stagedPhotos.list()) {
            if (f is! File) continue;
            await f.copy(p.join(livePhotos.path, p.basename(f.path)));
          }
        }
      } catch (_) {
        // Put the app back on whatever file is there now; the safety backup is
        // named in the error so the shop can retry.
        await db.reopen();
        closed = false;
        return RestoreResult(
            restored: false,
            problem: 'The data could not be replaced. The safety backup '
                '${safety.info.fileName} is intact.',
            safetyBackup: safety.info);
      }

      await db.reopen();
      closed = false;
      return RestoreResult(
        restored: true,
        safetyBackup: safety.info,
        restoredPhotos: photoCount,
      );
    } catch (_) {
      if (closed) {
        try {
          await db.reopen();
        } catch (_) {/* reported below */}
      }
      return const RestoreResult(
          restored: false, problem: 'The restore could not be completed.');
    } finally {
      if (work != null) await _deleteQuietly(work);
    }
  }

  /// Reads a finished archive back and checks that it is restorable. Returns
  /// an error message, or null when the archive is sound.
  ///
  /// [compareWithLive] is true for a backup that was just created (its counts
  /// must match the live database). A restore validates an OLDER snapshot, so
  /// it passes false — the counts are expected to differ from today's.
  Future<String?> validateArchive(String zipPath,
      {bool compareWithLive = true}) async {
    if (!await File(zipPath).exists()) {
      return 'The backup file does not exist.';
    }
    final Archive archive;
    try {
      archive = ZipDecoder()
          .decodeBytes(await File(zipPath).readAsBytes(), verify: true);
    } catch (_) {
      return 'The backup archive is not readable.';
    }
    if (!archive.files.any((f) => f.name == dbEntry)) {
      return 'The backup archive has no database inside.';
    }
    if (!archive.files.any((f) => f.name == manifestEntry)) {
      return 'The backup archive has no manifest.';
    }

    final work = await Directory.systemTemp.createTemp('js_verify_');
    try {
      final entry = archive.files.firstWhere((f) => f.name == dbEntry);
      final bytes = entry.readBytes();
      if (bytes == null) return 'The archived database is empty.';
      final extracted = File(p.join(work.path, 'check.db'))
        ..writeAsBytesSync(bytes, flush: true);
      return await _checkDatabase(
          extracted.path, compareWithLive ? await liveCounts() : const {});
    } catch (_) {
      return 'The archived database could not be verified.';
    } finally {
      await _deleteQuietly(work);
    }
  }

  /// Row counts of the live database, per tracked table.
  Future<Map<String, int>> liveCounts() async {
    final out = <String, int>{};
    for (final t in trackedTables) {
      try {
        final r = await db.db.rawQuery('SELECT COUNT(*) AS c FROM $t');
        out[t] = (r.first['c'] as int?) ?? 0;
      } catch (_) {
        out[t] = -1; // table absent on this install, not "zero rows"
      }
    }
    return out;
  }

  /// Existing backups, newest first.
  Future<List<BackupInfo>> listBackups() async {
    final Directory dir;
    try {
      dir = await backupDir();
    } catch (_) {
      return const [];
    }
    final out = <BackupInfo>[];
    await for (final f in dir.list(followLinks: false)) {
      if (f is! File || !f.path.endsWith('.zip')) continue;
      final stat = f.statSync();
      out.add(BackupInfo(
        path: f.path,
        fileName: p.basename(f.path),
        createdAt: stat.modified,
        bytes: stat.size,
        dbBytes: await _entrySize(f.path, dbEntry),
        photoCount: await _entryCount(f.path, photoFolder),
      ));
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Deletes a backup. Refuses any path outside the backup folder, so this can
  /// never be turned into a way to remove the live database or a photo.
  Future<bool> deleteBackup(String path) async {
    final dir = await backupDir();
    if (p.dirname(p.normalize(path)) != p.normalize(dir.path)) return false;
    final f = File(path);
    if (!await f.exists()) return false;
    await f.delete();
    return true;
  }

  /// The manifest of an archive, for the details view.
  Future<Map<String, Object?>?> readManifest(String zipPath) async {
    try {
      final archive =
          ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
      final entry = archive.files.firstWhere((f) => f.name == manifestEntry);
      final bytes = entry.readBytes();
      if (bytes == null) return null;
      return jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }

  /// A consistent copy of [source] at [dest], without modifying [source].
  Future<String?> _snapshot(String source, String dest) async {
    // Preferred: VACUUM INTO writes a fresh, defragmented file from a
    // read-only view. Needs SQLite 3.27+ (Android 11+); older builds reject the
    // statement, which is what the fallback below is for.
    try {
      await db.db.rawQuery('VACUUM INTO ?', [dest]);
      if (await File(dest).exists()) return null;
    } catch (_) {
      // fall through to the byte copy
    }
    try {
      // Fold any pending WAL pages into the main file so a plain copy is
      // complete. This moves pages that are already committed — it does not
      // change any customer record.
      try {
        await db.db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {/* not in WAL mode */}
      await File(dest)
          .writeAsBytes(await File(source).readAsBytes(), flush: true);
      return null;
    } catch (_) {
      return 'The database could not be copied.';
    }
  }

  /// Opens [dbFile] read-only, runs SQLite's integrity check, and compares
  /// every tracked table's row count with the live database.
  Future<String?> _checkDatabase(String dbFile, Map<String, int> live) async {
    Database? copy;
    try {
      copy = await openDatabase(dbFile, readOnly: true);
      final rows = await copy.rawQuery('PRAGMA integrity_check');
      final verdict = rows.isEmpty ? '' : '${rows.first.values.first}';
      if (verdict.toLowerCase() != 'ok') {
        return 'The backup failed SQLite\'s integrity check.';
      }
      for (final entry in live.entries) {
        if (entry.value < 0) continue; // table absent, nothing to compare
        final n = await copy.rawQuery('SELECT COUNT(*) AS c FROM ${entry.key}');
        if (((n.first['c'] as int?) ?? 0) != entry.value) {
          return 'The backup is missing rows (${entry.key}).';
        }
      }
      return null;
    } catch (_) {
      return 'The backup database could not be read back.';
    } finally {
      await copy?.close();
    }
  }

  /// Never overwrites: a name collision gets a counter instead.
  Future<String> _uniquePath(Directory dir, DateTime at) async {
    final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(at);
    var candidate = p.join(dir.path, 'jewellery_suite_$stamp.zip');
    var n = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(dir.path, 'jewellery_suite_${stamp}_$n.zip');
      n++;
    }
    return candidate;
  }

  Future<int> _entryCount(String zipPath, String prefix) async {
    try {
      final archive =
          ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
      return archive.files.where((f) => f.name.startsWith('$prefix/')).length;
    } catch (_) {
      return 0;
    }
  }

  Future<int?> _entrySize(String zipPath, String entry) async {
    try {
      final archive =
          ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
      return archive.files.firstWhere((e) => e.name == entry).size;
    } catch (_) {
      return null;
    }
  }

  BackupResult _failed(String problem, Map<String, int> counts) => BackupResult(
        info: BackupInfo(
            path: '', fileName: '', createdAt: DateTime.now(), bytes: 0),
        verified: false,
        problem: problem,
        counts: counts,
      );

  Future<void> _closeQuietly(ZipFileEncoder encoder) async {
    try {
      await encoder.close();
    } catch (_) {/* a close failure is reported by validateArchive, not here */}
  }

  Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {/* temp cleanup is best effort */}
  }
}
