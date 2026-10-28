import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/migration_v11.dart';
import '../data/migration_v12.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import '../util/ids.dart';
import '../util/khata_schedule.dart';
import 'customer_profile_screen.dart';
import 'customers_screen.dart';
import 'location_picker_screen.dart';
import 'admin_guard.dart';
import 'palette.dart';
import 'reports_screen.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Loan schedule helpers (mirror the server's frequency model).
// ---------------------------------------------------------------------------

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? _parseDate(Object? v) => DateTime.tryParse(v?.toString() ?? '');

/// Next installment due for a khata loan (null once the balance is cleared).
///
/// v1.0.11: owing anything at all means there IS a due date. A part-payment
/// (e.g. 400 paid towards 800) does **not** clear the due — the member stays
/// in the due list until the outstanding reaches zero.
DateTime? loanNextDue(Map<String, Object?> loan, DateTime today) {
  if (Num.toDouble(loan['outstanding']) <= 0) return null;
  final start = _parseDate(loan['start_date'] ?? loan['loan_date']);
  if (start == null) return null;
  final freq = _frequencyName(loan['collection_frequency']?.toString());
  if (MigrationV11.isInterestOnly(loan)) {
    // Interest-only principal is never scheduled: the next due is the current
    // interest period, and nothing is due once interest is clear.
    if (Num.toDouble(loan['interest_outstanding'] ?? 0) <= 0) return null;
    final elapsed = _periodsElapsed(_day(start), _day(today), freq);
    return _day(KhataSchedule.dueDate(
        _day(start), freq, (elapsed < 0 ? 0 : elapsed) + 1));
  }
  final paid = (loan['paid_installments'] as num?)?.toInt() ?? 0;
  final count = (loan['installment_count'] as num?)?.toInt() ?? 0;
  // Schedule finished by the counter but money still out: it needs chasing
  // now, so it is due today.
  if (count > 0 && paid >= count) return _day(today);
  // Installment paid+1 is next; installment 1 falls one interval after start.
  return _day(KhataSchedule.dueDate(_day(start), freq, paid + 1));
}

/// Canonical frequency name for scheduling (calendar months for Monthly).
String _frequencyName(String? raw) {
  final s = (raw ?? '').toLowerCase();
  if (s.contains('bi')) return 'Biweekly';
  if (s.contains('month')) return 'Monthly';
  return 'Weekly';
}

/// Full periods elapsed between two day-precision dates.
int _periodsElapsed(DateTime start, DateTime today, String freq) {
  if (freq == 'Monthly') {
    var n = 0;
    while (!_day(KhataSchedule.dueDate(start, freq, n + 1)).isAfter(today)) {
      n++;
    }
    return n;
  }
  final step = freq == 'Biweekly' ? 14 : 7;
  final diff = today.difference(start).inDays ~/ step;
  return diff < 0 ? 0 : diff;
}

/// v1.0.11 colour rule, as a pure function so it can be tested: a reminder only
/// turns a member row BLUE when the promised date is still in the FUTURE.
/// A reminder set to today — or a date already passed — stays DUE (red).
bool reminderIsLater(DateTime? reminder, DateTime today) =>
    reminder != null && _day(reminder).isAfter(_day(today));

/// Is anything DUE right now (the date has arrived or already passed)?
bool memberIsDue(int overdueLoans, bool anyDueToday) =>
    overdueLoans > 0 || anyDueToday;

enum LoanBucket { overdue, dueToday, upcoming, onSchedule }

LoanBucket loanBucket(Map<String, Object?> loan, DateTime today) {
  final due = loanNextDue(loan, today);
  if (due == null) return LoanBucket.onSchedule;
  final late = _day(today).difference(due).inDays;
  if (late > 0) return LoanBucket.overdue;
  if (late == 0) return LoanBucket.dueToday;
  if (late >= -7) return LoanBucket.upcoming;
  return LoanBucket.onSchedule;
}

String? _khataOf(Map<String, Object?> row) {
  final v = row['village']?.toString();
  return (v == null || v.trim().isEmpty) ? null : v;
}

class _Chip {
  const _Chip(this.label, this.bg, this.fg);
  final String label;
  final Color bg;
  final Color fg;
}

