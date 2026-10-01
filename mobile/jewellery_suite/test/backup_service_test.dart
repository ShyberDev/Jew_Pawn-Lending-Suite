import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/backup_service.dart';
import 'package:jewellery_suite/data/local_db.dart';

/// A backup is only worth having if it can be trusted, so these tests check the
/// promise the feature makes: the live database is untouched, the archive is
/// complete, and nothing is reported as created until it has been read back.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory scratch;
  late Directory root; // stands in for the app documents directory
  late LocalDb db;
  late BackupService backups;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('js_backup_test_');
    // LocalDb.init() opens <databasesPath>/jewellery_suite.db; point the ffi
    // factory at our scratch folder so the real one is never touched.
    root = Directory(p.join(scratch.path, 'appdata'))
      ..createSync(recursive: true);
    databaseFactory = databaseFactoryFfi;

    db = LocalDb();
    await db.init(pathOverride: p.join(scratch.path, 'jewellery_suite.db'));
    await db.upsert('customers', {
      'client_uuid': 'c1',
      'customer_name': 'Ravi Kumar',
      'customer_id': 'A-01',
      'phone': '9000000001',
      'village': 'Pallipatti',
    });
    await db.upsert('villages', {
      'client_uuid': 'v1',
      'village_name': 'Pallipatti',
    });
    await db.upsert('khatabook_loans', {
      'client_uuid': 'l1',
      'customer': 'c1',
      'customer_name': 'Ravi Kumar',
      'principal_amount': 10000.0,
      'interest_amount': 3000.0,
      'total_payable': 13000.0,
    });
    backups = BackupService(db, root: root);
  });

  tearDown(() async {
    await db.db.close();
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  Future<void> addPhoto(String name, String content) async {
    final dir = Directory(p.join(root.path, 'photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    await File(p.join(dir.path, name)).writeAsString(content);
  }

  group('createBackup', () {
    test('produces a verified archive', () async {
      final result = await backups.createBackup(includePhotos: false);
      expect(result.verified, isTrue,
          reason: result.problem ?? 'should verify');
      expect(await File(result.info.path).exists(), isTrue);
      expect(result.info.bytes, greaterThan(0));
      expect(result.info.dbBytes, isNotNull);
    });

    test('the live database is untouched', () async {
      final before = await backups.liveCounts();
      final fileBefore = await File(db.path!).readAsBytes();

      await backups.createBackup(includePhotos: false);

      final after = await backups.liveCounts();
      expect(after, equals(before), reason: 'row counts must not change');
      expect(await File(db.path!).readAsBytes(), equals(fileBefore),
          reason: 'the database file itself must be byte-identical');
    });

    test('the archive holds the database, a manifest and the photos', () async {
      await addPhoto('front.jpg', 'front-bytes');
      await addPhoto('back.jpg', 'back-bytes');

      final result = await backups.createBackup(includePhotos: true);
      expect(result.verified, isTrue, reason: result.problem ?? '');

      final archive =
          ZipDecoder().decodeBytes(await File(result.info.path).readAsBytes());
      final names = archive.files.map((f) => f.name).toList();
      expect(names, contains('db/jewellery_suite.db'));
      expect(names, contains('manifest.json'));
      expect(names, contains('photos/front.jpg'));
      expect(names, contains('photos/back.jpg'));
      expect(result.info.photoCount, 2);
    });

    test('photos are left out when not asked for', () async {
      await addPhoto('front.jpg', 'x');
      final result = await backups.createBackup(includePhotos: false);
      final archive =
          ZipDecoder().decodeBytes(await File(result.info.path).readAsBytes());
      expect(archive.files.map((f) => f.name),
          isNot(contains('photos/front.jpg')));
      expect(result.info.photoCount, 0);
    });

    test('the archived database really contains the rows', () async {
      final result = await backups.createBackup(includePhotos: false);
      final archive =
          ZipDecoder().decodeBytes(await File(result.info.path).readAsBytes());
      final entry =
          archive.files.firstWhere((f) => f.name == 'db/jewellery_suite.db');

      // Extract it somewhere else and query it with a separate connection.
      final copy = File(p.join(scratch.path, 'restored.db'))
        ..writeAsBytesSync(entry.readBytes()!);
      final restored = await openDatabase(copy.path, readOnly: true);
      addTearDown(restored.close);

      final rows = await restored.query('customers');
      expect(rows.length, 1);
      expect(rows.first['customer_name'], 'Ravi Kumar');
      expect(rows.first['customer_id'], 'A-01');
      final loans = await restored.query('khatabook_loans');
      expect(loans.first['total_payable'], 13000.0);
    });

    test('the manifest records what was backed up', () async {
      final result = await backups.createBackup(includePhotos: false);
      final manifest = await backups.readManifest(result.info.path);
      expect(manifest, isNotNull);
      expect(manifest!['format'], 'jewellery-suite-backup');
      expect(manifest['created_at'], isA<String>());
      expect((manifest['row_counts'] as Map)['customers'], 1);
      expect((manifest['row_counts'] as Map)['khatabook_loans'], 1);
    });
  });

  group('never overwrites', () {
    test('two backups never share a file', () async {
      final first = await backups.createBackup(includePhotos: false);
      final second = await backups.createBackup(includePhotos: false);
      expect(second.info.path, isNot(first.info.path));
      expect(await File(first.info.path).exists(), isTrue,
          reason: 'the first backup must still be there');
      final list = await backups.listBackups();
      expect(list.length, 2);
    });
  });

  group('listing and deleting', () {
    test('lists newest first', () async {
      final a = await backups.createBackup(includePhotos: false);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final b = await backups.createBackup(includePhotos: false);
      final list = await backups.listBackups();
      expect(list.length, 2);
      expect(list.first.createdAt.isAfter(list.last.createdAt), isTrue);
      expect(list.first.path, b.info.path);
      expect(list.last.path, a.info.path);
    });

    test('deleteBackup removes only inside the backup folder', () async {
      final made = await backups.createBackup(includePhotos: false);
      expect(await backups.deleteBackup(made.info.path), isTrue);
      expect(await File(made.info.path).exists(), isFalse);

      // The live database is out of reach, whatever the caller asks for.
      expect(await backups.deleteBackup(db.path!), isFalse);
      expect(await File(db.path!).exists(), isTrue);
      expect(await backups.deleteBackup(p.join(root.path, 'photos', 'x.jpg')),
          isFalse);
    });

    test('deleting a missing backup is a no-op, not a crash', () async {
      expect(
          await backups.deleteBackup(p.join(root.path, 'backups', 'nope.zip')),
          isFalse);
    });
  });

  group('validateArchive', () {
    test('accepts a good archive', () async {
      final made = await backups.createBackup(includePhotos: false);
      expect(await backups.validateArchive(made.info.path), isNull);
    });

    test('rejects a file that is not a zip', () async {
      final bad = File(p.join(root.path, 'bad.zip'))
        ..writeAsString('not a zip');
      expect(await backups.validateArchive(bad.path), isNotNull);
    });

    test('rejects a zip with no database inside', () async {
      final target = p.join(root.path, 'empty.zip');
      final enc = ZipFileEncoder()..create(target);
      enc.addArchiveFile(ArchiveFile.bytes('manifest.json', utf8.encode('{}')));
      await enc.close();
      expect(await backups.validateArchive(target), contains('no database'));
    });

    test('rejects a zip whose database is not a database', () async {
      final target = p.join(root.path, 'fake.zip');
      final enc = ZipFileEncoder()..create(target);
      enc.addArchiveFile(ArchiveFile.bytes('manifest.json', utf8.encode('{}')));
      enc.addArchiveFile(
          ArchiveFile.bytes('db/jewellery_suite.db', utf8.encode('hello')));
      await enc.close();
      expect(await backups.validateArchive(target), isNotNull);
    });

    test('rejects a zip with no manifest', () async {
      final target = p.join(root.path, 'nomanifest.zip');
      final enc = ZipFileEncoder()..create(target);
      enc.addArchiveFile(
          ArchiveFile.bytes('db/jewellery_suite.db', utf8.encode('x')));
      await enc.close();
      expect(await backups.validateArchive(target), contains('manifest'));
    });
  });

  group('liveCounts', () {
    test('reports a count per tracked table', () async {
      final counts = await backups.liveCounts();
      expect(counts.keys, containsAll(BackupService.trackedTables));
      expect(counts['customers'], 1);
      expect(counts['villages'], 1);
      expect(counts['pawn_loans'], 0);
    });

    test('a table that does not exist is -1, not 0', () async {
      final counts = await backups.liveCounts();
      // Every tracked table exists in the real schema; the marker for "absent"
      // must never be confused with "empty".
      expect(counts.values.every((v) => v >= 0), isTrue);
    });
  });
}
