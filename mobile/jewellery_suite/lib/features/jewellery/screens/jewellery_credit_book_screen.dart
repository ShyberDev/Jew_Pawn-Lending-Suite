import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import 'jewellery_customer_ledger_screen.dart';

/// Customer credit book for jewellery **sales**.
///
/// One row per customer name (case-insensitive), showing what was billed, what
/// was received and what is still due. Purchases are supplier payables and are
/// deliberately not mixed into this list.
class JewelleryCreditBookScreen extends StatefulWidget {
  const JewelleryCreditBookScreen({super.key});

  @override
  State<JewelleryCreditBookScreen> createState() =>
      _JewelleryCreditBookScreenState();
}

class _JewelleryCreditBookScreenState extends State<JewelleryCreditBookScreen> {
  final _search = TextEditingController();
  List<JewelleryCreditCustomer> _customers = const [];
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
    final customers = await store.creditCustomers();
    if (!mounted) return;
    setState(() {
      _customers = customers;
      _loading = false;
    });
  }

  List<JewelleryCreditCustomer> get _visible {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final c in _customers)
        if ((query.isEmpty || c.name.toLowerCase().contains(query)) &&
            (_filter == 0 ||
                (_filter == 1 && c.outstanding > 0) ||
                (_filter == 2 && c.outstanding <= 0)))
          c,
    ];
  }

  double get _totalBilled => _customers.fold(0, (sum, c) => sum + c.billed);
  double get _totalReceived => _customers.fold(0, (sum, c) => sum + c.received);
  double get _totalOutstanding =>
      _customers.fold(0, (sum, c) => sum + c.outstanding);
  int get _withDues => _customers.where((c) => c.outstanding > 0).length;

  Future<void> _openCustomer(JewelleryCreditCustomer customer) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            JewelleryCustomerLedgerScreen(customerName: customer.name),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Credit Book'),
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
                  decoration: fieldDecoration('Search customer').copyWith(
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
                  for (final customer in _visible) _customerTile(customer),
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
            Text('Jewellery customer dues',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                _stat('Outstanding', inr(_totalOutstanding),
                    color: _totalOutstanding > 0 ? kRed : kGreen),
                _stat('Billed', inr(_totalBilled)),
                _stat('Received', inr(_totalReceived)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$_withDues customer${_withDues == 1 ? '' : 's'} with dues · '
              '${_customers.length} in the book',
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

  Widget _customerTile(JewelleryCreditCustomer customer) {
    final due = customer.outstanding > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => _openCustomer(customer),
        leading: CircleAvatar(
          backgroundColor: (due ? kGoldDark : kGreen).withValues(alpha: .14),
          child: Text(
            _initials(customer.name),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: due ? kGoldDark : kGreen),
          ),
        ),
        title: Text(customer.name,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: inkOf(context))),
        subtitle: Text(
          '${customer.invoiceCount} invoice${customer.invoiceCount == 1 ? '' : 's'}'
          ' · last ${customer.lastDate.isEmpty ? '—' : fmtDate(customer.lastDate)}',
          style: TextStyle(fontSize: 11, color: mutedOf(context)),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(inr(customer.outstanding),
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: due ? kRed : kGreen)),
            Text(due ? 'due' : 'settled',
                style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    final hasAny = _customers.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.menu_book_outlined, size: 36, color: mutedOf(context)),
          const SizedBox(height: 8),
          Text(
            hasAny
                ? 'No customer matches this search or filter.'
                : 'No jewellery credit yet.\nSave a sale to start a customer ledger.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: mutedOf(context)),
          ),
        ],
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
