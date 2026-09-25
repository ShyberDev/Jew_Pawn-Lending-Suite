import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/format.dart';
import 'customers_screen.dart';
import 'khata_screen.dart';
import 'pawn_screen.dart';
import 'reports_screen.dart';
import 'sync_screen.dart';

const kBg = Color(0xFFEFECE4);
const kGold = Color(0xFFC9A227);
const kInk = Color(0xFF2B2B2B);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, Object?> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final stats = await context.read<AppState>().dashboard();
    if (mounted) {
      setState(() {
        _stats = stats;
        _loading = false;
      });
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    await _refresh();
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Coming in a later release'),
        duration: Duration(seconds: 1),
      ));
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _dateLine {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const d = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    return '${d[now.weekday - 1]}, ${now.day} ${m[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: kGold,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _header(state),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                      child: CircularProgressIndicator(color: kGold)),
                )
              else ...[
                _kpiStrip(state),
                const SizedBox(height: 22),
                _sectionTitle('Core Modules'),
                const SizedBox(height: 8),
                _modulesGrid(state),
                const SizedBox(height: 22),
                _sectionTitle('More'),
                const SizedBox(height: 8),
                _moreRow(state),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppState state) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: kInk)),
              const SizedBox(height: 2),
              Text(_dateLine,
                  style: TextStyle(
                      fontSize: 13, color: kInk.withValues(alpha: .55))),
            ],
          ),
        ),
        if (state.pending > 0)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Badge(
              backgroundColor: kGold,
              label: Text('${state.pending}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        _roundIcon(
          state.syncing
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: kGold))
              : const Icon(Icons.sync, color: kInk),
          onTap: state.syncing
              ? null
              : () async {
                  try {
                    final summary = await state.sync();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Synced: $summary')));
                    await _refresh();
                  } catch (error) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Sync failed: $error')));
                  }
                },
        ),
        const SizedBox(width: 6),
        _roundIcon(const Icon(Icons.logout, color: kInk),
            onTap: () => state.logout()),
      ],
    );
  }

  Widget _kpiStrip(AppState state) {
    final kpi = <(IconData, String, String)>[
      (Icons.today_outlined, 'Collected today',
          '₹${moneyWhole(_stats['collected_today'] as num?)}'),
      (Icons.account_balance_outlined, 'Pawn outstanding',
          '₹${moneyWhole(_stats['pawn_out'] as num?)}'),
      (Icons.account_balance_wallet_outlined, 'Active pawns',
          '${_stats['active_pawn'] ?? 0}'),
      (Icons.menu_book_outlined, 'Active khata',
          '${_stats['khatabook_active'] ?? 0}'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 3.1,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final (icon, label, value) in kpi)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: kGold),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: kInk)),
                      Text(label,
                          style: TextStyle(
                              fontSize: 10.5, color: kInk.withValues(alpha: .55))),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title.toUpperCase(),
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Color(0xFF8A6D14)));
  }

  Widget _modulesGrid(AppState state) {
    final modules = <(IconData, String, String, VoidCallback)>[
      (Icons.menu_book_outlined, 'Khatabook',
          '${_stats['khatabook_active'] ?? 0} active · Khata & villages',
          () => _open(const KhataGroupsScreen())),
      (Icons.account_balance_outlined, 'Pawn Loans',
          '${_stats['active_pawn'] ?? 0} active · ₹${moneyWhole(_stats['pawn_out'] as num?)} out',
          () => _open(const PawnScreen())),
      (Icons.diamond_outlined, 'Jewellery', 'Coming soon', _comingSoon),
      (Icons.book_outlined, 'Cashbook', 'Coming soon', _comingSoon),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.25,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (final (icon, title, subtitle, onTap) in modules)
          _moduleCard(icon, title, subtitle, onTap),
      ],
    );
  }

  Widget _moduleCard(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: const Color(0xFF9A7B10)),
              ),
              const Spacer(),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
              const SizedBox(height: 1),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5, color: kInk.withValues(alpha: .5))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreRow(AppState state) {
    final rows = <(IconData, String, String, VoidCallback)>[
      (Icons.people_outline, 'Customers',
          '${_stats['customers'] ?? 0} saved',
          () => _open(const CustomersScreen())),
      (Icons.bar_chart_outlined, 'Reports',
          'Khata & Pawn reports', () => _open(const ReportsScreen())),
      (Icons.sync, 'Sync',
          state.pending > 0
              ? '${state.pending} change(s) waiting'
              : 'All changes synced',
          () => _open(const SyncScreen())),
    ];
    return Column(
      children: [
        for (final (icon, title, subtitle, onTap) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                dense: true,
                leading: Icon(icon, color: kGold),
                title: Text(title,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: kInk)),
                subtitle: Text(subtitle,
                    style: TextStyle(
                        fontSize: 11, color: kInk.withValues(alpha: .55))),
                trailing: const Icon(Icons.chevron_right, color: kInk),
                onTap: onTap,
              ),
            ),
          ),
      ],
    );
  }

  Widget _roundIcon(Widget child, {VoidCallback? onTap}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}