import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'customers_screen.dart';
import 'khatabook_screen.dart';
import 'pawn_screen.dart';
import 'sync_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, Object?> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final stats = await context.read<AppState>().dashboard();
    if (mounted) {
      setState(() {
        _stats = stats;
        _loading = false;
      });
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => screen));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jewellery Suite'),
        actions: [
          if (state.pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Badge(label: Text('${state.pending}')),
            ),
          IconButton(
            icon: state.syncing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            onPressed: state.syncing
                ? null
                : () async {
                    try {
                      final summary = await state.sync();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Synced: $summary')));
                      await _refresh();
                    } catch (error) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Sync failed: $error')));
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => state.logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _Dashboard(stats: _stats),
            const SizedBox(height: 8),
            _Tile(
              icon: Icons.people_outline,
              title: 'Customers',
              subtitle: '${_stats['customers'] ?? 0} saved',
              onTap: () => _open(const CustomersScreen()),
            ),
            _Tile(
              icon: Icons.account_balance,
              title: 'Pawn Loans',
              subtitle:
                  '${_stats['active_pawn'] ?? 0} active · ₹${moneyText(_stats['pawn_out'] as num?)} out',
              onTap: () => _open(const PawnScreen()),
            ),
            _Tile(
              icon: Icons.menu_book_outlined,
              title: 'Khatabook',
              subtitle: '${_stats['khatabook_active'] ?? 0} active loans',
              onTap: () => _open(const KhatabookScreen()),
            ),
            _Tile(
              icon: Icons.sync,
              title: 'Sync',
              subtitle: state.pending > 0
                  ? '${state.pending} change(s) waiting'
                  : 'All changes synced',
              onTap: () => _open(const SyncScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.stats});

  final Map<String, Object?> stats;

  @override
  Widget build(BuildContext context) {
    final cards = [
      ('Customers', '${stats['customers'] ?? 0}', Icons.people_outline),
      ('Active pawn', '${stats['active_pawn'] ?? 0}', Icons.account_balance),
      ('Pawn outstanding', '₹${moneyText(stats['pawn_out'] as num?)}',
          Icons.savings_outlined),
      ('Collected today', '₹${moneyText(stats['collected_today'] as num?)}',
          Icons.today_outlined),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.7,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final card in cards)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(card.$3, color: Theme.of(context).colorScheme.primary),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.$2,
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(card.$1,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
