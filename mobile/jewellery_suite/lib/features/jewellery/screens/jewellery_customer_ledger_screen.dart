import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import '../widgets/jewellery_invoice_sheet.dart';

/// One customer's jewellery ledger: every sale debits, every receipt credits,
/// with the running balance shown against each row.
class JewelleryCustomerLedgerScreen extends StatefulWidget {
  const JewelleryCustomerLedgerScreen({
    super.key,
    required this.customerName,
  });

  final String customerName;

  @override
  State<JewelleryCustomerLedgerScreen> createState() =>
      _JewelleryCustomerLedgerScreenState();
}

class _JewelleryCustomerLedgerScreenState
    extends State<JewelleryCustomerLedgerScreen> {
  List<JewelleryLedgerEntry> _entries = const [];
  List<Map<String, Object?>> _openInvoices = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<AppState>().jewelleryStore;
    final entries = await store.ledgerForCustomer(widget.customerName);
    final open = await store.openInvoicesForCustomer(widget.customerName);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _openInvoices = open;
      _loading = false;
    });
  }

  double get _billed => _entries.fold(0, (sum, e) => sum + e.debit);
  double get _received => _entries.fold(0, (sum, e) => sum + e.credit);
  double get _outstanding => _entries.isEmpty ? 0 : _entries.first.balance;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// One receipt, split by hand across this customer's open invoices.
  ///
  /// Each invoice gets its own amount box, so the shop decides which sale the
  /// money belongs to; whichever box is raised above that invoice's balance
  /// becomes a customer advance instead of being refused. `JewelleryStore`
  /// trims every part to what the invoice still owes.
  Future<void> _receive() async {
    if (_openInvoices.isEmpty) return;
    final state = context.read<AppState>();
    final controllers = <String, TextEditingController>{
      for (final inv in _openInvoices)
        inv['client_uuid'].toString(): TextEditingController(
            text: Num.toDouble(inv['outstanding']).toStringAsFixed(0)),
    };
    var mode = 'CASH';
    try {
      final plan = await showDialog<Map<String, double>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            var total = 0.0;
            for (final c in controllers.values) {
              total += parseMoney(c.text);
            }
            return AlertDialog(
              title: const Text('Receive payment'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final inv in _openInvoices) ...[
                      Text(
                        '${inv['doc_no']} · balance '
                        '${inr(Num.toDouble(inv['outstanding']))}',
                        style: TextStyle(fontSize: 12, color: mutedOf(ctx)),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: controllers[inv['client_uuid'].toString()],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: fieldDecoration('Amount ₹'),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 10),
                    ],
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
                      'Receipt ${inr(total)}. Each invoice takes at most its '
                      'balance; anything above it stays as a customer advance.',
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
                  onPressed: () => Navigator.pop(ctx, {
                    for (final inv in _openInvoices)
                      inv['client_uuid'].toString(): parseMoney(
                          controllers[inv['client_uuid'].toString()]!.text),
                  }),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        ),
      );
      if (plan == null) return;
      final manual = <String, double>{
        for (final entry in plan.entries)
          if (entry.value > 0) entry.key: entry.value,
      };
      final amount = manual.values.fold<double>(0, (sum, v) => sum + v);
      if (amount <= 0) return;
      final result = await state.receiveJewelleryReceipt(
        partyName: widget.customerName,
        amount: amount,
        date: DateTime.now(),
        mode: mode,
        allocations: manual,
      );
      await _load();
      _toast(result.unallocated > 0.005
          ? 'Saved · ${inr(result.unallocated)} kept as advance.'
          : 'Payment saved.');
    } on FormatException catch (e) {
      _toast(e.message);
    } finally {
      for (final c in controllers.values) {
        c.dispose();
      }
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
        title: Text(widget.customerName),
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
                    onPressed: _receive,
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Receive payment'),
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
            Text(widget.customerName,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: inkOf(context))),
            const SizedBox(height: 8),
            Row(
              children: [
                _stat('Billed', inr(_billed)),
                _stat('Received', inr(_received)),
                _stat('Outstanding', inr(_outstanding),
                    color: _outstanding > 0 ? kRed : kGreen),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_openInvoices.length} open invoice'
              '${_openInvoices.length == 1 ? '' : 's'} · '
              '${_entries.where((e) => e.isSale).length} sale'
              '${_entries.where((e) => e.isSale).length == 1 ? '' : 's'}',
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

  Widget _ledgerRow(JewelleryLedgerEntry entry) {
    final note = entry.note.trim();
    final showNote = note.isNotEmpty &&
        note != 'Sale receipt' &&
        note != 'Jewellery invoice payment';
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
                    entry.isSale ? inr(entry.debit) : '-${inr(entry.credit)}',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: entry.isSale ? kRed : kGreen),
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
              if (entry.oldMetalValue > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Old metal ${inr(entry.oldMetalValue)} credited',
                    style: TextStyle(fontSize: 11, color: mutedOf(context)),
                  ),
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
