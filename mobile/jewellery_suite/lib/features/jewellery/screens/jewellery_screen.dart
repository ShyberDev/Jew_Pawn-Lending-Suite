import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import '../../../util/jewellery_math.dart';
import '../widgets/jewellery_invoice_sheet.dart';
import 'jewellery_credit_book_screen.dart';
import 'jewellery_invoice_screen.dart';
import 'jewellery_old_metal_screen.dart';
import 'jewellery_orders_screen.dart';
import 'jewellery_reports_screen.dart';
import 'jewellery_returns_screen.dart';
import 'jewellery_supplier_book_screen.dart';
import 'jewellery_workers_screen.dart';

/// Jewellery — the module's core counter.
///
/// Shows today's saved rates, the stock position the documents produced, and
/// every sale/purchase with its outstanding. All figures come from
/// [JewelleryStore]; nothing is calculated on the screen itself except the
/// recovery colour, which uses [JewelleryMath.recovery].
class JewelleryScreen extends StatefulWidget {
  const JewelleryScreen({super.key});

  @override
  State<JewelleryScreen> createState() => _JewelleryScreenState();
}

class _JewelleryScreenState extends State<JewelleryScreen> {
  final _search = TextEditingController();
  List<Map<String, Object?>> _invoices = const [];
  Map<String, double> _stock = const {};
  Map<String, double?> _rates = const {};
  int _docFilter = 0; // 0 all, 1 sales, 2 purchases
  String _metalFilter = 'all';
  int _statusFilter = 0; // 0 all, 1 dues, 2 settled
  ({
    double salesToday,
    double purchasesToday,
    double collectedToday,
    double outstanding,
    int openInvoices,
  })? _summary;
  ({double outstanding, int customers})? _credit;
  ({double outstanding, int suppliers})? _supplier;
  ({
    double goldGrams,
    double silverGrams,
    double acceptedValue,
    int vouchers,
  })? _oldMetal;
  List<JewelleryWorkerPosition> _workers = const [];
  Map<String, int> _orderCounts = const {};
  List<Map<String, Object?>> _returns = const [];
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

  List<Map<String, Object?>> get _visibleInvoices {
    final needle = _search.text.trim().toLowerCase();
    return [
      for (final invoice in _invoices)
        if (_matchesInvoice(invoice, needle)) invoice,
    ];
  }

  bool _matchesInvoice(Map<String, Object?> invoice, String needle) {
    final docType = invoice['doc_type']?.toString() ?? '';
    if (_docFilter == 1 && docType != JewelleryStore.saleDoc) return false;
    if (_docFilter == 2 && docType != JewelleryStore.purchaseDoc) return false;
    if (_metalFilter != 'all' &&
        (invoice['metal']?.toString().toUpperCase() ?? '') != _metalFilter) {
      return false;
    }
    final outstanding = Num.toDouble(invoice['outstanding']);
    if (_statusFilter == 1 && outstanding <= 0.005) return false;
    if (_statusFilter == 2 && outstanding > 0.005) return false;
    if (needle.isEmpty) return true;
    final haystack = ('${invoice['doc_no'] ?? ''} '
            '${invoice['party_name'] ?? ''} '
            '${invoice['notes'] ?? ''}')
        .toLowerCase();
    return haystack.contains(needle);
  }

  Future<void> _load() async {
    final store = context.read<AppState>().jewelleryStore;
    final invoices = (await store.invoices())
        .where(
            (i) => (i['doc_type']?.toString() ?? '') != JewelleryStore.orderDoc)
        .toList();
    final stock = await store.stockTotals();
    final gold = await store.latestRate(JewelleryStore.gold);
    final silver = await store.latestRate(JewelleryStore.silver);
    final summary = await store.summary();
    final credit = await store.creditBookTotals();
    final supplier = await store.supplierBookTotals();
    final oldMetal = await store.oldMetalTotals();
    final workers = await store.workerPositions();
    final orderCounts = await store.orderStatusSummary();
    final returns = await store.returns();
    if (!mounted) return;
    setState(() {
      _invoices = invoices;
      _stock = stock;
      _rates = {JewelleryStore.gold: gold, JewelleryStore.silver: silver};
      _summary = summary;
      _credit = credit;
      _supplier = supplier;
      _oldMetal = oldMetal;
      _workers = workers;
      _orderCounts = orderCounts;
      _returns = returns;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openForm(String docType) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => JewelleryInvoiceScreen(docType: docType)),
    );
    if (saved == true) {
      await _load();
      _toast(docType == JewelleryStore.purchaseDoc
          ? 'Purchase saved.'
          : 'Sale saved.');
    }
  }