/// The due chip on a member row: date first, amount always.
///
/// - No next due date at all → green ON TIME (everything cleared).
/// - Future date (first schedule due, Tomorrow / Next-week / Next-month /
///   Calendar reminder) → blue with the date. A new loan therefore shows its
///   first due in blue from day one.
/// - Today → red DUE TODAY. Past → red DUE X DAYS AGO.
/// The amount is the member's due figure (today + arrears), never the full
/// outstanding.
_Chip _dueChip(BuildContext context, _MemberRow r) {
  final next = r.nextDue == null
      ? null
      : DateTime(r.nextDue!.year, r.nextDue!.month, r.nextDue!.day);
  if (next == null) {
    return _Chip('ON TIME', greenSoftOf(context), kGreen);
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (next.isAfter(today)) {
    // Future date: name the upcoming installment, not today's (zero) dues.
    final amount = '₹${moneyWholeDown(r.upcoming)}';
    return _Chip('DUE ${fmtDate(next.toIso8601String())} $amount',
        blueSoftOf(context), kBlue);
  }
  final amount = '₹${moneyWholeDown(r.due)}';
  if (next == today) {
    return _Chip('DUE TODAY $amount', redSoftOf(context), kRed);
  }
  final late = today.difference(next).inDays;
  return _Chip('DUE $late DAY${late == 1 ? '' : 'S'} AGO $amount',
      redSoftOf(context), kRed);
}

// ---------------------------------------------------------------------------
// Khata list (villages + General group), matching Stitch 02-khata-list.
// ---------------------------------------------------------------------------

class KhataGroupsScreen extends StatefulWidget {
  const KhataGroupsScreen({super.key});

  @override
  State<KhataGroupsScreen> createState() => _KhataGroupsScreenState();
}

class _KhataGroupsScreenState extends State<KhataGroupsScreen> {
  bool _loading = true;
  List<Map<String, Object?>> _khatas = [];
  double _totalPrincipal = 0;
  double _totalOutstanding = 0;
  int _totalMembers = 0;
  int _overdueToday = 0;
  double _collectedToday = 0;

  /// True while a khata tile is being dragged (shows the trash bin).
  bool _dragActive = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    final villages =
        await state.db.query('villages', orderBy: 'village_name asc');
    final customers = await state.db.query('customers');
    final loans = await state.db.query('khatabook_loans');
    final today = DateTime.now();
    final todayIso = today.toIso8601String().substring(0, 10);

    // v1.0.11: what was collected today, across every khata.
    final todaysCollections = await state.db.query('khatabook_collections',
        where: 'collection_date = ?', whereArgs: [todayIso]);
    final collectedToday = Num.rupees(todaysCollections.fold<double>(
        0, (s, c) => s + Num.toDouble(c['amount'])));

    // A loan belongs to the khata of its CUSTOMER (the customer's record is
    // the source of truth). Grouping by the loan's own village column made this
    // page disagree with the member list, which groups customers.
    //
    // Matched by the customer's uuid first, and only then by name. Keying on
    // the name alone silently merged two people who share one: the map kept
    // whichever was read last, so one Ravi's loans were counted in the other
    // Ravi's khata and every village total came out wrong. Name is now only a
    // fallback for rows written before the uuid was stored.
    final villageByUuid = <String, String?>{};
    final villageByName = <String, String?>{};
    for (final c in customers) {
      final village = _khataOf(c);
      final uuid = c['client_uuid']?.toString() ?? '';
      if (uuid.isNotEmpty) villageByUuid[uuid] = village;
      final name = c['customer_name']?.toString() ?? '';
      // Only claim a name when it is unique, so an ambiguous name falls
      // through to the loan's own village rather than picking a wrong one.
      villageByName[name] = villageByName.containsKey(name) ? null : village;
    }
    String villageOfLoan(Map<String, Object?> l) {
      // v9: customer_uuid is the identity. `customer` and `customer_name` are
      // fallbacks for rows written before the uuid existed.
      for (final key in const ['customer_uuid', 'customer']) {
        final owner = l[key]?.toString() ?? '';
        if (owner.isNotEmpty && villageByUuid.containsKey(owner)) {
          return villageByUuid[owner] ?? '';
        }
      }
      final name = l['customer_name']?.toString() ?? '';
      if (villageByName.containsKey(name)) {
        return villageByName[name] ?? '';
      }
      return _khataOf(l) ?? '';
    }

    final built = <Map<String, Object?>>[];
    double totalPrin = 0;
    double totalOut = 0;
    int totalMembers = 0;
    int overdue = 0;

    void addKhata(String name, String type) {
      final members = customers.where((c) => _khataOf(c) == name).toList();
      final khataLoans = loans
          .where((l) =>
              villageOfLoan(l) == name && isActiveKhataStatus(l['status']))
          .toList();
      double prin = 0;
      double out = 0;
      int due = 0;
      for (final l in khataLoans) {
        prin += Num.toDouble(l['principal_amount']);
        final o = Num.toDouble(l['outstanding']);
        out += o;
        if (loanBucket(l, today) == LoanBucket.overdue) due++;
        overdue +=
            (LoanBucket.overdue == loanBucket(l, today)) ? (o > 0 ? 1 : 0) : 0;
      }
      totalPrin += prin;
      totalOut += out;
      totalMembers += members.length;
      built.add({
        'name': name,
        'type': type,
        'members': members.length,
        'principal': Num.rupees(prin),
        'outstanding': Num.rupees(out),
        'overdue': due,
      });
    }

    for (final v in villages) {
      final vName = v['village_name']?.toString() ?? '-';
      addKhata(
        vName,
        MigrationV12.isLossKhata(vName)
            ? 'Loss'
            : ((v['khata_type']?.toString().isNotEmpty ?? false)
                ? v['khata_type'].toString()
                : 'Village Location'),
      );
    }
    // General group: customers without any khata/village.
    if (customers.any((c) => _khataOf(c) == null)) {
      addKhata('General', 'General');
    }
    if (!built.any((k) => MigrationV12.isLossKhata(k['name']?.toString()))) {
      addKhata(MigrationV12.lossVillageName, 'Loss');
    }
    // Loss Khata is always pinned to the very bottom of all Khatas.
    built.sort((a, b) {
      final aLoss = MigrationV12.isLossKhata(a['name']?.toString()) ||
          a['type'] == 'Loss';
      final bLoss = MigrationV12.isLossKhata(b['name']?.toString()) ||
          b['type'] == 'Loss';
      if (aLoss && !bLoss) return 1;
      if (!aLoss && bLoss) return -1;
      return 0;
    });

    overdue = built.fold<int>(0, (s, k) => s + (k['overdue'] as int));

    if (mounted) {
      setState(() {
        _khatas = built;
        _totalPrincipal = Num.rupees(totalPrin);
        _totalOutstanding = Num.rupees(totalOut);
        _totalMembers = totalMembers;
        _overdueToday = overdue;
        _collectedToday = collectedToday;
        _loading = false;
      });
    }
  }

  Future<void> _openCreate() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const KhataCreateScreen()));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(
        title: const Text('Khata Books'),
        actions: [
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ReportsScreen())),
          ),
          IconButton(
            tooltip: 'New Khata',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _openCreate,
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            color: kGold,
            onRefresh: _refresh,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kGold))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
                    children: [
                      _summaryCard(),
                      const SizedBox(height: 14),
                      Text('YOUR KHATAS'.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: Color(0xFF8A6D14))),
                      const SizedBox(height: 8),
                      if (_khatas.isEmpty)
                        const _EmptyState(
                            icon: Icons.menu_book_outlined,
                            message:
                                'No khatas yet. Tap + to create one (village, personal or business).')
                      else
                        for (final k in _khatas) _khataRow(k),
                    ],
                  ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: DeleteTrashTarget(
                visible: _dragActive,
                onDrop: (p) async {
                  setState(() => _dragActive = false);
                  return p.drop();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('INVESTMENT',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            color: Color(0xFFE7D48B))),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('₹${moneyWholeDown(_totalPrincipal)}',
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('OUTSTANDING',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            color: Color(0xFFE7D48B))),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('₹${moneyWholeDown(_totalOutstanding)}',
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ],
                ),
              ),
              // v1.0.11: what actually came in today.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('COLLECTED',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            color: Color(0xFFE7D48B))),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('₹${moneyWholeDown(_collectedToday)}',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text('Today',
              style: TextStyle(fontSize: 10.5, color: Color(0xFFE7D48B))),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _miniStat('$_totalMembers', 'Members')),
              const SizedBox(width: 18),
              Expanded(
                  child: _miniStat('$_overdueToday', 'Overdue accounts')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              maxLines: 1,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
        Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11, color: Colors.white.withValues(alpha: .7))),
      ],
    );
  }

  Widget _khataRow(Map<String, Object?> k) {
    final type = k['type']?.toString() ?? 'Village Location';
    // Loss Khata is visually distinct and can never be deleted.
    final isLoss = MigrationV12.isLossKhata(k['name']?.toString());
    final IconData icon = isLoss
        ? Icons.warning_amber_outlined
        : type.toLowerCase().contains('personal')
            ? Icons.person_outline
            : type.toLowerCase().contains('business')
                ? Icons.storefront_outlined
                : Icons.location_on_outlined;
    final accent = isLoss ? kRed : kGoldDark;
    final overdue = (k['overdue'] as int? ?? 0);
    return DragToDeleteTile(
      onDragChanged: (v) => setState(() => _dragActive = v),
      payload: DeletePayload(
        drop: () async {
          if (isLoss) {
            _toast(context, 'Loss Khata cannot be deleted.');
            return false;
          }
          final granted = await askPasswordIfEnabled(
              context, context.read<AppState>(),
              actionId: 'khata_delete',
              action: 'delete',
              detail: k['name']?.toString());
          // Password prompt was async - the row may have been swiped away.
          if (!mounted) return false;
          if (granted != true) {
            _toast(context, 'Delete cancelled / wrong password.');
            return false;
          }
          await _performDeleteKhata(k);
          return true;
        },
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: surfaceOf(context),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => KhataCustomersScreen(
                        khataName: k['name']?.toString() ?? '',
                        khataType: type)),
              );
              await _refresh();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (isLoss ? kRed : kGold).withValues(alpha: .14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 21, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(k['name']?.toString() ?? '-',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: inkOf(context))),
                          ),
                          // v1.0.9: the "Village Location" tag is gone — it
                          // squeezed the village name on big-font phones. The
                          // icon above still shows the khata type.
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          [
                            '${k['members'] ?? 0} member(s)',
                            if ((k['principal'] as num?) != null &&
                                Num.toDouble(k['principal']) > 0)
                              '₹${moneyWholeDown(k['principal'] as num?)} invested',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: mutedOf(context)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                              '₹${moneyWholeDown(k['outstanding'] as num?)}',
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: inkOf(context))),
                        ),
                        const SizedBox(height: 3),
                        if (overdue > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: redSoftOf(context),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('$overdue overdue',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: kRed)),
                          )
                        else
                          const Text('All clear',
                              maxLines: 1,
                              style:
                                  TextStyle(fontSize: 10.5, color: kGreen)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Performs the khata deletion (called after the admin gate): removes its
  /// customers, loans, collections, givens, refinances and frees member IDs.
  Future<void> _performDeleteKhata(Map<String, Object?> k) async {
    final name = k['name']?.toString() ?? '';
    if (MigrationV12.isLossKhata(name)) {
      _toast(context, 'Loss Khata cannot be deleted.');
      return;
    }
    final state = context.read<AppState>();
    final db = state.db;
    // Find the khata's customers (General = customers without a village).
    final customers = name == 'General'
        ? await db
            .query('customers')
            .then((all) => all.where((c) => _khataOf(c) == null).toList())
        : await db.query('customers', where: 'village = ?', whereArgs: [name]);
    var deleted = 0.0;
    for (final c in customers) {
      final cn = c['customer_name']?.toString() ?? '';
      final cu = c['client_uuid']?.toString() ?? '';
      final pawnLoans = await db.query('pawn_loans',
          where: 'customer_uuid = ? OR customer = ? OR customer_name = ?',
          whereArgs: [cu, cn, cn]);
      if (pawnLoans.isEmpty) {
        // v1.0.8: free the customer ID so the next new customer reuses it.
        await state.freeCustomerId(c['customer_id']?.toString());
      }
      final loans = await db.query('khatabook_loans',
          where: 'customer = ? OR customer_name = ?', whereArgs: [cu, cn]);
      for (final l in loans) {
        final ref = (l['server_name'] as String?) ?? l['client_uuid'];
        await state.deleteCashbookForLoan({
          ref?.toString() ?? '',
          l['client_uuid']?.toString() ?? '',
        });
        await db.delete('khatabook_given',
            where: 'khatabook_loan = ?', whereArgs: [ref]);
        await db.delete('khatabook_collections',
            where: 'khatabook_loan = ?', whereArgs: [ref]);
        await db.delete('khatabook_refinances',
            where: 'khatabook_loan = ?', whereArgs: [ref]);
        deleted += Num.toDouble(l['total_payable']);
      }
      await db.delete('khatabook_loans',
          where: 'customer = ? OR customer_name = ?', whereArgs: [cu, cn]);
      await db.delete('khatabook_given',
          where: 'customer = ? OR customer_name = ? OR customer = ?',
          whereArgs: [cu, cn, cu]);
      await db.delete('khatabook_collections',
          where: 'customer = ? OR customer = ?', whereArgs: [cu, cn]);
      if (pawnLoans.isEmpty) {
        await db.delete('customers', where: 'client_uuid = ?', whereArgs: [cu]);
      } else {
        await db.upsert('customers', {...c, 'village': null, 'dirty': 1});
      }
    }
    if (name != 'General') {
      await db.delete('villages', where: 'village_name = ?', whereArgs: [name]);
    }
    await state.logEvent('khata', 'khata_delete', 'Khata deleted — $name',
        amount: deleted);
    // The delete above already happened and must stand. Only the feedback and
    // the redraw are UI, so they are what we drop if the screen is gone.
    if (!mounted) return;
    _toast(context, '$name deleted.');
    await _refresh();
  }
}

