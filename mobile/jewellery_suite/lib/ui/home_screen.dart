import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/format.dart';
import 'about_app_screen.dart';
import 'customers_screen.dart';
import 'history_screen.dart';
import 'interest_calculator_screen.dart';
import 'khata_screen.dart';
import 'palette.dart';
import 'pawn_screen.dart';
import 'photo_local.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';
import 'user_details_screen.dart';

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
    comingSoon(context);
  }

  /// Coming-soon used inside the side drawer: close the drawer first so the
  /// snackbar is actually visible.
  void _drawerComingSoon() {
    Navigator.pop(context);
    comingSoon(context);
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
      backgroundColor: bgOf(context),
      drawer: _buildDrawer(state),
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
                _kpiStrip(),
                const SizedBox(height: 18),
                _sectionTitle('Core Modules'),
                const SizedBox(height: 6),
                _modulesGrid(),
                const SizedBox(height: 18),
                _sectionTitle('More'),
                const SizedBox(height: 6),
                _moreRow(state),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Left side-dashboard (opens from the Home button). Payments/QR first,
  /// then User Details, Customers, Sync, Settings, appearance & system
  /// settings, About App, Help & Support, and Logout at the bottom.
  Widget _buildDrawer(AppState state) {
    void go(Widget screen) {
      Navigator.pop(context);
      _open(screen);
    }

    Widget sec(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Color(0xFF8A6D14))),
        );

    Widget tile(IconData icon, String title, VoidCallback onTap,
        {String? subtitle,
        Widget? trailing,
        Color? color}) {
      return ListTile(
        dense: true,
        leading: Icon(icon, size: 22, color: color ?? kGoldDark),
        title: Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: trailing ?? const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      );
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: kGold.withValues(alpha: .16),
                    backgroundImage: state.userPhoto.isNotEmpty
                        ? photoProvider(state.userPhoto)
                        : null,
                    child: state.userPhoto.isEmpty
                        ? const Icon(Icons.diamond_outlined,
                            size: 22, color: kGoldDark)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Jewellery Suite',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                        Text(
                          state.userName.isNotEmpty
                              ? state.userName
                              : 'Version 1.0.9 • user details',
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: .55)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            // v1.0.9 order requested by the shop: Payments → General (User
            // details, Customers) → System → Logout. Languages, Notifications,
            // Reminders and Dark mode live in Settings only (no duplicates).
            sec('Payments'),
            tile(Icons.qr_code_2, 'QR codes',
                () => go(const QrCodesScreen()),
                subtitle: 'Bank / UPI QR codes'),
            sec('General'),
            tile(Icons.person_outline, 'User Details',
                () => go(const UserDetailsScreen()),
                subtitle: 'Photo, phone, email'),
            tile(Icons.people_outline, 'Customers',
                () => go(const CustomersScreen()),
                subtitle: '${_stats['customers'] ?? 0} saved'),
            sec('System'),
            tile(Icons.fingerprint, 'Biometric & screen lock',
                _drawerComingSoon),
            tile(Icons.lock_outline, 'Change password', _drawerComingSoon),
            tile(Icons.settings_outlined, 'Settings',
                () => go(const SettingsScreen()),
                subtitle: 'Zoom, dark mode, languages & more'),
            tile(Icons.info_outline, 'About App',
                () => go(const AboutAppScreen()),
                subtitle: 'Version 1.0.9, size & data'),
            tile(Icons.support_agent, 'Help & Support', _drawerComingSoon),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: kRed),
              title: const Text('Logout',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kRed)),
              onTap: () => state.logout(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _header(AppState state) {
    // Home button: the user's profile photo if one was uploaded, else the
    // home icon. It opens the side dashboard. NOTE: the Builder is required —
    // this State's own context sits ABOVE the Scaffold, so Scaffold.of() on it
    // throws and the drawer would never open.
    return Row(
      children: [
        Builder(
          builder: (inner) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Scaffold.of(inner).openDrawer(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white,
                backgroundImage: state.userPhoto.isNotEmpty
                    ? photoProvider(state.userPhoto)
                    : null,
                child: state.userPhoto.isEmpty
                    ? Icon(Icons.home, color: inkOf(context), size: 22)
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: inkOf(context))),
              const SizedBox(height: 2),
              Text(_dateLine,
                  style: TextStyle(
                      fontSize: 13, color: mutedOf(context))),
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
              : Icon(Icons.sync, color: inkOf(context)),
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
      ],
    );
  }

  Widget _kpiStrip() {
    final kpi = <(IconData, String, String)>[
      (Icons.today_outlined, 'Collected today',
          '₹${moneyWhole(_stats['collected_today'] as num?)}'),
      (Icons.account_balance_outlined, 'Pawn outstanding',
          '₹${moneyWhole(_stats['pawn_out'] as num?)}'),
      (Icons.account_balance_wallet_outlined, 'Pawns',
          '${_stats['active_pawn'] ?? 0}'),
      (Icons.menu_book_outlined, 'Active khata',
          '${_stats['khatabook_active'] ?? 0}'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final (icon, label, value) in kpi)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: surfaceOf(context),
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
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: inkOf(context))),
                      Text(label,
                          style: TextStyle(
                              fontSize: 10.5, color: mutedOf(context))),
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

  /// Core modules: logo + name only, all the SAME smaller size.
  Widget _modulesGrid() {
    final modules = <(IconData, String, VoidCallback)>[
      (Icons.menu_book_outlined, 'Khatabook',
          () => _open(const KhataGroupsScreen())),
      (Icons.account_balance_outlined, 'Pawn Loans',
          () => _open(const PawnScreen())),
      (Icons.account_balance_wallet_outlined, 'Cashbook', _comingSoon),
      (Icons.diamond_outlined, 'Jewellery', _comingSoon),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final (icon, title, onTap) in modules)
          _moduleCard(icon, title, onTap),
      ],
    );
  }

  Widget _moduleCard(IconData icon, String title, VoidCallback onTap) {
    return Material(
      color: surfaceOf(context),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: const Color(0xFF9A7B10)),
              ),
              const SizedBox(height: 3),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: inkOf(context))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreRow(AppState state) {
    final rows = <(IconData, String, String, VoidCallback)>[
      (Icons.bar_chart_outlined, 'Reports',
          'Khata & Pawn reports', () => _open(const ReportsScreen())),
      (Icons.history, 'History',
          'Recent activity & deletions', () => _open(const HistoryScreen())),
      (Icons.calculate_outlined, 'Interest Calculator',
          'Normal & compound interest, date range',
          () => _open(const InterestCalculatorScreen())),
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
              color: surfaceOf(context),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                dense: true,
                leading: Icon(icon, color: kGold),
                title: Text(title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: inkOf(context))),
                subtitle: Text(subtitle,
                    style: TextStyle(
                        fontSize: 11, color: mutedOf(context))),
                trailing: Icon(Icons.chevron_right, color: inkOf(context)),
                onTap: onTap,
              ),
            ),
          ),
      ],
    );
  }

  Widget _roundIcon(Widget child, {VoidCallback? onTap}) {
    return Material(
      color: surfaceOf(context),
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