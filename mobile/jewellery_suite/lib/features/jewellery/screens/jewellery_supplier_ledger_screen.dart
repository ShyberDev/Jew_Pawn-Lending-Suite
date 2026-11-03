import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import '../widgets/jewellery_invoice_sheet.dart';

/// One supplier's jewellery ledger: every purchase credits the payable, every
/// payment debits it, with the running payable shown against each row.
class JewellerySupplierLedgerScreen extends StatefulWidget {
  const JewellerySupplierLedgerScreen({
    super.key,
    required this.supplierName,
  });

  final String supplierName;

  @override
  State<JewellerySupplierLedgerScreen> createState() =>
      _JewellerySupplierLedgerScreenState();
}

class _JewellerySupplierLedgerScreenState
    extends State<JewellerySupplierLedgerScreen> {
  List<JewellerySupplierLedgerEntry> _entries = const [];
  List<Map<String, Object?>> _openInvoices = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<AppState>().jewelleryStore;
    final entries = await store.ledgerForSupplier(widget.supplierName);
    final open =
        await store.openPurchaseInvoicesForSupplier(widget.supplierName);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _openInvoices = open;
      _loading = false;
    });
  }

  double get _billed => _entries.fold(0, (sum, e) => sum + e.credit);
  double get _paid => _entries.fold(0, (sum, e) => sum + e.debit);
  double get _outstanding => _entries.isEmpty ? 0 : _entries.first.balance;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _chooseInvoice() async {
    if (_openInvoices.isEmpty) return;
    if (_openInvoices.length == 1) {
      await _pay(_openInvoices.first);
      return;
    }
    final chosen = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Which purchase is this payment for?',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: inkOf(ctx))),
            ),
            for (final invoice in _openInvoices)
              ListTile(
                title: Text(
                  '${invoice['doc_no']} · ${fmtDate(invoice['invoice_date'])}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: inkOf(ctx)),
                ),
                subtitle: Text(
                  'Balance ${inr(Num.toDouble(invoice['outstanding']))}',
                  style: TextStyle(fontSize: 11, color: mutedOf(ctx)),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, invoice),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) await _pay(chosen);
  }

  Future<void> _pay(Map<String, Object?> invoice) async {
    final state = context.read<AppState>();
    final outstanding = (invoice['outstanding'] as num?)?.toDouble() ?? 0;
    final ctl = TextEditingController(text: outstanding.toStringAsFixed(0));
    var mode = 'CASH';
    try {
      final amount = await showDialog<double>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Pay supplier'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ctl,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: fieldDecoration('Amount ₹'),
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
                  const SizedBox(height: 8),
                  Text(
                    'Purchase ${invoice['doc_no']} · balance ${inr(outstanding)}',
                    style: TextStyle(fontSize: 11, color: mutedOf(ctx)),
                  ),
                ],
              ),
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
        ),
      );
      if (amount == null || amount <= 0) return;
      await state.addJewelleryPayment(
        invoiceUuid: invoice['client_uuid']?.toString() ?? '',
        partyName: widget.supplierName,
        amount: amount,
        date: DateTime.now(),
        mode: mode,
      );
      await _load();
      _toast('Supplier payment saved.');
    } on FormatException catch (e) {
      _toast(e.message);
    } finally {
      ctl.dispose();
    }
  }

  Future<void> _openInvoice(String uuid) async {
    if (uuid.isEmpty) return;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => JewelleryInvoiceSheet(invoiceUuid: uuid),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplierName),
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
                _headerCard(),
                if (_outstanding > 0) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _chooseInvoice,
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Pay supplier'),
                  ),
                ],
                const SizedBox(height: 14),
                Text('LEDGER',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: mutedOf(context))),
                const SizedBox(height: 6),
                if (_entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                      child: Text('No ledger entries yet.',
                          style: TextStyle(color: mutedOf(context))),
                    ),
                  )
                else
                  for (final entry in _entries) _ledgerRow(entry),
              ],
            ),
    );
  }

  Widget _headerCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.supplierName,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: inkOf(context))),
            const SizedBox(height: 8),
            Row(
              children: [
                _stat('Purchased', inr(_billed)),
                _stat('Paid', inr(_paid)),
                _stat('Payable', inr(_outstanding),
                    color: _outstanding > 0 ? kRed : kGreen),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_openInvoices.length} open purchase'
              '${_openInvoices.length == 1 ? '' : 's'} · '
              '${_entries.where((e) => e.isPurchase).length} purchase'
              '${_entries.where((e) => e.isPurchase).length == 1 ? '' : 's'}',
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

  Widget _ledgerRow(JewellerySupplierLedgerEntry entry) {
    final note = entry.note.trim();
    final showNote = note.isNotEmpty &&
        note != 'Purchase payment' &&
        note != 'Jewellery purchase payment';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => _openInvoice(entry.invoiceUuid),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${entry.description}'
                      '${entry.reference.isEmpty ? '' : ' · ${entry.reference}'}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: inkOf(context)),
                    ),
                  ),
                  Text(
                    entry.isPurchase
                        ? inr(entry.credit)
                        : '-${inr(entry.debit)}',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: entry.isPurchase ? kRed : kGreen),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${fmtDate(entry.date)}'
                      '${entry.mode.isEmpty ? '' : ' · ${entry.mode}'}',
                      style: TextStyle(fontSize: 11, color: mutedOf(context)),
                    ),
                  ),
                  Text('Bal ${inr(entry.balance)}',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: mutedOf(context))),
                ],
              ),
              if (showNote)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(note,
                      style: TextStyle(fontSize: 11, color: mutedOf(context))),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
