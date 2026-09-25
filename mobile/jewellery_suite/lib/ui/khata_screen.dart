import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/format.dart';
import '../util/ids.dart';
import 'customer_profile_screen.dart';
import 'customers_screen.dart';
import 'location_picker_screen.dart';
import 'palette.dart';
import 'reports_screen.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Loan schedule helpers (mirror the server's frequency model).
// ---------------------------------------------------------------------------

int _freqDays(String? frequency) {
  final s = (frequency ?? '').toLowerCase();
  if (s.contains('bi')) return 14;
  if (s.contains('month')) return 30;
  return 7;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? _parseDate(Object? v) => DateTime.tryParse(v?.toString() ?? '');

/// Next installment due for a khata loan (null once fully paid).
DateTime? loanNextDue(Map<String, Object?> loan, DateTime today) {
  final paid = (loan['paid_installments'] as num?)?.toInt() ?? 0;
  final count = (loan['installment_count'] as num?)?.toInt() ?? 0;
  if (paid >= count) return null;
  final start = _parseDate(loan['start_date'] ?? loan['loan_date']);
  if (start == null) return null;
  return _day(start).add(Duration(days: paid * _freqDays(loan['collection_frequency']?.toString())));
}

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

_Chip _bucketChip(LoanBucket bucket, int lateDays) {
  switch (bucket) {
    case LoanBucket.overdue:
      return _Chip('OVERDUE · $lateDays d', kRedSoft, kRed);
    case LoanBucket.dueToday:
      return _Chip('DUE TODAY', kGold.withValues(alpha: .18), kGoldDark);
    case LoanBucket.upcoming:
      return _Chip('UPCOMING', kBlueSoft, kBlue);
    case LoanBucket.onSchedule:
      return _Chip('ON TIME', kGreenSoft, kGreen);
  }
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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    final villages = await state.db.query('villages', orderBy: 'village_name asc');
    final customers = await state.db.query('customers');
    final loans = await state.db.query('khatabook_loans');
    final today = DateTime.now();

    final built = <Map<String, Object?>>[];
    double totalPrin = 0;
    double totalOut = 0;
    int totalMembers = 0;
    int overdue = 0;

    void addKhata(String name, String type) {
      final members =
          customers.where((c) => _khataOf(c) == name).toList();
      final khataLoans = loans
          .where((l) =>
              _khataOf(l) == name &&
              (l['status']?.toString() ?? 'Active') == 'Active')
          .toList();
      double prin = 0;
      double out = 0;
      int due = 0;
      for (final l in khataLoans) {
        prin += Num.toDouble(l['principal_amount']);
        final o = Num.toDouble(l['outstanding']);
        out += o;
        if (loanBucket(l, today) == LoanBucket.overdue) due++;
        overdue += (LoanBucket.overdue == loanBucket(l, today))
            ? (o > 0 ? 1 : 0)
            : 0;
      }
      totalPrin += prin;
      totalOut += out;
      totalMembers += members.length;
      built.add({
        'name': name,
        'type': type,
        'members': members.length,
        'principal': Num.money(prin),
        'outstanding': Num.money(out),
        'overdue': due,
      });
    }

    for (final v in villages) {
      addKhata(
        v['village_name']?.toString() ?? '-',
        (v['khata_type']?.toString().isNotEmpty ?? false)
            ? v['khata_type'].toString()
            : 'Village Location',
      );
    }
    // General group: customers without any khata/village.
    if (customers.any((c) => _khataOf(c) == null)) {
      addKhata('General', 'General');
    }
    overdue = built.fold<int>(0, (s, k) => s + (k['overdue'] as int));

    if (mounted) {
      setState(() {
        _khatas = built;
        _totalPrincipal = Num.money(totalPrin);
        _totalOutstanding = Num.money(totalOut);
        _totalMembers = totalMembers;
        _overdueToday = overdue;
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
      backgroundColor: kBg,
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
      body: RefreshIndicator(
        color: kGold,
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kGold))
            : ListView(
                padding: const EdgeInsets.all(16),
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
                    const Text('PRINCIPAL (INVESTED)',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            color: Color(0xFFE7D48B))),
                    const SizedBox(height: 4),
                    Text('₹${moneyWhole(_totalPrincipal)}',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TOTAL OUTSTANDING',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            color: Color(0xFFE7D48B))),
                    const SizedBox(height: 4),
                    Text('₹${moneyWhole(_totalOutstanding)}',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _miniStat('$_totalMembers', 'Members'),
              const SizedBox(width: 18),
              _miniStat('$_overdueToday', 'Overdue accounts'),
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
        Text(value,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: Colors.white.withValues(alpha: .7))),
      ],
    );
  }

  Widget _khataRow(Map<String, Object?> k) {
    final type = k['type']?.toString() ?? 'Village Location';
    final IconData icon = type.toLowerCase().contains('personal')
        ? Icons.person_outline
        : type.toLowerCase().contains('business')
            ? Icons.storefront_outlined
            : Icons.location_on_outlined;
    final overdue = (k['overdue'] as int? ?? 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
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
                    color: kGold.withValues(alpha: .14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 21, color: kGoldDark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(k['name']?.toString() ?? '-',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: kInk)),
                        ),
                        const SizedBox(width: 6),
                        _typeTag(type),
                      ]),
                      const SizedBox(height: 2),
                      Text(
                        [
                          '${k['members'] ?? 0} member(s)',
                          if ((k['principal'] as num?) != null &&
                              Num.toDouble(k['principal']) > 0)
                            '₹${moneyWhole(k['principal'] as num?)} invested',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: kInk.withValues(alpha: .55)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${moneyWhole(k['outstanding'] as num?)}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kInk)),
                    const SizedBox(height: 3),
                    if (overdue > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: kRedSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('$overdue overdue',
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: kRed)),
                      )
                    else
                      const Text('All clear',
                          style: TextStyle(fontSize: 10.5, color: kGreen)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeTag(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: kBg, borderRadius: BorderRadius.circular(6)),
      child: Text(type,
          style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: kInk.withValues(alpha: .6))),
    );
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
  final _notes = TextEditingController();
  String _type = 'Village Location';
  double? _latitude;
  double? _longitude;

  @override
  void dispose() {
    for (final c in [_name, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
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
        'khata_type': _type,
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
      backgroundColor: kBg,
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
                decoration: fieldDecoration('Khata name *  (e.g. Pallipatti)'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: fieldDecoration('Khata type'),
                items: const ['Village Location', 'Personal', 'Business']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
            ]),
            SectionCard(title: 'Location (optional)', children: [
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
                          child: Text(
                            _latitude != null
                                ? 'Pinned: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                                : 'Set khata location on the map',
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: fieldDecoration('Notes'),
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

enum _MemberFilter { all, overdue, dueToday, thisWeek, upcoming }

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

  Future<List<Map<String, Object?>>> _load() {
    final db = context.read<AppState>().db;
    if (_search.trim().isNotEmpty) {
      final term = '%${_search.trim()}%';
      return db.query('customers',
          where: 'customer_name LIKE ? OR phone LIKE ?',
          whereArgs: [term, term],
          orderBy: 'customer_name asc');
    }
    return db.query('customers', orderBy: 'customer_name asc');
  }

  Future<void> _openAdd() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerForm(
          initialVillage: widget.khataName == 'General' ? null : widget.khataName,
          initialType: 'Khatabook',
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Group the khata's customers with their loan state, collection-first.
  Future<List<_MemberRow>> _buildRows(List<Map<String, Object?>> customers) async {
    final db = context.read<AppState>().db;
    final loans = await db.query('khatabook_loans');
    final today = DateTime.now();
    final members = customers.where((c) {
      if (widget.khataName == 'General') return _khataOf(c) == null;
      return _khataOf(c) == widget.khataName;
    }).toList();

    final rows = <_MemberRow>[];
    for (final c in members) {
      final name = c['customer_name']?.toString() ?? '';
      final myLoans = loans
          .where((l) =>
              l['customer_name']?.toString() == name &&
              (l['status']?.toString() ?? 'Active') == 'Active')
          .toList();
      double prin = 0, out = 0, paid = 0;
      int overdue = 0, late = 0;
      bool anyDueToday = false, anyUpcoming = false;
      DateTime? nextDue;
      for (final l in myLoans) {
        prin += Num.toDouble(l['principal_amount']);
        double o = Num.toDouble(l['outstanding']);
        out += o;
        paid += Num.toDouble(l['total_collected']);
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
      rows.add(_MemberRow(
        customer: c,
        principal: Num.money(prin),
        outstanding: Num.money(out),
        paid: Num.money(paid),
        lateDays: late,
        overdueLoans: overdue,
        anyDueToday: anyDueToday,
        anyUpcoming: anyUpcoming,
        nextDue: nextDue,
        activeLoans: myLoans.length,
      ));
    }
    rows.sort((a, b) {
      int rank(_MemberRow r) => r.overdueLoans > 0
          ? 0
          : r.anyDueToday
              ? 1
              : r.anyUpcoming
                  ? 2
                  : 3;
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

  bool _passes(_MemberRow r) {
    switch (_filter) {
      case _MemberFilter.all:
        return true;
      case _MemberFilter.overdue:
        return r.overdueLoans > 0;
      case _MemberFilter.dueToday:
        return r.anyDueToday;
      case _MemberFilter.thisWeek:
        return r.overdueLoans > 0 || r.anyDueToday || r.anyUpcoming;
      case _MemberFilter.upcoming:
        return r.anyUpcoming && !r.anyDueToday && r.overdueLoans == 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: Text(widget.khataName)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add Member'),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: kGold));
          }
          return FutureBuilder<List<_MemberRow>>(
            future: _buildRows(snapshot.data!),
            builder: (context, rowsSnap) {
              if (!rowsSnap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: kGold));
              }
              final all = rowsSnap.data!;
              final visible = all.where(_passes).toList();
              final prin = all.fold<double>(
                  0, (s, r) => s + Num.toDouble(r.principal));
              final out = all.fold<double>(
                  0, (s, r) => s + Num.toDouble(r.outstanding));
              final overdueCount =
                  all.where((r) => r.overdueLoans > 0).length;
              return Column(
                children: [
                  _summaryStrip(prin, out, overdueCount, all.length),
                  _chipRow(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      decoration: fieldDecoration('Search member or phone'),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  Expanded(
                    child: visible.isEmpty
                        ? const _EmptyState(
                            icon: Icons.people_outline,
                            message:
                                'No members match. Tap Add Member to start a khata.')
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) =>
                                _rowTile(visible[index]),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _summaryStrip(
      double principal, double outstanding, int overdueCount, int members) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _stat('Principal', '₹${moneyWhole(principal)}', kGoldDark),
          ),
          _dividerV(),
          Expanded(
            child: _stat('Outstanding', '₹${moneyWhole(outstanding)}', kInk),
          ),
          _dividerV(),
          Expanded(
            child: _stat('Overdue', '$overdueCount', kRed),
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
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 10.5, color: kInk.withValues(alpha: .55))),
      ],
    );
  }

  Widget _dividerV() => Container(
        width: 1, height: 30, color: kInk.withValues(alpha: .1),
      );

  Widget _chipRow() {
    final chips = <(String, _MemberFilter)>[
      ('All', _MemberFilter.all),
      ('Overdue', _MemberFilter.overdue),
      ('Due Today', _MemberFilter.dueToday),
      ('This Week', _MemberFilter.thisWeek),
      ('Upcoming', _MemberFilter.upcoming),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        children: [
          for (final (label, value) in chips)
            ChoiceChip(
              label: Text(label),
              selected: _filter == value,
              selectedColor: kGold.withValues(alpha: .3),
              labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      _filter == value ? FontWeight.w700 : FontWeight.w500,
                  color: _filter == value ? kGoldDark : kInk.withValues(alpha: .7)),
              onSelected: (_) => setState(() => _filter = value),
            ),
        ],
      ),
    );
  }

  Widget _rowTile(_MemberRow r) {
    final c = r.customer;
    final bucket = r.overdueLoans > 0
        ? LoanBucket.overdue
        : r.anyDueToday
            ? LoanBucket.dueToday
            : r.anyUpcoming
                ? LoanBucket.upcoming
                : LoanBucket.onSchedule;
    final chip = _bucketChip(bucket, r.lateDays);
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => CustomerProfileScreen(customer: c)),
        );
        if (mounted) setState(() {});
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
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: kInk)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (_khataOf(c) != null) _khataOf(c)!,
                      if (c['phone'] != null) c['phone'].toString(),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: kInk.withValues(alpha: .55)),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                        color: kInk.withValues(alpha: .04),
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
                        backgroundColor: kInk.withValues(alpha: .08),
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
                Text('₹${moneyWhole(r.outstanding)}',
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: chip.bg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                      r.activeLoans == 0 ? 'NO LOAN' : chip.label,
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
    );
  }

  Widget _avatar(Map<String, Object?> c) {
    final photo = c['photo_path'] as String?;
    return CircleAvatar(
      radius: 22,
      backgroundColor: kGold.withValues(alpha: .16),
      foregroundImage: (photo != null && photo.isNotEmpty)
          ? (awaitFileImage(photo))
          : null,
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
    required this.lateDays,
    required this.overdueLoans,
    required this.anyDueToday,
    required this.anyUpcoming,
    required this.nextDue,
    required this.activeLoans,
  });

  final Map<String, Object?> customer;
  final double principal;
  final double outstanding;
  final double paid;
  final int lateDays;
  final int overdueLoans;
  final bool anyDueToday;
  final bool anyUpcoming;
  final DateTime? nextDue;
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