import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/format.dart';
import 'palette.dart';
import 'pawn_screen.dart';
import 'reports_screen.dart';

/// Pawn dashboard (Stitch pawn/01-dashboard): outstanding, reserve and age
/// distribution with quick links into the pawn list.
class PawnDashboardScreen extends StatefulWidget {
  const PawnDashboardScreen({super.key});

  @override
  State<PawnDashboardScreen> createState() => _PawnDashboardScreenState();
}

class _PawnDashboardScreenState extends State<PawnDashboardScreen> {
  Map<String, Object?> _r = {};
  bool _loading = true;

  Future<void> _load() async {
    final db = context.read<AppState>().db;
    final loans = await db.query('pawn_loans');
    final items = await db.query('pawn_items');
    final releases = await db.query('pawn_releases');
    final today = DateTime.now();

    double principal = 0, interest = 0, receivable = 0;
    int activeCount = 0;
    double gold = 0, silver = 0;
    final buckets = {'0-3M': 0, '3-6M': 0, '6-12M': 0, '12M+': 0};
    final recent = <Map<String, Object?>>[];

    final activeUuids = loans
        .where((l) => (l['status']?.toString() ?? 'Active') == 'Active')
        .toList();
    for (final l in activeUuids) {
      final out = Num.toDouble(l['balance']);
      principal += Num.toDouble(l['loan_amount']);
      interest += Num.toDouble(l['interest_accrued']);
      receivable += out;
      activeCount++;
      final start =
          DateTime.tryParse(l['loan_date']?.toString() ?? '') ?? today;
      final months = today.difference(start).inDays / 30.0;
      final key = months < 3
          ? '0-3M'
          : months < 6
              ? '3-6M'
              : months < 12
                  ? '6-12M'
                  : '12M+';
      buckets[key] = (buckets[key] ?? 0) + 1;
    }
    for (final it in items) {
      if (it['loan_uuid'] == null ||
          !activeUuids.any((l) => l['client_uuid'] == it['loan_uuid'])) {
        continue;
      }
      final metal = it['metal_type']?.toString() ?? '';
      final w = Num.toDouble(it['net_weight']);
      if (metal == 'Gold') gold += w;
      if (metal == 'Silver') silver += w;
    }
    final oldCount = buckets['12M+'] ?? 0;
    final sorted = [...activeUuids]
      ..sort((a, b) => (b['loan_date']?.toString() ?? '')
          .compareTo(a['loan_date']?.toString() ?? ''));
    recent.addAll(sorted.take(3));

    int released = 0;
    double realised = 0, principalReturned = 0;
    for (final r in releases) {
      released++;
      realised += Num.toDouble(r['interest_paid']);
      principalReturned += Num.toDouble(r['principal_paid']);
    }

    if (mounted) {
      setState(() {
        _r = {
          'principal': Num.money(principal),
          'interest': Num.money(interest),
          'receivable': Num.money(receivable),
          'active': activeCount,
          'gold': Num.round3(gold),
          'silver': Num.round3(silver),
          'buckets': buckets,
          'old_count': oldCount,
          'recent': recent,
          'released': released,
          'realised': Num.money(realised),
          'principal_returned': Num.money(principalReturned),
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

  void _openPawn(String filter) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => PawnScreen(filter: filter)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(
        title: const Text('Pawn Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ReportsScreen(initialTab: 1))),
          ),
          IconButton(
            tooltip: 'Above the list',
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PawnScreen())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : RefreshIndicator(
              color: kGold,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _heroCard(),
                  const SizedBox(height: 12),
                  _statsRow(),
                  const SizedBox(height: 16),
                  _section('PAWN AGE GROUPS'),
                  const SizedBox(height: 8),
                  _ageRow(),
                  const SizedBox(height: 16),
                  _section('QUICK VIEWS'),
                  const SizedBox(height: 8),
                  _quickTile(
                      Icons.payments_outlined,
                      'Interest due',
                      'Active loans with accrued interest',
                      () => _openPawn('interest')),
                  _quickTile(Icons.hourglass_bottom_outlined,
                      'Old pawns (12M+)',
                      '${_r['old_count']} loans older than a year',
                      () => _openPawn('old')),
                  _quickTile(Icons.history,
                      'Recently added',
                      'Latest ${(_r['recent'] as List).length} pawn loans',
                      () => _openPawn('recent')),
                  _quickTile(Icons.gpp_good_outlined,
                      'Released & settled',
                      '${_r['released']} released · '
                          '₹${_r['realised']} interest realised',
                      () => _openPawn('released')),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _section(String title) => Text(title,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Color(0xFF8A6D14)));

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3A2E0E), Color(0xFF6B5417)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PRINCIPAL OUTSTANDING',
              style: TextStyle(
                  fontSize: 11, letterSpacing: 1, color: Color(0xFFE7D48B))),
          const SizedBox(height: 4),
          Text('₹${_r['principal']}',
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 12),
          Row(
            children: [
              _heroStat('Interest due', '₹${_r['interest']}'),
              const SizedBox(width: 22),
              _heroStat('Total receivable', '₹${_r['receivable']}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: Colors.white.withValues(alpha: .75))),
      ],
    );
  }

  Widget _statCard(String value, String label, {String? unit}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value${unit ?? ''}',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: inkOf(context))),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5, color: mutedOf(context))),
        ],
      ),
    );
  }

  Widget _statsRow() {
    return Row(children: [
      Expanded(child: _statCard('${_r['active']}', 'Active pawns')),
      const SizedBox(width: 8),
      Expanded(child: _statCard('${_r['gold']}', 'Gold reserve', unit: ' g')),
      const SizedBox(width: 8),
      Expanded(
          child: _statCard('${_r['silver']}', 'Silver reserve', unit: ' g')),
    ]);
  }

  Widget _ageRow() {
    final buckets = _r['buckets'] as Map<String, Object?>;
    final order = ['0-3M', '3-6M', '6-12M', '12M+'];
    return Row(
      children: [
        for (final key in order)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: key == '12M+'
                      ? kRedSoft
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text('${buckets[key] ?? 0}',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color:
                                key == '12M+' ? kRed : kInk)),
                    Text(key,
                        style: TextStyle(
                            fontSize: 10,
                            color: mutedOf(context))),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _quickTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
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
          title: Text(title,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: inkOf(context))),
          subtitle: Text(subtitle,
              style: TextStyle(fontSize: 11, color: mutedOf(context))),
          trailing: Icon(Icons.chevron_right, color: inkOf(context)),
          onTap: onTap,
        ),
      ),
    );
  }
}