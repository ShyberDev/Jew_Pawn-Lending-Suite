import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/jewellery_store.dart';
import '../../../state/app_state.dart';
import '../../../ui/palette.dart';
import '../../../util/format.dart';

/// On-screen jewellery reports. PDF/Excel/charts stay out until the packages
/// are available; every figure here is read from the store, never recomputed.
class JewelleryReportsScreen extends StatefulWidget {
  const JewelleryReportsScreen({super.key});

  @override
  State<JewelleryReportsScreen> createState() => _JewelleryReportsScreenState();
}

class _JewelleryReportsScreenState extends State<JewelleryReportsScreen> {
  int _range = 1; // 0 day, 1 month, 2 all
  ({
    double sales,
    double purchases,
    double collections,
    double returns,
    double refunds,
    double oldMetalValue,
    double oldGold,
    double oldSilver,
    double outstandingSales,
    double outstandingPurchases,
    int saleCount,
    int purchaseCount,
  })? _totals;
  ({
    double estimated,
    double finalProfit,
    double cost,
    double actualCost
  })? _profit;
  Map<String, double> _stock = const {};
  JewelleryStockValuation? _valuation;
  List<JewelleryMonthTotal> _monthly = const [];
  Map<String, int> _orders = const {};
  List<JewelleryWorkerPosition> _workers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime?, DateTime?) get _window {
    final now = DateTime.now();
    return switch (_range) {
      0 => (DateTime(now.year, now.month, now.day), null),
      1 => (DateTime(now.year, now.month, 1), null),
      _ => (null, null),
    };
  }

  Future<void> _load() async {
    final store = context.read<AppState>().jewelleryStore;
    final (from, to) = _window;
    final totals = await store.reportTotals(from: from, to: to);
    final profit = await store.profitSummary(from: from, to: to);
    final stock = await store.stockTotals();
    final valuation = await store.stockValuation();
    final monthly = await store.monthlyTotals();
    final orders = await store.orderStatusSummary();
    final workers = await store.workerPositions();
    if (!mounted) return;
    setState(() {
      _totals = totals;
      _profit = profit;
      _stock = stock;
      _valuation = valuation;
      _monthly = monthly;
      _orders = orders;
      _workers = workers;
      _loading = false;
    });
  }

  double _weight(String metal, String kind) => _stock['${metal}_$kind'] ?? 0;

  String _fine(String metal, String kind) =>
      Num.round3(_valuation?.fineWeight(metal, kind) ?? 0).toStringAsFixed(3);

  double get _workerCash => _workers.fold(0, (sum, w) => sum + w.cashReserve);
  double get _workerGold => _workers.fold(0, (sum, w) => sum + w.goldReserve);

  String get _rangeLabel => switch (_range) {
        0 => 'Today',
        1 => 'This month',
        _ => 'All time',
      };

  @override
  Widget build(BuildContext context) {
    final t = _totals;
    final p = _profit;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jewellery Reports'),
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
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in const [
                      (0, 'Day'),
                      (1, 'Month'),
                      (2, 'All'),
                    ])
                      ChoiceChip(
                        label: Text(entry.$2),
                        selected: _range == entry.$1,
                        onSelected: (_) {
                          setState(() {
                            _range = entry.$1;
                            _loading = true;
                          });
                          _load();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _card('Money · $_rangeLabel', [
                  _row('Sales', inr(t?.sales ?? 0),
                      caption: '${t?.saleCount ?? 0} invoice(s)'),
                  _row('Purchases', inr(t?.purchases ?? 0),
                      caption: '${t?.purchaseCount ?? 0} invoice(s)'),
                  _row('Collections', inr(t?.collections ?? 0)),
                  _row('Returns', inr(t?.returns ?? 0)),
                  _row('Refunds paid', inr(t?.refunds ?? 0)),
                  const Divider(height: 16),
                  _row('Customer dues', inr(t?.outstandingSales ?? 0),
                      bold: true, color: kRed),
                  _row('Supplier payable', inr(t?.outstandingPurchases ?? 0),
                      bold: true, color: kRed),
                ]),
                _card('Sales vs purchases · last 6 months', [
                  _MonthlyBars(months: _monthly),
                  const SizedBox(height: 8),
                  Text(
                    'Bars use invoice totals. Orders and cancelled documents '
                    'are excluded; the Day / Month / All chips above do not '
                    'change this six-month view.',
                    style: TextStyle(fontSize: 11, color: mutedOf(context)),
                  ),
                ]),
                _card('Old metal', [
                  _row('Gold equivalent',
                      '${Num.round3(t?.oldGold ?? 0).toStringAsFixed(3)} g'),
                  _row('Silver equivalent',
                      '${Num.round3(t?.oldSilver ?? 0).toStringAsFixed(3)} g'),
                  _row('Accepted value', inr(t?.oldMetalValue ?? 0),
                      bold: true, color: kGoldDark),
                ]),
                _card('Stock position', [
                  _row('Raw gold',
                      '${Num.round3(_weight(JewelleryStore.gold, JewelleryStore.stockRaw)).toStringAsFixed(3)} g'),
                  _row('Raw silver',
                      '${Num.round3(_weight(JewelleryStore.silver, JewelleryStore.stockRaw)).toStringAsFixed(3)} g'),
                  _row('Finished gold',
                      '${Num.round3(_weight(JewelleryStore.gold, JewelleryStore.stockFinished)).toStringAsFixed(3)} g'),
                  _row('Finished silver',
                      '${Num.round3(_weight(JewelleryStore.silver, JewelleryStore.stockFinished)).toStringAsFixed(3)} g'),
                  _row('Old gold',
                      '${Num.round3(_weight(JewelleryStore.gold, JewelleryStore.stockOld)).toStringAsFixed(3)} g'),
                  _row('Old silver',
                      '${Num.round3(_weight(JewelleryStore.silver, JewelleryStore.stockOld)).toStringAsFixed(3)} g'),
                ]),
                _card('Stock valuation', [
                  _row(
                    'Gold rate',
                    _valuation?.goldRate == null
                        ? 'Not set'
                        : '${moneyWhole(_valuation!.goldRate)}/g pure',
                  ),
                  _row(
                    'Silver rate',
                    _valuation?.silverRate == null
                        ? 'Not set'
                        : '${moneyWhole(_valuation!.silverRate)}/g pure',
                  ),
                  const Divider(height: 16),
                  _row(
                    'Raw gold',
                    '${_fine(JewelleryStore.gold, JewelleryStore.stockRaw)} g fine',
                    caption: inr(_valuation?.valueFor(
                            JewelleryStore.gold, JewelleryStore.stockRaw) ??
                        0),
                  ),
                  _row(
                    'Finished gold',
                    '${_fine(JewelleryStore.gold, JewelleryStore.stockFinished)} g fine',
                    caption: inr(_valuation?.valueFor(JewelleryStore.gold,
                            JewelleryStore.stockFinished) ??
                        0),
                  ),
                  _row(
                    'Old gold',
                    '${_fine(JewelleryStore.gold, JewelleryStore.stockOld)} g fine',
                    caption: inr(_valuation?.valueFor(
                            JewelleryStore.gold, JewelleryStore.stockOld) ??
                        0),
                  ),
                  _row(
                    'Raw silver',
                    '${_fine(JewelleryStore.silver, JewelleryStore.stockRaw)} g fine',
                    caption: inr(_valuation?.valueFor(
                            JewelleryStore.silver, JewelleryStore.stockRaw) ??
                        0),
                  ),
                  _row(
                    'Finished silver',
                    '${_fine(JewelleryStore.silver, JewelleryStore.stockFinished)} g fine',
                    caption: inr(_valuation?.valueFor(JewelleryStore.silver,
                            JewelleryStore.stockFinished) ??
                        0),
                  ),
                  _row(
                    'Old silver',
                    '${_fine(JewelleryStore.silver, JewelleryStore.stockOld)} g fine',
                    caption: inr(_valuation?.valueFor(
                            JewelleryStore.silver, JewelleryStore.stockOld) ??
                        0),
                  ),
                  const Divider(height: 16),
                  _row('Total stock value', inr(_valuation?.totalValue ?? 0),
                      bold: true, color: kGoldDark),
                  const SizedBox(height: 6),
                  Text(
                    'Fine grams × latest saved pure-metal rate. Old metal is '
                    'included as an asset; negative stock means a sale was '
                    'recorded before its purchase.',
                    style: TextStyle(fontSize: 11, color: mutedOf(context)),
                  ),
                ]),
                _card('Order pipeline', [
                  _row('Pending', '${_orders['Pending'] ?? 0}'),
                  _row('Ready', '${_orders['Ready'] ?? 0}'),
                  _row('Delivered', '${_orders['Delivered'] ?? 0}'),
                  _row('Cancelled', '${_orders['Cancelled'] ?? 0}'),
                ]),
                _card('Worker reserve', [
                  _row('Cash held by workers', inr(_workerCash)),
                  _row('Metal held by workers',
                      '${Num.round3(_workerGold).toStringAsFixed(3)} g'),
                  _row('Workers', '${_workers.length}'),
                ]),
                _card('Estimated vs final profit', [
                  _row('Estimated cost', inr(p?.cost ?? 0)),
                  _row('Actual cost', inr(p?.actualCost ?? 0)),
                  _row('Estimated profit', inr(p?.estimated ?? 0), bold: true),
                  _row('Final profit', inr(p?.finalProfit ?? 0),
                      bold: true, color: kGreen),
                  const SizedBox(height: 6),
                  Text(
                    'Estimated uses the recorded cost. Final uses actual item cost '
                    'where a worker order has supplied it. Returns are netted off.',
                    style: TextStyle(fontSize: 11, color: mutedOf(context)),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, Color? color, String? caption}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              caption == null ? label : '$label · $caption',
              style: TextStyle(fontSize: 12.5, color: mutedOf(context)),
            ),
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

/// A package-free grouped bar chart. Sales and purchases share one scale so
/// the two bars in a month are directly comparable; a zero month draws no bar
/// rather than a misleading sliver.
class _MonthlyBars extends StatelessWidget {
  const _MonthlyBars({required this.months});

  final List<JewelleryMonthTotal> months;

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) {
      return Text('No monthly documents yet.',
          style: TextStyle(fontSize: 12, color: mutedOf(context)));
    }
    final peak = months.fold<double>(
        0, (m, e) => math.max(m, math.max(e.sales, e.purchases)));
    final scale = peak <= 0 ? 1.0 : peak;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _legend(context, kGoldDark, 'Sales'),
            const SizedBox(width: 12),
            _legend(context, kRed, 'Purchases'),
            const Spacer(),
            Text('Peak ${inr(peak)}',
                style: TextStyle(fontSize: 11, color: mutedOf(context))),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final month in months)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (ctx, constraints) => Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: _bar(
                                    context,
                                    month.sales,
                                    scale,
                                    constraints.maxHeight,
                                    kGoldDark,
                                    '${month.label} sales ${inr(month.sales)}',
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: _bar(
                                    context,
                                    month.purchases,
                                    scale,
                                    constraints.maxHeight,
                                    kRed,
                                    '${month.label} purchases '
                                    '${inr(month.purchases)}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(month.label,
                            style: TextStyle(
                                fontSize: 10, color: mutedOf(context))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bar(
    BuildContext context,
    double value,
    double scale,
    double maxHeight,
    Color color,
    String tooltip,
  ) {
    if (value <= 0) return const SizedBox.shrink();
    final height = math.max(2.0, maxHeight * value / scale);
    return Tooltip(
      message: tooltip,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: mutedOf(context))),
      ],
    );
  }
}
