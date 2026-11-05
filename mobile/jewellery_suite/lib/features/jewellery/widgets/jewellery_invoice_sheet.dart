import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import '../../../util/jewellery_math.dart';
import '../screens/jewellery_return_screen.dart';

/// Invoice detail: lines, payments, old metal, add-payment and delete.
///
/// Used by the jewellery dashboard, the credit book and the old-metal register
/// so every entry opens the same document view. A purchase payment is posted to
/// the cashbook as an OUT (we pay the supplier); a sale receipt is an IN.
class JewelleryInvoiceSheet extends StatefulWidget {
  const JewelleryInvoiceSheet({
    super.key,
    required this.invoiceUuid,
    this.onChanged,
  });

  final String invoiceUuid;
  final VoidCallback? onChanged;

  @override
  State<JewelleryInvoiceSheet> createState() => _JewelleryInvoiceSheetState();
}

class _JewelleryInvoiceSheetState extends State<JewelleryInvoiceSheet> {
  Map<String, Object?>? _invoice;
  List<Map<String, Object?>> _items = const [];
  List<Map<String, Object?>> _payments = const [];
  Map<String, Object?>? _oldMetal;
  double _returnedCredit = 0;
  bool _loading = true;

  bool get _isPurchase =>
      (_invoice?['doc_type']?.toString() ?? '') == JewelleryStore.purchaseDoc;
  bool get _isOrder =>
      (_invoice?['doc_type']?.toString() ?? '') == JewelleryStore.orderDoc;

