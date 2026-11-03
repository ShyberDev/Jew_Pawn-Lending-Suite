import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';

/// One signed cash/metal movement with a worker.
///
/// Positive cash means the shop paid the worker; positive gold means the shop
/// issued metal. Negative values are the worker paying or returning metal.
class JewelleryWorkerTxnScreen extends StatefulWidget {
  const JewelleryWorkerTxnScreen({super.key, this.workerName = ''});

  final String workerName;

  @override
  State<JewelleryWorkerTxnScreen> createState() =>
      _JewelleryWorkerTxnScreenState();
}

class _JewelleryWorkerTxnScreenState extends State<JewelleryWorkerTxnScreen> {
  late final TextEditingController _worker =
      TextEditingController(text: widget.workerName);
  final _cash = TextEditingController();
  final _gold = TextEditingController();
  final _purity = TextEditingController(text: '100');
  final _rate = TextEditingController();
  final _notes = TextEditingController();

  List<Map<String, Object?>> _orders = const [];
  String? _orderUuid;
  String _metal = JewelleryStore.gold;
  DateTime _date = DateTime.now();
  bool _shopGave = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    for (final c in [_worker, _cash, _gold, _purity, _rate, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOrders() async {
    final store = context.read<AppState>().jewelleryStore;
    final orders = await store.workerOrders();
    if (!mounted) return;
    setState(() => _orders = orders);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final cash = parseMoney(_cash.text) * (_shopGave ? 1 : -1);
    final gold = parseMoney(_gold.text) * (_shopGave ? 1 : -1);
    if (_worker.text.trim().isEmpty) {
      _toast('Enter the worker name.');
      return;
    }
    if (cash.abs() < 0.005 && gold.abs() < 0.005) {
      _toast('Enter a cash or gold amount.');
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppState>().saveJewelleryWorkerTransaction(
            workerName: _worker.text.trim(),
            date: _date,
            type: gold.abs() > 0.005
                ? (cash.abs() > 0.005 ? 'CASH_GOLD' : 'GOLD')
                : 'CASH',
            cashAmount: cash,
            goldWeight: gold,
            metal: _metal,
            ratePerGram: parseMoney(_rate.text),
            purity: parseMoney(_purity.text),
            orderUuid: _orderUuid ?? '',
            notes: _notes.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FormatException catch (e) {
      if (mounted) setState(() => _saving = false);
      _toast(e.message);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _toast('Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Worker movement')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          SectionCard(
            title: 'Worker',
            children: [
              TextField(
                controller: _worker,
                decoration: fieldDecoration('Worker name'),
                textCapitalization: TextCapitalization.words,
                enabled: widget.workerName.isEmpty,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event, size: 18),
                label: Text(fmtDate(_date.toIso8601String())),
              ),
            ],
          ),
          SectionCard(
            title: 'Direction',
            children: [
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Shop gave'),
                      selected: _shopGave,
                      onSelected: (_) => setState(() => _shopGave = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Worker gave'),
                      selected: !_shopGave,
                      onSelected: (_) => setState(() => _shopGave = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _shopGave
                    ? 'Cash paid and metal issued increase the worker reserve.'
                    : 'Cash received and metal returned reduce the worker reserve.',
                style: TextStyle(fontSize: 11, color: mutedOf(context)),
              ),
            ],
          ),
          SectionCard(
            title: 'Cash',
            children: [
              TextField(
                controller: _cash,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDecoration('Cash amount ₹ (optional)'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          SectionCard(
            title: 'Metal',
            children: [
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Gold'),
                    selected: _metal == JewelleryStore.gold,
                    onSelected: (_) => setState(() {
                      _metal = JewelleryStore.gold;
                      _purity.text = '100';
                    }),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Silver'),
                    selected: _metal == JewelleryStore.silver,
                    onSelected: (_) => setState(() {
                      _metal = JewelleryStore.silver;
                      _purity.text = '100';
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _gold,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDecoration('Metal weight (g, optional)'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _purity,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: fieldDecoration('Purity %'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _rate,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: fieldDecoration('Rate ₹/g (optional)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          SectionCard(
            title: 'Link to a worker order (optional)',
            children: [
              DropdownButtonFormField<String?>(
                initialValue: _orderUuid,
                decoration: fieldDecoration('Worker order'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('None')),
                  for (final order in _orders)
                    DropdownMenuItem<String?>(
                      value: order['client_uuid']?.toString(),
                      child: Text(
                        '${order['worker_name'] ?? ''} · '
                        '${fmtDate(order['order_date'])} · '
                        '${Num.round3(Num.toDouble(order['ordered_weight'])).toStringAsFixed(3)} g',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _orderUuid = v),
              ),
            ],
          ),
          SectionCard(
            title: 'Notes',
            children: [
              TextField(
                controller: _notes,
                decoration: fieldDecoration('Notes (optional)'),
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('SAVE MOVEMENT'),
          ),
        ],
      ),
    );
  }
}
