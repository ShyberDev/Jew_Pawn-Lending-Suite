import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/backup_service.dart';
import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/util/auto_backup.dart';

/// #048 — the automatic local backup: off unless the shop turns it on, one
/// verified copy per calendar day, and pruning that can only ever remove the
/// copies this feature made.
void main() {
  late Directory scratch;
  late Directory root; // stands in for the app documents directory
  late LocalDb db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('js_auto_backup_');
    root = Directory(p.join(scratch.path, 'appdata'))
      ..createSync(recursive: true);
    db = LocalDb();
    await db.init(pathOverride: p.join(scratch.path, 'jewellery_suite.db'));
    await db.upsert('customers', {
      'client_uuid': 'c1',
      'customer_name': 'Ravi Kumar',
      'customer_id': 'A-01',
    });
  });

  tearDown(() async {
    await db.db.close();
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  Future<List<String>> archiveNames() async {
    final dir = Directory(p.join(root.path, 'backups'));
    if (!await dir.exists()) return const [];
    final names = <String>[];
    await for (final f in dir.list()) {
      if (f is File) names.add(p.basename(f.path));
    }
    names.sort();
    return names;
  }

  test('does nothing while the shop has it switched off', () async {
    final result = await runAutoBackup(db, root: root);
    expect(result.created, isFalse);
    expect(result.skipped, isTrue);
    expect(await archiveNames(), isEmpty);
  });

  test('makes one verified copy a day, named so pruning can find it', () async {
    await db.setSetting(AutoBackupPolicy.enabledKey, '1');

    final first =
        await runAutoBackup(db, root: root, now: DateTime(2026, 11, 2, 9, 30));
    expect(first.created, isTrue);
    expect(first.fileName, startsWith('${AutoBackupPolicy.filePrefix}_'));
    expect(await archiveNames(), hasLength(1));

    // The same day, however many times the shop opens the app.
    final again =
        await runAutoBackup(db, root: root, now: DateTime(2026, 11, 2, 18, 5));
    expect(again.created, isFalse);
    expect(again.skipped, isTrue);
    expect(await archiveNames(), hasLength(1));

    // The next day gets its own copy.
    final next =
        await runAutoBackup(db, root: root, now: DateTime(2026, 11, 3, 8, 0));
    expect(next.created, isTrue);
    expect(await archiveNames(), hasLength(2));
    expect(await db.getSetting(AutoBackupPolicy.lastKey), contains('2026-11-03'));
  });

  test('prunes old automatic copies and never a manual backup', () async {
    await db.setSetting(AutoBackupPolicy.enabledKey, '1');
    await db.setSetting(AutoBackupPolicy.keepKey, '3');

    // The shop's own backup: it may be the copy being handed over, so pruning
    // must leave it alone.
    final manual = await BackupService(db, root: root).createBackup();
    expect(manual.verified, isTrue);

    for (var day = 1; day <= 5; day++) {
      final r =
          await runAutoBackup(db, root: root, now: DateTime(2026, 11, day, 9));
      expect(r.created, isTrue, reason: 'day $day should have been backed up');
    }

    final names = await archiveNames();
    expect(
        names.where((n) => n.startsWith('${AutoBackupPolicy.filePrefix}_')),
        hasLength(3),
        reason: 'only the newest 3 automatic copies may remain');
    expect(names.any((n) => n.startsWith('jewellery_suite_')), isTrue,
        reason: 'the manual backup must survive pruning');
  });

  test('a bad retention setting can never mean "keep none"', () {
    expect(AutoBackupPolicy.keepFrom(null), AutoBackupPolicy.defaultKeep);
    expect(AutoBackupPolicy.keepFrom('garbage'), AutoBackupPolicy.defaultKeep);
    expect(AutoBackupPolicy.keepFrom('0'), AutoBackupPolicy.minKeep);
    expect(AutoBackupPolicy.keepFrom('999'), AutoBackupPolicy.maxKeep);
  });
}
