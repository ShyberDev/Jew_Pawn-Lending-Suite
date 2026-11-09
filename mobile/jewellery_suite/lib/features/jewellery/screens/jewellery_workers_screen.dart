import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/cloud_refresh.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import 'jewellery_worker_screen.dart';
import 'jewellery_worker_txn_screen.dart';

/// Workers and their reserve position.
///
/// Positive cash is money the shop has paid the worker; positive gold is metal
/// the shop has issued. Both are assets held by the worker, never a loss.
class JewelleryWorkersScreen extends StatefulWidget {
  const JewelleryWorkersScreen({super.key});

  @override
  State<JewelleryWorkersScreen> createState() => _JewelleryWorkersScreenState();
}

class _JewelleryWorkersScreenState extends State<JewelleryWorkersScreen>
    with CloudRefreshMixin<JewelleryWorkersScreen> {
  @override
  Future<void> reloadFromCloud() => _load();

  final _search = TextEditingController();
  List<JewelleryWorkerPosition> _workers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = context.read<AppState>().jewelleryStore;
    final workers = await store.workerPositions();
    if (!mounted) return;
    setState(() {
      _workers = workers;
      _loading = false;
    });
  }

  List<JewelleryWorkerPosition> get _visible {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final w in _workers)
        if (query.isEmpty || w.name.toLowerCase().contains(query)) w,
    ];
  }

  double get _cashTotal => _workers.fold(0, (sum, w) => sum + w.cashReserve);
  double get _goldTotal => _workers.fold(0, (sum, w) => sum + w.goldReserve);

  Future<void> _newMovement() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const JewelleryWorkerTxnScreen()),
    );
    if (saved == true) await _load();
  }

  Future<void> _openWorker(JewelleryWorkerPosition worker) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JewelleryWorkerScreen(workerName: worker.name),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workers'),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newMovement,
        icon: const Icon(Icons.swap_vert),
        label: const Text('New movement'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Held by workers',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _stat('Cash reserve', inr(_cashTotal)),
                            _stat('Metal reserve',
                                '${Num.round3(_goldTotal).toStringAsFixed(3)} g'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Cash paid and metal issued are assets with the worker. '
                          'They are not expenses.',
                          style:
                              TextStyle(fontSize: 11, color: mutedOf(context)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _search,
                  decoration: fieldDecoration('Search worker')
                      .copyWith(prefixIcon: const Icon(Icons.search, size: 20)),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                if (_visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.handyman_outlined,
                            size: 36, color: mutedOf(context)),
                        const SizedBox(height: 8),
                        Text(
                          'No workers yet.\nRecord a cash or metal movement to start.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 12, color: mutedOf(context)),
                        ),
                      ],
                    ),
                  )
                else
                  for (final worker in _visible) _workerTile(worker),
              ],
            ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: inkOf(context))),
          Text(label,
              style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
        ],
      ),
    );
  }

  Widget _workerTile(JewelleryWorkerPosition worker) {
    final hasCash = worker.cashReserve.abs() > 0.005;
    final hasGold = worker.goldReserve.abs() > 0.005;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => _openWorker(worker),
        leading: CircleAvatar(
          backgroundColor: kGoldDark.withValues(alpha: .14),
          child: Text(
            _initials(worker.name),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: kGoldDark),
          ),
        ),
        title: Text(worker.name,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: inkOf(context))),
        subtitle: Text(
          '${worker.txnCount} movement${worker.txnCount == 1 ? '' : 's'}'
          '${worker.lastDate.isEmpty ? '' : ' · last ${fmtDate(worker.lastDate)}'}',
          style: TextStyle(fontSize: 11, color: mutedOf(context)),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (hasCash)
              Text(inr(worker.cashReserve),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: worker.cashReserve >= 0 ? kBlue : kGreen)),
            if (hasGold)
              Text('${Num.round3(worker.goldReserve).toStringAsFixed(3)} g',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: worker.goldReserve >= 0 ? kGoldDark : kGreen)),
            if (!hasCash && !hasGold)
              Text('settled',
                  style: TextStyle(fontSize: 11, color: mutedOf(context))),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
