import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import '../widgets/jewellery_invoice_sheet.dart';

/// Old-metal register: every exchange voucher the shop received, with the
/// accepted value and equivalent grams. Rows open the source invoice.
class JewelleryOldMetalScreen extends StatefulWidget {
  const JewelleryOldMetalScreen({super.key});

  @override
  State<JewelleryOldMetalScreen> createState() =>
      _JewelleryOldMetalScreenState();
}

class _JewelleryOldMetalScreenState extends State<JewelleryOldMetalScreen> {
  final _search = TextEditingController();
  List<Map<String, Object?>> _vouchers = const [];
  ({
    double goldGrams,
    double silverGrams,
    double acceptedValue,
    int vouchers,
  })? _totals;
  String _metal = '';
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
    final rows = await store.oldMetalVouchers(
      search: _search.text,
      metal: _metal.isEmpty ? null : _metal,
    );
    final totals = await store.oldMetalTotals();
    if (!mounted) return;
    setState(() {
      _vouchers = rows;
      _totals = totals;
      _loading = false;
    });
  }

  Future<void> _openInvoice(Map<String, Object?> voucher) async {
    final uuid = voucher['invoice_uuid']?.toString() ?? '';
    if (uuid.isEmpty) return;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => JewelleryInvoiceSheet(invoiceUuid: uuid),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Old Metal'),
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
                _summaryCard(),
                const SizedBox(height: 10),
                TextField(
                  controller: _search,
                  decoration:
                      fieldDecoration('Search voucher, customer or invoice')
                          .copyWith(
                              prefixIcon: const Icon(Icons.search, size: 20)),
                  onChanged: (_) {
                    setState(() {});
                    _load();
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in const [
                      ('', 'All'),
                      (JewelleryStore.gold, 'Gold'),
                      (JewelleryStore.silver, 'Silver'),
                    ])
                      ChoiceChip(
                        label: Text(entry.$2),
                        selected: _metal == entry.$1,
                        onSelected: (_) {
                          setState(() => _metal = entry.$1);
                          _load();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_vouchers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.recycling_outlined,
                            size: 36, color: mutedOf(context)),
                        const SizedBox(height: 8),
                        Text(
                          'No old metal recorded yet.\nTurn on the exchange switch on a sale.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 12, color: mutedOf(context)),
                        ),
                      ],
                    ),
                  )
                else
                  for (final voucher in _vouchers) _voucherTile(voucher),
              ],
            ),
    );
  }

  Widget _summaryCard() {
    final t = _totals;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Old metal received',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                _stat('Gold equivalent',
                    '${Num.round3(t?.goldGrams ?? 0).toStringAsFixed(3)} g'),
                _stat('Silver equivalent',
                    '${Num.round3(t?.silverGrams ?? 0).toStringAsFixed(3)} g'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _stat('Accepted value', inr(t?.acceptedValue ?? 0),
                    color: kGoldDark),
                _stat('Vouchers', '${t?.vouchers ?? 0}'),
              ],
            ),
          ],
        ),
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

  Widget _voucherTile(Map<String, Object?> voucher) {
    final metal = (voucher['metal']?.toString() ?? '').toUpperCase();
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => _openInvoice(voucher),
        leading: CircleAvatar(
          backgroundColor: kGoldDark.withValues(alpha: .14),
          child: Icon(
            metal == JewelleryStore.silver
                ? Icons.circle_outlined
                : Icons.workspace_premium_outlined,
            size: 20,
            color: kGoldDark,
          ),
        ),
        title: Text(
          '${voucher['customer'] ?? voucher['invoice_party'] ?? ''}'
          ' · ${voucher['voucher_no'] ?? ''}',
          style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: inkOf(context)),
        ),
        subtitle: Text(
          '${fmtDate(voucher['received_date'])} · $metal'
          ' · ${Num.round3(Num.toDouble(voucher['equivalent_weight'])).toStringAsFixed(3)} g'
          ' · ${Num.round3(Num.toDouble(voucher['purity'])).toStringAsFixed(2)}%'
          '${voucher['invoice_doc_no'] == null ? '' : ' · ${voucher['invoice_doc_no']}'}',
          style: TextStyle(fontSize: 11, color: mutedOf(context)),
        ),
        trailing: Text(inr(Num.toDouble(voucher['accepted_value'])),
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: inkOf(context))),
      ),
    );
  }
}
