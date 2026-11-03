import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import '../../../util/jewellery_math.dart';

/// One customer order: items, advance, status changes and delivery.
///
/// Delivery is the only moment stock moves. It records actual gross, stone and
/// net weights, any extra collection and any refund.
class JewelleryOrderDetailScreen extends StatefulWidget {
  const JewelleryOrderDetailScreen({super.key, required this.orderUuid});

  final String orderUuid;

  @override
  State<JewelleryOrderDetailScreen> createState() =>
      _JewelleryOrderDetailScreenState();
}

class _JewelleryOrderDetailScreenState
    extends State<JewelleryOrderDetailScreen> {
  Map<String, Object?>? _order;
  List<Map<String, Object?>> _items = const [];
  List<Map<String, Object?>> _payments = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<AppState>().jewelleryStore;
    final order = await store.invoice(widget.orderUuid);
    final items = await store.itemsFor(widget.orderUuid);
    final payments = await store.paymentsFor(widget.orderUuid);
    if (!mounted) return;
    setState(() {
      _order = order;
      _items = items;
      _payments = payments;
      _loading = false;
    });
  }

  String get _status => _order?['status']?.toString() ?? 'Pending';
  bool get _canAct => _status != 'Delivered' && _status != 'Cancelled';

  double get _orderedNet => _items.fold<double>(
      0, (sum, item) => sum + Num.toDouble(item['net_weight']));

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _updateStatus(String status) async {
    if (status == 'Cancelled') {
      final ok = await confirmDialog(
          context,
          'Cancel this order? Any advance already received is not refunded '
          'automatically.',
          title: 'Cancel order');
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await context
          .read<AppState>()
          .jewelleryStore
          .updateOrderStatus(widget.orderUuid, status);
      await _load();
      _toast('Order marked $status.');
    } on FormatException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receivePayment() async {
    final order = _order;
    if (order == null) return;
    final outstanding = Num.toDouble(order['outstanding']);
    final ctl = TextEditingController(
        text: outstanding > 0 ? outstanding.toStringAsFixed(0) : '');
    try {
      final amount = await showDialog<double>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Receive order payment'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fieldDecoration('Amount ₹'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, parseMoney(ctl.text)),
                child: const Text('Save')),
          ],
        ),
      );
      if (amount == null || amount <= 0) return;
      if (!mounted) return;
      await context.read<AppState>().addJewelleryPayment(
            invoiceUuid: widget.orderUuid,
            partyName: order['party_name']?.toString() ?? '',
            amount: amount,
            date: DateTime.now(),
          );
      await _load();
    } on FormatException catch (e) {
      _toast(e.message);
    } finally {
      ctl.dispose();
    }
  }

  Future<void> _deliver() async {
    final order = _order;
    if (order == null) return;
    final gross = TextEditingController(
        text: _orderedNet > 0 ? _orderedNet.toStringAsFixed(3) : '');
    final stone = TextEditingController(text: '0');
    final extra = TextEditingController(text: '0');
    final refund = TextEditingController(text: '0');
    final notes = TextEditingController();
    DateTime date = DateTime.now();
    var mode = 'CASH';
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Deliver order'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setDialogState(() => date = picked);
                    },
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(fmtDate(date.toIso8601String())),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: gross,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: fieldDecoration('Delivered gross weight (g)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: stone,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: fieldDecoration('Stone / pearl weight (g)'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Ordered net ${Num.round3(_orderedNet).toStringAsFixed(3)} g',
                    style: TextStyle(fontSize: 11, color: mutedOf(ctx)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: extra,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: fieldDecoration('Extra amount collected ₹'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: refund,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: fieldDecoration('Refund now ₹'),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in const ['CASH', 'UPI', 'BANK'])
                        ChoiceChip(
                          label: Text(m),
                          selected: mode == m,
                          onSelected: (_) => setDialogState(() => mode = m),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    decoration: fieldDecoration('Delivery notes (optional)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Deliver')),
            ],
          ),
        ),
      );
      if (confirmed != true) return;
      if (!mounted) return;
      setState(() => _busy = true);
      await context.read<AppState>().deliverJewelleryOrder(
            orderUuid: widget.orderUuid,
            date: date,
            deliveredGrossWeight: parseMoney(gross.text),
            stoneWeight: parseMoney(stone.text),
            extraAmount: parseMoney(extra.text),
            refundAmount: parseMoney(refund.text),
            paymentMode: mode,
            notes: notes.text.trim(),
          );
      await _load();
      _toast('Order delivered.');
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Could not deliver: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      gross.dispose();
      stone.dispose();
      extra.dispose();
      refund.dispose();
      notes.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(
        title: Text(order?['doc_no']?.toString() ?? 'Order'),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading || order == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                _headerCard(order),
                if (_items.isNotEmpty) _itemsCard(),
                _moneyCard(order),
                if (_status == 'Delivered') _deliveryCard(order),
                if (_payments.isNotEmpty) _paymentsCard(),
                const SizedBox(height: 8),
                if (_canAct) ...[
                  Row(
                    children: [
                      if (_status == 'Pending')
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                _busy ? null : () => _updateStatus('Ready'),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Mark Ready'),
                          ),
                        ),
                      if (_status == 'Pending') const SizedBox(width: 8),
                      if (_status == 'Pending')
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                _busy ? null : () => _updateStatus('Cancelled'),
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Cancel'),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _deliver,
                    icon: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: const Text('DELIVER ORDER'),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_status != 'Cancelled' && _status != 'Delivered')
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _receivePayment,
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Receive payment'),
                  ),
              ],
            ),
    );
  }

  Widget _headerCard(Map<String, Object?> order) {
    final status = _status;
    final color = status == 'Delivered'
        ? kGreen
        : (status == 'Cancelled'
            ? kRed
            : (status == 'Ready' ? kGoldDark : kBlue));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(order['party_name']?.toString() ?? '',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: inkOf(context))),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if ((order['mobile']?.toString() ?? '').isNotEmpty)
              Text(order['mobile'].toString(),
                  style: TextStyle(fontSize: 12, color: mutedOf(context))),
            if ((order['address']?.toString() ?? '').isNotEmpty)
              Text(order['address'].toString(),
                  style: TextStyle(fontSize: 12, color: mutedOf(context))),
            const SizedBox(height: 6),
            Text(
              'Ordered ${fmtDate(order['invoice_date'])}'
              '${(order['promised_date']?.toString() ?? '').isEmpty ? '' : ' · promised ${fmtDate(order['promised_date'])}'}',
              style: TextStyle(fontSize: 12, color: mutedOf(context)),
            ),
            if ((order['notes']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(order['notes'].toString(),
                  style: TextStyle(fontSize: 12, color: mutedOf(context))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemsCard() {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Items',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final item in _items) _itemTile(item),
            const Divider(height: 18),
            _row('Ordered net',
                '${Num.round3(_orderedNet).toStringAsFixed(3)} g'),
          ],
        ),
      ),
    );
  }

  Widget _itemTile(Map<String, Object?> item) {
    final line = JewelleryMath.line(
      weight: Num.toDouble(item['net_weight']),
      purityPct: Num.toDouble(item['purity']),
      pureRate: Num.toDouble(item['rate_per_gram']),
      makingMode: MakingMode.values.firstWhere(
        (m) => m.name == (item['making_mode']?.toString() ?? ''),
        orElse: () => MakingMode.none,
      ),
      makingValue: Num.toDouble(item['making_value']),
      additionalCost: Num.toDouble(item['additional_cost']),
      discount: Num.toDouble(item['discount']),
      billingBasis: BillingBasis.values.firstWhere(
        (b) => b.name == (item['billing_basis']?.toString() ?? ''),
        orElse: () => BillingBasis.raw,
      ),
      wastagePct: Num.toDouble(item['wastage_pct']),
      makingCharge: Num.toDouble(item['making_charge']),
    );
    final retail = line.billingBasis != BillingBasis.raw;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${Num.round3(line.weight).toStringAsFixed(3)} g'
                  ' · ${Num.round3(line.purityPct).toStringAsFixed(2)}%'
                  ' · ₹${moneyWhole(line.pureRate)}/g',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: inkOf(context)),
                ),
                Text(
                  retail
                      ? '${line.billingBasis == BillingBasis.kdm ? 'KDM · wastage ${Num.round3(line.wastageWeight).toStringAsFixed(3)} g · ' : 'Non-KDM · '}'
                          'billing ${Num.round3(line.billedWeight).toStringAsFixed(3)} g'
                          ' × ₹${moneyWhole(line.pureRate)} + making ${inr(line.makingAmount)}'
                      : 'Wastage ${Num.round3(line.wastageWeight).toStringAsFixed(3)} g'
                          ' · total ${Num.round3(line.totalEquivalentWeight).toStringAsFixed(3)} g'
                          ' × ₹${moneyWhole(line.pureRate)}',
                  style: TextStyle(fontSize: 11, color: mutedOf(context)),
                ),
              ],
            ),
          ),
          Text(inr(line.total),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: inkOf(context))),
        ],
      ),
    );
  }

  Widget _moneyCard(Map<String, Object?> order) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _row('Payable', inr(Num.toDouble(order['total'])), bold: true),
            _row('Advance / received', inr(Num.toDouble(order['amount_paid']))),
            _row('Balance', inr(Num.toDouble(order['outstanding'])),
                bold: true),
          ],
        ),
      ),
    );
  }

  Widget _deliveryCard(Map<String, Object?> order) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delivery',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _row('Delivered on', fmtDate(order['delivery_date'])),
            _row('Gross weight',
                '${Num.round3(Num.toDouble(order['delivered_gross_weight'])).toStringAsFixed(3)} g'),
            _row('Stone weight',
                '${Num.round3(Num.toDouble(order['stone_weight'])).toStringAsFixed(3)} g'),
            _row('Net weight',
                '${Num.round3(Num.toDouble(order['delivered_net_weight'])).toStringAsFixed(3)} g',
                bold: true),
            _row('Difference',
                '${Num.round3(Num.toDouble(order['difference_weight'])).toStringAsFixed(3)} g'),
            if (Num.toDouble(order['extra_amount']) > 0)
              _row('Extra collected', inr(Num.toDouble(order['extra_amount']))),
            if (Num.toDouble(order['refund_amount']) > 0)
              _row('Refunded', inr(Num.toDouble(order['refund_amount']))),
          ],
        ),
      ),
    );
  }

  Widget _paymentsCard() {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payments',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final p in _payments)
              _row(
                '${fmtDate(p['pay_date'])} · ${p['payment_mode'] ?? ''}',
                inr(Num.toDouble(p['amount'])),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: mutedOf(context))),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: inkOf(context))),
        ],
      ),
    );
  }
}
