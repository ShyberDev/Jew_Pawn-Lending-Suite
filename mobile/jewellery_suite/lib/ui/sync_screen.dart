import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'widgets.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  List<Map<String, Object?>> _failed = [];

  @override
  void initState() {
    super.initState();
    _loadFailed();
  }

  Future<void> _loadFailed() async {
    final rows = await context
        .read<AppState>()
        .db
        .query('outbox', where: 'status = ?', whereArgs: ['error']);
    if (mounted) setState(() => _failed = rows);
  }

  Future<void> _sync() async {
    final state = context.read<AppState>();
    try {
      final summary = await state.sync();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Synced: $summary')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Sync failed: $error')));
    }
    await _loadFailed();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(title: 'Connection', children: [
            _kv('Server', state.serverUrl),
            _kv('User', state.user),
            _kv('Pending changes', '${state.pending}'),
            if (state.lastSync != null)
              _kv('Last sync', state.lastSync.toString()),
          ]),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: state.syncing ? null : _sync,
            icon: state.syncing
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: Text(state.syncing ? 'Syncing…' : 'Sync now'),
          ),
          const SizedBox(height: 16),
          if (_failed.isNotEmpty) ...[
            Text('Needs attention',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry failed changes'),
              onPressed: () async {
                await context.read<AppState>().retryFailed();
                await _loadFailed();
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 8),
            for (final row in _failed)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: Text(row['doctype']?.toString() ?? '-'),
                  subtitle: Text(row['error']?.toString() ?? 'Unknown error'),
                ),
              ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Data is stored on the phone and pushed when connected. '
            'Transactions (pawn loans, releases, collections) are append-only '
            'and never edited after they reach the server.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(key, style: const TextStyle(color: Colors.grey)),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
