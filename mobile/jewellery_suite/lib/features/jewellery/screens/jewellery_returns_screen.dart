import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';

/// Linked return credit notes. Every row is its own document; the original
/// sale is never rewritten.
class JewelleryReturnsScreen extends StatefulWidget {
  const JewelleryReturnsScreen({super.key});

  @override
  State<JewelleryReturnsScreen> createState() => _JewelleryReturnsScreenState();
}

class _JewelleryReturnsScreenState extends State<JewelleryReturnsScreen> {
  final _search = TextEditingController();
  List<Map<String, Object?>> _returns = const [];
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
    final rows = await store.returns(search: _search.text);
    if (!mounted) return;
    setState(() {
      _returns = rows;
      _loading = false;
    });
  }

  double get _totalValue =>
      _returns.fold(0, (sum, r) => sum + Num.toDouble(r['total']));
  double get _totalRefund =>
      _returns.fold(0, (sum, r) => sum + Num.toDouble(r['refund_amount']));
  double get _totalCredit => _totalValue - _totalRefund;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showReturn(Map<String, Object?> row) async {
    final store = context.read<AppState>().jewelleryStore;
    final uuid = row['client_uuid']?.toString() ?? '';
    final items = await store.returnItems(uuid);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${row['party_name'] ?? ''} · ${row['return_no'] ?? ''}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: inkOf(ctx)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${fmtDate(row['return_date'])} · against '
                  '${row['source_doc_no'] ?? 'sale'}',
                  style: TextStyle(fontSize: 12, color: mutedOf(ctx)),
                ),
                const Divider(height: 22),
                for (final item in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '${Num.round3(Num.toDouble(item['net_weight'])).toStringAsFixed(3)} g'
                      ' · ${Num.round3(Num.toDouble(item['purity'])).toStringAsFixed(2)}%'
                      ' · ₹${moneyWhole(Num.toDouble(item['rate_per_gram']))}/g',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: inkOf(ctx)),
                    ),
                    subtitle: Text(
                      '${item['description'] ?? ''}'
                      '${Num.toDouble(item['restock']) == 1 ? ' · restocked' : ' · not restocked'}',
                      style: TextStyle(fontSize: 11, color: mutedOf(ctx)),
                    ),
                    trailing: Text(inr(Num.toDouble(item['value'])),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: inkOf(ctx))),
                  ),
                const Divider(height: 22),
                _kv(ctx, 'Return value', inr(Num.toDouble(row['total'])),
                    bold: true),
                _kv(ctx, 'Cash refund',
                    inr(Num.toDouble(row['refund_amount']))),
                _kv(
                    ctx,
                    'Credit to ledger',
                    inr(Num.toDouble(row['total']) -
                        Num.toDouble(row['refund_amount'])),
                    bold: true),
                if ((row['notes']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(row['notes'].toString(),
                      style: TextStyle(fontSize: 12, color: mutedOf(ctx))),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await confirmDialog(
                          ctx, 'Delete this return and its stock movement?',
                          title: 'Delete return');
                      if (!ok || !ctx.mounted) return;
                      await ctx.read<AppState>().deleteJewelleryReturn(uuid);
                      if (!mounted) return;
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _load();
                      _toast('Return deleted.');
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete return'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext ctx, String label, String value,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: mutedOf(ctx))),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: inkOf(ctx))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Returns'),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Return credits',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _stat('Value', inr(_totalValue)),
                            _stat('Refunded', inr(_totalRefund), color: kRed),
                            _stat('Credited', inr(_totalCredit), color: kGreen),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_returns.length} return${_returns.length == 1 ? '' : 's'} · '
                          'sale invoices stay unchanged',
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
                  decoration: fieldDecoration('Search return, customer or sale')
                      .copyWith(prefixIcon: const Icon(Icons.search, size: 20)),
                  onChanged: (_) {
                    setState(() {});
                    _load();
                  },
                ),
                const SizedBox(height: 12),
                if (_returns.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.assignment_return_outlined,
                            size: 36, color: mutedOf(context)),
                        const SizedBox(height: 8),
                        Text(
                          'No returns yet.\nOpen a sale and choose Return.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 12, color: mutedOf(context)),
                        ),
                      ],
                    ),
                  )
                else
                  for (final row in _returns)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        onTap: () => _showReturn(row),
                        leading: const Icon(Icons.assignment_return_outlined),
                        title: Text(
                          '${row['party_name'] ?? ''} · ${row['return_no'] ?? ''}',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: inkOf(context)),
                        ),
                        subtitle: Text(
                          '${fmtDate(row['return_date'])} · against '
                          '${row['source_doc_no'] ?? 'sale'}'
                          '${Num.toDouble(row['refund_amount']) > 0 ? ' · refund ${inr(Num.toDouble(row['refund_amount']))}' : ''}',
                          style:
                              TextStyle(fontSize: 11, color: mutedOf(context)),
                        ),
                        trailing: Text(inr(Num.toDouble(row['total'])),
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: inkOf(context))),
                      ),
                    ),
              ],
            ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color ?? inkOf(context))),
          Text(label,
              style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
        ],
      ),
    );
  }
}
