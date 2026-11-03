import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import '../../../util/jewellery_math.dart';

/// Work given to a worker. A worker order may link to a customer order; it does
/// not move stock until metal is issued through a worker movement.
class JewelleryWorkerOrderScreen extends StatefulWidget {
  const JewelleryWorkerOrderScreen({super.key, this.workerName = ''});

  final String workerName;

  @override
  State<JewelleryWorkerOrderScreen> createState() =>
      _JewelleryWorkerOrderScreenState();
}

class _JewelleryWorkerOrderScreenState
    extends State<JewelleryWorkerOrderScreen> {
  late final TextEditingController _worker =
      TextEditingController(text: widget.workerName);
  final _description = TextEditingController();
  final _weight = TextEditingController();
  final _making = TextEditingController();
  final _additional = TextEditingController();
  final _notes = TextEditingController();

  List<Map<String, Object?>> _customerOrders = const [];
  String? _customerOrderUuid;
  String _metal = JewelleryStore.gold;
  MakingMode _makingMode = MakingMode.none;
  DateTime _date = DateTime.now();
  DateTime? _expected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    for (final c in [
      _worker,
      _description,
      _weight,
      _making,
      _additional,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOrders() async {
    final store = context.read<AppState>().jewelleryStore;
    final orders = await store.orders();
    if (!mounted) return;
    setState(() => _customerOrders = orders);
  }

  Future<void> _pickDate({required bool expected}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          expected ? (_expected ?? _date.add(const Duration(days: 14))) : _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (expected) {
        _expected = picked;
      } else {
        _date = picked;
      }
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_worker.text.trim().isEmpty) {
      _toast('Enter the worker name.');
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppState>().jewelleryStore.saveWorkerOrder(
            workerName: _worker.text.trim(),
            date: _date,
            expectedDate: _expected,
            orderUuid: _customerOrderUuid ?? '',
            metal: _metal,
            description: _description.text.trim(),
            orderedWeight: parseMoney(_weight.text),
            makingMode: _makingMode,
            makingValue: parseMoney(_making.text),
            additionalCost: parseMoney(_additional.text),
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
      appBar: AppBar(title: const Text('Worker order')),
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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(expected: false),
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(fmtDate(_date.toIso8601String())),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(expected: true),
                      icon: const Icon(Icons.event_available, size: 18),
                      label: Text(_expected == null
                          ? 'Expected date'
                          : fmtDate(_expected!.toIso8601String())),
                    ),
                  ),
                ],
              ),
            ],
          ),
          SectionCard(
            title: 'Customer order (optional)',
            children: [
              DropdownButtonFormField<String?>(
                initialValue: _customerOrderUuid,
                decoration: fieldDecoration('Linked customer order'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('None')),
                  for (final order in _customerOrders)
                    DropdownMenuItem<String?>(
                      value: order['client_uuid']?.toString(),
                      child: Text(
                        '${order['party_name'] ?? ''} · ${order['doc_no'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _customerOrderUuid = v),
              ),
            ],
          ),
          SectionCard(
            title: 'Work',
            children: [
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Gold'),
                    selected: _metal == JewelleryStore.gold,
                    onSelected: (_) =>
                        setState(() => _metal = JewelleryStore.gold),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Silver'),
                    selected: _metal == JewelleryStore.silver,
                    onSelected: (_) =>
                        setState(() => _metal = JewelleryStore.silver),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                decoration: fieldDecoration('Item description'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDecoration('Ordered weight (g)'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<MakingMode>(
                initialValue: _makingMode,
                decoration: fieldDecoration('Making / wastage'),
                items: const [
                  DropdownMenuItem(value: MakingMode.none, child: Text('None')),
                  DropdownMenuItem(
                      value: MakingMode.percentage, child: Text('Wastage %')),
                  DropdownMenuItem(
                      value: MakingMode.weight,
                      child: Text('Wastage weight (g)')),
                  DropdownMenuItem(
                      value: MakingMode.amount, child: Text('Making amount ₹')),
                ],
                onChanged: (v) =>
                    setState(() => _makingMode = v ?? MakingMode.none),
              ),
              if (_makingMode != MakingMode.none) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _making,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: fieldDecoration(_makingMode == MakingMode.amount
                      ? 'Making amount ₹'
                      : (_makingMode == MakingMode.weight
                          ? 'Wastage weight (g)'
                          : 'Wastage %')),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _additional,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDecoration('Additional cost ₹'),
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
            label: const Text('SAVE WORKER ORDER'),
          ),
        ],
      ),
    );
  }
}