  Future<void> _openCreditBook() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const JewelleryCreditBookScreen()),
    );
    await _load();
  }

  Future<void> _openSupplierBook() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const JewellerySupplierBookScreen()),
    );
    await _load();
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    await _load();
  }

  Future<void> _editRate(String metal) async {
    final state = context.read<AppState>();
    final ctl =
        TextEditingController(text: _rates[metal]?.toStringAsFixed(2) ?? '');
    try {
      final value = await showDialog<double>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${_metalLabel(metal)} rate'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fieldDecoration('Pure-metal rate ₹/g'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, parseMoney(ctl.text)),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (value == null) return;
      if (value <= 0) {
        _toast('Enter a rate above zero.');
        return;
      }
      await state.saveJewelleryRate(metal, value);
      await _load();
    } finally {
      ctl.dispose();
    }
  }

  Future<void> _openInvoice(Map<String, Object?> invoice) async {
    final uuid = invoice['client_uuid']?.toString() ?? '';
    if (uuid.isEmpty) return;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => JewelleryInvoiceSheet(invoiceUuid: uuid),
    );
    await _load();
  }

  static String _metalLabel(String metal) =>
      metal == JewelleryStore.silver ? 'Silver (100%)' : 'Gold';

  int get _pendingOrders => _orderCounts['Pending'] ?? 0;
  int get _readyOrders => _orderCounts['Ready'] ?? 0;
  double get _workerCash => _workers.fold(0, (sum, w) => sum + w.cashReserve);
  double get _workerGold => _workers.fold(0, (sum, w) => sum + w.goldReserve);

  String _weight(String key) =>
      '${Num.round3(_stock[key] ?? 0).toStringAsFixed(3)} g';

  Color _recoveryColor(RecoveryStatus status) => switch (status) {
        RecoveryStatus.green => kGreen,
        RecoveryStatus.lightGreen => const Color(0xFF7CB342),
        RecoveryStatus.red => kRed,
        RecoveryStatus.grey => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final visible = _visibleInvoices;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jewellery'),
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
                _ratesCard(),
                const SizedBox(height: 8),
                _summaryCard(summary),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _openForm(JewelleryStore.saleDoc),
                        icon: const Icon(Icons.sell_outlined, size: 18),
                        label: const Text('New Sale'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openForm(JewelleryStore.purchaseDoc),
                        icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                        label: const Text('New Purchase'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    onTap: _openCreditBook,
                    leading: const Icon(Icons.menu_book_outlined),
                    title: const Text('Customer Credit Book'),
                    subtitle: Text(
                      (_credit?.customers ?? 0) == 0
                          ? 'No jewellery customer dues'
                          : '${inr(_credit!.outstanding)} due from '
                              '${_credit!.customers} customer'
                              '${_credit!.customers == 1 ? '' : 's'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    onTap: _openSupplierBook,
                    leading: const Icon(Icons.local_shipping_outlined),
                    title: const Text('Supplier Payables'),
                    subtitle: Text(
                      (_supplier?.suppliers ?? 0) == 0
                          ? 'No jewellery supplier dues'
                          : '${inr(_supplier!.outstanding)} payable to '
                              '${_supplier!.suppliers} supplier'
                              '${_supplier!.suppliers == 1 ? '' : 's'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _moduleTile(
                        icon: Icons.receipt_long_outlined,
                        title: 'Orders',
                        subtitle: '$_pendingOrders pending · '
                            '$_readyOrders ready',
                        onTap: () => _openScreen(const JewelleryOrdersScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _moduleTile(
                        icon: Icons.handyman_outlined,
                        title: 'Workers',
                        subtitle: '${_workers.length} worker'
                            '${_workers.length == 1 ? '' : 's'} · '
                            '${Num.round3(_workerGold).toStringAsFixed(3)} g',
                        onTap: () =>
                            _openScreen(const JewelleryWorkersScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _moduleTile(
                        icon: Icons.recycling_outlined,
                        title: 'Old Metal',
                        subtitle:
                            '${Num.round3(_oldMetal?.goldGrams ?? 0).toStringAsFixed(3)} g gold · '
                            '${inr(_oldMetal?.acceptedValue ?? 0)}',
                        onTap: () =>
                            _openScreen(const JewelleryOldMetalScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _moduleTile(
                        icon: Icons.assignment_return_outlined,
                        title: 'Returns',
                        subtitle:
                            '${_returns.length} credit note${_returns.length == 1 ? '' : 's'}',
                        onTap: () =>
                            _openScreen(const JewelleryReturnsScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    onTap: () => _openScreen(const JewelleryReportsScreen()),
                    leading: const Icon(Icons.insights_outlined),
                    title: const Text('Reports'),
                    subtitle: Text(
                      'Sales, stock, orders, workers and profit · '
                      'cash with workers ${inr(_workerCash)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                const SizedBox(height: 14),
                Text('SALES & PURCHASES',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: mutedOf(context))),
                if (_invoices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _search,
                    decoration: fieldDecoration('Search doc no, party or notes')
                        .copyWith(
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final entry in const [
                        (0, 'All types'),
                        (1, 'Sales'),
                        (2, 'Purchases'),
                      ])
                        ChoiceChip(
                          label: Text(entry.$2),
                          selected: _docFilter == entry.$1,
                          onSelected: (_) =>
                              setState(() => _docFilter = entry.$1),
                        ),
                      for (final entry in const [
                        ('all', 'All metals'),
                        (JewelleryStore.gold, 'Gold'),
                        (JewelleryStore.silver, 'Silver'),
                      ])
                        ChoiceChip(
                          label: Text(entry.$2),
                          selected: _metalFilter == entry.$1,
                          onSelected: (_) =>
                              setState(() => _metalFilter = entry.$1),
                        ),
                      for (final entry in const [
                        (0, 'All status'),
                        (1, 'Dues'),
                        (2, 'Settled'),
                      ])
                        ChoiceChip(
                          label: Text(entry.$2),
                          selected: _statusFilter == entry.$1,
                          onSelected: (_) =>
                              setState(() => _statusFilter = entry.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${visible.length} of ${_invoices.length} document'
                    '${_invoices.length == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 11, color: mutedOf(context)),
                  ),
                ],
                const SizedBox(height: 6),
                if (_invoices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: Text('No jewellery documents yet.',
                            style: TextStyle(color: mutedOf(context)))),
                  )
                else if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: Text('No documents match these filters.',
                            style: TextStyle(color: mutedOf(context)))),
                  )
                else
                  for (final invoice in visible) _invoiceTile(invoice),
              ],
            ),
    );
  }

  Widget _moduleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: kGoldDark),
              const SizedBox(height: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: inkOf(context))),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: mutedOf(context))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ratesCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Today\'s saved rates',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final metal in const [
              JewelleryStore.gold,
              JewelleryStore.silver
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_metalLabel(metal),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: inkOf(context))),
                    ),
                    Text(
                      _rates[metal] == null
                          ? 'Not set'
                          : '${moneyWhole(_rates[metal])}/g'
                              '${metal == JewelleryStore.gold ? ' · 92% ${moneyWhole(JewelleryMath.rateForPurity(_rates[metal]!, 92))}/g' : ''}',
                      style: TextStyle(fontSize: 12, color: mutedOf(context)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _editRate(metal),
                    ),
                  ],
                ),
              ),
            Text(
              'A saved rate is history: older documents keep the rate they used.',
              style: TextStyle(fontSize: 11, color: mutedOf(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(
      ({
        double salesToday,
        double purchasesToday,
        double collectedToday,
        double outstanding,
        int openInvoices,
      })? summary) {
    final s = summary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _stat('Raw gold', _weight('${JewelleryStore.gold}_RAW')),
                _stat('Raw silver', _weight('${JewelleryStore.silver}_RAW')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _stat('Old gold', _weight('${JewelleryStore.gold}_OLD')),
                _stat('Old silver', _weight('${JewelleryStore.silver}_OLD')),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                _stat("Today's sales", inr(s?.salesToday ?? 0)),
                _stat('Collected today', inr(s?.collectedToday ?? 0)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _stat('Purchases today', inr(s?.purchasesToday ?? 0)),
                _stat('Outstanding', inr(s?.outstanding ?? 0),
                    caption: '${s?.openInvoices ?? 0} open'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, {String? caption}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: inkOf(context))),
          Text(caption == null ? label : '$label · $caption',
              style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
        ],
      ),
    );
  }

  Widget _invoiceTile(Map<String, Object?> invoice) {
    final isPurchase =
        (invoice['doc_type']?.toString() ?? '') == JewelleryStore.purchaseDoc;
    final status = JewelleryStore.recoveryFor(invoice);
    final outstanding = (invoice['outstanding'] as num?)?.toDouble() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () => _openInvoice(invoice),
        leading: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: _recoveryColor(status), shape: BoxShape.circle),
        ),
        title: Text(
          '${invoice['party_name'] ?? ''} · ${invoice['doc_no'] ?? ''}',
          style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: inkOf(context)),
        ),
        subtitle: Text(
          '${fmtDate(invoice['invoice_date'])} · '
          '${isPurchase ? 'Purchase' : 'Sale'} · ${invoice['metal'] ?? ''}'
          '${outstanding > 0 ? ' · Bal ${inr(outstanding)}' : ' · Settled'}',
          style: TextStyle(fontSize: 11, color: mutedOf(context)),
        ),
        trailing: Text(inr(Num.toDouble(invoice['total'])),
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: inkOf(context))),
      ),
    );
  }
}
