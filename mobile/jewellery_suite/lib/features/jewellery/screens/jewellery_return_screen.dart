import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';

/// One line being returned against a sale.
class _ReturnLine {
  _ReturnLine({
    required this.description,
    required this.metal,
    required this.rate,
    required this.soldWeight,
    required double purity,
    required double weight,
  })  : purity = TextEditingController(text: purity.toStringAsFixed(2)),
        weight = TextEditingController(text: weight.toStringAsFixed(3));

  final String description;
  final String metal;
  final double rate;
  final double soldWeight;
  final TextEditingController purity;
  final TextEditingController weight;
  bool selected = true;
  bool restock = true;

  double get netWeight => parseMoney(weight.text);
  double get purityPct => parseMoney(purity.text);
  double get value => netWeight * purityPct / 100.0 * rate;

  void dispose() {
    purity.dispose();
    weight.dispose();
  }
}

/// Linked credit note against an existing sale.
///
/// The original invoice is never rewritten. Saving the return adds the accepted
/// metal back to stock (when restocked), posts any refund as cash OUT and
/// reduces the customer's outstanding through the ledger.
class JewelleryReturnScreen extends StatefulWidget {
  const JewelleryReturnScreen({super.key, required this.sourceInvoiceUuid});

  final String sourceInvoiceUuid;

  @override
  State<JewelleryReturnScreen> createState() => _JewelleryReturnScreenState();
}

class _JewelleryReturnScreenState extends State<JewelleryReturnScreen> {
  Map<String, Object?>? _invoice;
  final List<_ReturnLine> _lines = [];
  final _refund = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  double _alreadyReturned = 0;
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _refund.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = context.read<AppState>().jewelleryStore;
    final invoice = await store.invoice(widget.sourceInvoiceUuid);
    final items = await store.itemsFor(widget.sourceInvoiceUuid);
    final returned =
        await store.returnedWeightForInvoice(widget.sourceInvoiceUuid);
    if (!mounted) return;
    setState(() {
      _invoice = invoice;
      _alreadyReturned = returned;
      _lines
        ..clear()
        ..addAll([
          for (final item in items)
            _ReturnLine(
              description: item['description']?.toString() ?? '',
              metal: item['metal']?.toString() ?? JewelleryStore.gold,
              rate: Num.toDouble(item['rate_per_gram']),
              soldWeight: Num.toDouble(item['net_weight']),
              purity: Num.toDouble(item['purity']),
              weight: Num.toDouble(item['net_weight']),
            ),
        ]);
      _loading = false;
    });
  }

  double get _returnTotal => _lines.fold<double>(
      0, (sum, line) => sum + (line.selected ? line.value : 0));

  double get _returnWeight => _lines.fold<double>(
      0, (sum, line) => sum + (line.selected ? line.netWeight : 0));

  double get _soldWeight =>
      _lines.fold<double>(0, (sum, line) => sum + line.soldWeight);

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
    final selected = _lines.where((l) => l.selected).toList();
    if (selected.isEmpty) {
      _toast('Select at least one item to return.');
      return;
    }
    for (final line in selected) {
      if (line.netWeight <= 0) {
        _toast('Return weight must be above zero.');
        return;
      }
      if (line.purityPct <= 0 || line.purityPct > 100) {
        _toast('Purity must be between 0 and 100.');
        return;
      }
    }
    if (_alreadyReturned + _returnWeight > _soldWeight + 0.0005) {
      _toast('Return is more than the weight still on this sale.');
      return;
    }
    final refund = parseMoney(_refund.text);
    if (refund > _returnTotal + 0.005) {
      _toast('Refund is more than the return value.');
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppState>().saveJewelleryReturn(
            sourceInvoiceUuid: widget.sourceInvoiceUuid,
            date: _date,
            items: [
              for (final line in selected)
                JewelleryReturnItemInput(
                  description: line.description,
                  metal: line.metal,
                  grossWeight: line.netWeight,
                  netWeight: line.netWeight,
                  purity: line.purityPct,
                  rate: line.rate,
                  restock: line.restock,
                ),
            ],
            refundAmount: refund,
            notes: _notes.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FormatException catch (e) {
      if (mounted) setState(() => _saving = false);
      _toast(e.message);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _toast('Could not save the return: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _invoice;
    return Scaffold(
      appBar: AppBar(title: const Text('Return against sale')),
      body: _loading || invoice == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                SectionCard(
                  title: 'Original sale',
                  children: [
                    Text(
                      '${invoice['party_name'] ?? ''} · ${invoice['doc_no'] ?? ''}',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: inkOf(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${fmtDate(invoice['invoice_date'])} · '
                      '${invoice['metal'] ?? ''} · total ${inr(Num.toDouble(invoice['total']))}',
                      style: TextStyle(fontSize: 12, color: mutedOf(context)),
                    ),
                    if (_alreadyReturned > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Already returned ${Num.round3(_alreadyReturned).toStringAsFixed(3)} g',
                        style: TextStyle(fontSize: 12, color: kRed),
                      ),
                    ],
                  ],
                ),
                SectionCard(
                  title: 'Return date',
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(fmtDate(_date.toIso8601String())),
                    ),
                  ],
                ),
                for (var i = 0; i < _lines.length; i++) _lineCard(i),
                SectionCard(
                  title: 'Refund',
                  children: [
                    TextField(
                      controller: _refund,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: fieldDecoration('Cash refund ₹ (optional)'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The rest of the value becomes a credit on the customer ledger.',
                      style: TextStyle(fontSize: 11, color: mutedOf(context)),
                    ),
                  ],
                ),
                SectionCard(
                  title: 'Notes',
                  children: [
                    TextField(
                      controller: _notes,
                      decoration: fieldDecoration('Reason / notes (optional)'),
                    ),
                  ],
                ),
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _row('Return weight',
                            '${Num.round3(_returnWeight).toStringAsFixed(3)} g'),
                        _row('Return value', inr(_returnTotal), bold: true),
                        _row('Refund now', inr(parseMoney(_refund.text))),
                        _row(
                            'Credit to ledger',
                            inr((_returnTotal - parseMoney(_refund.text))
                                .clamp(0, double.infinity)),
                            bold: true),
                      ],
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: const Text('SAVE RETURN'),
                ),
              ],
            ),
    );
  }

  Widget _lineCard(int index) {
    final line = _lines[index];
    return SectionCard(
      title: line.description.isEmpty ? 'Item ${index + 1}' : line.description,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Return this item'),
          value: line.selected,
          onChanged: (v) => setState(() => line.selected = v),
        ),
        if (line.selected) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: line.weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: fieldDecoration('Return weight (g)'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: line.purity,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: fieldDecoration('Purity %'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sold ${Num.round3(line.soldWeight).toStringAsFixed(3)} g'
            ' · rate ₹${moneyWhole(line.rate)}/g'
            ' · value ${inr(line.value)}',
            style: TextStyle(fontSize: 11, color: mutedOf(context)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Add back to stock'),
            subtitle: Text(
              'Turn off for damaged or customer-retained metal.',
              style: TextStyle(fontSize: 11, color: mutedOf(context)),
            ),
            value: line.restock,
            onChanged: (v) => setState(() => line.restock = v),
          ),
        ],
      ],
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
