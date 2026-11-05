import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import '../../../util/jewellery_math.dart';
import '../../../util/phone.dart';

/// New jewellery sale / purchase / customer order.
///
/// A sale and an order use **retail** pricing: KDM bills net + wastage,
/// non-KDM bills net weight, and both add a flat rupee making charge. Purity is
/// recorded for cost/profit only. A purchase uses **raw** pricing: weight ×
/// purity% × rate, with the supplier's making mode.
class JewelleryInvoiceScreen extends StatefulWidget {
  const JewelleryInvoiceScreen({super.key, required this.docType});

  final String docType;

  bool get isPurchase => docType == JewelleryStore.purchaseDoc;
  bool get isOrder => docType == JewelleryStore.orderDoc;

  @override
  State<JewelleryInvoiceScreen> createState() => _JewelleryInvoiceScreenState();
}

class _ItemLine {
  _ItemLine({
    String purity = '92',
    String rate = '',
    this.basis = BillingBasis.kdm,
  }) {
    this.purity.text = purity;
    this.rate.text = rate;
  }

  final description = TextEditingController();
  final weight = TextEditingController();
  final purity = TextEditingController();
  final rate = TextEditingController();
  final making = TextEditingController();
  final wastage = TextEditingController();
  final cost = TextEditingController();
  final additional = TextEditingController();
  MakingMode makingMode = MakingMode.none;
  BillingBasis basis;

  void dispose() {
    for (final c in [
      description,
      weight,
      purity,
      rate,
      making,
      wastage,
      cost,
      additional,
    ]) {
      c.dispose();
    }
  }
}

class _JewelleryInvoiceScreenState extends State<JewelleryInvoiceScreen> {
  final _party = TextEditingController();
  final _mobile = TextEditingController();
  final _address = TextEditingController();
  final _discount = TextEditingController();
  final _paid = TextEditingController();
  final _shared = TextEditingController();
  final _notes = TextEditingController();
  final _oldWeight = TextEditingController();
  final _oldPurity = TextEditingController(text: '92');
  final _oldRate = TextEditingController();

  final List<_ItemLine> _lines = [];
  String _metal = JewelleryStore.gold;
  String _mode = 'CASH';
  DateTime _date = DateTime.now();
  DateTime? _promisedDate;
  bool _oldMetal = false;
  bool _saving = false;
  Map<String, double> _lastRates = const {};

  bool get _isPurchase => widget.isPurchase;
  bool get _isOrder => widget.isOrder;
  bool get _isRetail => !_isPurchase;

  @override
  void initState() {
    super.initState();
    _lines.add(_newLine());
    _loadRates();
  }

