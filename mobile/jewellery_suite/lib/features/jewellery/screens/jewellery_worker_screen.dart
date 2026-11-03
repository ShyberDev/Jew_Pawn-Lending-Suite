import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import 'jewellery_worker_order_screen.dart';
import 'jewellery_worker_txn_screen.dart';

/// One worker's ledger: every signed cash/metal movement and every work order.
class JewelleryWorkerScreen extends StatefulWidget {
  const JewelleryWorkerScreen({super.key, required this.workerName});

  final String workerName;

  @override
  State<JewelleryWorkerScreen> createState() => _JewelleryWorkerScreenState();
}

class _JewelleryWorkerScreenState extends State<JewelleryWorkerScreen> {
  List<Map<String, Object?>> _txns = const [];
  List<Map<String, Object?>> _orders = const [];
  JewelleryWorkerPosition? _position;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<AppState>().jewelleryStore;
    final txns = await store.workerTransactions(widget.workerName);
    final orders = await store.workerOrders(workerName: widget.workerName);
    final positions = await store.workerPositions();
    if (!mounted) return;
    JewelleryWorkerPosition? position;
    for (final p in positions) {
      if (p.name.toLowerCase() == widget.workerName.trim().toLowerCase()) {
        position = p;
        break;
      }
    }
    setState(() {
      _txns = txns;
      _orders = orders;
      _position = position;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openTxn() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              JewelleryWorkerTxnScreen(workerName: widget.workerName)),
    );
    if (saved == true) await _load();
  }

  Future<void> _openOrder() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              JewelleryWorkerOrderScreen(workerName: widget.workerName)),
    );
    if (saved == true) await _load();
  }

  Future<void> _deleteTxn(Map<String, Object?> txn) async {
    final ok = await confirmDialog(
        context, 'Delete this movement and its stock/cash effect?',
        title: 'Delete movement');
    if (!ok) return;
    if (!mounted) return;
    await context.read<AppState>().deleteJewelleryWorkerTransaction(
          txn['client_uuid']?.toString() ?? '',
        );
    await _load();
  }

  Future<void> _deliverOrder(Map<String, Object?> order) async {
    final ordered = Num.toDouble(order['ordered_weight']);
    final gross = TextEditingController(
        text: ordered > 0 ? ordered.toStringAsFixed(3) : '');
    final stone = TextEditingController(text: '0');
    final cash = TextEditingController(text: '0');
    final metal = TextEditingController(text: '0');
    final notes = TextEditingController();
    DateTime date = DateTime.now();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Deliver worker order'),
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
                  TextField(
                    controller: cash,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: fieldDecoration('Cash paid to worker now ₹'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: metal,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        fieldDecoration('Metal issued to worker now (g)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    decoration: fieldDecoration('Notes (optional)'),
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
      final state = context.read<AppState>();
      await state.jewelleryStore.deliverWorkerOrder(
        uuid: order['client_uuid']?.toString() ?? '',
        date: date,
        deliveredGrossWeight: parseMoney(gross.text),
        stoneWeight: parseMoney(stone.text),
        cashPaid: parseMoney(cash.text),
        metalPaid: parseMoney(metal.text),
        notes: notes.text.trim(),
      );
      final cashPaid = parseMoney(cash.text);
      final metalPaid = parseMoney(metal.text);
      if (cashPaid > 0 || metalPaid > 0) {
        await state.saveJewelleryWorkerTransaction(
          workerName: widget.workerName,
          date: date,
          type: 'WORKER_ORDER',
          cashAmount: cashPaid,
          goldWeight: metalPaid,
          metal: order['metal']?.toString() ?? JewelleryStore.gold,
          purity: 100,
          orderUuid: order['client_uuid']?.toString() ?? '',
          notes: 'Worker order delivery',
        );
      }
      await _load();
      _toast('Worker order delivered.');
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Could not deliver: $e');
    } finally {
      gross.dispose();
      stone.dispose();
      cash.dispose();
      metal.dispose();
      notes.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workerName),
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
                        Text('Reserve with worker',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _stat('Cash', inr(position?.cashReserve ?? 0)),
                            _stat('Metal',
                                '${Num.round3(position?.goldReserve ?? 0).toStringAsFixed(3)} g'),
                            _stat('Fine gold',
                                '${Num.round3(position?.fineGoldReserve ?? 0).toStringAsFixed(3)} g'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Positive cash = paid to worker. Positive metal = issued to worker.',
                          style:
                              TextStyle(fontSize: 11, color: mutedOf(context)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openTxn,
                        icon: const Icon(Icons.swap_vert, size: 18),
                        label: const Text('Cash / metal'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openOrder,
                        icon: const Icon(Icons.add_task, size: 18),
                        label: const Text('Work order'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('WORK ORDERS',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: mutedOf(context))),
                const SizedBox(height: 6),
                if (_orders.isEmpty)
                  Text('No work orders for this worker.',
                      style: TextStyle(fontSize: 12, color: mutedOf(context)))
                else
                  for (final order in _orders) _orderTile(order),
                const SizedBox(height: 14),
                Text('MOVEMENTS',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: mutedOf(context))),
                const SizedBox(height: 6),
                if (_txns.isEmpty)
                  Text('No movements yet.',
                      style: TextStyle(fontSize: 12, color: mutedOf(context)))
                else
                  for (final txn in _txns) _txnTile(txn),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: inkOf(context))),
          Text(label,
              style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
        ],
      ),
    );
  }

  Widget _orderTile(Map<String, Object?> order) {
    final status = order['status']?.toString() ?? 'Pending';
    final delivered = status == 'Delivered';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: delivered ? null : () => _deliverOrder(order),
        leading: Icon(
          delivered ? Icons.check_circle_outline : Icons.pending_outlined,
          color: delivered ? kGreen : kGoldDark,
        ),
        title: Text(
          '${Num.round3(Num.toDouble(order['ordered_weight'])).toStringAsFixed(3)} g'
          ' · ${order['item_description'] ?? 'Work'}',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: inkOf(context)),
        ),
        subtitle: Text(
          '${fmtDate(order['order_date'])}'
          '${(order['expected_date']?.toString() ?? '').isEmpty ? '' : ' · expected ${fmtDate(order['expected_date'])}'}'
          '${delivered ? ' · delivered ${Num.round3(Num.toDouble(order['delivered_net_weight'])).toStringAsFixed(3)} g' : ''}',
          style: TextStyle(fontSize: 11, color: mutedOf(context)),
        ),
        trailing: Text(status,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: delivered ? kGreen : kGoldDark)),
      ),
    );
  }

  Widget _txnTile(Map<String, Object?> txn) {
    final cash = Num.toDouble(txn['cash_amount']);
    final gold = Num.toDouble(txn['gold_weight']);
    final parts = <String>[
      if (cash.abs() > 0.005)
        '${cash > 0 ? 'Paid' : 'Received'} ${inr(cash.abs())}',
      if (gold.abs() > 0.005)
        '${gold > 0 ? 'Issued' : 'Returned'} ${Num.round3(gold.abs()).toStringAsFixed(3)} g',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onLongPress: () => _deleteTxn(txn),
        title: Text(parts.join(' · '),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: inkOf(context))),
        subtitle: Text(
          '${fmtDate(txn['txn_date'])}'
          '${(txn['notes']?.toString() ?? '').isEmpty ? '' : ' · ${txn['notes']}'}',
          style: TextStyle(fontSize: 11, color: mutedOf(context)),
        ),
        trailing: IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () => _deleteTxn(txn),
        ),
      ),
    );
  }
}
