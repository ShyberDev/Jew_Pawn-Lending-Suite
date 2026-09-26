import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/format.dart';
import 'khata_screen.dart' show LoanBucket, loanBucket;
import 'palette.dart';
import 'widgets.dart';

/// Reports hub — Khata reports (blueprint §17) and Pawn reports (§14).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      initialIndex: widget.initialTab,
      length: 2,
      child: Scaffold(
        backgroundColor: bgOf(context),
        appBar: AppBar(
          title: const Text('Reports'),
          bottom: const TabBar(
            indicatorColor: kGold,
            labelColor: kInk,
            unselectedLabelColor: Color(0xFF8A8A80),
            labelStyle: TextStyle(fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'KHATA'),
              Tab(text: 'PAWN'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [KhataReportsView(), PawnReportsView()],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Khata reports
// ---------------------------------------------------------------------------

class KhataReportsView extends StatefulWidget {
  const KhataReportsView({super.key});

  @override
  State<KhataReportsView> createState() => _KhataReportsViewState();
}

class _KhataReportsViewState extends State<KhataReportsView> {
  Map<String, Object?> _r = {};
  bool _loading = true;

  Future<void> _load() async {
    final db = context.read<AppState>().db;
    final loans = await db.query('khatabook_loans');
    final collections = await db.query('khatabook_collections');
    final customers = await db.query('customers');
    final today = DateTime.now();
    final todayStr = today.toIso8601String().substring(0, 10);
    final weekAgo = today.subtract(const Duration(days: 7));
    final monthAgo = today.subtract(const Duration(days: 30));
    String dstr(DateTime d) => d.toIso8601String().substring(0, 10);

    double todayCol = 0, weekCol = 0, monthCol = 0, totalReceived = 0;
    final todayRows = <Map<String, Object?>>[];
    final weekRows = <Map<String, Object?>>[];
    final monthRows = <Map<String, Object?>>[];
    for (final c in collections) {
      final date = c['collection_date']?.toString() ?? '';
      final amt = Num.toDouble(c['amount']);
      totalReceived += amt;
      if (date == todayStr) {
        todayCol += amt;
        todayRows.add(c);
      }
      if (date.compareTo(dstr(weekAgo)) >= 0) {
        weekCol += amt;
        weekRows.add(c);
      }
      if (date.compareTo(dstr(monthAgo)) >= 0) {
        monthCol += amt;
        monthRows.add(c);
      }
    }

    double totalGiven = 0, outstanding = 0, overdueAmt = 0;
    int overdueCount = 0;
    final villageMap = <String, double>{};
    final villageCount = <String, int>{};
    final customerMap = <String, double>{};
    final overdueRows = <Map<String, Object?>>[];
    for (final l in loans) {
      totalGiven += Num.toDouble(l['principal_amount']);
      final active = (l['status']?.toString() ?? 'Active') == 'Active';
      final out = Num.toDouble(l['outstanding']);
      if (active) {
        outstanding += out;
        final village = l['village']?.toString() ?? 'General';
        villageMap[village] = Num.money(
            (villageMap[village] ?? 0) + Num.toDouble(out));
        villageCount[village] = (villageCount[village] ?? 0) + 1;
        final customer = l['customer_name']?.toString() ?? '-';
        customerMap[customer] =
            Num.money((customerMap[customer] ?? 0) + Num.toDouble(out));
        if (loanBucket(l, today) == LoanBucket.overdue) {
          overdueCount++;
          overdueAmt += Num.toDouble(out);
          overdueRows.add(l);
        }
      }
    }

    final badCredit =
        customers.where((c) => (c['rating']?.toString() ?? '') == 'Bad').length;
    final blocked = customers
        .where((c) =>
            (c['status']?.toString() ?? '') == 'Blocked' ||
            (c['status']?.toString() ?? '') == 'Inactive')
        .length;

    if (mounted) {
      setState(() {
        _r = {
          'today_col': Num.money(todayCol),
          'week_col': Num.money(weekCol),
          'month_col': Num.money(monthCol),
          'total_given': Num.money(totalGiven),
          'total_received': Num.money(totalReceived),
          'interest_earned': Num.money(totalReceived - totalGiven),
          'outstanding': Num.money(outstanding),
          'overdue_count': overdueCount,
          'overdue_amt': Num.money(overdueAmt),
          'today_rows': todayRows,
          'week_rows': weekRows,
          'month_rows': monthRows,
          'overdue_rows': overdueRows,
          'village_map': villageMap,
          'village_count': villageCount,
          'customer_map': customerMap,
          'bad_credit': badCredit,
          'blocked': blocked,
          'village_rows': [
            for (final e in villageMap.entries)
              {
                'name': e.key,
                'count': villageCount[e.key] ?? 0,
                'amount': e.value,
              }
          ]..sort((a, b) =>
              (b['amount'] as num).compareTo(a['amount'] as num)),
          'customer_rows': [
            for (final e in customerMap.entries)
              {'name': e.key, 'amount': e.value}
          ]..sort((a, b) =>
              (b['amount'] as num).compareTo(a['amount'] as num)),
        };
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _sheet(String title, Widget body) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Expanded(
                child: ListView(controller: controller, children: [body])),
          ],
        ),
      ),
    );
  }

  Widget _moneyListRow(Map<String, Object?> row, {String? date}) {
    return ListTile(
      title: Text(
          (date != null && date.isNotEmpty)
              ? '$date  ·  ${row['customer'] ?? row['name'] ?? '-'}'
              : (row['customer_name']?.toString() ??
                  row['customer']?.toString() ??
                  row['name']?.toString() ??
                  '-')),
      subtitle: row['village'] != null
          ? Text(row['village'].toString())
          : (row['count'] != null
              ? Text('${row['count']} active loan(s)')
              : const SizedBox.shrink()),
      trailing: Text('₹${moneyWhole(row['amount'] as num?)}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kGold));
    }
    final rows = <(IconData, String, String, VoidCallback)>[
      (
        Icons.today_outlined,
        "Today's collection",
        '₹${_r['today_col']}',
        () => _sheet("Today's collection",
            (_r['today_rows'] as List).isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No collections today.'))
                : Column(children: [
                    for (final c in _r['today_rows'] as List)
                      _moneyListRow(c as Map<String, Object?>,
                          date: fmtDate(c['collection_date'])),
                  ])),
      ),
      (
        Icons.weekend_outlined,
        'This week (7 days)',
        '₹${_r['week_col']}',
        () => _sheet('This week collection',
            (_r['week_rows'] as List).isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No collections this week.'))
                : Column(children: [
                    for (final c in _r['week_rows'] as List)
                      _moneyListRow(c as Map<String, Object?>,
                          date: fmtDate(c['collection_date'])),
                  ])),
      ),
      (
        Icons.date_range_outlined,
        'This month (30 days)',
        '₹${_r['month_col']}',
        () => _sheet('This month collection',
            (_r['month_rows'] as List).isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No collections this month.'))
                : Column(children: [
                    for (final c in _r['month_rows'] as List)
                      _moneyListRow(c as Map<String, Object?>,
                          date: fmtDate(c['collection_date'])),
                  ])),
      ),
      (
        Icons.north_east,
        'Total given (all time)',
        '₹${_r['total_given']}',
        () => _sheet('Total given — principal of all loans',
            const Center(
                heightFactor: 4,
                child: Text('Sum of all khata loan principal amounts.'))),
      ),
      (
        Icons.south_west,
        'Total received (all time)',
        '₹${_r['total_received']}',
        () => _sheet('Total received — all collections',
            const Center(
                heightFactor: 4,
                child: Text('Sum of every collection recorded.'))),
      ),
      (
        Icons.trending_up_outlined,
        'Interest earned',
        '₹${_r['interest_earned']}',
        () => _sheet('Interest earned (received − given)',
            const Center(
                heightFactor: 4,
                child:
                    Text('Total received minus total principal given.'))),
      ),
      (
        Icons.account_balance_wallet_outlined,
        'Outstanding overall',
        '₹${_r['outstanding']}',
        () => _sheet('Outstanding overall',
            const Center(
                heightFactor: 4,
                child: Text('Sum of outstanding on all active loans.'))),
      ),
      (
        Icons.warning_amber_outlined,
        'Overdue accounts',
        '${_r['overdue_count']} · ₹${_r['overdue_amt']}',
        () => _sheet('Overdue accounts',
            (_r['overdue_rows'] as List).isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No overdue loans. 🎉'))
                : Column(children: [
                    for (final c in _r['overdue_rows'] as List)
                      _moneyListRow(c as Map<String, Object?>),
                  ])),
      ),
      (
        Icons.location_on_outlined,
        'Village-wise',
        '${(_r['village_rows'] as List).length} khatas',
        () => _sheet('Village-wise outstanding',
            Column(children: [
              for (final c in _r['village_rows'] as List)
                _moneyListRow(c as Map<String, Object?>),
            ])),
      ),
      (
        Icons.people_outline,
        'Customer-wise',
        '${(_r['customer_rows'] as List).length} customers',
        () => _sheet('Customer-wise outstanding',
            Column(children: [
              for (final c in _r['customer_rows'] as List)
                _moneyListRow(c as Map<String, Object?>),
            ])),
      ),
      (
        Icons.block_outlined,
        'Bad credit / Blocked',
        '${_r['bad_credit']} bad · ${_r['blocked']} blocked',
        () => _sheet('Bad credit & blocked customers',
            const Center(
                heightFactor: 4,
                child: Text(
                    'Customers rated Bad appear here. Marked on the customer record.'))),
      ),
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final (icon, label, value, onTap) = rows[index];
        return Material(
          color: surfaceOf(context),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 19, color: kGoldDark),
            ),
            title: Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: inkOf(context))),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
            onTap: onTap,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Pawn reports (blueprint §14: period / metal / status filters + totals)
// ---------------------------------------------------------------------------

class PawnReportsView extends StatefulWidget {
  const PawnReportsView({super.key});

  @override
  State<PawnReportsView> createState() => _PawnReportsViewState();
}

class _PawnReportsViewState extends State<PawnReportsView> {
  String _period = 'All';
  String _metal = 'All';
  String _status = 'All';
  bool _loading = true;
  Map<String, Object?> _r = {};

  Future<void> _load() async {
    final db = context.read<AppState>().db;
    final loans = await db.query('pawn_loans');
    final items = await db.query('pawn_items');
    final releases = await db.query('pawn_releases');
    final today = DateTime.now();
    final year = today.year.toString();
    final month = today.toIso8601String().substring(0, 7);

    bool periodOk(String? date) {
      if (_period == 'All') return true;
      if (date == null) return false;
      if (_period == 'This year') return date.startsWith(year);
      return date.startsWith(month);
    }

    bool statusOk(String? status) {
      final s = status ?? 'Active';
      if (_status == 'All') return true;
      return s == _status;
    }

    // Loans in filter.
    final filtered = loans.where((l) =>
        periodOk(l['loan_date']?.toString()) &&
        statusOk(l['status']?.toString()));
    double principal = 0, interest = 0, receivable = 0;
    double goldReserve = 0, silverReserve = 0;
    final activeUuids = loans
        .where((l) => (l['status']?.toString() ?? 'Active') == 'Active')
        .map((l) => l['client_uuid']?.toString())
        .toSet();
    for (final l in filtered) {
      final out = Num.toDouble(l['balance']);
      principal += Num.toDouble(l['loan_amount']);
      interest += Num.toDouble(l['interest_accrued']);
      receivable += out;
    }
    for (final it in items) {
      final loanUuid = it['loan_uuid']?.toString();
      // Reserve only counts against active loans.
      if (loanUuid == null || !activeUuids.contains(loanUuid)) continue;
      final metal = it['metal_type']?.toString() ?? '';
      final w = Num.toDouble(it['net_weight']);
      if (_metal != 'All' && metal != _metal) continue;
      if (metal == 'Gold') {
        goldReserve += w;
      } else if (metal == 'Silver') {
        silverReserve += w;
      }
    }
    double realised = 0;
    int releasedCount = 0;
    for (final r in releases) {
      final date = r['release_date']?.toString();
      if (periodOk(date)) {
        realised += Num.toDouble(r['interest_paid']);
        releasedCount++;
      }
    }

    if (mounted) {
      setState(() {
        _r = {
          'active': filtered
              .where((l) => (l['status']?.toString() ?? 'Active') == 'Active')
              .length,
          'principal': Num.money(principal),
          'interest': Num.money(interest),
          'receivable': Num.money(receivable),
          'gold_reserve': Num.round3(goldReserve),
          'silver_reserve': Num.round3(silverReserve),
          'released_count': releasedCount,
          'realised': Num.money(realised),
          'rows': filtered.toList()
            ..sort((a, b) => (b['loan_date']?.toString() ?? '')
                .compareTo(a['loan_date']?.toString() ?? '')),
        };
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, key, values)
                  in [('Period', _period, ['All', 'This year', 'This month']),
                      ('Metal', _metal, ['All', 'Gold', 'Silver']),
                      ('Status', _status, ['All', 'Active', 'Released'])])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _filterChip(label, key, values),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kGold))
              : RefreshIndicator(
                  color: kGold,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _metricGrid(),
                      const SizedBox(height: 14),
                      Text('LOANS IN VIEW'.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: Color(0xFF8A6D14))),
                      const SizedBox(height: 6),
                      if ((_r['rows'] as List).isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child: Text('No pawn loans match these filters.')),
                        )
                      else ...[
                        for (final l in _r['rows'] as List)
                          _pawnRow(l as Map<String, Object?>),
                        const SizedBox(height: 6),
                        _rowFooter(),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String current, List<String> values) {
    Widget chip(String v) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(v),
            selected: current == v,
            selectedColor: kGold.withValues(alpha: .3),
            labelStyle: TextStyle(
                fontSize: 11.5,
                fontWeight: current == v ? FontWeight.w700 : FontWeight.w500),
            onSelected: (_) {
              if (label == 'Period') _period = v;
              if (label == 'Metal') _metal = v;
              if (label == 'Status') _status = v;
              setState(() => _loading = true);
              _load();
            },
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: mutedOf(context))),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [for (final v in values) chip(v)],
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String value, String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: color ?? kInk)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5, color: mutedOf(context))),
        ],
      ),
    );
  }

  Widget _metricGrid() {
    return Column(children: [
      Row(children: [
        Expanded(
            child: _metricCard(
                '${_r['active']}', 'Active loans in view')),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard('₹${_r['principal']}',
                'Principal outstanding', color: kGoldDark)),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard('₹${_r['interest']}',
                'Interest due', color: kRed)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: _metricCard('₹${_r['receivable']}',
                'Total receivable')),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard('${_r['gold_reserve']} g',
                'Gold reserve')),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard('${_r['silver_reserve']} g',
                'Silver reserve')),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: _metricCard(
                '${_r['released_count']}', 'Released'),
            ),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard('₹${_r['realised']}',
                'Interest realised', color: kGreen),
            ),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard('${(_r['rows'] as List).length}', 'Loans listed')),
      ]),
    ]);
  }

  Widget _pawnRow(Map<String, Object?> l) {
    final released = (l['status']?.toString() ?? 'Active') == 'Released';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(released ? Icons.check_circle_outline : Icons.lock_clock,
              size: 20, color: released ? kGreen : kGoldDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l['customer_name']?.toString() ?? '-',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: inkOf(context))),
                Text(
                    '${l['loan_date']}  ·  ${released ? 'Released' : 'Active'}'
                    '${l['release_date'] != null ? ' · ${l['release_date']}' : ''}',
                    style: TextStyle(
                        fontSize: 11, color: mutedOf(context))),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${moneyText(l['loan_amount'] as num?)}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              Text(released
                  ? 'Settled'
                  : 'Bal ₹${moneyText(l['balance'] as num?)}',
                  style: TextStyle(
                      fontSize: 10.5,
                      color: released ? kGreen : mutedOf(context))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowFooter() {
    final rows = _r['rows'] as List;
    double principal = 0, receivable = 0;
    for (final l in rows) {
      principal += Num.toDouble((l as Map<String, Object?>)['loan_amount']);
      receivable += Num.toDouble(l['balance']);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: lineOf(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${rows.length} loans',
              style: TextStyle(
                  color: inkOf(context), fontWeight: FontWeight.w700)),
          Text('₹${moneyText(principal)} · ₹${moneyText(receivable)} bal',
              style: TextStyle(
                  color: mutedOf(context), fontSize: 12)),
        ],
      ),
    );
  }
}