  String get _docLabel =>
      _isPurchase ? 'Purchase' : (_isOrder ? 'Order' : 'Sale');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<AppState>().jewelleryStore;
    final invoice = await store.invoice(widget.invoiceUuid);
    final items = await store.itemsFor(widget.invoiceUuid);
    final payments = await store.paymentsFor(widget.invoiceUuid);
    final old = await store.oldMetalFor(widget.invoiceUuid);
    final returned = await store.returnsForInvoice(widget.invoiceUuid);
    if (!mounted) return;
    setState(() {
      _invoice = invoice;
      _items = items;
      _payments = payments;
      _oldMetal = old;
      _returnedCredit = returned;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addPayment() async {
    final invoice = _invoice;
    if (invoice == null) return;
    final state = context.read<AppState>();
    final outstanding = (invoice['outstanding'] as num?)?.toDouble() ?? 0;
    final ctl = TextEditingController(
        text: outstanding > 0 ? outstanding.toStringAsFixed(0) : '');
    try {
      final amount = await showDialog<double>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_isPurchase ? 'Pay supplier' : 'Receive payment'),
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
      await state.addJewelleryPayment(
        invoiceUuid: widget.invoiceUuid,
        partyName: invoice['party_name']?.toString() ?? '',
        amount: amount,
        date: DateTime.now(),
        isPurchase: _isPurchase,
      );
      await _load();
      widget.onChanged?.call();
    } on FormatException catch (e) {
      _toast(e.message);
    } finally {
      ctl.dispose();
    }
  }

  /// A manual late fee (spec §7). It is filed as its own charge: the invoice's
  /// item total and recorded cost are untouched, the customer's balance rises
  /// and the ledger shows the fee as a separate debit. No cash moves.
  Future<void> _addLateFee() async {
    final invoice = _invoice;
    if (invoice == null) return;
    final state = context.read<AppState>();
    final amountCtl = TextEditingController();
    final noteCtl = TextEditingController();
    try {
      final amount = await showDialog<double>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Late fee'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: fieldDecoration('Late fee ₹'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtl,
                decoration: fieldDecoration('Note (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, parseMoney(amountCtl.text)),
                child: const Text('Add')),
          ],
        ),
      );
      if (amount == null || amount <= 0) return;
      await state.addJewelleryLateFee(
        invoiceUuid: widget.invoiceUuid,
        amount: amount,
        date: DateTime.now(),
        note: noteCtl.text.trim(),
      );
      await _load();
      widget.onChanged?.call();
    } on FormatException catch (e) {
      _toast(e.message);
    } finally {
      amountCtl.dispose();
      noteCtl.dispose();
    }
  }

  /// Turns a draft into a real document. The stock movement happens in the
  /// store, once, guarded by the status so a double tap cannot receive twice.
  Future<void> _confirmDraft() async {
    final ok = await confirmDialog(
        context, 'Confirm this purchase? Its stock is received now.',
        title: 'Confirm purchase');
    if (!ok || !mounted) return;
    final state = context.read<AppState>();
    try {
      await state.confirmJewelleryInvoice(widget.invoiceUuid);
      await _load();
      widget.onChanged?.call();
      _toast('Confirmed. Stock received once.');
    } on FormatException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _openReturn() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            JewelleryReturnScreen(sourceInvoiceUuid: widget.invoiceUuid),
      ),
    );
    if (saved == true) {
      await _load();
      widget.onChanged?.call();
    }
  }

  Future<void> _delete() async {
    final uuid = widget.invoiceUuid;
    final ok = await confirmDialog(
        context, 'Delete this document and its stock movement?',
        title: 'Delete document');
    if (!ok || !mounted) return;
    final state = context.read<AppState>();
    await state.deleteJewelleryInvoice(uuid);
    widget.onChanged?.call();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _invoice;
    final outstanding = (invoice?['outstanding'] as num?)?.toDouble() ?? 0;
    final status = invoice?['status']?.toString() ?? 'Active';
    final isDraft = status == JewelleryStore.draftStatus;
    final lateFees = (invoice?['late_fee_total'] as num?)?.toDouble() ?? 0;
    final deliveredNet = Num.toDouble(invoice?['delivered_net_weight'] ?? 0);
    final orderedNet = _items.fold<double>(
        0, (sum, item) => sum + Num.toDouble(item['net_weight']));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: _loading || invoice == null
            ? const SizedBox(
                height: 200, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${invoice['party_name'] ?? ''} · ${invoice['doc_no'] ?? ''}',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: inkOf(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${fmtDate(invoice['invoice_date'])} · $_docLabel'
                      ' · ${invoice['metal'] ?? ''}',
                      style: TextStyle(fontSize: 12, color: mutedOf(context)),
                    ),
                    if (_isOrder) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${invoice['status'] ?? 'Pending'}'
                        '${invoice['promised_date'] == null ? '' : ' · promised ${fmtDate(invoice['promised_date'])}'}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: mutedOf(context)),
                      ),
                    ],
                    const Divider(height: 22),
                    for (final item in _items) _itemTile(context, item),
                    if (_oldMetal != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Old metal ${Num.round3(Num.toDouble(_oldMetal!['equivalent_weight'])).toStringAsFixed(3)} g'
                          ' · credit ${inr(Num.toDouble(_oldMetal!['accepted_value']))}',
                          style:
                              TextStyle(fontSize: 12, color: mutedOf(context)),
                        ),
                      ),
                    if (_isOrder && deliveredNet > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Delivered ${Num.round3(deliveredNet).toStringAsFixed(3)} g'
                          ' · ordered ${Num.round3(orderedNet).toStringAsFixed(3)} g'
                          ' · difference ${Num.round3(deliveredNet - orderedNet).toStringAsFixed(3)} g',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: inkOf(context)),
                        ),
                      ),
                    const Divider(height: 22),
                    _kv('Payable', inr(Num.toDouble(invoice['total'])),
                        bold: true),
                    _kv(_isPurchase ? 'Paid' : 'Received',
                        inr(Num.toDouble(invoice['amount_paid']))),
                    if (lateFees > 0) _kv('Late fee', inr(lateFees)),
                    _kv('Balance', inr(outstanding), bold: true),
                    if (isDraft)
                      Text(
                        'Draft · stock is not received until you confirm.',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: mutedOf(context)),
                      ),
                    if (_returnedCredit > 0)
                      _kv('Return credit', inr(_returnedCredit)),
                    if (_payments.isNotEmpty) ...[
                      const Divider(height: 22),
                      Text('Payments',
                          style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700,
                              color: mutedOf(context))),
                      for (final p in _payments)
                        _kv(
                          '${fmtDate(p['pay_date'])} · ${p['payment_mode'] ?? ''}',
                          inr(Num.toDouble(p['amount'])),
                        ),
                    ],
                    const SizedBox(height: 14),
                    if (!_isPurchase && !_isOrder)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openReturn,
                          icon: const Icon(Icons.assignment_return_outlined,
                              size: 18),
                          label: const Text('Return against this sale'),
                        ),
                      ),
                    if (!_isPurchase && !_isOrder) const SizedBox(height: 8),
                    if (isDraft)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _confirmDraft,
                          icon:
                              const Icon(Icons.inventory_2_outlined, size: 18),
                          label: const Text('Confirm purchase · receive stock'),
                        ),
                      ),
                    if (!_isPurchase && !_isOrder && !isDraft) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _addLateFee,
                          icon: const Icon(Icons.timer_outlined, size: 18),
                          label: const Text('Add late fee'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (!isDraft)
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _addPayment,
                              icon:
                                  const Icon(Icons.payments_outlined, size: 18),
                              label: Text(_isPurchase
                                  ? 'Pay supplier'
                                  : (_isOrder
                                      ? 'Receive payment'
                                      : 'Add payment')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _delete,
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete document',
                          ),
                        ],
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _itemTile(BuildContext context, Map<String, Object?> item) {
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
    final description = item['description']?.toString().trim() ?? '';
    final retail = line.billingBasis != BillingBasis.raw;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        '${Num.round3(line.weight).toStringAsFixed(3)} g'
        ' · ${Num.round3(line.purityPct).toStringAsFixed(2)}%'
        ' · ₹${moneyWhole(line.pureRate)}/g',
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: inkOf(context)),
      ),
      subtitle: Text(
        retail
            ? '${description.isEmpty ? '' : '$description · '}'
                '${line.billingBasis == BillingBasis.kdm ? 'KDM · wastage ${Num.round3(line.wastageWeight).toStringAsFixed(3)} g · ' : 'Non-KDM · '}'
                'billing ${Num.round3(line.billedWeight).toStringAsFixed(3)} g'
                ' × ₹${moneyWhole(line.pureRate)} = ${inr(line.metalValue)}'
                ' · making ${inr(line.makingAmount)}'
                ' · fine ${Num.round3(line.fineWeight).toStringAsFixed(3)} g'
                '${line.additionalCost > 0 ? ' · Additional ${inr(line.additionalCost)}' : ''}'
                '${line.discount > 0 ? ' · Discount ${inr(line.discount)}' : ''}'
            : '${description.isEmpty ? '' : '$description · '}'
                'Wastage ${Num.round3(line.wastageWeight).toStringAsFixed(3)} g'
                ' · total ${Num.round3(line.totalEquivalentWeight).toStringAsFixed(3)} g'
                ' × ₹${moneyWhole(line.pureRate)} = ${inr(line.metalValue + line.makingAmount)}'
                '${line.additionalCost > 0 ? ' · Additional ${inr(line.additionalCost)}' : ''}'
                '${line.discount > 0 ? ' · Discount ${inr(line.discount)}' : ''}',
        style: TextStyle(fontSize: 11, color: mutedOf(context)),
      ),
      trailing: Text(inr(line.total),
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: inkOf(context))),
    );
  }

  Widget _kv(String label, String value, {bool bold = false}) {
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
