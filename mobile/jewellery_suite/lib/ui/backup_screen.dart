import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup_service.dart';
import '../data/sample_data.dart';
import '../state/app_state.dart';
import 'admin_guard.dart';
import 'palette.dart';
import 'widgets.dart';

/// More → Settings → Backup & data.
///
/// Two jobs, both deliberately explicit — nothing here runs by itself:
///
/// * **Backup** — write a verified copy of the database (and the customer ID
///   photos) to a file the shopkeeper controls, then hand it to Android's
///   share sheet so it can be saved to Drive, Files, Downloads or sent to
///   themselves.
/// * **Sample data** — report the development rows that earlier builds wrote
///   into the database, prove nothing real is attached to them, and only then
///   remove them behind the admin password.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  BackupService? _backups;
  SampleDataService? _samples;

  bool _busy = false;
  bool _withPhotos = true;
  List<BackupInfo> _files = const [];
  SampleDataReport? _report;

  @override
  void initState() {
    super.initState();
    final db = context.read<AppState>().db;
    _backups = BackupService(db);
    _samples = SampleDataService(db);
    _reload();
  }

  Future<void> _reload() async {
    final files = await _backups?.listBackups() ?? const <BackupInfo>[];
    if (!mounted) return;
    setState(() => _files = files);
  }

  void _toast(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: bad ? kRed : null,
        duration: const Duration(seconds: 4),
      ));
  }

  // ------------------------------------------------------------------ backup

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await _backups!.createBackup(includePhotos: _withPhotos);
    await _reload();
    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.verified) {
      _toast('Backup NOT created: ${result.problem}', bad: true);
      return;
    }
    final when = DateFormat('d MMM yyyy, HH:mm').format(result.info.createdAt);
    _toast('Backup created and verified — $when');
  }

  Future<void> _share(BackupInfo info) async {
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(info.path, mimeType: 'application/zip')],
        subject: 'Jewellery Suite backup ${info.fileName}',
        text: 'Backup taken on '
            '${DateFormat('d MMM yyyy, HH:mm').format(info.createdAt)}.',
      ));
    } catch (_) {
      _toast('Could not open the share sheet.', bad: true);
    }
  }

  Future<void> _delete(BackupInfo info) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this backup?'),
        content: Text('${info.fileName}\n'
            '${DateFormat('d MMM yyyy, HH:mm').format(info.createdAt)}\n\n'
            'This removes the copy only. Your live data is not touched.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete backup')),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await _backups!.deleteBackup(info.path);
    await _reload();
    _toast(ok ? 'Backup deleted.' : 'That backup could not be deleted.',
        bad: !ok);
  }

  Future<void> _verify(BackupInfo info) async {
    setState(() => _busy = true);
    final problem = await _backups!.validateArchive(info.path);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(
        problem == null
            ? '${info.fileName} is complete and restorable.'
            : 'Problem found: $problem',
        bad: problem != null);
  }

  /// Replaces the live data with the contents of [info].
  ///
  /// Three separate confirmations stand between the tap and the replace:
  /// the explicit warning dialog, the admin password (when enabled), and the
  /// archive validation performed inside [BackupService.restoreBackup]. A
  /// verified safety backup of the current data is taken first, so even a
  /// mistaken restore can be undone.
  Future<void> _restore(BackupInfo info) async {
    if (_busy) return;
    final when = DateFormat('d MMM yyyy, HH:mm').format(info.createdAt);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: SingleChildScrollView(
          child: Text(
            'Backup: ${info.fileName}\n'
            'Taken: $when\n'
            'Size: ${_size(info.bytes)}'
            '${info.photoCount > 0 ? ' · ${info.photoCount} photo(s)' : ''}\n\n'
            'Your current customers, loans, collections, pawn records and '
            'cashbook will be REPLACED by the data in this file. '
            'A verified safety backup of the current data is taken first, so '
            'you can restore it if this was a mistake.\n\n'
            'This cannot be undone from inside the app.',
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    final state = context.read<AppState>();
    final granted = await askPasswordIfEnabled(
      context,
      state,
      actionId: 'backup_restore',
      action: 'restore this backup',
      detail: info.fileName,
      confirmLabel: 'Restore',
    );
    if (!mounted) return;
    if (!granted) {
      _toast('Restore cancelled / wrong password.');
      return;
    }

    setState(() => _busy = true);
    final result = await _backups!.restoreBackup(info.path);
    if (!mounted) return;
    if (!result.restored) {
      setState(() => _busy = false);
      _toast('Restore failed: ${result.problem}', bad: true);
      return;
    }

    // The database file was replaced while AppState kept its old in-memory
    // caches (counts, logged-in user, cached lists). Reload everything from
    // the restored file before any screen reads a stale number.
    await state.load();
    await _reload();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _report = null;
    });
    _toast(
        'Restored ${info.fileName}'
        '${result.restoredPhotos > 0 ? ' with ${result.restoredPhotos} photo(s)' : ''}. '
        'Safety backup: ${result.safetyBackup?.fileName ?? 'created'}',
        bad: false);
  }

  // ------------------------------------------------------------ sample data

  Future<void> _inspectSamples() async {
    setState(() => _busy = true);
    final report = await _samples!.inspect();
    _samples!.describeSafely(report);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _report = report;
    });
  }

  Future<void> _removeSamples() async {
    final report = _report;
    if (report == null || !report.safeToRemove) return;

    final rows = report.byTable.entries
        .map((e) => '• ${_tableLabel(e.key)}: ${e.value.length}')
        .join('\n');
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove sample data?'),
        content: SingleChildScrollView(
          child: Text(
            'These development records will be deleted:\n\n$rows\n\n'
            'Real customers, loans, collections and pawn records are not '
            'touched. This cannot be undone.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true) return;
    // Every line below awaits database work. If the shopkeeper backed out of
    // this screen in that window, `context` is dead - bail before touching it.
    if (!mounted) return;

    final granted = await askPasswordIfEnabled(
        context, context.read<AppState>(),
        actionId: 'sample_remove',
        action: 'remove all sample data',
        confirmLabel: 'Remove');
    if (!granted) {
      _toast('Cancelled / wrong password.');
      return;
    }

    setState(() => _busy = true);
    final after = await _samples!.remove(confirmedByUser: true);
    _samples!.describeSafely(after);
    await _reload();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _report = after;
    });
    _toast('Sample data removed. ${after.totalRows} sample rows left.');
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final newest = _files.isEmpty ? null : _files.first;
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(title: const Text('Backup & data')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(
            title: 'Backup',
            children: [
              if (newest == null)
                Text('No backup yet.',
                    style: TextStyle(fontSize: 12.5, color: mutedOf(context)))
              else
                Text(
                  'Latest: ${newest.fileName}\n'
                  '${DateFormat('EEE d MMM yyyy, HH:mm:ss').format(newest.createdAt)}'
                  ' · ${_size(newest.bytes)}'
                  '${newest.photoCount > 0 ? ' · ${newest.photoCount} photo(s)' : ''}',
                  style: TextStyle(
                      fontSize: 12, color: mutedOf(context), height: 1.4),
                ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Include ID photos',
                    style: TextStyle(fontSize: 13.5)),
                subtitle: Text(
                    'Customer photos and ID copies. Makes the file bigger.',
                    style: TextStyle(fontSize: 11, color: mutedOf(context))),
                value: _withPhotos,
                onChanged: (v) => setState(() => _withPhotos = v),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _create,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.backup_outlined, size: 18),
                label: Text(_busy ? 'Working…' : 'Create backup now'),
              ),
              const SizedBox(height: 6),
              Text(
                'A backup is written to the app folder, checked with SQLite\'s '
                'own integrity test and compared against your live data before '
                'it is called a success. Your data is never changed to make it.',
                style: TextStyle(fontSize: 11, color: mutedOf(context)),
              ),
            ],
          ),
          if (_files.isNotEmpty) ...[
            SectionCard(
              title: 'Saved backups (${_files.length})',
              children: _files
                  .map((f) => _backupRow(context, f))
                  .toList(growable: false),
            ),
          ],
          SectionCard(
            title: 'If you ever need to restore',
            children: [
              Text(
                'Open the ⋮ menu on a saved backup and choose "Restore this '
                'backup". The app validates the file, takes a verified safety '
                'backup of the current data, then replaces the database and '
                'the customer photos if the backup includes them. '
                'Use "Check" first if you want to confirm the file is '
                'complete without changing anything.',
                style: TextStyle(
                    fontSize: 12, color: mutedOf(context), height: 1.45),
              ),
            ],
          ),
          SectionCard(
            title: 'Sample data',
            children: [
              Text(
                'Earlier development builds wrote demo customers, villages and '
                'loans into the database. They are not real customers and can '
                'be removed.',
                style: TextStyle(fontSize: 12, color: mutedOf(context)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _inspectSamples,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Check for sample data'),
              ),
              if (_report != null) ...[
                const SizedBox(height: 10),
                _sampleReport(context, _report!),
              ],
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _backupRow(BuildContext context, BackupInfo f) {
    final when = DateFormat('d MMM yyyy, HH:mm').format(f.createdAt);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.archive_outlined, color: kGoldDark, size: 20),
      title: Text(when,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${f.fileName}\n${_size(f.bytes)}'
        '${f.photoCount > 0 ? ' · ${f.photoCount} photo(s)' : ''}',
        style: TextStyle(fontSize: 10.5, color: mutedOf(context), height: 1.35),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Check this backup',
            icon: const Icon(Icons.verified_outlined, size: 19),
            onPressed: _busy ? null : () => _verify(f),
          ),
          PopupMenuButton<String>(
            tooltip: 'Backup actions',
            enabled: !_busy,
            onSelected: (value) {
              switch (value) {
                case 'restore':
                  _restore(f);
                  break;
                case 'share':
                  _share(f);
                  break;
                case 'delete':
                  _delete(f);
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_backup_restore,
                      color: kGoldDark),
                  title: Text('Restore this backup'),
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.ios_share),
                  title: Text('Save or share'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, color: kRed),
                  title: Text('Delete backup'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sampleReport(BuildContext context, SampleDataReport r) {
    if (r.isEmpty) {
      return Text('No sample records found. Nothing to remove.',
          style: TextStyle(fontSize: 12.5, color: mutedOf(context)));
    }
    final lines = <Widget>[
      for (final e in r.byTable.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text('${_tableLabel(e.key)}: ${e.value.length}',
              style: const TextStyle(fontSize: 12.5)),
        ),
      Text('Total rows to remove: ${r.totalRows}',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
    ];
    for (final kept in r.keptVillages) {
      lines.add(Text('Kept village "$kept" — real customers still use it.',
          style: const TextStyle(fontSize: 11.5, color: kGreen)));
    }
    for (final b in r.blocked) {
      lines.add(Text('Blocked: $b',
          style: const TextStyle(fontSize: 11.5, color: kRed)));
    }
    if (r.safeToRemove) {
      lines.add(FilledButton.icon(
        onPressed: _busy ? null : _removeSamples,
        style: FilledButton.styleFrom(backgroundColor: kRed),
        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
        label: const Text('Remove sample data'),
      ));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [const SizedBox(height: 4), ...lines]);
  }

  static String _tableLabel(String table) {
    final labels = <String, String>{
      'customers': 'Demo customers',
      'villages': 'Demo villages',
      'pawn_loans': 'Demo pawn loans',
      'pawn_items': 'Demo pawn items',
      'pawn_transactions': 'Demo pawn transactions',
      'pawn_releases': 'Demo pawn releases',
      'khatabook_loans': 'Demo khata loans',
      'khatabook_collections': 'Demo collections',
      'khatabook_given': 'Demo "You Gave" rows',
      'khatabook_refinances': 'Demo refinances',
    };
    return labels[table] ?? table;
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
