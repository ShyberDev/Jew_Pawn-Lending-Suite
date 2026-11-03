import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import 'jewellery_supplier_ledger_screen.dart';

/// Supplier payable book for jewellery **purchases**.
///
/// One row per supplier name (case-insensitive), showing what was purchased,
/// what was paid and what the shop still owes. Customer sales are deliberately
/// not mixed into this list.
class JewellerySupplierBookScreen extends StatefulWidget {
  const JewellerySupplierBookScreen({super.key});

  @override
  State<JewellerySupplierBookScreen> createState() =>
      _JewellerySupplierBookScreenState();
}

class _JewellerySupplierBookScreenState
    extends State<JewellerySupplierBookScreen> {
  final _search = TextEditingController();
  List<JewellerySupplier> _suppliers = const [];
  bool _loading = true;
  int _filter = 0; // 0 all, 1 with dues, 2 settled

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
    final suppliers = await store.supplierPayables();
    if (!mounted) return;
    setState(() {
      _suppliers = suppliers;
      _loading = false;
    });
  }

  List<JewellerySupplier> get _visible {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final s in _suppliers)
        if ((query.isEmpty || s.name.toLowerCase().contains(query)) &&
            (_filter == 0 ||
                (_filter == 1 && s.outstanding > 0) ||
                (_filter == 2 && s.outstanding <= 0)))
          s,
    ];
  }

  double get _totalBilled => _suppliers.fold(0, (sum, s) => sum + s.billed);
  double get _totalPaid => _suppliers.fold(0, (sum, s) => sum + s.paid);
  double get _totalOutstanding =>
      _suppliers.fold(0, (sum, s) => sum + s.outstanding);
  int get _withDues => _suppliers.where((s) => s.outstanding > 0).length;

  Future<void> _openSupplier(JewellerySupplier supplier) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            JewellerySupplierLedgerScreen(supplierName: supplier.name),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supplier Payables'),
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
                  decoration: fieldDecoration('Search supplier').copyWith(
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in const [
                      (0, 'All'),
                      (1, 'With dues'),
                      (2, 'Settled'),
                    ])
                      ChoiceChip(
                        label: Text(entry.$2),
                        selected: _filter == entry.$1,
                        onSelected: (_) => setState(() => _filter = entry.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_visible.isEmpty)
                  _empty()
                else
                  for (final supplier in _visible) _supplierTile(supplier),
              ],
            ),
    );
  }

  Widget _summaryCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Jewellery supplier payables',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                _stat('Payable', inr(_totalOutstanding),
                    color: _totalOutstanding > 0 ? kRed : kGreen),
                _stat('Purchased', inr(_totalBilled)),
                _stat('Paid', inr(_totalPaid)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$_withDues supplier${_withDues == 1 ? '' : 's'} with dues · '
              '${_suppliers.length} in the book',
              style: TextStyle(fontSize: 11, color: mutedOf(context)),
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

  Widget _supplierTile(JewellerySupplier supplier) {
    final due = supplier.outstanding > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => _openSupplier(supplier),
        leading: CircleAvatar(
          backgroundColor: (due ? kRed : kGreen).withValues(alpha: .14),
          child: Text(
            _initials(supplier.name),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: due ? kRed : kGreen),
          ),
        ),
        title: Text(supplier.name,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: inkOf(context))),
        subtitle: Text(
          '${supplier.invoiceCount} purchase${supplier.invoiceCount == 1 ? '' : 's'}'
          ' · last ${supplier.lastDate.isEmpty ? '—' : fmtDate(supplier.lastDate)}',
          style: TextStyle(fontSize: 11, color: mutedOf(context)),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(inr(supplier.outstanding),
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: due ? kRed : kGreen)),
            Text(due ? 'payable' : 'settled',
                style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    final hasAny = _suppliers.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.local_shipping_outlined,
              size: 42, color: mutedOf(context)),
          const SizedBox(height: 10),
          Text(
            hasAny
                ? 'No suppliers match this filter.'
                : 'No supplier payables yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: mutedOf(context)),
          ),
          if (!hasAny) ...[
            const SizedBox(height: 4),
            Text(
              'A purchase creates the supplier payable; purchase payments reduce it.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: mutedOf(context)),
            ),
          ],
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
