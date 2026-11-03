import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import 'jewellery_invoice_screen.dart';
import 'jewellery_order_detail_screen.dart';

/// Customer jewellery orders. Orders are invoices with `doc_type = ORDER`;
/// they only move stock when delivered.
class JewelleryOrdersScreen extends StatefulWidget {
  const JewelleryOrdersScreen({super.key});

  @override
  State<JewelleryOrdersScreen> createState() => _JewelleryOrdersScreenState();
}

class _JewelleryOrdersScreenState extends State<JewelleryOrdersScreen> {
  final _search = TextEditingController();
  List<Map<String, Object?>> _orders = const [];
  Map<String, int> _counts = const {};
  String _status = '';
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
    final rows = await store.orders(status: _status, search: _search.text);
    final counts = await store.orderStatusSummary();
    if (!mounted) return;
    setState(() {
      _orders = rows;
      _counts = counts;
      _loading = false;
    });
  }

  Future<void> _newOrder() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              const JewelleryInvoiceScreen(docType: JewelleryStore.orderDoc)),
    );
    if (saved == true) await _load();
  }

  Future<void> _open(Map<String, Object?> order) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JewelleryOrderDetailScreen(
          orderUuid: order['client_uuid']?.toString() ?? '',
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _counts['Pending'] ?? 0;
    final ready = _counts['Ready'] ?? 0;
    final delivered = _counts['Delivered'] ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Orders'),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newOrder,
        icon: const Icon(Icons.add),
        label: const Text('New Order'),
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
                        Text('Order pipeline',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _stat('Pending', '$pending', color: kGoldDark),
                            _stat('Ready', '$ready'),
                            _stat('Delivered', '$delivered', color: kGreen),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _search,
                  decoration:
                      fieldDecoration('Search customer, order no or mobile')
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
                      ('Pending', 'Pending'),
                      ('Ready', 'Ready'),
                      ('Delivered', 'Delivered'),
                      ('Cancelled', 'Cancelled'),
                    ])
                      ChoiceChip(
                        label: Text(entry.$2),
                        selected: _status == entry.$1,
                        onSelected: (_) {
                          setState(() => _status = entry.$1);
                          _load();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_orders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 36, color: mutedOf(context)),
                        const SizedBox(height: 8),
                        Text(
                          'No orders yet.\nTake an order without moving stock.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 12, color: mutedOf(context)),
                        ),
                      ],
                    ),
                  )
                else
                  for (final order in _orders) _orderTile(order),
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
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: color ?? inkOf(context))),
          Text(label,
              style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
        ],
      ),
    );
  }

  Widget _orderTile(Map<String, Object?> order) {
    final status = order['status']?.toString() ?? 'Pending';
    final outstanding = Num.toDouble(order['outstanding']);
    final overdue = status != 'Delivered' &&
        status != 'Cancelled' &&
        (order['promised_date']?.toString() ?? '').isNotEmpty &&
        (order['promised_date']?.toString() ?? '')
                .compareTo(DateTime.now().toIso8601String().substring(0, 10)) <
            0;
    final color = status == 'Delivered'
        ? kGreen
        : (status == 'Cancelled'
            ? kRed
            : (status == 'Ready' ? kGoldDark : kBlue));
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => _open(order),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .14),
          child: Icon(
            status == 'Delivered'
                ? Icons.check_circle_outline
                : (status == 'Cancelled'
                    ? Icons.cancel_outlined
                    : Icons.receipt_long_outlined),
            size: 20,
            color: color,
          ),
        ),
        title: Text(
          '${order['party_name'] ?? ''} · ${order['doc_no'] ?? ''}',
          style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: inkOf(context)),
        ),
        subtitle: Text(
          '$status'
          '${(order['promised_date']?.toString() ?? '').isEmpty ? '' : ' · promised ${fmtDate(order['promised_date'])}'}'
          '${overdue ? ' · OVERDUE' : ''}'
          '${outstanding > 0 ? ' · bal ${inr(outstanding)}' : ' · settled'}',
          style: TextStyle(
              fontSize: 11,
              color: overdue ? kRed : mutedOf(context),
              fontWeight: overdue ? FontWeight.w700 : FontWeight.normal),
        ),
        trailing: Text(inr(Num.toDouble(order['total'])),
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: inkOf(context))),
      ),
    );
  }
}