// ---------------------------------------------------------------------------
// Create a new Khata (Stitch 12-new-khata).
// ---------------------------------------------------------------------------

class KhataCreateScreen extends StatefulWidget {
  const KhataCreateScreen({super.key});

  @override
  State<KhataCreateScreen> createState() => _KhataCreateScreenState();
}

class _KhataCreateScreenState extends State<KhataCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _typeController = TextEditingController(text: 'Village Location');
  final _notes = TextEditingController();
  double? _latitude;
  double? _longitude;

  @override
  void dispose() {
    for (final c in [_name, _typeController, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initial: (_latitude != null && _longitude != null)
              ? LatLng(_latitude!, _longitude!)
              : null,
          title: 'Pin Khata Location',
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _latitude = result.latitude;
        _longitude = result.longitude;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    await state.saveEntity(
      table: 'villages',
      doctype: 'Village',
      uuid: newUuid(),
      data: {
        'village_name': _name.text.trim(),
        'khata_type': _typeController.text.trim().isNotEmpty
            ? _typeController.text.trim()
            : 'Village Location',
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'latitude': _latitude,
        'longitude': _longitude,
      },
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(
        title: const Text('New Khata'),
        actions: [TextButton(onPressed: _save, child: const Text('SAVE'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SectionCard(title: 'Khata details', children: [
              TextFormField(
                controller: _name,
                decoration: fieldDecoration('Khata name *  (e.g. Lolugu or Shyam)'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (MigrationV12.isLossVillageName(v)) {
                    return '“Loss” is reserved for the Loss Khata.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _typeController,
                decoration: fieldDecoration('Khata type * (Editable)'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: ['Village Location', 'Personal', 'Business'].map((t) {
                  final selected = _typeController.text.trim() == t;
                  return ChoiceChip(
                    label: Text(t,
                        style: TextStyle(
                            fontSize: 12,
                            color: selected ? Colors.white : inkOf(context))),
                    selected: selected,
                    selectedColor: kGoldDark,
                    backgroundColor: surfaceOf(context),
                    onSelected: (_) =>
                        setState(() => _typeController.text = t),
                  );
                }).toList(),
              ),
            ]),
            SectionCard(title: 'Location', children: [
              Material(
                color: kBg,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickLocation,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          _latitude != null
                              ? Icons.location_on
                              : Icons.add_location_alt_outlined,
                          color: kGoldDark,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _latitude != null
                                    ? 'Pinned: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                                    : 'Set khata location on the map',
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _latitude != null
                                    ? 'Tap to adjust pin location'
                                    : 'Default center: Lolugu / Kadapa region',
                                style: TextStyle(
                                    fontSize: 11, color: mutedOf(context)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
              if (_latitude != null && _longitude != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kGoldDark,
                          side: const BorderSide(color: kGoldDark),
                        ),
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('Open in Google Maps',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () async {
                          final uri = Uri.parse(
                              'https://www.google.com/maps/search/?api=1&query=$_latitude,$_longitude');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Clear location',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _latitude = null;
                        _longitude = null;
                      }),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: fieldDecoration('Notes (Landmarks, directions, info)'),
              ),
            ]),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Customer list inside a Khata — collection-first (Stitch 03-customer-list).
// ---------------------------------------------------------------------------

// v1.0.11: what the shop actually asks — is it due, is it coming up later, or
// is there no due date at all? (Overdue and Due Today are the same thing, so
// they collapsed into "Due".)
enum _MemberFilter { all, due, upcoming, noDueDate }

class KhataCustomersScreen extends StatefulWidget {
  const KhataCustomersScreen(
      {super.key, required this.khataName, required this.khataType});

  final String khataName;
  final String khataType;

  @override
  State<KhataCustomersScreen> createState() => _KhataCustomersScreenState();
}

class _KhataCustomersScreenState extends State<KhataCustomersScreen> {
  String _search = '';
  _MemberFilter _filter = _MemberFilter.all;

  /// True while a member tile is being dragged (shows the trash bin).
  bool _dragActive = false;

  /// v1.0.11: the member list is ONE future held in state. Creating it inside
  /// build() restarted every query on each rebuild, so the screen hung and
  /// showed a permanent spinner while typing in the search box.
  late Future<List<_MemberRow>> _rowsFuture;
  List<_MemberRow> _lastRows = const [];
  Timer? _debounce;
  double? _villageLat;
  double? _villageLng;

  @override
  void initState() {
    super.initState();
    _rowsFuture = _fetchRows();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<_MemberRow>> _fetchRows() async {
    final customers = await _load();
    return _buildRows(customers);
  }

  /// Re-reads the list: after a save or delete, and (debounced) on search.
  void _reload() {
    if (!mounted) return;
    setState(() {
      _rowsFuture = _fetchRows();
    });
  }

  void _onSearchChanged(String v) {
    _search = v;
    _debounce?.cancel();
    // 300ms — one query per pause in typing instead of one per key press.
    _debounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  Future<List<Map<String, Object?>>> _load() async {
    final db = context.read<AppState>().db;
    if (widget.khataName != 'General') {
      try {
        final vRows = await db.query('villages',
            where: 'village_name = ?', whereArgs: [widget.khataName], limit: 1);
        if (vRows.isNotEmpty) {
          final row = vRows.first;
          _villageLat = (row['latitude'] as num?)?.toDouble();
          _villageLng = (row['longitude'] as num?)?.toDouble();
        }
      } catch (_) {}
    }
    final term = _search.trim();
    if (term.isEmpty) {
      return db.query('customers', orderBy: 'customer_name asc');
    }
    // One box searches name, CUSTOMER ID and mobile number.
    // IDs are hyphen-insensitive: typing A, A-, A03 or A-03 all match A03.
    final like = '%$term%';
    final normTerm = term.replaceAll('-', '').toLowerCase();
    final normLike = '%$normTerm%';
    List<Map<String, Object?>> rows;
    try {
      rows = await db.query('customers',
          where:
              'customer_name LIKE ? OR REPLACE(customer_id, \'-\', \'\') LIKE ? OR phone LIKE ?',
          whereArgs: [like, normLike, like]);
    } catch (_) {
      // An older database without the customer_id column: still search by name
      // and mobile instead of failing the whole screen.
      rows = await db.query('customers',
          where: 'customer_name LIKE ? OR phone LIKE ?',
          whereArgs: [like, like]);
    }
    // Name and ID matches are the ones the shopkeeper is looking for, so they
    // come first; a mobile-number match only follows if nothing else matched.
    int rank(Map<String, Object?> c) {
      final name = (c['customer_name']?.toString() ?? '').toLowerCase();
      final id = (c['customer_id']?.toString() ?? '')
          .toLowerCase()
          .replaceAll('-', '');
      if (name.contains(term.toLowerCase())) return 0;
      if (id.contains(normTerm)) return 1;
      return 2;
    }

    rows.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return (a['customer_name']?.toString() ?? '')
          .compareTo(b['customer_name']?.toString() ?? '');
    });
    return rows;
  }

  Future<void> _openAdd() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerForm(
          initialVillage:
              widget.khataName == 'General' ? null : widget.khataName,
          initialType: 'Khatabook',
        ),
      ),
    );
    if (mounted) _reload();
  }

  /// Group the khata's customers with their loan state, collection-first.
  Future<List<_MemberRow>> _buildRows(
      List<Map<String, Object?>> customers) async {
    // Read once, above the per-loan awaits in the loop below.
    final state = context.read<AppState>();
    final db = state.db;
    final loans = await db.query('khatabook_loans');
    final today = DateTime.now();
    final members = customers.where((c) {
      if (widget.khataName == 'General') return _khataOf(c) == null;
      return _khataOf(c) == widget.khataName;
    }).toList();

    // Which members share a name? Their loans cannot be split apart by name, so
    // those members get no loan total rather than each being credited with the
    // other's money — a wrong figure is worse than an obviously empty one.
    final nameCounts = <String, int>{};
    final uuidsWithName = <String, Set<String>>{};
    for (final c in customers) {
      final n = c['customer_name']?.toString() ?? '';
      if (n.isEmpty) continue;
      nameCounts[n] = (nameCounts[n] ?? 0) + 1;
      uuidsWithName
          .putIfAbsent(n, () => <String>{})
          .add(c['client_uuid']?.toString() ?? '');
    }

    final rows = <_MemberRow>[];
    for (final c in members) {
      final name = c['customer_name']?.toString() ?? '';
      final uuid = c['client_uuid']?.toString() ?? '';
      final ambiguous = nameCounts[name] != null && nameCounts[name]! > 1;
      final myLoans = <Map<String, Object?>>[];
      if (!ambiguous) {
        // The uuid is the identity. The name is only a fallback for rows
        // written before a uuid was stored — and never when another customer
        // shares that name, because then the rows cannot be told apart.
        for (final l in loans) {
          if (!isActiveKhataStatus(l['status'])) continue;
          final loanUuid = l['customer_uuid']?.toString() ?? '';
          final owner = l['customer']?.toString() ?? '';
          final ownerName = l['customer_name']?.toString() ?? '';
          if (uuid.isNotEmpty && (loanUuid == uuid || owner == uuid)) {
            myLoans.add(l);
          } else if (uuid.isNotEmpty && owner.isEmpty && ownerName == name) {
            myLoans.add(l); // legacy row: no owner uuid stored
          } else if (uuid.isNotEmpty &&
              ownerName == name &&
              uuidsWithName[name]?.length == 1) {
            myLoans.add(l); // legacy row, and the name is unambiguous
          }
        }
      }
      double prin = 0, out = 0, paid = 0, due = 0, upcoming = 0;
      int overdue = 0, late = 0;
      bool anyDueToday = false, anyUpcoming = false;
      DateTime? nextDue;
      for (final l in myLoans) {
        prin += Num.toDouble(l['principal_amount']);
        double o = Num.toDouble(l['outstanding']);
        out += o;
        paid += Num.toDouble(l['total_collected']);
        // To Collect is the due installments' remainder, never the balance.
        // Interest-only loans read their billed period rows instead: only
        // arrived periods count, and a prepaid future period stays silent.
        if (MigrationV11.isInterestOnly(l)) {
          final loanUuid = l['client_uuid']?.toString() ?? '';
          final rows = await state.ensureInterestPeriods(l, today: today);
          final day = DateTime(today.year, today.month, today.day);
          var futureBilled = 0.0;
          for (final r in rows) {
            final dueDate = _parseDate(r['due_date']);
            final remaining = Num.toDouble(r['remaining_amount']);
            if (remaining <= 0 || dueDate == null) continue;
            if (!DateTime(dueDate.year, dueDate.month, dueDate.day)
                .isAfter(day)) {
              due += remaining;
            } else {
              futureBilled += remaining;
            }
          }
          // The blue future chip names what arrives next: billed future
          // periods first, otherwise the next period's current interest.
          upcoming += futureBilled > 0
              ? futureBilled
              : Num.toDouble(l['current_interest'] ?? l['interest_amount']);
          // Keep the counters truthful for every display that reads them.
          await state.rebuildInterestPeriods(loanUuid);
        } else {
          final count = (l['installment_count'] as num?)?.toInt() ?? 0;
          final start = _parseDate(l['start_date'] ?? l['loan_date']);
          due += KhataSchedule.dueRemaining(
            expectedRepayment: Num.toDouble(l['total_payable']),
            collected: Num.toDouble(l['total_collected']),
            count: count,
            start: start,
            frequency: l['collection_frequency']?.toString() ?? '',
            today: today,
            fallbackOutstanding: o,
          );
          // The blue future chip names the earliest still-unpaid installment
          // ahead, so a new loan shows its first due with a real amount.
          final day = DateTime(today.year, today.month, today.day);
          for (final r in KhataSchedule.scheduleRemaining(
            expectedRepayment: Num.toDouble(l['total_payable']),
            collected: Num.toDouble(l['total_collected']),
            count: count,
            start: start,
            frequency: l['collection_frequency']?.toString() ?? '',
          )) {
            final d = r.dueDate;
            if (r.remainingPaise > 0 &&
                DateTime(d.year, d.month, d.day).isAfter(day)) {
              upcoming += r.remainingPaise / 100.0;
              break;
            }
          }
        }
        final bucket = loanBucket(l, today);
        if (bucket == LoanBucket.overdue) {
          overdue++;
          final d = loanNextDue(l, today);
          if (d != null) {
            final lat = _day(today).difference(d).inDays;
            if (lat > late) late = lat;
          }
        }
        if (bucket == LoanBucket.dueToday) anyDueToday = true;
        if (bucket == LoanBucket.upcoming) anyUpcoming = true;
        final nd = loanNextDue(l, today);
        if (nd != null && (nextDue == null || nd.isBefore(nextDue))) {
          nextDue = nd;
        }
      }
      // A reminder date set on the customer drives the due display — the
      // shopkeeper's word overrides the loan schedule ("collect this week").
      final reminder = _parseDate(c['reminder_date']);
      if (reminder != null) {
        final rLate = _day(today).difference(reminder).inDays;
        if (rLate > 0) {
          overdue = overdue > 0 ? overdue : 1;
          if (rLate > late) late = rLate;
        } else if (rLate == 0) {
          anyDueToday = true;
        } else {
          // Any future reminder (near or far) flags this member as upcoming;
          // the chip shows "DUE 15-10-26" when it is beyond a week.
          anyUpcoming = true;
        }
        nextDue = reminder;
      }
      rows.add(_MemberRow(
        customer: c,
        principal: Num.rupees(prin),
        outstanding: Num.rupees(out),
        paid: Num.rupees(paid),
        due: Num.rupees(due),
        upcoming: Num.rupees(upcoming),
        lateDays: late,
        overdueLoans: overdue,
        anyDueToday: anyDueToday,
        anyUpcoming: anyUpcoming,
        nextDue: nextDue,
        activeLoans: myLoans.length,
        reminderSet: reminder != null,
      ));
    }
    rows.sort((a, b) {
      // Due (red) members float to the top, then the promised ones, then the
      // rest — so the collection list is in the order the shop needs it.
      int rank(_MemberRow r) {
        if (_isDue(r) && !_promisedLater(r)) return 0;
        if (_promisedLater(r)) return 1;
        return 2;
      }

      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byLate = b.lateDays.compareTo(a.lateDays);
      if (byLate != 0) return byLate;
      final aDue = a.nextDue, bDue = b.nextDue;
      if (aDue != null && bDue != null) return aDue.compareTo(bDue);
      return (a.customer['customer_name']?.toString() ?? '')
          .compareTo(b.customer['customer_name']?.toString() ?? '');
    });
    return rows;
  }

  /// Is anything DUE right now (the date has arrived or already passed)?
  static bool _isDue(_MemberRow r) =>
      memberIsDue(r.overdueLoans, r.anyDueToday);

  /// v1.0.11: a reminder only turns the row BLUE when the date is still in the
  /// FUTURE ("come next week"). A reminder set to today — or a date already
  /// passed — is still DUE, so it stays RED.
  static bool _promisedLater(_MemberRow r) =>
      r.reminderSet && reminderIsLater(r.nextDue, DateTime.now());

  /// Still to come — a future promise OR a future due date.
  /// A member the shopkeeper moved to next week counts as Upcoming even when
  /// the loan itself is late: the promise overrides the schedule, and the row
  /// must not vanish from both Due and Upcoming lists.
  static bool _isUpcoming(_MemberRow r) =>
      _promisedLater(r) || (!_isDue(r) && (r.anyUpcoming || r.nextDue != null));

  bool _passes(_MemberRow r) {
    switch (_filter) {
      case _MemberFilter.all:
        return true;
      case _MemberFilter.due:
        return _isDue(r) && !_promisedLater(r);
      case _MemberFilter.upcoming:
        return _isUpcoming(r);
      case _MemberFilter.noDueDate:
        // This filter has always meant "no reminder date set on the Customer
        // Profile", not "no loan schedule". The old label ("No Due Date")
        // claimed the second thing and misled the shopkeeper.
        return !r.reminderSet;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(
        title: Text(widget.khataName),
        actions: [
          if (_villageLat != null && _villageLng != null)
            IconButton(
              icon: const Icon(Icons.location_on_outlined),
              tooltip: 'Open in Google Maps',
              onPressed: () async {
                final uri = Uri.parse(
                    'https://www.google.com/maps/search/?api=1&query=$_villageLat,$_villageLng');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
      // v1.0.11: a plain "+" — simpler and less crowded on big phones.
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        tooltip: 'Add Member',
        child: const Icon(Icons.add, size: 28),
      ),
      body: FutureBuilder<List<_MemberRow>>(
        future: _rowsFuture,
        builder: (context, rowsSnap) {
          if (rowsSnap.hasData) _lastRows = rowsSnap.data ?? const [];
          // Show the error only when there is nothing to fall back on.
          if (rowsSnap.hasError && _lastRows.isEmpty) {
            return _loadFailed(rowsSnap.error);
          }
          // A pending load that already has rows on screen keeps those rows, so
          // the page never blanks out to a bare spinner while searching. But an
          // EMPTY khata whose query has finished is not "loading" — it has to
          // reach the empty state below, or the page spins forever with no
          // search box, no chips and no way forward.
          final pending = rowsSnap.connectionState != ConnectionState.done;
          if (pending && _lastRows.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: kGold));
          }
          final all = _lastRows;
          final visible = all.where(_passes).toList();
          final prin =
              all.fold<double>(0, (s, r) => s + Num.toDouble(r.principal));
          final out =
              all.fold<double>(0, (s, r) => s + Num.toDouble(r.outstanding));
          // "To Collect" = scheduled dues arrived (today + arrears) for
          // members who are due and not promised for later. Never the full
          // balance: a ₹12,000 outstanding with a ₹1,000 weekly due means
          // ₹1,000, not ₹12,000.
          final toCollect = all
              .where((r) => _isDue(r) && !_promisedLater(r))
              .fold<double>(0, (s, r) => s + r.due);
          return Column(
            children: [
              _summaryStrip(prin, out, toCollect, all.length),
              _chipRow(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  decoration: fieldDecoration('Search name, ID or mobile'),
                  onChanged: _onSearchChanged,
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    visible.isEmpty
                        ? _EmptyState(
                            icon: Icons.people_outline,
                            message: _search.trim().isEmpty
                                ? 'No members in this khata yet. Tap + to add one.'
                                : 'No member matches "${_search.trim()}".')
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 140),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) =>
                                _rowTile(visible[index]),
                          ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: DeleteTrashTarget(
                          visible: _dragActive,
                          onDrop: (p) async {
                            setState(() => _dragActive = false);
                            return p.drop();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// v1.0.11: a failed query must never look like "still loading".
  Widget _loadFailed(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: kRed),
            const SizedBox(height: 10),
            const Text('Could not load the members list.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('$error',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: mutedOf(context))),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStrip(
      double investment, double outstanding, double toCollect, int members) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _stat(
                'Investment', '₹${moneyWholeDown(investment)}', kGoldDark),
          ),
          _dividerV(),
          Expanded(
            child:
                _stat('Outstanding', '₹${moneyWholeDown(outstanding)}', kInk),
          ),
          _dividerV(),
          Expanded(
            child: _stat('To Collect', '₹${moneyWholeDown(toCollect)}', kRed),
          ),
          _dividerV(),
          Expanded(
            child: _stat('Members', '$members', kGoldDark),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
      ],
    );
  }

  Widget _dividerV() => Container(
        width: 1,
        height: 30,
        color: inkOf(context).withValues(alpha: .1),
      );

  Widget _chipRow() {
    final chips = <(String, _MemberFilter)>[
      ('All', _MemberFilter.all),
      ('Due', _MemberFilter.due),
      ('Upcoming', _MemberFilter.upcoming),
      ('No reminder', _MemberFilter.noDueDate),
    ];
    // Always ONE row: the chips scroll sideways instead of wrapping, so a big
    // font / Zoom setting can never push them onto a second line.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (label, value) in chips) ...[
              ChoiceChip(
                label: Text(label, maxLines: 1),
                selected: _filter == value,
                selectedColor: kGold.withValues(alpha: .3),
                labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        _filter == value ? FontWeight.w700 : FontWeight.w500,
                    color: _filter == value
                        ? kGoldDark
                        : kInk.withValues(alpha: .7)),
                onSelected: (_) => setState(() => _filter = value),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rowTile(_MemberRow r) {
    final c = r.customer;
    // In the Loss Khata every row also names the village the customer came
    // from, so the origin is visible without opening the profile.
    final inLoss = MigrationV12.isLossKhata(widget.khataName);
    final origin =
        inLoss ? (c['previous_village']?.toString() ?? '').trim() : '';
    final chip = _dueChip(context, r);
    return DragToDeleteTile(
      onDragChanged: (v) => setState(() => _dragActive = v),
      payload: DeletePayload(
        drop: () async {
          final granted = await askPasswordIfEnabled(
              context, context.read<AppState>(),
              actionId: 'member_delete',
              action: 'delete',
              detail: c['customer_name']?.toString());
          // Password prompt was async - the row may have been swiped away.
          if (!mounted) return false;
          if (granted != true) {
            _toast(context, 'Delete cancelled / wrong password.');
            return false;
          }
          await _performDeleteMember(c);
          return true;
        },
      ),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => CustomerProfileScreen(customer: c)),
          );
          // v1.0.11: re-read the list — a collection or a "cleared" loan made in
          // the profile must not stay on screen as a pending amount here.
          if (mounted) _reload();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              _avatar(c),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['customer_name']?.toString() ?? '-',
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: inkOf(context))),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if ((c['customer_id']?.toString() ?? '').isNotEmpty)
                          'ID ${c['customer_id']}',
                        if (origin.isNotEmpty) 'from $origin',
                        if ((c['phone']?.toString() ?? '').isNotEmpty)
                          c['phone'].toString(),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: mutedOf(context)),
                    ),
                    // Recency of real money movement only — grey, never the
                    // red/blue/green/gold status colours. Empty when nothing
                    // has ever moved.
                    Builder(builder: (_) {
                      final ago = timeAgo(c['last_activity_at']);
                      if (ago.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(ago,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10.5, color: mutedOf(context))),
                      );
                    }),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                          color: inkOf(context).withValues(alpha: .04),
                          borderRadius: BorderRadius.circular(6)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: r.activeLoans > 0
                              ? (r.paid /
                                      (r.paid + Num.toDouble(r.outstanding)))
                                  .clamp(0.0, 1.0)
                              : 0,
                          minHeight: 5,
                          backgroundColor: inkOf(context).withValues(alpha: .08),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(kGold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${moneyWholeDown(r.outstanding)}',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: inkOf(context))),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: chip.bg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(r.activeLoans == 0 ? 'NO LOAN' : chip.label,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: r.activeLoans == 0
                                ? kInk.withValues(alpha: .4)
                                : chip.fg)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Performs the member deletion (called after the admin gate): removes the
  /// customer, their loans/collections/givens/refinances and frees the ID.
  Future<void> _performDeleteMember(Map<String, Object?> c) async {
    final state = context.read<AppState>();
    final db = state.db;
    final name = c['customer_name']?.toString() ?? '';
    final uuid = c['client_uuid'];
    // v1.0.8: free the customer ID so the next new customer reuses it.
    await state.freeCustomerId(c['customer_id']?.toString());
    final loans = await db.query('khatabook_loans',
        where: 'customer = ? OR customer_name = ?', whereArgs: [uuid, name]);
    var deleted = 0.0;
    for (final l in loans) {
      final ref = (l['server_name'] as String?) ?? l['client_uuid'];
      await state.deleteCashbookForLoan({
        ref?.toString() ?? '',
        l['client_uuid']?.toString() ?? '',
      });
      await db.delete('khatabook_given',
          where: 'khatabook_loan = ?', whereArgs: [ref]);
      await db.delete('khatabook_collections',
          where: 'khatabook_loan = ?', whereArgs: [ref]);
      await db.delete('khatabook_refinances',
          where: 'khatabook_loan = ?', whereArgs: [ref]);
      deleted += Num.toDouble(l['total_payable']);
    }
    final pawnLoans = await db.query('pawn_loans',
        where: 'customer_uuid = ? OR customer = ? OR customer_name = ?',
        whereArgs: [uuid, name, name]);
    await db.delete('khatabook_loans',
        where: 'customer = ? OR customer_name = ?', whereArgs: [uuid, name]);
    await db.delete('khatabook_given',
        where: 'customer = ? OR customer_name = ? OR customer = ?',
        whereArgs: [uuid, name, uuid]);
    await db.delete('khatabook_collections',
        where: 'customer = ? OR customer = ?', whereArgs: [uuid, name]);
    if (pawnLoans.isEmpty) {
      await state.freeCustomerId(c['customer_id']?.toString());
      await db.delete('customers', where: 'client_uuid = ?', whereArgs: [uuid]);
    } else {
      await db.upsert('customers', {...c, 'village': null, 'dirty': 1});
    }
    await state.logEvent('khata', 'customer_delete', 'Customer deleted — $name',
        amount: deleted, village: c['village']?.toString());
    // Re-query the list: a bare setState reuses the completed future and the
    // deleted row stays visible until you leave and come back.
    if (mounted) _reload();
  }

  Widget _avatar(Map<String, Object?> c) {
    final photo = c['photo_path'] as String?;
    return CircleAvatar(
      radius: 22,
      backgroundColor: kGold.withValues(alpha: .16),
      foregroundImage:
          (photo != null && photo.isNotEmpty) ? (awaitFileImage(photo)) : null,
      child: Text((c['customer_name']?.toString() ?? '?')
          .characters
          .first
          .toUpperCase()),
    );
  }
}

class _MemberRow {
  _MemberRow({
    required this.customer,
    required this.principal,
    required this.outstanding,
    required this.paid,
    this.due = 0,
    this.upcoming = 0,
    required this.lateDays,
    required this.overdueLoans,
    required this.anyDueToday,
    required this.anyUpcoming,
    required this.nextDue,
    required this.activeLoans,
    this.reminderSet = false,
  });

  final Map<String, Object?> customer;
  final double principal;
  final double outstanding;
  final double paid;

  /// Scheduled dues with date arrived (today + arrears) — the To Collect
  /// figure. Never the full balance.
  final double due;

  /// Remaining on each loan's earliest still-future installment, summed.
  /// Display-only: a blue future chip names an amount that actually arrives
  /// on the named date, even when nothing is due today.
  final double upcoming;
  final int lateDays;
  final int overdueLoans;
  final bool anyDueToday;
  final bool anyUpcoming;
  final DateTime? nextDue;

  /// True when the shopkeeper set/confirmed a collection date in the customer
  /// profile (the Reminder). Such a member is NOT red.
  final bool reminderSet;
  final int activeLoans;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: kGold),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared delete helpers (khata + customer), used across the khata screens.
// ---------------------------------------------------------------------------

/// "Are you sure to delete {name}?" + admin password; returns true when the
/// password equals "admin" (case-insensitive).
void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