  @override
  void dispose() {
    for (final c in [
      _party,
      _mobile,
      _address,
      _discount,
      _paid,
      _shared,
      _notes,
      _oldWeight,
      _oldPurity,
      _oldRate,
    ]) {
      c.dispose();
    }
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  String _defaultPurity() => _metal == JewelleryStore.silver ? '100' : '92';

  _ItemLine _newLine() {
    final rate = _lastRates[_metal];
    final basis = _isRetail ? BillingBasis.kdm : BillingBasis.raw;
    return _ItemLine(
      purity: _defaultPurity(),
      rate: rate == null ? '' : rate.toStringAsFixed(2),
      basis: basis,
    );
  }

  Future<void> _loadRates() async {
    final store = context.read<AppState>().jewelleryStore;
    final gold = await store.latestRate(JewelleryStore.gold);
    final silver = await store.latestRate(JewelleryStore.silver);
    if (!mounted) return;
    setState(() {
      _lastRates = {
        if (gold != null) JewelleryStore.gold: gold,
        if (silver != null) JewelleryStore.silver: silver,
      };
      for (final line in _lines) {
        final rate = _lastRates[_metal];
        if (line.rate.text.trim().isEmpty && rate != null) {
          line.rate.text = rate.toStringAsFixed(2);
        }
      }
      final rate = _lastRates[_metal];
      if (rate != null) {
        _oldRate.text = rate.toStringAsFixed(2);
      }
    });
  }

  void _setMetal(String metal) {
    if (metal == _metal) return;
    setState(() {
      _metal = metal;
      final rate = _lastRates[metal];
      for (final line in _lines) {
        line.purity.text = _defaultPurity();
        line.rate.text = rate == null ? '' : rate.toStringAsFixed(2);
      }
      _oldPurity.text = metal == JewelleryStore.gold ? '92' : '100';
      _oldRate.text = rate == null ? '' : rate.toStringAsFixed(2);
    });
  }

  void _setBasis(int index, BillingBasis basis) {
    final line = _lines[index];
    if (line.basis == basis) return;
    setState(() => line.basis = basis);
  }

  double _d(TextEditingController c) => parseMoney(c.text);

  JewelleryLine _lineOf(_ItemLine line) => _isPurchase
      ? JewelleryMath.line(
          weight: _d(line.weight),
          purityPct: _d(line.purity),
          pureRate: _d(line.rate),
          makingMode: line.makingMode,
          makingValue: _d(line.making),
          additionalCost: _d(line.additional),
        )
      : JewelleryMath.line(
          weight: _d(line.weight),
          purityPct: _d(line.purity),
          pureRate: _d(line.rate),
          billingBasis: line.basis,
          wastagePct: _d(line.wastage),
          makingCharge: _d(line.making),
          additionalCost: _d(line.additional),
        );

  double get _lineTotal =>
      _lines.fold<double>(0, (sum, line) => sum + _lineOf(line).total);

  double get _totalCost =>
      _lines.fold<double>(0, (sum, line) => sum + _d(line.cost));

  ({double equivalent, double value}) get _old {
    if (!_oldMetal) return (equivalent: 0, value: 0);
    final v = JewelleryMath.oldMetal(
      netWeight: _d(_oldWeight),
      purityPct: _d(_oldPurity),
      ratePerGram: _d(_oldRate),
    );
    return (equivalent: v.equivalentWeight, value: v.suggestedValue);
  }

  double get _rawPayable =>
      (_lineTotal + _d(_shared) - _d(_discount) - _old.value)
          .clamp(0, double.infinity)
          .toDouble();
  int get _roundedPayable => JewelleryMath.roundRupee(_rawPayable);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickPromisedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _promisedDate ?? _date.add(const Duration(days: 7)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _promisedDate = picked);
  }

