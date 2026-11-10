import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/cloud_refresh.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../../../util/format.dart';
import '../../../util/jewellery_math.dart';
import '../../../util/overdue_orders.dart';
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

class _JewelleryScreenState extends State<JewelleryScreen>
    with CloudRefreshMixin<JewelleryScreen> {
  @override
  Future<void> reloadFromCloud() => _load();

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
  int _overdueCount = 0;
  Map<String, double> _wip = const {};
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
    final openOrders = await store.orders(status: 'Pending');
    final readyOrders = await store.orders(status: 'Ready');
    final wip = await store.wipWeight();
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
      _overdueCount = countOverdueOrders([...openOrders, ...readyOrders]);
      _wip = wip;
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
  double get _wipGrams => _wip.values.fold(0, (sum, g) => sum + g);
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
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
              children: [
                _ratesStrip(),
                const SizedBox(height: 12),
                _todayCard(summary),
                const SizedBox(height: 12),
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
                if (_overdueCount > 0) ...[
                  const SizedBox(height: 12),
                  _overdueBanner(),
                ],
                const SizedBox(height: 22),
                _group('Workshop', [
                  _navRow(
                    icon: Icons.receipt_long_outlined,
                    title: 'Orders',
                    subtitle: 'Repairs and custom pieces',
                    metric: _overdueCount > 0
                        ? '$_overdueCount overdue'
                        : _pendingOrders > 0
                            ? '$_pendingOrders pending'
                            : '$_readyOrders ready',
                    metricColor: _overdueCount > 0 ? kRed : null,
                    onTap: () => _openScreen(const JewelleryOrdersScreen()),
                  ),
                  _navRow(
                    icon: Icons.handyman_outlined,
                    title: 'Workers',
                    subtitle: 'Karigars · cash ${inr(_workerCash)}',
                    metric: '${_workers.length} · '
                        '${Num.round3(_workerGold).toStringAsFixed(3)} g',
                    onTap: () => _openScreen(const JewelleryWorkersScreen()),
                  ),
                  _navRow(
                    icon: Icons.recycling_outlined,
                    title: 'Old metal',
                    subtitle: 'Gold and silver bought from customers',
                    metric:
                        '${Num.round3(_oldMetal?.goldGrams ?? 0).toStringAsFixed(3)} g',
                    onTap: () => _openScreen(const JewelleryOldMetalScreen()),
                  ),
                  _navRow(
                    icon: Icons.assignment_return_outlined,
                    title: 'Returns',
                    subtitle: 'Credit notes for returned pieces',
                    metric: '${_returns.length} note'
                        '${_returns.length == 1 ? '' : 's'}',
                    onTap: () => _openScreen(const JewelleryReturnsScreen()),
                  ),
                ]),
                _group('Money', [
                  _navRow(
                    icon: Icons.menu_book_outlined,
                    title: 'Customer credit',
                    subtitle: 'Who owes the shop',
                    metric: (_credit?.customers ?? 0) == 0
                        ? 'None due'
                        : inr(_credit!.outstanding),
                    onTap: _openCreditBook,
                  ),
                  _navRow(
                    icon: Icons.local_shipping_outlined,
                    title: 'Supplier payables',
                    subtitle: 'What the shop owes suppliers',
                    metric: (_supplier?.suppliers ?? 0) == 0
                        ? 'None due'
                        : inr(_supplier!.outstanding),
                    onTap: _openSupplierBook,
                  ),
                  _navRow(
                    icon: Icons.insights_outlined,
                    title: 'Reports',
                    subtitle: 'Profit, stock, sales and worker balances',
                    onTap: () => _openScreen(const JewelleryReportsScreen()),
                  ),
                ]),
                _documentsHeader(visible),
                const SizedBox(height: 10),
                if (_invoices.isNotEmpty) ...[
                  TextField(
                    controller: _search,
                    decoration: fieldDecoration('Search doc no, party or notes')
                        .copyWith(
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 0, label: Text('All')),
                            ButtonSegment(value: 1, label: Text('Sales')),
                            ButtonSegment(value: 2, label: Text('Purchases')),
                          ],
                          selected: {_docFilter},
                          onSelectionChanged: (selection) =>
                              setState(() => _docFilter = selection.first),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Badge.count(
                        count: _activeFilterCount,
                        isLabelVisible: _activeFilterCount > 0,
                        child: IconButton.filledTonal(
                          tooltip: 'Filter by metal or payment status',
                          onPressed: _openFilters,
                          icon: const Icon(Icons.tune, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                if (_invoices.isEmpty)
                  _documentsEmpty()
                else if (visible.isEmpty)
                  _noMatch()
                else
                  for (final invoice in visible) _invoiceTile(invoice),
              ],
            ),
    );
  }

  int get _activeFilterCount =>
      (_metalFilter == 'all' ? 0 : 1) + (_statusFilter == 0 ? 0 : 1);

  void _clearFilters() => setState(() {
        _docFilter = 0;
        _metalFilter = 'all';
        _statusFilter = 0;
      });

  /// Metal and payment-status filters live behind one control: nine chips on
  /// the counter screen made every document list look like a form.
  Future<void> _openFilters() async {
    var metal = _metalFilter;
    var status = _statusFilter;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filter documents',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: inkOf(sheet))),
                const SizedBox(height: 14),
                Text('Metal',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: mutedOf(sheet))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final entry in const [
                      ('all', 'All metals'),
                      (JewelleryStore.gold, 'Gold'),
                      (JewelleryStore.silver, 'Silver'),
                    ])
                      ChoiceChip(
                        label: Text(entry.$2),
                        selected: metal == entry.$1,
                        onSelected: (_) => setSheet(() => metal = entry.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('Payment status',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: mutedOf(sheet))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final entry in const [
                      (0, 'All status'),
                      (1, 'Dues'),
                      (2, 'Settled'),
                    ])
                      ChoiceChip(
                        label: Text(entry.$2),
                        selected: status == entry.$1,
                        onSelected: (_) => setSheet(() => status = entry.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setSheet(() {
                        metal = 'all';
                        status = 0;
                      }),
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(sheet, true),
                      child: const Text('Show results'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        _metalFilter = metal;
        _statusFilter = status;
      });
    }
  }

  /// Today's rate is the one figure every document depends on, so it sits at
  /// the top on its own and is edited in place.
  Widget _ratesStrip() {
    return Card(
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: _rateItem(JewelleryStore.gold, 'Gold'),
          ),
          Container(width: 1, height: 56, color: lineOf(context)),
          Expanded(
            child: _rateItem(JewelleryStore.silver, 'Silver'),
          ),
        ],
      ),
    );
  }

  Widget _rateItem(String metal, String label) {
    final rate = _rates[metal];
    return Tooltip(
      message: 'Edit today\'s $label rate',
      child: InkWell(
        onTap: () => _editRate(metal),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: mutedOf(context))),
                  const SizedBox(width: 4),
                  Icon(Icons.edit_outlined, size: 13, color: mutedOf(context)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                rate == null ? 'Not set' : '${moneyWhole(rate)}/g',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: rate == null ? kGoldDark : inkOf(context)),
              ),
              if (metal == JewelleryStore.gold && rate != null)
                Text(
                  '92% ${moneyWhole(JewelleryMath.rateForPurity(rate, 92))}/g',
                  style: TextStyle(fontSize: 11, color: mutedOf(context)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Money and metal are different questions — what came in today, and what is
  /// physically in the safe — so they get two labelled blocks, not eight
  /// identical stat pairs.
  Widget _todayCard(
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
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _blockLabel('Money today'),
            const SizedBox(height: 10),
            Row(
              children: [
                _metric('Sales', inr(s?.salesToday ?? 0)),
                _metric('Collected', inr(s?.collectedToday ?? 0)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _metric('Purchases', inr(s?.purchasesToday ?? 0)),
                _metric('Outstanding', inr(s?.outstanding ?? 0),
                    caption: '${s?.openInvoices ?? 0} open'),
              ],
            ),
            const Divider(height: 26),
            _blockLabel('Metal in hand'),
            const SizedBox(height: 10),
            Row(
              children: [
                _metric('Raw gold', _weight('${JewelleryStore.gold}_RAW')),
                _metric('Raw silver', _weight('${JewelleryStore.silver}_RAW')),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _metric('Old gold', _weight('${JewelleryStore.gold}_OLD')),
                _metric('Old silver', _weight('${JewelleryStore.silver}_OLD')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _blockLabel(String text) => Text(text,
      style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: .2,
          color: mutedOf(context)));

  Widget _metric(String label, String value, {String? caption}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: inkOf(context))),
          Text(caption == null ? label : '$label · $caption',
              style: TextStyle(fontSize: 11, color: mutedOf(context))),
        ],
      ),
    );
  }

  Widget _group(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: inkOf(context))),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: lineOf(context)),
                rows[i],
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _navRow({
    required IconData icon,
    required String title,
    String? subtitle,
    String? metric,
    Color? metricColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 22, color: kGoldDark),
      title: Text(title,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: inkOf(context))),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: TextStyle(fontSize: 11.5, color: mutedOf(context))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (metric != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 104),
              child: Text(
                metric,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: metricColor ?? mutedOf(context)),
              ),
            ),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right, size: 20, color: mutedOf(context)),
        ],
      ),
    );
  }

  Widget _overdueBanner() {
    return Material(
      color: kRed.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openScreen(const JewelleryOrdersScreen()),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.schedule, color: kRed, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_overdueCount overdue order'
                      '${_overdueCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: kRed),
                    ),
                    Text(
                      '${_wipGrams.toStringAsFixed(3)} g with workers · '
                      'promised date passed',
                      style: TextStyle(fontSize: 11, color: mutedOf(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: kRed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _documentsHeader(List<Map<String, Object?>> visible) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text('Documents',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: inkOf(context))),
        ),
        Text(
          _invoices.isEmpty
              ? 'None yet'
              : '${visible.length} of ${_invoices.length}',
          style: TextStyle(fontSize: 11.5, color: mutedOf(context)),
        ),
      ],
    );
  }

  Widget _documentsEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 34, color: mutedOf(context)),
          const SizedBox(height: 10),
          Text('No sales or purchases yet',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: inkOf(context))),
          const SizedBox(height: 4),
          Text('Record a sale to start the shop ledger.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: mutedOf(context))),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _openForm(JewelleryStore.saleDoc),
            icon: const Icon(Icons.sell_outlined, size: 18),
            label: const Text('Record a sale'),
          ),
        ],
      ),
    );
  }

  Widget _noMatch() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text('No documents match these filters.',
              style: TextStyle(fontSize: 12.5, color: mutedOf(context))),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
            label: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }

  Widget _invoiceTile(Map<String, Object?> invoice) {
    final isPurchase =
        (invoice['doc_type']?.toString() ?? '') == JewelleryStore.purchaseDoc;
    final status = JewelleryStore.recoveryFor(invoice);
    final isDraft =
        (invoice['status']?.toString() ?? '') == JewelleryStore.draftStatus;
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
          // A draft must not read like a real purchase: it holds no stock and
          // is not a payable yet, so the row says so instead of showing a
          // balance the shop may think it owes.
          '${isDraft ? ' · DRAFT · stock pending' : (outstanding > 0 ? ' · Bal ${inr(outstanding)}' : ' · Settled')}',
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
