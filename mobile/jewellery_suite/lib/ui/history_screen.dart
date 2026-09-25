import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/format.dart';
import 'palette.dart';

/// History of recent activity + deleted content for both Pawn Loans and
/// Khatabook. Village filters, retention-based auto-clear (1/3/6/12 months)
/// and an admin-password protected "Clear Now".
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, Object?>> _events = [];
  bool _loading = true;

  String _village = 'All';
  String _module = 'All';
  int _retentionMonths = 6;

  static const _retentionOptions = [1, 3, 6, 12];
  static const _moduleOptions = ['All', 'Khata', 'Pawn'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    // Auto-clear: drop events older than the retention period.
    await state.purgeHistory(DateTime.now()
        .subtract(Duration(days: 30 * _retentionMonths)));
    final events = await state.db.query('history_log',
        orderBy: 'created_at desc');
    if (mounted) setState(() {
      _events = events;
      _loading = false;
    });
  }

  Set<String> get _villages =>
      _events.map((e) => e['village']?.toString() ?? '—').toSet();

  List<Map<String, Object?>> get _filtered {
    return _events.where((e) {
      final m = e['module']?.toString() ?? 'khata';
      if (_module == 'Khata' && m != 'khata') return false;
      if (_module == 'Pawn' && m != 'pawn') return false;
      final v = e['village']?.toString() ?? '—';
      if (_village != 'All' && v != _village) return false;
      return true;
    }).toList();
  }

  Future<void> _clearNow() async {
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all history?'),
        content: TextField(
          controller: pw,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Type admin password',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, pw.text.trim().toLowerCase() == 'admin'),
              child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) _toast('Clear cancelled / wrong password.');
      return;
    }
    await context.read<AppState>().clearHistory();
    await _load();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          TextButton.icon(
            onPressed: _clearNow,
            icon: const Icon(Icons.delete_sweep_outlined,
                size: 18, color: kRed),
            label: const Text('Clear now',
                style: TextStyle(color: kRed)),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: kGold,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kGold))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _filterRow(),
                  const SizedBox(height: 10),
                  if (_filtered.isEmpty)
                    const _EmptyHistory()
                  else
                    for (final e in _filtered) _eventTile(e),
                ],
              ),
      ),
    );
  }

  Widget _filterRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final m in _moduleOptions)
              ChoiceChip(
                label: Text(m, style: const TextStyle(fontSize: 12)),
                selected: _module == m,
                selectedColor: kGold.withValues(alpha: .25),
                onSelected: (_) => setState(() => _module = m),
              ),
          ],
        ),
        if (_villages.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text('All', style: TextStyle(fontSize: 12)),
                selected: _village == 'All',
                selectedColor: kGold.withValues(alpha: .25),
                onSelected: (_) => setState(() => _village = 'All'),
              ),
              for (final v in _villages)
                ChoiceChip(
                  label: Text(v, style: const TextStyle(fontSize: 12)),
                  selected: _village == v,
                  selectedColor: kGold.withValues(alpha: .25),
                  onSelected: (_) => setState(() => _village = v),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Auto-clear:',
                style: TextStyle(
                    fontSize: 12, color: kInk.withValues(alpha: .6))),
            const SizedBox(width: 8),
            for (final m in _retentionOptions)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('$m mo', style: const TextStyle(fontSize: 11.5)),
                  selected: _retentionMonths == m,
                  selectedColor: kGold.withValues(alpha: .25),
                  onSelected: (_) async {
                    setState(() => _retentionMonths = m);
                    await _load();
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _eventTile(Map<String, Object?> e) {
    final module = e['module']?.toString() ?? 'khata';
    final kind = e['kind']?.toString() ?? '';
    final title = e['title']?.toString() ?? '';
    final amount = Num.toDouble(e['amount']);
    final village = e['village']?.toString();
    final at = fmtDateTime(e['created_at']);
    final isKhatabook = module == 'khata';
    final color = kind.contains('delete')
        ? kRed
        : kind.contains('collect')
            ? kGreen
            : kind == 'refinance'
                ? kGoldDark
                : kBlue;
    final icon = kind.contains('delete')
        ? Icons.delete_outline
        : kind.contains('collect')
            ? Icons.south_west
            : kind == 'refinance'
                ? Icons.change_history
                : Icons.menu_book_outlined;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
                const SizedBox(height: 2),
                Text(
                  [
                    isKhatabook ? 'Khata' : 'Pawn',
                    if (village != null && village.isNotEmpty) village,
                    at,
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: 11, color: kInk.withValues(alpha: .55)),
                ),
              ],
            ),
          ),
          if (amount > 0)
            Text('₹${moneyWhole(amount)}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color)),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Icon(Icons.history, size: 48, color: kGold),
          const SizedBox(height: 10),
          Text('No history yet',
              style: TextStyle(color: kInk.withValues(alpha: .6))),
        ],
      ),
    );
  }
}