  Future<void> _save({bool draft = false}) async {
    final state = context.read<AppState>();
    if (_party.text.trim().isEmpty) {
      _toast('Enter the ${_isPurchase ? 'supplier' : 'customer'} name.');
      return;
    }
    for (final line in _lines) {
      if (_d(line.weight) <= 0) {
        _toast('Enter the weight on every item.');
        return;
      }
      if (_d(line.purity) <= 0 || _d(line.purity) > 100) {
        _toast('Purity must be between 0 and 100.');
        return;
      }
      if (_d(line.rate) <= 0) {
        _toast('Enter the pure-metal rate on every item.');
        return;
      }
      if (_isRetail && _d(line.wastage) < 0) {
        _toast('Wastage cannot be negative.');
        return;
      }
      if (_isRetail && _d(line.making) < 0) {
        _toast('Making charges cannot be negative.');
        return;
      }
    }
    if (_oldMetal && _d(_oldWeight) > 0 && _d(_oldPurity) <= 0) {
      _toast('Enter the old-metal purity.');
      return;
    }
    // An order carries the customer's mobile for delivery; a typo there is
    // only discovered when the shop tries to call, so check it here.
    if (_isOrder &&
        _mobile.text.trim().isNotEmpty &&
        !Phone.isValid(_mobile.text)) {
      _toast(Phone.invalidMessage);
      return;
    }
    // A draft deliberately records no money. Say so before the typed amount is
    // thrown away, instead of saving a draft the shop thinks was part-paid.
    if (draft && _d(_paid) > 0) {
      final ok = await confirmDialog(
          context,
          'A draft records no payment, so "Paid now" will not be saved.\n'
          'Confirm it later and add the payment then.',
          title: 'Save as draft');
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await state.saveJewelleryInvoice(
        docType: widget.docType,
        partyName: _party.text.trim(),
        date: _date,
        metal: _metal,
        items: [
          for (var i = 0; i < _lines.length; i++)
            JewelleryItemInput(
              description: _lines[i].description.text.trim().isEmpty
                  ? '${_isPurchase ? 'Purchase' : (_isOrder ? 'Order' : 'Sale')} · $_metal'
                  : _lines[i].description.text.trim(),
              metal: _metal,
              grossWeight: _d(_lines[i].weight),
              netWeight: _d(_lines[i].weight),
              purity: _d(_lines[i].purity),
              rate: _d(_lines[i].rate),
              makingMode:
                  _isPurchase ? _lines[i].makingMode : MakingMode.amount,
              makingValue: _d(_lines[i].making),
              additionalCost: _d(_lines[i].additional),
              estimatedCost: _isRetail ? _d(_lines[i].cost) : 0,
              actualCost: _isRetail ? _d(_lines[i].cost) : 0,
              billingBasis: _isPurchase ? BillingBasis.raw : _lines[i].basis,
              wastagePct: _isRetail ? _d(_lines[i].wastage) : 0,
              makingCharge: _isRetail ? _d(_lines[i].making) : 0,
            ),
        ],
        discount: _d(_discount),
        amountPaid: draft ? 0 : _d(_paid),
        sharedExpense: _d(_shared),
        status: draft ? JewelleryStore.draftStatus : null,
        paymentMode: _mode,
        oldMetal: _oldMetal
            ? OldMetalInput(
                metal: _metal,
                grossWeight: _d(_oldWeight),
                purity: _d(_oldPurity),
                rate: _d(_oldRate),
              )
            : null,
        notes: _notes.text.trim(),
        costTotal: _isRetail ? _totalCost : 0,
        promisedDate: _promisedDate,
        mobile: _mobile.text.trim(),
        address: _address.text.trim(),
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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    final roundOff = _roundedPayable - _rawPayable;
    final paid = _d(_paid);
    final balance = (_roundedPayable - paid).clamp(0, double.infinity);
    // Old metal is an asset exchange, not a discount, so it is left out of the
    // profit preview. The invoice discount does reduce the shop's revenue.
    final estimatedProfit =
        _lineTotal - _d(_discount) - _totalCost - _d(_shared);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isPurchase
            ? 'New Purchase'
            : (_isOrder ? 'New Order' : 'New Sale')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          SectionCard(
            title: _isPurchase ? 'Supplier' : 'Customer',
            children: [
              TextField(
                controller: _party,
                decoration: fieldDecoration('Name'),
                textCapitalization: TextCapitalization.words,
              ),
              if (_isOrder) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  decoration:
                      fieldDecoration('Mobile', hint: '9876543210 or +91 …'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _address,
                  decoration: fieldDecoration('Address'),
                  maxLines: 2,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(fmtDate(_date.toIso8601String())),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Rate saved with this document',
                      style: TextStyle(fontSize: 11, color: mutedOf(context)),
                    ),
                  ),
                ],
              ),
              if (_isOrder) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _pickPromisedDate,
                  icon: const Icon(Icons.event_available, size: 18),
                  label: Text(_promisedDate == null
                      ? 'Promised delivery date'
                      : 'Promised ${fmtDate(_promisedDate!.toIso8601String())}'),
                ),
              ],
            ],
          ),
          SectionCard(
            title: 'Metal',
            children: [
              Row(
                children: [
                  _metalChip(JewelleryStore.gold, 'Gold'),
                  const SizedBox(width: 8),
                  _metalChip(JewelleryStore.silver, 'Silver'),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _isPurchase
                    ? 'Raw purchase: weight × purity% × rate. The supplier making charge is added separately.'
                    : _isOrder
                        ? 'Retail order: KDM bills net + wastage, non-KDM bills net. Stock moves only on delivery.'
                        : 'Retail sale: KDM bills net + wastage, non-KDM bills net. Purity is kept for cost/profit.',
                style: TextStyle(fontSize: 11, color: mutedOf(context)),
              ),
            ],
          ),
          for (var i = 0; i < _lines.length; i++) ...[
            _lineCard(i),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: () => setState(() => _lines.add(_newLine())),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add item line'),
          ),
          const SizedBox(height: 8),
          SectionCard(
            title: 'Invoice discount',
            children: [
              TextField(
                controller: _discount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDecoration('Discount ₹'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          if (!_isPurchase)
            SectionCard(
              title: 'Old metal exchange',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Old metal handed in'),
                  subtitle: Text(
                    'Credited once on this document and received into old-metal stock.',
                    style: TextStyle(fontSize: 11, color: mutedOf(context)),
                  ),
                  value: _oldMetal,
                  onChanged: (v) => setState(() => _oldMetal = v),
                ),
                if (_oldMetal) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _oldWeight,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: fieldDecoration('Weight (g)'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _oldPurity,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: fieldDecoration('Purity %'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _oldRate,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: fieldDecoration('Old-metal rate ₹/g'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${old.equivalent.toStringAsFixed(3)} g equivalent · '
                    'credit ${inr(old.value)}',
                    style: TextStyle(fontSize: 12, color: mutedOf(context)),
                  ),
                ],
              ],
            ),
          SectionCard(
            title: 'Payment',
            children: [
              Row(
                children: [
                  for (final m in const ['CASH', 'UPI', 'BANK'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(m),
                        selected: _mode == m,
                        onSelected: (_) => setState(() => _mode = m),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _paid,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDecoration(_isPurchase
                    ? 'Paid now ₹'
                    : (_isOrder
                        ? 'Advance received now ₹'
                        : 'Amount received now ₹')),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _shared,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    fieldDecoration('Shared expense ₹ (split by weight)'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                decoration: fieldDecoration('Notes (optional)'),
              ),
            ],
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (var i = 0; i < _lines.length; i++) ...[
                    _row(
                        _lines[i].description.text.trim().isEmpty
                            ? 'Item ${i + 1}'
                            : _lines[i].description.text.trim(),
                        inr(_lineOf(_lines[i]).total)),
                    const SizedBox(height: 4),
                  ],
                  if (_d(_discount) > 0)
                    _row('Invoice discount', '-${inr(_d(_discount))}'),
                  if (_d(_shared) > 0) _row('Shared expense', inr(_d(_shared))),
                  if (old.value > 0)
                    _row('Old-metal credit', '-${inr(old.value)}'),
                  _row(
                      'Round-off',
                      '${roundOff >= 0 ? '+' : ''}'
                          '${roundOff.toStringAsFixed(2)}'),
                  const Divider(),
                  _row('Payable', inr(_roundedPayable), bold: true),
                  _row(_isPurchase ? 'Paid now' : 'Received now', inr(paid)),
                  _row('Balance', inr(balance), bold: true),
                  if (_isRetail && _totalCost > 0) ...[
                    const Divider(),
                    _row('Cost to shop', inr(_totalCost)),
                    _row('Estimated profit', inr(estimatedProfit),
                        bold: true,
                        color: estimatedProfit >= 0 ? kGreen : kRed),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(_isPurchase
                ? 'SAVE PURCHASE'
                : (_isOrder ? 'SAVE ORDER' : 'SAVE SALE')),
          ),
          if (_isPurchase) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _save(draft: true),
              icon: const Icon(Icons.edit_note),
              label: const Text('SAVE AS DRAFT'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lineCard(int index) {
    final line = _lines[index];
    final computed = _lineOf(line);
    final retail = _isRetail;
    final cost = _d(line.cost);
    return SectionCard(
      title: 'Item ${index + 1}',
      trailing: _lines.length == 1
          ? null
          : IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () {
                setState(() {
                  final removed = _lines.removeAt(index);
                  removed.dispose();
                });
              },
            ),
      children: [
        TextField(
          controller: line.description,
          decoration: fieldDecoration('Item description (optional)'),
          onChanged: (_) => setState(() {}),
        ),
        if (retail) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('KDM'),
                  selected: line.basis == BillingBasis.kdm,
                  onSelected: (_) => _setBasis(index, BillingBasis.kdm),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Non-KDM'),
                  selected: line.basis == BillingBasis.nonKdm,
                  onSelected: (_) => _setBasis(index, BillingBasis.nonKdm),
                ),
              ),
            ],
          ),
          Text(
            line.basis == BillingBasis.kdm
                ? 'Bills net weight + wastage. Purity is for cost/profit only.'
                : 'Bills net weight only. Purity is for cost/profit only.',
            style: TextStyle(fontSize: 11, color: mutedOf(context)),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: line.weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDecoration('Net weight (g)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: line.purity,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDecoration(
                    retail ? 'Actual purity % (cost)' : 'Purity %'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: line.rate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldDecoration(
              '${_metal == JewelleryStore.gold ? 'Gold' : 'Silver'} rate ₹/g'),
          onChanged: (_) => setState(() {}),
        ),
        if (retail) ...[
          if (line.basis == BillingBasis.kdm) ...[
            const SizedBox(height: 10),
            TextField(
              controller: line.wastage,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: fieldDecoration('Wastage % (e.g. 10)'),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: line.making,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fieldDecoration('Making charges ₹ (flat)'),
            onChanged: (_) => setState(() {}),
          ),
        ] else ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<MakingMode>(
            initialValue: line.makingMode,
            decoration: fieldDecoration('Supplier making'),
            items: const [
              DropdownMenuItem(value: MakingMode.none, child: Text('None')),
              DropdownMenuItem(
                  value: MakingMode.percentage, child: Text('Making %')),
              DropdownMenuItem(
                  value: MakingMode.weight, child: Text('Making weight (g)')),
              DropdownMenuItem(
                  value: MakingMode.amount, child: Text('Making amount ₹')),
            ],
            onChanged: (v) =>
                setState(() => line.makingMode = v ?? MakingMode.none),
          ),
          if (line.makingMode != MakingMode.none) ...[
            const SizedBox(height: 10),
            TextField(
              controller: line.making,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: fieldDecoration(_makingLabel(line.makingMode)),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
        const SizedBox(height: 10),
        TextField(
          controller: line.additional,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldDecoration('Additional ₹'),
          onChanged: (_) => setState(() {}),
        ),
        if (retail) ...[
          const SizedBox(height: 10),
          TextField(
            controller: line.cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                fieldDecoration('Cost to shop ₹ (optional, for profit)'),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const Divider(height: 20),
        if (retail) ...[
          _row('Net weight', '${computed.weight.toStringAsFixed(3)} g'),
          _row(
              line.basis == BillingBasis.kdm ? 'Wastage' : 'Wastage',
              line.basis == BillingBasis.kdm
                  ? '${computed.wastageWeight.toStringAsFixed(3)} g '
                      '(${computed.wastagePct.toStringAsFixed(2)}%)'
                  : 'None'),
          _row(
            'Billing weight',
            '${computed.billedWeight.toStringAsFixed(3)} g × '
                '₹${moneyWhole(computed.pureRate)}/g = ${inr(computed.metalValue)}',
          ),
          _row('Making charges', inr(computed.makingAmount)),
          if (computed.additionalCost > 0)
            _row('Additional', inr(computed.additionalCost)),
          _row('Line total', inr(computed.total), bold: true),
          _row(
            'Fine metal (cost)',
            '${computed.fineWeight.toStringAsFixed(3)} g '
                '@ ${computed.purityPct.toStringAsFixed(2)}%',
          ),
          if (cost > 0)
            _row('Cost · est. profit',
                '${inr(cost)} · ${inr(computed.total - cost)}',
                color: computed.total - cost >= 0 ? kGreen : kRed),
        ] else ...[
          _row('Net metal', '${computed.fineWeight.toStringAsFixed(3)} g'),
          _row('Wastage / making',
              '${computed.wastageWeight.toStringAsFixed(3)} g'),
          _row(
            'Total metal',
            '${computed.totalEquivalentWeight.toStringAsFixed(3)} g × '
                '₹${moneyWhole(computed.pureRate)}/g',
          ),
          _row('Metal + making',
              inr(computed.metalValue + computed.makingAmount),
              bold: true),
          if (computed.additionalCost > 0)
            _row('Additional', inr(computed.additionalCost)),
          _row('Line total', inr(computed.total), bold: true),
        ],
      ],
    );
  }

  String _makingLabel(MakingMode mode) => switch (mode) {
        MakingMode.percentage => 'Making %',
        MakingMode.weight => 'Making weight (g)',
        MakingMode.amount => 'Making amount ₹',
        MakingMode.none => 'Making',
      };

  Widget _metalChip(String metal, String label) {
    final selected = _metal == metal;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setMetal(metal),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
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
                  color: color ?? inkOf(context))),
        ],
      ),
    );
  }
}
