import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/doc_scanner.dart';
import '../../../data/slip_ocr.dart';
import '../../../state/app_state.dart';
import '../../../util/format.dart';
import '../../../util/ids.dart';
import '../../../util/pawn_math.dart';
import '../../../ui/customers_screen.dart';
import '../../../ui/admin_guard.dart';
import '../../../ui/palette.dart';
import '../../../ui/pawn_categories_screen.dart';
import '../../../ui/pawn_dashboard_screen.dart';
import '../../../features/reports/screens/reports_screen.dart';
import '../../../ui/widgets.dart';

class PawnScreen extends StatefulWidget {
  const PawnScreen({super.key, this.filter});

  /// 'active' | 'released' | 'old' | 'recent' | 'interest'
  final String? filter;

  @override
  State<PawnScreen> createState() => _PawnScreenState();
}

class _PawnScreenState extends State<PawnScreen> {
  String _search = '';
  late String _filter = widget.filter ?? 'active';
  String _metal = 'all'; // all | gold | silver | mixed
  String? _village;
  List<String> _villageOptions = const [];
  List<String> _categories = const [];
  String? _category;
  DateTimeRange? _range;
  (double, double)? _amountRange;
  final Set<String> _selected = {};
  bool _selectMode = false;
  bool _dragActive = false;

  /// loan uuid -> metals found on its items, used by the tile's item label.
  Map<String, List<String>> _metalsByLoan = {};

  /// loan uuid -> customer row (photo, village, book ID, address, KYC paths).
  /// Kept OUT of the loan row map so it can never leak into a db.upsert() of
  /// pawn_loans — an unknown column would abort the write.
  final Map<String, Map<String, Object?>> _customerByLoan = {};

  @override
  void initState() {
    super.initState();
    _loadVillageOptions();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final names = await context.read<AppState>().pawnCategories();
    if (mounted) setState(() => _categories = names);
  }

  Future<void> _loadVillageOptions() async {
    final db = context.read<AppState>().db;
    final villages = await db.query('villages', columns: ['village_name']);
    final loans = await db.query('pawn_loans', columns: ['village']);
    final customers = await db.query('customers', columns: ['village']);
    final names = <String>{
      for (final v in villages) (v['village_name']?.toString() ?? '').trim(),
      for (final l in loans) (l['village']?.toString() ?? '').trim(),
      for (final c in customers) (c['village']?.toString() ?? '').trim(),
    };
    names.removeWhere((n) => n.isEmpty);
    final sorted = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (mounted) setState(() => _villageOptions = sorted);
  }

  /// One query serves both the list and the summary strip. The loan rows keep
  /// only cached display fields; the live customers table has the photo,
  /// address, mobile and KYC images.
  Future<
      ({
        Map<String, Map<String, Object?>> byUuid,
        Map<String, Map<String, Object?>> byName,
      })> _customerLookup() async {
    final customers = await context.read<AppState>().db.query(
      'customers',
      columns: [
        'client_uuid',
        'customer_name',
        'customer_id',
        'village',
        'address',
        'phone',
        'photo_path',
        'id_photo_front',
        'id_photo_back',
      ],
    );
    return (
      byUuid: {
        for (final c in customers)
          if ((c['client_uuid']?.toString() ?? '').isNotEmpty)
            c['client_uuid']!.toString(): c,
      },
      byName: {
        for (final c in customers)
          if ((c['customer_name']?.toString() ?? '').isNotEmpty)
            c['customer_name']!.toString(): c,
      },
    );
  }

  Map<String, Object?>? _customerFor(
    Map<String, Object?> loan,
    Map<String, Map<String, Object?>> byUuid,
    Map<String, Map<String, Object?>> byName,
  ) {
    final uuid = loan['customer_uuid']?.toString() ?? '';
    if (uuid.isNotEmpty && byUuid.containsKey(uuid)) return byUuid[uuid];
    return byName[loan['customer_name']?.toString() ?? ''];
  }

  /// Village lives on the customer; older loans may carry only the cached copy.
  String _villageOf(
    Map<String, Object?> loan,
    Map<String, Map<String, Object?>> byUuid,
    Map<String, Map<String, Object?>> byName,
  ) {
    final customer = _customerFor(loan, byUuid, byName);
    final saved = (customer?['village'] ?? '').toString().trim();
    return saved.isNotEmpty ? saved : (loan['village'] ?? '').toString().trim();
  }

  /// loan_uuid -> list of normalised metals found on its items.
  Future<Map<String, List<String>>> _metalIndex() async {
    final items = await context
        .read<AppState>()
        .db
        .query('pawn_items', columns: ['loan_uuid', 'metal_type']);
    final idx = <String, List<String>>{};
    for (final it in items) {
      final uuid = it['loan_uuid']?.toString() ?? '';
      if (uuid.isEmpty) continue;
      final m = (it['metal_type']?.toString() ?? '').toLowerCase();
      final list = idx.putIfAbsent(uuid, () => []);
      if (m.contains('gold') && !list.contains('gold')) list.add('gold');
      if (m.contains('silver') && !list.contains('silver')) list.add('silver');
    }
    return idx;
  }

  bool _matchesMetal(
      Map<String, List<String>> idx, String uuid, String basis, String metal) {
    final metals = idx[uuid] ?? const [];
    switch (metal) {
      case 'gold':
        return metals.contains('gold') ||
            (metals.isEmpty && basis.toLowerCase().contains('gold'));
      case 'silver':
        return metals.contains('silver') ||
            (metals.isEmpty && basis.toLowerCase().contains('silver'));
      case 'mixed':
        return metals.contains('gold') && metals.contains('silver');
    }
    return true;
  }

  Future<List<Map<String, Object?>>> _load() async {
    final db = context.read<AppState>().db;
    String? where;
    List<Object?> args = [];
    switch (_filter) {
      case 'active':
        where = 'status = ? OR status IS NULL';
        args = ['Active'];
        break;
      case 'released':
        where = 'status = ?';
        args = ['Released'];
        break;
      case 'old':
        final days = DateTime.now()
            .subtract(const Duration(days: 365))
            .toIso8601String()
            .substring(0, 10);
        where = '(status = ? OR status IS NULL) AND loan_date <= ?';
        args = ['Active', days];
        break;
      case 'interest':
        where = 'status = ? OR status IS NULL';
        args = ['Active'];
        break;
      case 'recent':
      case 'all':
      default:
        // 'all' = both Active and Released (the Active chip was tapped off).
        break;
    }
    final order =
        _filter == 'interest' ? 'interest_accrued desc' : 'loan_date desc';
    var rows = await db.query('pawn_loans',
        where: where,
        whereArgs: args.isEmpty ? null : args,
        orderBy: order,
        limit: _filter == 'recent' ? 10 : null);

    // Metal filter (Gold / Silver / Mixed) based on the loan's pawn items.
    final idx = await _metalIndex();
    _metalsByLoan = idx;
    if (_metal != 'all') {
      rows = rows
          .where((r) => _matchesMetal(idx, r['client_uuid']?.toString() ?? '',
              r['interest_basis']?.toString() ?? '', _metal))
          .toList();
    }

    final lookup = await _customerLookup();
    if (_village != null) {
      rows = rows
          .where((r) => _villageOf(r, lookup.byUuid, lookup.byName) == _village)
          .toList();
    }
    if (_category != null) {
      rows = rows
          .where((r) => (r['category']?.toString() ?? '') == _category)
          .toList();
    }
    if (_range != null) {
      final from = _range!.start.toIso8601String().substring(0, 10);
      final to = _range!.end.toIso8601String().substring(0, 10);
      rows = rows.where((r) {
        final d = r['loan_date']?.toString() ?? '';
        return d.isNotEmpty && d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
      }).toList();
    }

    // Attach the customer row for display only (photo, village, book ID).
    // Never add these keys to the loan row itself — it is spread into
    // db.upsert('pawn_loans'), and an unknown column would abort the write.
    _customerByLoan.clear();
    for (final r in rows) {
      final customer = _customerFor(r, lookup.byUuid, lookup.byName);
      if (customer != null) {
        _customerByLoan[r['client_uuid']?.toString() ?? ''] = customer;
      }
    }

    // Search by name, book ID or amount — the three things written on a slip.
    // Phone and village still match for the old habit.
    final term = _search.trim().toLowerCase();
    if (term.isNotEmpty) {
      rows = rows.where((r) {
        final customer = _customerByLoan[r['client_uuid']?.toString() ?? ''];
        final name = (r['customer_name'] ?? customer?['customer_name'] ?? '')
            .toString()
            .toLowerCase();
        final id = (customer?['customer_id'] ?? '').toString().toLowerCase();
        final phone =
            (customer?['phone'] ?? r['phone'] ?? '').toString().toLowerCase();
        final amount = Num.toDouble(r['loan_amount']).toStringAsFixed(0);
        final village =
            _villageOf(r, lookup.byUuid, lookup.byName).toLowerCase();
        return name.contains(term) ||
            id.contains(term) ||
            phone.contains(term) ||
            amount.contains(term.replaceAll(',', '')) ||
            village.contains(term);
      }).toList();
    }
    return rows;
  }

  Future<void> _openForm() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const PawnLoanForm()));
    if (mounted) {
      setState(() {});
      _loadVillageOptions();
    }
  }

  Future<void> _openDetail(Map<String, Object?> loan) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PawnDetail(
        loan: loan,
        customerId: (_customerByLoan[loan['client_uuid']?.toString() ?? '']
                    ?['customer_id']
                ?.toString()) ??
            '',
        onProfileAction: (action) => _runProfileAction(action, loan),
      ),
    );
    if (mounted) {
      setState(() {});
      _loadVillageOptions();
    }
  }

  void _runProfileAction(String action, Map<String, Object?> loan) {
    switch (action) {
      case 'call':
        _call(loan);
      case 'sms':
        _sms(loan);
      case 'whatsapp':
        _whatsapp(loan);
      case 'move':
        _showActions(loan);
      case 'edit':
        _editLoan(loan);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(
        title: const Text('Pawn Loans'),
        actions: [
          IconButton(
            tooltip: _selectMode ? 'Cancel selection' : 'Select multiple',
            icon: Icon(_selectMode ? Icons.close : Icons.checklist),
            onPressed: () => setState(() {
              _selectMode = !_selectMode;
              if (!_selectMode) _selected.clear();
            }),
          ),
          IconButton(
            tooltip: 'Dashboard',
            icon: const Icon(Icons.dashboard_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PawnDashboardScreen())),
          ),
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ReportsScreen(initialTab: 1))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('New Loan'),
      ),
      body: Column(
        children: [
          _summaryStrip(),
          _chipRow(),
          _metalRow(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              decoration: fieldDecoration('Search name, ID or amount'),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FutureBuilder<List<Map<String, Object?>>>(
                  future: _load(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                          child: CircularProgressIndicator(color: kGold));
                    }
                    final rows = snapshot.data!;
                    if (rows.isEmpty) {
                      return const Center(child: Text('No pawn loans here.'));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return _loanRow(row);
                      },
                    );
                  },
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
                if (_selectMode && _selected.isNotEmpty)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Material(
                        color: kInk,
                        borderRadius: BorderRadius.circular(14),
                        elevation: 6,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${_selected.length} selected',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () =>
                                    _chooseCategory(uuids: _selected.toList()),
                                icon: const Icon(Icons.drive_file_move_outline,
                                    size: 16, color: kGold),
                                label: const Text('Move to category',
                                    style:
                                        TextStyle(color: kGold, fontSize: 12)),
                              ),
                              IconButton(
                                tooltip: 'Clear selection',
                                icon: const Icon(Icons.close,
                                    color: Colors.white70, size: 18),
                                onPressed: () =>
                                    setState(() => _selected.clear()),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Two-row pledge tile:
  ///
  /// * row 1 — photo, **Name** and **₹Amount** (the two things the shop scans
  ///   for first);
  /// * row 2 — a highlighted **ID** badge, village, loan date and item, then
  ///   the cloud sync state and the Call/SMS/WhatsApp/Move/Edit menu.
  ///
  /// The Active / Released word is deliberately gone: the filter row already
  /// says which list is open. A released loan is muted and carries a small
  /// "Released" tag so it is not confused with an active one.
  Widget _loanRow(Map<String, Object?> row) {
    final uuid = row['client_uuid']?.toString() ?? '';
    final released = (row['status']?.toString() ?? 'Active') == 'Released';
    final customer = _customerByLoan[uuid];
    final name =
        (row['customer_name'] ?? customer?['customer_name'] ?? '-').toString();
    final id = (customer?['customer_id'] ?? '').toString().trim();
    final savedVillage = (customer?['village'] ?? '').toString().trim();
    final village = savedVillage.isNotEmpty
        ? savedVillage
        : (row['village'] ?? '').toString().trim();
    final metals = _metalsByLoan[uuid] ?? const <String>[];
    final item = metals.isEmpty
        ? (row['interest_basis']?.toString() ?? '')
        : metals.length > 1
            ? 'Mixed'
            : metals.first == 'gold'
                ? 'Gold'
                : 'Silver';
    final selected = _selected.contains(uuid);
    final amountValue = Num.toDouble(row['loan_amount']);

    return DragToDeleteTile(
      onDragChanged: (v) => setState(() => _dragActive = v),
      payload: DeletePayload(drop: () => _deleteLoan(row)),
      child: Material(
        color: selected ? kGold.withValues(alpha: .12) : Colors.transparent,
        child: InkWell(
          onTap:
              _selectMode ? () => _toggleSelect(uuid) : () => _openDetail(row),
          onLongPress: _selectMode ? null : () => _showActions(row),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                if (_selectMode)
                  Checkbox(
                    value: selected,
                    onChanged: (_) => _toggleSelect(uuid),
                  )
                else
                  _customerAvatar(customer, name),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: released
                                        ? mutedOf(context)
                                        : inkOf(context))),
                          ),
                          const SizedBox(width: 8),
                          Text('₹${moneyWhole(amountValue)}',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color:
                                      released ? mutedOf(context) : kGoldDark)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (id.isNotEmpty) ...[
                            _idBadge(id),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              [
                                if (village.isNotEmpty) village,
                                fmtDate(row['loan_date']),
                                if (item.isNotEmpty) item,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5, color: mutedOf(context)),
                            ),
                          ),
                          if (released)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: greenSoftOf(context),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Released',
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: kGreen)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runAction(String action, Map<String, Object?> row) async {
    switch (action) {
      case 'call':
        await _call(row);
        break;
      case 'sms':
        await _sms(row);
        break;
      case 'whatsapp':
        await _whatsapp(row);
        break;
      case 'move':
        await _chooseCategory(
            uuids: [row['client_uuid']?.toString() ?? ''],
            current: row['category']?.toString());
        break;
      case 'edit':
        await _editLoan(row);
        break;
    }
  }

  Widget _customerAvatar(Map<String, Object?>? customer, String name) {
    final photo = customer?['photo_path']?.toString() ?? '';
    final hasPhoto = photo.isNotEmpty && File(photo).existsSync();
    return CircleAvatar(
      radius: 22,
      backgroundColor: kGold.withValues(alpha: .16),
      foregroundImage: hasPhoto ? FileImage(File(photo)) : null,
      child: hasPhoto
          ? null
          : Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: kGoldDark),
            ),
    );
  }

  /// Removes the loan plus its items, transactions, releases and payment rows.
  Future<bool> _deleteLoan(Map<String, Object?> row) async {
    final state = context.read<AppState>();
    final granted = await askPasswordIfEnabled(context, state,
        actionId: 'pawn_delete',
        action: 'delete',
        detail: row['customer_name']?.toString() ?? 'pawn loan');
    // The password dialog was async - the loan sheet may be closed by now.
    if (!mounted) return false;
    if (granted != true) {
      _toast(context, 'Delete cancelled / wrong password.');
      return false;
    }
    final db = state.db;
    final uuid = row['client_uuid'] as String?;
    final ref = (row['server_name'] as String?) ?? uuid;
    if (uuid == null) return false;
    // Releases have their own Cash IN entry; remove them with the loan so a
    // delete cannot leave cash that never came in.
    final releases = await db.query('pawn_releases',
        where: 'pawn_loan = ? OR pawn_loan = ?', whereArgs: [ref, uuid]);
    await state.deleteCashbookFor({
      uuid,
      if (ref != null) ref,
      for (final r in releases) r['client_uuid']?.toString() ?? '',
    });
    await db.delete('pawn_loans', where: 'client_uuid = ?', whereArgs: [uuid]);
    await db.delete('pawn_items', where: 'loan_uuid = ?', whereArgs: [uuid]);
    await db.delete('pawn_transactions',
        where: 'pawn_loan = ? OR pawn_loan = ?', whereArgs: [ref, uuid]);
    await db.delete('pawn_releases',
        where: 'pawn_loan = ? OR pawn_loan = ?', whereArgs: [ref, uuid]);
    await state.logEvent(
        'pawn', 'delete', 'Pawn loan deleted — ${row['customer_name'] ?? ''}',
        amount: Num.toDouble(row['loan_amount']));
    if (mounted) setState(() {});
    return true;
  }

  Widget _summaryStrip() {
    final db = context.read<AppState>().db;
    final metal = _metal;
    final village = _village;
    return FutureBuilder<Map<String, Object?>>(
      future: () async {
        final loans = await db.query('pawn_loans',
            where: 'status = ? OR status IS NULL', whereArgs: ['Active']);
        var filtered = loans;
        if (metal != 'all') {
          final idx = await _metalIndex();
          filtered = filtered
              .where((l) => _matchesMetal(
                  idx,
                  l['client_uuid']?.toString() ?? '',
                  l['interest_basis']?.toString() ?? '',
                  metal))
              .toList();
        }
        if (village != null) {
          final lookup = await _customerLookup();
          filtered = filtered
              .where(
                  (l) => _villageOf(l, lookup.byUuid, lookup.byName) == village)
              .toList();
        }
        double out = 0, intDue = 0, outstanding = 0;
        final totals = PawnMath.totals(filtered);
        out = totals.investment;
        intDue = totals.interest;
        outstanding = totals.outstanding;
        return {
          'out': out,
          'int': intDue,
          'total': outstanding,
          'metal': metal,
          'village': village,
        };
      }(),
      builder: (context, snap) {
        final r = snap.data ?? const {};
        final caption = switch (r['metal']) {
          'gold' => 'Gold pawns only',
          'silver' => 'Silver pawns only',
          'mixed' => 'Gold + Silver pawns (mixed)',
          _ => null,
        };
        final captions = [
          if (caption != null) caption,
          if (r['village'] != null) 'Village: ${r['village']}',
        ];
        Widget stat(String value, String label) => Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: .75))),
                ],
              ),
            );
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3A2E0E), Color(0xFF6B5417)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  stat('₹${moneyWhole(r['out'] as num?)}', 'Investment'),
                  stat('₹${moneyWhole(r['int'] as num?)}', 'Interest due'),
                  stat('₹${moneyWhole(r['total'] as num?)}', 'Outstanding'),
                ],
              ),
              if (captions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_alt_outlined,
                          size: 13, color: Colors.white70),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(captions.join(' · '),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _chipRow() {
    final tags = <(String, String)>[
      ('Active', 'active'),
      ('Released', 'released'),
      if (_filter == 'old') ('Old 12M+', 'old'),
      if (_filter == 'recent') ('Recent', 'recent'),
      if (_filter == 'interest') ('Interest due', 'interest'),
    ];
    final selectedVillage = _village;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (label, value) in tags)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(label),
                  selected: _filter == value,
                  selectedColor: kGold.withValues(alpha: .3),
                  labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          _filter == value ? FontWeight.w700 : FontWeight.w500,
                      color: _filter == value
                          ? kGoldDark
                          : kInk.withValues(alpha: .7)),
                  // Tapping the selected chip clears it, so the list shows
                  // Active + Released together.
                  onSelected: (_) => setState(
                      () => _filter = _filter == value ? 'all' : value),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PopupMenuButton<String>(
                key: const ValueKey('pawn-village-filter'),
                tooltip: 'Filter by village',
                onSelected: (value) =>
                    setState(() => _village = value.isEmpty ? null : value),
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    value: '',
                    key: ValueKey('pawn-village-all'),
                    child: Text('All villages'),
                  ),
                  for (final village in _villageOptions)
                    PopupMenuItem<String>(
                      value: village,
                      key: ValueKey('pawn-village-$village'),
                      child: Text(village),
                    ),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: selectedVillage == null
                        ? Colors.transparent
                        : kGold.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selectedVillage == null
                          ? Theme.of(context).dividerColor
                          : kGold,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 15,
                          color: selectedVillage == null
                              ? kInk.withValues(alpha: .7)
                              : kGoldDark),
                      const SizedBox(width: 4),
                      Text(
                        selectedVillage == null
                            ? 'Villages'
                            : 'Villages: $selectedVillage',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selectedVillage == null
                              ? FontWeight.w500
                              : FontWeight.w700,
                          color: selectedVillage == null
                              ? kInk.withValues(alpha: .7)
                              : kGoldDark,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PopupMenuButton<String>(
                key: const ValueKey('pawn-filter'),
                tooltip: 'Filter: Categories, Date range, Amount range',
                onSelected: (value) {
                  if (value == '__manage__') {
                    _openCategories();
                    return;
                  }
                  if (value == '__date__') {
                    _pickDateRange();
                    return;
                  }
                  if (value.startsWith('__amount__')) {
                    _pickAmountRange(value);
                    return;
                  }
                  setState(() => _category = value.isEmpty ? null : value);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                      value: '', child: Text('All categories')),
                  for (final name in _categories)
                    PopupMenuItem<String>(
                      value: name,
                      key: ValueKey('pawn-category-$name'),
                      child: Text(name),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                      value: '__date__',
                      child: Row(
                        children: [
                          Icon(Icons.date_range_outlined,
                              size: 18, color: kGoldDark),
                          SizedBox(width: 10),
                          Text('Date range'),
                        ],
                      )),
                  PopupMenuItem<String>(
                    value: '__amount__min_null_max_null',
                    enabled: _amountRange == null,
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_wallet_outlined,
                            size: 18, color: kGoldDark),
                        SizedBox(width: 10),
                        Text('Amount range'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                      value: '__manage__', child: Text('Manage categories…')),
                ],
                child: _filterPill(
                  icon: Icons.filter_list_outlined,
                  label: _filterLabel,
                  active: _category != null ||
                      _range != null ||
                      _amountRange != null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _filterLabel {
    if (_category != null) return 'Category: $_category';
    if (_range != null)
      return '${_short(_range!.start)} – ${_short(_range!.end)}';
    if (_amountRange != null) {
      final (lo, hi) = _amountRange!;
      return '${moneyWhole(lo)} – ${moneyWhole(hi)}';
    }
    return 'Filter';
  }

  void _pickAmountRange(String value) {
    _toast(context, 'Amount range picker — coming next.');
  }

  /// Gold / Silver / Mixed item filter — the summary strip and the loan list
  /// both respect it (Mixed = loans holding both gold AND silver pawn items).
  Widget _metalRow() {
    final tags = <(String, String, IconData)>[
      ('Gold', 'gold', Icons.diamond_outlined),
      ('Silver', 'silver', Icons.circle_outlined),
      ('Mixed', 'mixed', Icons.join_inner),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (label, value, icon) in tags)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  avatar: Icon(icon,
                      size: 15,
                      color: _metal == value ? kGoldDark : mutedOf(context)),
                  label: Text(label),
                  selected: _metal == value,
                  selectedColor: kGold.withValues(alpha: .3),
                  labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          _metal == value ? FontWeight.w700 : FontWeight.w500,
                      color: _metal == value
                          ? kGoldDark
                          : kInk.withValues(alpha: .7)),
                  // Same as Active / Released: tap again to clear it.
                  onSelected: (_) =>
                      setState(() => _metal = _metal == value ? 'all' : value),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- categories
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _short(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  void _toggleSelect(String uuid) {
    setState(() {
      if (!_selected.remove(uuid)) _selected.add(uuid);
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _range,
      helpText: 'Pawn loans by loan date',
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
  }

  Future<void> _openCategories() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const PawnCategoriesScreen()));
    if (!mounted) return;
    final names = await context.read<AppState>().pawnCategories();
    if (!mounted) return;
    setState(() {
      _categories = names;
      if (_category != null && !names.contains(_category)) _category = null;
    });
  }

  /// "Move to another pawn profile" — the shop's wording for a category.
  Future<void> _chooseCategory({
    required List<String> uuids,
    String? current,
    String title = 'Move to another pawn profile',
  }) async {
    final state = context.read<AppState>();
    final names = await state.pawnCategories();
    if (!mounted) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, '__none__'),
            child: const Text('No category'),
          ),
          for (final name in names)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, name),
              child: Row(
                children: [
                  Expanded(child: Text(name)),
                  if (name == current) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
          const Divider(height: 8),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, '__manage__'),
            child: const Text('Manage categories…'),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    if (chosen == '__manage__') {
      await _openCategories();
      return;
    }
    await state.setPawnCategory(uuids, chosen == '__none__' ? null : chosen);
    if (!mounted) return;
    setState(() => _selected.clear());
    _toast(context,
        chosen == '__none__' ? 'Category removed.' : 'Moved to $chosen.');
  }

  // --------------------------------------------------------------- actions
  String _phoneOf(Map<String, Object?> row) {
    final customer = _customerByLoan[row['client_uuid']?.toString() ?? ''];
    final saved = (customer?['phone'] ?? '').toString().trim();
    return saved.isNotEmpty ? saved : (row['phone'] ?? '').toString().trim();
  }

  Future<void> _call(Map<String, Object?> row) async {
    final phone = _phoneOf(row).replaceAll(RegExp(r'\s'), '');
    if (phone.isEmpty) {
      _toast(context, 'No phone number saved.');
      return;
    }
    final ok = await launchUrl(Uri.parse('tel:$phone'),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) _toast(context, 'Could not open the dialer.');
  }

  Future<void> _sms(Map<String, Object?> row) async {
    final phone = _phoneOf(row).replaceAll(RegExp(r'\s'), '');
    if (phone.isEmpty) {
      _toast(context, 'No phone number saved.');
      return;
    }
    final uri = Uri(scheme: 'sms', path: phone, queryParameters: {
      'body': 'Namaste ${row['customer_name'] ?? ''} 🙏\n'
          'Your pawn loan of ₹${moneyWhole(row['loan_amount'] as num?)} is with us.',
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _toast(context, 'Could not open SMS.');
  }

  Future<void> _whatsapp(Map<String, Object?> row) async {
    final digits = _phoneOf(row).replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      _toast(context, 'No phone number saved.');
      return;
    }
    final text = Uri.encodeComponent(
        'Namaste ${row['customer_name'] ?? ''} 🙏\n'
        'Your pawn loan of ₹${moneyWhole(row['loan_amount'] as num?)} is with us.');
    final ok = await launchUrl(Uri.parse('https://wa.me/$digits?text=$text'),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) _toast(context, 'Could not open WhatsApp.');
  }

  Future<void> _showActions(Map<String, Object?> row) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(row['customer_name']?.toString() ?? '-',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('₹${moneyWhole(row['loan_amount'] as num?)} · '
                  '${fmtDate(row['loan_date'])}'),
            ),
            const Divider(height: 1),
            ListTile(
                leading: const Icon(Icons.call_outlined),
                title: const Text('Call'),
                onTap: () => Navigator.pop(ctx, 'call')),
            ListTile(
                leading: const Icon(Icons.sms_outlined),
                title: const Text('SMS'),
                onTap: () => Navigator.pop(ctx, 'sms')),
            ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: const Text('WhatsApp'),
                onTap: () => Navigator.pop(ctx, 'whatsapp')),
            ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text('Move to another pawn profile'),
                onTap: () => Navigator.pop(ctx, 'move')),
            ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(ctx, 'edit')),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    await _runAction(action, row);
  }

  Future<void> _editLoan(Map<String, Object?> row) async {
    final state = context.read<AppState>();
    final paid = Num.toDouble(row['amount_paid']);
    final amount = TextEditingController(
        text: Num.toDouble(row['loan_amount']).toStringAsFixed(0));
    final rate = TextEditingController(
        text: Num.toDouble(row['interest_rate']).toString());
    var loanDate =
        DateTime.tryParse(row['loan_date']?.toString() ?? '') ?? DateTime.now();
    var dueDate = DateTime.tryParse(row['due_date']?.toString() ?? '') ??
        loanDate.add(const Duration(days: 90));
    var actualDue = DateTime.tryParse(row['pawn_due_actual']?.toString() ?? '');
    actualDue ??= dueDate;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            title: const Text('Edit pawn loan'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amount,
                    enabled: paid <= 0,
                    keyboardType: TextInputType.number,
                    decoration: fieldDecoration(paid > 0
                        ? 'Principal (payments recorded)'
                        : 'Principal'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: rate,
                    keyboardType: TextInputType.number,
                    decoration: fieldDecoration('Interest rate % / month'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: loanDate,
                      );
                      if (picked != null) setDlg(() => loanDate = picked);
                    },
                    icon: const Icon(Icons.event, size: 17),
                    label: Text('Loan date: ${_iso(loanDate)}'),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: dueDate,
                      );
                      if (picked != null) setDlg(() => dueDate = picked);
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text('Due date (promised): ${_iso(dueDate)}'),
                  ),
                  if (paid > 0) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Money has already been paid on this loan, so the '
                      'principal stays fixed. Use the profile for payments.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save')),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
      final principal = paid > 0
          ? Num.toDouble(row['loan_amount'])
          : Num.money(parseMoney(amount.text));
      if (principal <= 0) {
        _toast(context, 'Enter a valid principal.');
        return;
      }
      final parsedRate = parseMoney(rate.text);
      final useRate = parsedRate <= 0 ? 3.0 : parsedRate;
      final interest = Num.simpleInterest(
        principal: principal,
        ratePerMonth: useRate,
        days: dueDate.difference(loanDate).inDays,
      );
      final total = Num.money(principal + interest);
      final items = await state.db.query('pawn_items',
          where: 'loan_uuid = ?', whereArgs: [row['client_uuid']]);
      await state.savePawnLoan(
        uuid: row['client_uuid'] as String,
        data: {
          ...row,
          'loan_amount': principal,
          'interest_rate': useRate,
          'loan_date': _iso(loanDate),
          'due_date': _iso(dueDate),
          // v1.1.6: when the shop “closes the date” on a pawn, the actual
          // due date advanced and interest is recalculated from it. Initially
          // the actual column is null and the form falls back to the promised
          // due date, so the profile still shows something useful.
          if (actualDue.isBefore(loanDate)) 'pawn_due_actual': _iso(loanDate),
          'interest_accrued': interest,
          'total_payable': total,
          'balance': Num.money(total - paid),
          'last_interest_date': _iso(dueDate),
        },
        items: items,
      );
      if (!mounted) return;
      setState(() {});
      _toast(context, 'Pawn loan updated.');
    } catch (e) {
      if (mounted) _toast(context, 'Could not save: $e');
    } finally {
      amount.dispose();
      rate.dispose();
    }
  }

  // ------------------------------------------------------------------ bits
  Widget _idBadge(String id) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(
          color: kGold.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: kGold.withValues(alpha: .45)),
        ),
        child: Text('ID $id',
            style: const TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: kGoldDark)),
      );

  Widget _filterPill({
    required IconData icon,
    required String label,
    required bool active,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active ? kGold.withValues(alpha: .3) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? kGold : Theme.of(context).dividerColor,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 15, color: active ? kGoldDark : kInk.withValues(alpha: .7)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? kGoldDark : kInk.withValues(alpha: .7))),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing,
          ] else
            const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }
}

class _PawnDetail extends StatefulWidget {
  const _PawnDetail({
    required this.loan,
    this.customerId = '',
    this.onProfileAction,
  });

  final Map<String, Object?> loan;
  final String customerId;
  final void Function(String)? onProfileAction;

  @override
  State<_PawnDetail> createState() => _PawnDetailState();
}

class _PawnDetailState extends State<_PawnDetail> {
  List<Map<String, Object?>> _items = [];
  List<Map<String, Object?>> _transactions = [];
  late Map<String, Object?> _loan;
  Map<String, Object?> _customer = {};
  bool _dragActive = false;

  @override
  void initState() {
    super.initState();
    _loan = widget.loan;
    _loadCustomer();
    _loadItems();
    _loadTransactions();
  }

  String get _name =>
      (_customer['customer_name'] ?? _loan['customer_name'] ?? '-').toString();

  String get _village {
    final saved = (_customer['village'] ?? '').toString().trim();
    return saved.isNotEmpty
        ? saved
        : (_loan['village'] ?? '').toString().trim();
  }

  String get _address => (_customer['address'] ?? '').toString().trim();

  /// The actual due date is the date the shop closed the pawn for calculation
  /// — e.g. opened on 5 Nov 2026, the Actual Due Date later shows 5/Nov/26
  /// after the dates are updated. Pending a first recalc, it falls back to the
  /// promised due date so the profile still shows something useful.
  DateTime? _actualDue(Map<String, Object?> loan) {
    final raw = loan['pawn_due_actual']?.toString().trim();
    if (raw != null && raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    final promised = DateTime.tryParse(loan['due_date']?.toString() ?? '');
    return promised ?? DateTime.now();
  }

  String get _phone {
    final saved = (_customer['phone'] ?? '').toString().trim();
    return saved.isNotEmpty ? saved : (_loan['phone'] ?? '').toString().trim();
  }

  String get _bookId {
    final saved = (_customer['customer_id'] ?? '').toString().trim();
    return saved.isNotEmpty ? saved : widget.customerId.trim();
  }

  String get _photo => (_customer['photo_path'] ?? '').toString().trim();
  String get _kycFront => (_customer['id_photo_front'] ?? '').toString().trim();
  String get _kycBack => (_customer['id_photo_back'] ?? '').toString().trim();

  Future<void> _loadCustomer() async {
    final db = context.read<AppState>().db;
    Map<String, Object?>? found;
    final uuid = _loan['customer_uuid']?.toString() ?? '';
    if (uuid.isNotEmpty) found = await db.byUuid('customers', uuid);
    if (found == null) {
      final rows = await db.query(
        'customers',
        where: 'customer_name = ?',
        whereArgs: [_loan['customer_name']],
        limit: 1,
      );
      if (rows.isNotEmpty) found = rows.first;
    }
    if (mounted) setState(() => _customer = found ?? {});
  }

  Future<void> _loadItems() async {
    final items = await context
        .read<AppState>()
        .itemsFor(widget.loan['client_uuid'] as String);
    if (mounted) setState(() => _items = items);
  }

  /// Latest transaction's effective date anchors future interest accrual
  /// ("new calculations start from that date").
  DateTime? get _anchorDate {
    for (final t in _transactions) {
      final d = DateTime.tryParse(t['effective_date']?.toString() ?? '');
      if (d != null) return d;
    }
    return null;
  }

  Future<void> _loadTransactions() async {
    final state = context.read<AppState>();
    final db = state.db;
    final ref = (_loan['server_name'] as String?) ?? _loan['client_uuid'];
    final tx = await db
        .query('pawn_transactions', where: 'pawn_loan = ?', whereArgs: [ref]);
    final releases = await db
        .query('pawn_releases', where: 'pawn_loan = ?', whereArgs: [ref]);
    final combined = <Map<String, Object?>>[
      ...tx,
      for (final r in releases)
        {
          'tx_type': 'release',
          'tx_date': r['release_date'],
          'effective_date': r['release_date'],
          'amount': r['total_paid'],
          'principal_part': r['principal_paid'],
          'interest_part': r['interest_paid'],
        },
    ];
    combined.sort((a, b) {
      final da = DateTime.tryParse(a['effective_date']?.toString() ?? '');
      final dbd = DateTime.tryParse(b['effective_date']?.toString() ?? '');
      return (dbd ?? DateTime(0)).compareTo(da ?? DateTime(0));
    });
    if (mounted) setState(() => _transactions = combined);
  }

  String _dateOnly(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$dd';
  }

  /// Local-only ledger row (no server DocType): records when the change was
  /// entered (`tx_date`) AND the date it applies from (`effective_date`).
  Future<void> _recordTransaction({
    required String type,
    required double amount,
    required double principalPart,
    required double interestPart,
    required DateTime effective,
  }) async {
    final state = context.read<AppState>();
    await state.db.upsert('pawn_transactions', {
      'client_uuid': newUuid(),
      'server_name': null,
      'dirty': 0,
      'pawn_loan': (_loan['server_name'] as String?) ?? _loan['client_uuid'],
      'customer': _loan['client_uuid'],
      'customer_name': _loan['customer_name'],
      'customer_uuid': _loan['customer_uuid'],
      'tx_date': todayIso(),
      'effective_date': _dateOnly(effective),
      'tx_type': type,
      'amount': Num.money(amount),
      'principal_part': Num.money(principalPart),
      'interest_part': Num.money(interestPart),
      'notes': null,
      'updated_at': DateTime.now().toIso8601String(),
    });
    await _loadTransactions();
  }

  /// Persists the loan change locally and queues a Pawn Loan update so the
  /// server keeps the same numbers (pull would otherwise overwrite us).
  Future<void> _applyToLoan(
    Map<String, Object?> overrides, {
    required String logKind,
    required String logTitle,
    double logAmount = 0,
  }) async {
    final state = context.read<AppState>();
    final uuid = _loan['client_uuid'] as String;
    final serverName = _loan['server_name'] as String?;
    final updated = <String, Object?>{
      ..._loan,
      ...overrides,
      'dirty': 1,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await state.db.upsert('pawn_loans', updated);
    await state.db.enqueue(
      op: 'update',
      doctype: 'Pawn Loan',
      clientUuid: uuid,
      data: {
        ...updated,
        if (serverName != null) 'name': serverName,
      },
    );
    await state.refreshCounts();
    await state.logEvent('pawn', logKind, logTitle,
        amount: logAmount,
        village: _loan['village']?.toString(),
        ref: _loan['server_name']?.toString());
    if (mounted) setState(() => _loan = updated);
  }

  /// Drag-to-delete for a pawn ITEM: removes the item row and recomputes the
  /// loan's weight / market value / LTV totals from the remaining items.
  Future<bool> _deleteItem(Map<String, Object?> item) async {
    final state = context.read<AppState>();
    final ok = await confirmDialog(
      context,
      'Remove this item from the pawn? Removing it lowers the collateral.',
      title: 'Remove item',
    );
    if (!ok) return false;
    final id = item['id'] as int?;
    if (id == null) return false;
    await state.db.deleteWhere('pawn_items', 'id = ?', [id]);
    final items = await state.itemsFor(widget.loan['client_uuid'] as String);
    var tg = 0.0, tn = 0.0, hm = 0.0, mv = 0.0;
    for (final i in items) {
      tg += Num.toDouble(i['gross_weight']);
      tn += Num.toDouble(i['net_weight']);
      if (i['hallmarked'] == 1) hm += Num.toDouble(i['net_weight']);
      mv += Num.toDouble(i['market_value']);
    }
    final loanAmount = Num.toDouble(_loan['loan_amount']);
    await _applyToLoan(
      {
        'total_gross_weight': Num.round3(tg),
        'total_net_weight': Num.round3(tn),
        'hallmarked_weight': Num.round3(hm),
        'non_hallmarked_weight': Num.round3(tn - hm),
        'total_market_value': Num.money(mv),
        'ltv': mv > 0 ? Num.roundPct(loanAmount / mv * 100) : 0,
      },
      logKind: 'delete-item',
      logTitle: 'Pawn item removed — ${item['item_description'] ?? ''}',
    );
    if (mounted) setState(() => _items = items);
    return true;
  }

  /// Drag-to-delete for a pawn LEDGER entry: removes the row and undoes its
  /// effect on the loan (payments restore principal/interest, requests reduce
  /// the principal, releases reopen the loan).
  Future<bool> _deleteTransaction(Map<String, Object?> t) async {
    final type = t['tx_type']?.toString() ?? '';
    final state = context.read<AppState>();
    final ok = await confirmDialog(
      context,
      'Remove this ledger entry and undo its effect on the loan?',
      title: 'Remove entry',
    );
    if (!ok) return false;
    final db = state.db;
    final ref = (_loan['server_name'] as String?) ?? _loan['client_uuid'];

    var np = Num.toDouble(_loan['loan_amount']);
    var ni = Num.toDouble(_loan['interest_accrued']);
    var nPaid = Num.toDouble(_loan['amount_paid']);

    if (type == 'release') {
      final releases = await db
          .query('pawn_releases', where: 'pawn_loan = ?', whereArgs: [ref]);
      await state.deleteCashbookFor(
          releases.map((r) => r['client_uuid']?.toString() ?? ''));
      await db
          .delete('pawn_releases', where: 'pawn_loan = ?', whereArgs: [ref]);
      np = Num.money(np + Num.toDouble(t['principal_part']));
      ni = Num.money(ni + Num.toDouble(t['interest_part']));
      nPaid = Num.money(nPaid - Num.toDouble(t['amount']));
    } else {
      final cu = t['client_uuid'] as String?;
      if (cu != null) {
        await db.delete('pawn_transactions',
            where: 'client_uuid = ?', whereArgs: [cu]);
      }
      if (type == 'paying' || type == 'interest_paid') {
        np = Num.money(np + Num.toDouble(t['principal_part']));
        ni = Num.money(ni + Num.toDouble(t['interest_part']));
        nPaid = Num.money(nPaid - Num.toDouble(t['amount']));
      } else if (type == 'requesting') {
        np = Num.money((np - Num.toDouble(t['principal_part']))
            .clamp(0.0, double.infinity));
        ni = Num.money((ni - Num.toDouble(t['interest_part']))
            .clamp(0.0, double.infinity));
      }
    }
    if (nPaid < 0) nPaid = 0;
    final total = Num.money(np + ni);
    final balance = Num.money(total - nPaid);
    final overrides = <String, Object?>{
      'loan_amount': np,
      'interest_accrued': ni,
      'total_payable': total,
      'amount_paid': nPaid,
      'balance': balance < 0 ? 0 : balance,
    };
    if (_loan['status']?.toString() == 'Released') {
      if (balance > 0.005) {
        overrides['status'] = 'Active';
        overrides['release_date'] = null;
      } else {
        overrides['status'] = 'Released';
      }
    }
    await _applyToLoan(overrides,
        logKind: 'undo',
        logTitle: 'Pawn ledger entry removed — $type',
        logAmount: Num.toDouble(t['amount']));
    await _loadTransactions();
    return true;
  }

  /// Single amount + date dialog shared by the pawn ops (v1.0.8). Returns
  /// (amount, effectiveDate) or null when cancelled.
  Future<(double, DateTime)?> _amountDialog(
      String title, String label, double suggest) async {
    final controller = TextEditingController(text: moneyWhole(suggest));
    var picked = _anchorDate ?? DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(title)),
              IconButton(
                tooltip: 'Date (past or future)',
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: picked,
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2100),
                    helpText: 'Date the change applies from',
                  );
                  if (d != null) {
                    setDlg(() => picked = DateTime(d.year, d.month, d.day));
                  }
                },
                icon: const Icon(Icons.calendar_month),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: fieldDecoration(label)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: picked,
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2100),
                    helpText: 'Date the change applies from',
                  );
                  if (d != null) {
                    setDlg(() => picked = DateTime(d.year, d.month, d.day));
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event, size: 16, color: kGoldDark),
                    const SizedBox(width: 6),
                    Text('Applies from ${fmtDate(picked)}',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: kGoldDark)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    final amount = Num.money(parseMoney(controller.text));
    if (amount <= 0) return null;
    return (amount, picked);
  }

  /// Amount Paying — the payment clears interest FIRST, then principal
  /// (e.g. ₹4,000 on an ₹10,300 balance). Writes a dated ledger row and
  /// restarts interest accrual from the chosen date.
  Future<void> _amountPaying() async {
    final loan = _loan;
    // Interest runs with the calendar, so settle everything up to the chosen
    // effective date BEFORE splitting the payment. Without this the app would
    // clear only the interest it happened to have stored.
    final out = PawnMath.outstanding(loan);
    final res = await _amountDialog('Amount Paying', 'Amount received', out);
    if (res == null) return;
    final (pay, effective) = res;
    final asOf = effective;
    final dueInterest = PawnMath.interestDue(loan, asOf);
    final interestPart = Num.money(dueInterest < pay ? dueInterest : pay);
    final principalPart = Num.money(pay - interestPart);
    // Principal can never go below zero — a large "interest paid" on a small
    // loan must not write a negative principal (which the server would then
    // multiply by the rate to make negative interest).
    final newPrincipal =
        Num.money(math.max(0, PawnMath.principalOut(loan) - principalPart));
    final newInterest = Num.money(dueInterest - interestPart);
    final newPaid = Num.money(Num.toDouble(loan['amount_paid']) + pay);
    final total = Num.money(newPrincipal + newInterest);
    final newBalance = Num.money(total - newPaid);
    final overrides = <String, Object?>{
      'loan_amount': newPrincipal,
      'interest_accrued': newInterest,
      'total_payable': total,
      'amount_paid': newPaid,
      'balance': newBalance < 0 ? 0 : newBalance,
      'last_interest_date': PawnMath.isoDate(asOf),
      if (newBalance <= 0.005) ...{
        'status': 'Released',
        'release_date': _dateOnly(effective),
      },
    };
    await _recordTransaction(
      type: 'paying',
      amount: pay,
      principalPart: principalPart,
      interestPart: interestPart,
      effective: effective,
    );
    await _applyToLoan(overrides,
        logKind: 'pay',
        logTitle: 'Amount paying — ${loan['customer_name'] ?? ''}',
        logAmount: pay);
  }

  /// Amount Requesting — the borrower takes more on the item: adds to the
  /// principal (outstanding + pawn investment) and accrues interest on the
  /// fresh amount from the chosen date.
  Future<void> _amountRequesting() async {
    final loan = _loan;
    final res = await _amountDialog('Amount Requesting', 'New amount given', 0);
    if (res == null) return;
    final (more, effective) = res;
    final rate = Num.toDouble(loan['interest_rate']);
    final asOf = effective;
    // Settle the elapsed interest on the OLD principal first, then add the new
    // principal and start its own accrual from the same date.
    final days = DateTime.now().difference(asOf).inDays;
    final freshInterest = Num.simpleInterest(
        principal: more, ratePerMonth: rate, days: days < 0 ? 0 : days);
    final newPrincipal = Num.money(PawnMath.principalOut(loan) + more);
    final newInterest =
        Num.money(PawnMath.interestDue(loan, asOf) + freshInterest);
    final newPaid = Num.toDouble(loan['amount_paid']);
    final total = Num.money(newPrincipal + newInterest);
    final newBalance = Num.money(total - newPaid);
    await _recordTransaction(
      type: 'requesting',
      amount: more,
      principalPart: more,
      interestPart: freshInterest,
      effective: asOf,
    );
    await _applyToLoan({
      'loan_amount': newPrincipal,
      'interest_accrued': newInterest,
      'total_payable': total,
      'balance': newBalance < 0 ? 0 : newBalance,
      'last_interest_date': PawnMath.isoDate(asOf),
    },
        logKind: 'request',
        logTitle: 'Amount requesting — ${loan['customer_name'] ?? ''}',
        logAmount: more);
  }

  /// Interest Paid — the entered amount clears interest first; any excess
  /// reduces principal, exactly like Amount Paying.
  Future<void> _interestPaid() async {
    final loan = _loan;
    final res = await _amountDialog('Interest Paid', 'Interest amount paid', 0);
    if (res == null) return;
    final (amt, effective) = res;
    final asOf = effective;
    final accrued = PawnMath.interestDue(loan, asOf);
    final interestPart = Num.money(accrued < amt ? accrued : amt);
    final principalPart = Num.money(amt - interestPart);
    final newInterest = Num.money(accrued - interestPart);
    // Principal can never go below zero.
    final newPrincipal =
        Num.money(math.max(0, PawnMath.principalOut(loan) - principalPart));
    final newPaid = Num.money(Num.toDouble(loan['amount_paid']) + amt);
    final total = Num.money(newPrincipal + newInterest);
    final newBalance = Num.money(total - newPaid);
    final overrides = <String, Object?>{
      'interest_accrued': newInterest,
      'loan_amount': newPrincipal,
      'total_payable': total,
      'amount_paid': newPaid,
      'last_interest_date': PawnMath.isoDate(asOf),
      'balance': newBalance < 0 ? 0 : newBalance,
      if (newBalance <= 0.005) ...{
        'status': 'Released',
        'release_date': _dateOnly(effective),
      },
    };
    await _recordTransaction(
      type: 'interest_paid',
      amount: amt,
      principalPart: principalPart,
      interestPart: interestPart,
      effective: effective,
    );
    await _applyToLoan(overrides,
        logKind: 'interest',
        logTitle: 'Interest paid — ${loan['customer_name'] ?? ''}',
        logAmount: amt);
  }

  /// Full release: settles interest first, then principal, marks the loan
  /// Released and records the event in the pawn ledger.
  Future<void> _release() async {
    // Hoisted above the two dialogs below: releasing a pawn hands over gold and
    // takes cash, so it must never be abandoned on a UI-timing technicality.
    final state = context.read<AppState>();
    final loan = _loan;
    final asOf = DateTime.now();
    final rate = Num.toDouble(loan['interest_rate']);
    // Settlement comes from PawnMath: the interest owed TODAY (stored + earned
    // since the last anchor), never a stale stored figure — releasing a loan
    // for less than the customer owes loses the shop real money.
    final interestDue = PawnMath.interestDue(loan, asOf);
    final principalDue = PawnMath.principalOut(loan);
    final totalToReceive = Num.money(interestDue + principalDue);

    final principalController =
        TextEditingController(text: principalDue.toStringAsFixed(2));
    final interestController =
        TextEditingController(text: interestDue.toStringAsFixed(2));

    Widget sumRow(String label, String value, {bool bold = false}) {
      final color = Theme.of(context).colorScheme.onSurface;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                    color: bold ? color : color.withValues(alpha: .65))),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: color)),
          ],
        ),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release pawn'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Days since last settlement: '
                '${asOf.difference(PawnMath.anchorOf(loan)).inDays}'
                '  ·  Rate: $rate%/month'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  sumRow(
                      'Principal outstanding', '₹${moneyText(principalDue)}'),
                  sumRow('Interest outstanding', '₹${moneyText(interestDue)}'),
                  const Divider(height: 14),
                  sumRow('Total to receive', '₹${moneyText(totalToReceive)}',
                      bold: true),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: principalController,
                keyboardType: TextInputType.number,
                decoration: fieldDecoration('Principal paid')),
            const SizedBox(height: 10),
            TextField(
                controller: interestController,
                keyboardType: TextInputType.number,
                decoration: fieldDecoration('Interest paid')),
            const SizedBox(height: 8),
            Text(
              'Interest clears first, then principal. Partial release is '
              'not supported — the full Total to receive must be paid to '
              'release.',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .6)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Release')),
        ],
      ),
    );
    if (ok != true) return;

    if (!mounted) return;
    final granted = await askPasswordIfEnabled(context, state,
        actionId: 'pawn_release', action: 'release', detail: 'this pawn loan');
    if (!mounted) return;
    if (granted != true) {
      _toast(context, 'Release cancelled / wrong password.');
      return;
    }
    final pp = Num.money(parseMoney(principalController.text));
    final ip = Num.money(parseMoney(interestController.text));
    final total = Num.money(pp + ip);

    // Blueprint §10: interest clears first, remaining payment clears
    // principal, and partial release is intentionally not supported.
    final interestShort = ip < interestDue - 0.005;
    final totalOff = (total - totalToReceive).abs() > 0.005;
    if (interestShort || totalOff) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(interestShort
              ? 'Interest of ₹${moneyText(interestDue)} must be cleared '
                  'first — the remaining amount reduces principal.'
              : 'Partial release is not supported. The full balance of '
                  '₹${moneyText(totalToReceive)} is required to release.'),
        ));
      }
      return;
    }

    try {
      await state.saveEntity(
        table: 'pawn_releases',
        doctype: 'Pawn Release',
        uuid: newUuid(),
        data: {
          'pawn_loan': loan['server_name'] ?? loan['client_uuid'],
          'customer': loan['customer_name'],
          'customer_uuid': loan['customer_uuid'],
          'release_date': todayIso(),
          'payment_mode': 'Cash',
          'principal_paid': pp,
          'interest_paid': ip,
          'other_charges': 0,
          'total_paid': total,
        },
      );
      // The release settles the loan. CRITICAL: amount_paid is the running
      // total received over the life of the loan, so the settlement is ADDED
      // to it — overwriting it threw away every earlier payment and left a
      // "Amount paid" figure smaller than the money actually taken.
      final paidTotal = Num.money(Num.toDouble(loan['amount_paid']) + total);
      await state.db.upsert('pawn_loans', {
        ...loan,
        'status': 'Released',
        'release_date': todayIso(),
        'amount_paid': paidTotal,
        'interest_accrued': interestDue,
        'total_payable': paidTotal,
        'balance': 0,
        'last_interest_date': PawnMath.isoDate(asOf),
        'dirty': 1,
      });
      // v1.0.8: the release also lands in the pawn ledger with both dates.
      await _recordTransaction(
        type: 'release',
        amount: total,
        principalPart: pp,
        interestPart: ip,
        effective: DateTime.now(),
      );
      await state.logEvent(
          'pawn', 'release', 'Released — ${loan['customer_name'] ?? ''}',
          amount: total,
          village: loan['village']?.toString(),
          ref: loan['server_name']?.toString());
    } catch (error) {
      // Never fail silently — the shop owner must see why nothing happened.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Release failed: $error'),
          backgroundColor: kRed,
        ));
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final loan = _loan;
    final released = (loan['status']?.toString() ?? 'Active') == 'Released';
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, controller) => Stack(
          children: [
            ListView(
              controller: controller,
              padding: const EdgeInsets.all(16).copyWith(bottom: 96),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      key: const ValueKey('pawn-customer-photo'),
                      onTap: () => _expandPhoto(_photo, _name),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: kGold.withValues(alpha: .16),
                        foregroundImage:
                            _hasPhoto(_photo) ? FileImage(File(_photo)) : null,
                        child: _hasPhoto(_photo)
                            ? null
                            : Text(
                                _name.isEmpty
                                    ? '?'
                                    : _name.characters.first.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: kGoldDark),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Customer Pawn Profile',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: kGoldDark)),
                          Text(_name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          if (_village.isNotEmpty)
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined,
                                    size: 13, color: mutedOf(context)),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text(_village,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: mutedOf(context))),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: released
                                  ? kGreen.withValues(alpha: .15)
                                  : kGold.withValues(alpha: .2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              loan['status']?.toString() ?? 'Active',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: released ? kGreen : kGoldDark,
                              ),
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Call, SMS, WhatsApp, Move, Edit',
                          onSelected: (value) {
                            widget.onProfileAction?.call(value);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem<String>(
                              value: 'call',
                              child: Row(
                                children: [
                                  Icon(Icons.call_outlined,
                                      size: 18, color: kGoldDark),
                                  SizedBox(width: 10),
                                  Text('Call'),
                                ],
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'sms',
                              child: Row(
                                children: [
                                  Icon(Icons.sms_outlined,
                                      size: 18, color: kGoldDark),
                                  SizedBox(width: 10),
                                  Text('SMS'),
                                ],
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'whatsapp',
                              child: Row(
                                children: [
                                  Icon(Icons.chat_outlined,
                                      size: 18, color: kGoldDark),
                                  SizedBox(width: 10),
                                  Text('WhatsApp'),
                                ],
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'move',
                              child: Row(
                                children: [
                                  Icon(Icons.drive_file_move_outline,
                                      size: 18, color: kGoldDark),
                                  SizedBox(width: 10),
                                  Text('Move to another pawn profile'),
                                ],
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined,
                                      size: 18, color: kGoldDark),
                                  SizedBox(width: 10),
                                  Text('Edit loan'),
                                ],
                              ),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: released
                                  ? kGreen.withValues(alpha: .15)
                                  : kGold.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: released ? kGreen : kGold),
                            ),
                            child: const Icon(Icons.more_vert,
                                size: 20, color: kGoldDark),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: Theme.of(context).cardColor,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: ExpansionTile(
                    key: const ValueKey('pawn-kyc-tile'),
                    leading: const Icon(Icons.badge_outlined, color: kGoldDark),
                    title: const Text('Customer KYC & Details',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      if (_bookId.isNotEmpty) 'ID $_bookId',
                      if (_phone.isNotEmpty) _phone,
                      if (_village.isNotEmpty) _village,
                    ].join(' · ')),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kv('ID', _bookId.isEmpty ? '-' : _bookId),
                      _kv('Customer Name', _name),
                      _kv('Village', _village.isEmpty ? '-' : _village),
                      _kv('Address', _address.isEmpty ? '-' : _address),
                      _kv('Mobile Number', _phone.isEmpty ? '-' : _phone),
                      if (_hasPhoto(_kycFront) || _hasPhoto(_kycBack)) ...[
                        const SizedBox(height: 10),
                        Text('KYC photos',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: mutedOf(context))),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (_hasPhoto(_kycFront))
                              Expanded(
                                  child:
                                      _kycThumb(_kycFront, 'Front', 'front')),
                            if (_hasPhoto(_kycFront) && _hasPhoto(_kycBack))
                              const SizedBox(width: 8),
                            if (_hasPhoto(_kycBack))
                              Expanded(
                                  child: _kycThumb(_kycBack, 'Back', 'back')),
                          ],
                        ),
                      ],
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _openCustomerEdit,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit customer'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  key: const ValueKey('pawn-loan-details'),
                  elevation: 0,
                  color: Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Loan Details',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        _kv('Principal',
                            '₹${moneyText(PawnMath.principalOut(loan))}'),
                        _kv(
                          'Interest Rate',
                          '${loan['interest_rate'] ?? '-'} %/month'
                              '${(loan['interest_basis']?.toString() ?? '').isEmpty ? '' : ' · ${loan['interest_basis']}'}',
                        ),
                        _kv('Loan Date', fmtDate(loan['loan_date'])),
                        _kv('Due Date (Promised)',
                            fmtDate(loan['due_date'] ?? '')),
                        _kv('Actual Due Date', fmtDate(_actualDue(loan))),
                        _kv('Amount Paid',
                            '₹${moneyText(loan['amount_paid'] as num?)}'),
                        _kv('Outstanding',
                            '₹${moneyText(PawnMath.outstanding(loan, _actualDue(loan)))}'),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 24),
                Text('Items', style: Theme.of(context).textTheme.titleMedium),
                // v1.0.8: every pawn entry is deletable by dragging it to the
                // trash (the trash is hidden during normal use).
                for (final item in _items)
                  DragToDeleteTile(
                    onDragChanged: (v) => setState(() => _dragActive = v),
                    payload: DeletePayload(drop: () => _deleteItem(item)),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: (item['photo_path'] != null &&
                              File(item['photo_path'] as String).existsSync())
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                  File(item['photo_path'] as String),
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover))
                          : const Icon(Icons.diamond_outlined),
                      title: Text(item['item_description']?.toString() ?? '-'),
                      subtitle: Text(
                          '${item['metal_type'] ?? ''} · ${item['net_weight'] ?? 0} g · '
                          '${(item['hallmarked'] == 1) ? 'Hallmarked' : 'Non-hallmarked'}'),
                    ),
                  ),
                if (!released) ...[
                  const SizedBox(height: 16),
                  Text('Loan Actions',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  // Order agreed with the shop: interest first, then the two
                  // principal movements, release last. Every action logs a row
                  // in the pawn ledger.
                  Column(
                    key: const ValueKey('pawn-actions'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _interestPaid,
                        icon: const Icon(Icons.percent),
                        label: const Text('Interest Paying'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _amountPaying,
                        icon: const Icon(Icons.currency_rupee),
                        label: const Text('Amount Paying'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _amountRequesting,
                        icon: const Icon(Icons.add_card),
                        label: const Text('Amount Requesting'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _release,
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Release'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kRed,
                      side: const BorderSide(color: kRed),
                    ),
                    onPressed: () async {
                      final state = context.read<AppState>();
                      final granted = await askPasswordIfEnabled(context, state,
                          actionId: 'pawn_delete',
                          action: 'delete',
                          detail:
                              loan['customer_name']?.toString() ?? 'pawn loan');
                      if (!context.mounted) return;
                      if (granted != true) {
                        _toast(context, 'Delete cancelled / wrong password.');
                        return;
                      }
                      final db = state.db;
                      final uuid = loan['client_uuid'] as String?;
                      final ref = (loan['server_name'] as String?) ?? uuid;
                      if (uuid == null) return;
                      final releases = await db.query('pawn_releases',
                          where: 'pawn_loan = ? OR pawn_loan = ?',
                          whereArgs: [ref, uuid]);
                      await state.deleteCashbookFor({
                        uuid,
                        if (ref != null) ref,
                        for (final r in releases)
                          r['client_uuid']?.toString() ?? '',
                      });
                      await db.delete('pawn_loans',
                          where: 'client_uuid = ?', whereArgs: [uuid]);
                      await db.delete('pawn_items',
                          where: 'loan_uuid = ?', whereArgs: [uuid]);
                      await db.delete('pawn_transactions',
                          where: 'pawn_loan = ? OR pawn_loan = ?',
                          whereArgs: [ref, uuid]);
                      await db.delete('pawn_releases',
                          where: 'pawn_loan = ? OR pawn_loan = ?',
                          whereArgs: [ref, uuid]);
                      await state.logEvent('pawn', 'delete',
                          'Pawn loan deleted — ${loan['customer_name'] ?? ''}',
                          amount: Num.toDouble(loan['loan_amount']));
                      if (!context.mounted) return;
                      Navigator.pop(context, true);
                    },
                    icon: const Icon(Icons.delete_outline, color: kRed),
                    label: const Text('Delete Loan',
                        style: TextStyle(color: kRed)),
                  ),
                ],
                const Divider(height: 28),
                Text('Ledger', style: Theme.of(context).textTheme.titleMedium),
                if (_transactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No entries yet.'),
                  )
                else
                  for (final t in _transactions)
                    DragToDeleteTile(
                      onDragChanged: (v) => setState(() => _dragActive = v),
                      payload: DeletePayload(drop: () => _deleteTransaction(t)),
                      child: _txRowNew(t),
                    ),
                const SizedBox(height: 24),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
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
    );
  }

  /// A pawn ledger row: type, amount and BOTH dates — when the change was
  /// entered (tx_date) and the date it applies from (effective_date).
  Widget _txRowNew(Map<String, Object?> t) {
    final type = t['tx_type']?.toString() ?? '-';
    final label = switch (type) {
      'paying' => 'Amount Paying',
      'requesting' => 'Amount Requesting',
      'interest_paid' => 'Interest Paid',
      'release' => 'Release',
      _ => type,
    };

    final isOut =
        type == 'paying' || type == 'interest_paid' || type == 'release';
    final amount = Num.toDouble(t['amount']);
    final icon = switch (type) {
      'paying' => Icons.south_west,
      'requesting' => Icons.north_east,
      'interest_paid' => Icons.percent,
      'release' => Icons.lock_open,
      _ => Icons.sync,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isOut ? kGreen : kRed),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${fmtDate(t['effective_date'])} applies · '
                  'entered ${fmtDate(t['tx_date'])}',
                  style: TextStyle(fontSize: 10.5, color: mutedOf(context)),
                ),
                if (Num.toDouble(t['interest_part']) > 0 ||
                    Num.toDouble(t['principal_part']) > 0)
                  Text(
                    'P ₹${moneyWhole(Num.toDouble(t['principal_part']))} · '
                    'I ₹${moneyWhole(Num.toDouble(t['interest_part']))}',
                    style: TextStyle(fontSize: 10.5, color: mutedOf(context)),
                  ),
              ],
            ),
          ),
          Text(
            isOut ? '-₹${moneyWhole(amount)}' : '+₹${moneyWhole(amount)}',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isOut ? kGreen : kRed),
          ),
        ],
      ),
    );
  }

  bool _hasPhoto(String path) => path.isNotEmpty && File(path).existsSync();

// ---------------------------------------------------------------------------
// New pawn loan
// ---------------------------------------------------------------------------

  Widget _kycThumb(String path, String label, String slot) => GestureDetector(
        key: ValueKey('pawn-kyc-$slot'),
        onTap: () => _expandPhoto(path, _name),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(path),
                  height: 96, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(fontSize: 11, color: mutedOf(context))),
          ],
        ),
      );

  /// Full-screen photo viewer (pinch to zoom), used by the avatar and KYC
  /// images so a small thumbnail never hides the details.
  void _expandPhoto(String path, String name) {
    final hasPhoto = _hasPhoto(path);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  maxScale: 5,
                  child: hasPhoto
                      ? Image.file(File(path))
                      : Container(
                          width: 160,
                          height: 160,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: kGold.withValues(alpha: .2),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                              name.isEmpty
                                  ? '?'
                                  : name.characters.first.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 64,
                                  fontWeight: FontWeight.w800,
                                  color: kGoldDark)),
                        ),
                ),
              ),
              Positioned(
                top: 40 + MediaQuery.of(ctx).padding.top,
                right: 16,
                child: IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCustomerEdit() async {
    final custUuid = _loan['customer_uuid']?.toString() ?? '';
    var customer = _customer.isNotEmpty ? _customer : null;
    if (customer == null && custUuid.isNotEmpty) {
      customer =
          await context.read<AppState>().db.byUuid('customers', custUuid);
    }
    if (!mounted || customer == null) return;
    final existing = customer;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerForm(
          existing: existing,
          initialType: existing['customer_type']?.toString() ?? 'General',
        ),
      ),
    );
    if (mounted) _loadCustomer();
  }

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(key, style: const TextStyle(color: Colors.grey)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _ItemEntry {
  _ItemEntry({String? description, String metal = 'Gold', String? photo})
      : description = TextEditingController(text: description),
        purity = TextEditingController(),
        quantity = TextEditingController(text: '1'),
        gross = TextEditingController(),
        net = TextEditingController(),
        rate = TextEditingController(),
        metalType = metal,
        photoPath = photo;

  final TextEditingController description;
  final TextEditingController purity;
  final TextEditingController quantity;
  final TextEditingController gross;
  final TextEditingController net;
  final TextEditingController rate;
  String metalType;
  bool hallmarked = false;
  String? photoPath;

  void dispose() {
    for (final c in [description, purity, quantity, gross, net, rate]) {
      c.dispose();
    }
  }

  Map<String, Object?> toMap() {
    final netWeight = Num.round3(parseMoney(net.text));
    final valuationRate = parseMoney(rate.text);
    return {
      'item_description': description.text.trim(),
      'metal_type': metalType,
      'purity': purity.text.trim().isEmpty ? null : purity.text.trim(),
      'quantity': int.tryParse(quantity.text) ?? 1,
      'gross_weight': Num.round3(parseMoney(gross.text)),
      'net_weight': netWeight,
      'hallmarked': hallmarked ? 1 : 0,
      'valuation_rate': valuationRate,
      'market_value': Num.money(netWeight * valuationRate),
      'photo_path': photoPath,
    };
  }
}

class PawnLoanForm extends StatefulWidget {
  const PawnLoanForm({super.key});

  @override
  State<PawnLoanForm> createState() => _PawnLoanFormState();
}

class _PawnLoanFormState extends State<PawnLoanForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _rate = TextEditingController(text: '3');
  String _basis = 'Gold';
  DateTime _loanDate = DateTime.now();
  DateTime? _dueDate;
  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  String? _customerUuid;
  String? _customerName;
  final _customerNameController = TextEditingController();
  List<Map<String, Object?>> _customers = [];
  final List<_ItemEntry> _items = [_ItemEntry()];
  // v1.0.9: ID proof captured on the pawn loan itself.
  String _idProofType = 'Aadhaar';
  final _idNumber = TextEditingController();
  String? _idFront;
  String? _idBack;
  // v1.0.9: scanned customer address / village from the slip.
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _customerId = TextEditingController();
  bool _scanning = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final list = await context
        .read<AppState>()
        .db
        .query('customers', orderBy: 'customer_name asc');
    if (mounted) setState(() => _customers = list);
  }

  void _onCustomerSelected(Map<String, Object?> customer) {
    setState(() {
      _customerUuid = customer['client_uuid'] as String?;
      _customerName = customer['customer_name']?.toString() ?? '';
      _customerNameController.text = _customerName ?? '';
      _customerId.text = customer['customer_id']?.toString() ?? '';
      _phone.text = customer['phone']?.toString() ?? '';
      _address.text = customer['village']?.toString() ?? '';
      if ((customer['id_proof_type']?.toString() ?? '').isNotEmpty) {
        _idProofType = customer['id_proof_type'].toString();
      }
      if ((customer['id_proof_number']?.toString() ?? '').isNotEmpty) {
        _idNumber.text = customer['id_proof_number'].toString();
      }
      if ((customer['id_photo_front'] ?? customer['id_front']) != null) {
        _idFront =
            (customer['id_photo_front'] ?? customer['id_front']) as String?;
      }
      if ((customer['id_photo_back'] ?? customer['id_back']) != null) {
        _idBack = (customer['id_photo_back'] ?? customer['id_back']) as String?;
      }
      _setBasis(_basis, _customers);
    });
  }

  void _onCustomerTyped(String name) {
    _customerName = name;
    final match = _customers.where((c) =>
        (c['customer_name']?.toString() ?? '').trim().toLowerCase() ==
        name.trim().toLowerCase());
    if (match.isNotEmpty) {
      _onCustomerSelected(match.first);
    } else {
      setState(() {
        _customerUuid = null;
      });
    }
  }

  /// The "+" beside the customer picker opens the full customer form (photo,
  /// ID proof type/number/front/back), then re-selects the new customer.
  Future<void> _addCustomer() async {
    // Read before the push: the push awaits a whole screen.
    final state = context.read<AppState>();
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => const CustomerForm(initialType: 'General')),
    );
    await _loadCustomers();
    final newest =
        await state.db.query('customers', orderBy: 'updated_at desc', limit: 1);
    if (newest.isNotEmpty && mounted) {
      _onCustomerSelected(newest.first);
    }
  }

  /// v1.0.9: Scan the pawn slip. The camera image is read on-device (ML Kit)
  /// and the form is filled in with whatever the slip carries: ID Number,
  /// Customer Name, Item, Loan amount, Date, Item details and Address.
  Future<void> _scanSlip() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 1) Google's document scanner (Drive-style auto crop + straighten).
      var path = await captureDocument();
      // 2) Fallback: a normal camera shot or an existing photo.
      if (path == null) {
        if (!mounted) return;
        final source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading:
                      const Icon(Icons.photo_camera_outlined, color: kGoldDark),
                  title: const Text('Take a photo of the slip'),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined,
                      color: kGoldDark),
                  title: const Text('Choose an existing slip photo'),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
                ListTile(
                  leading: Icon(Icons.close, color: inkOf(context)),
                  title: const Text('Cancel'),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
        if (source == null || !mounted) return;
        final picked = await ImagePicker()
            .pickImage(source: source, imageQuality: 80, maxWidth: 2000);
        if (picked == null || !mounted) return;
        path = picked.path;
      }
      if (!mounted) return;
      final fields = await scanSlipImage(path);
      if (!mounted) return;
      _applyScannedSlip(fields);
      final found = fields.found;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(found.isEmpty
              ? 'Could not read the slip — please fill the form by hand.'
              : 'Slip read: ${found.join(', ')} — please check them.'),
          duration: const Duration(seconds: 4),
        ));
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Scan failed: $error'),
          backgroundColor: kRed,
        ));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _applyScannedSlip(SlipFields f) {
    setState(() {
      if (f.amount.isNotEmpty) _amount.text = parseMoney(f.amount).toString();
      if (f.date != null) _loanDate = f.date!;
      if (f.idNumber.isNotEmpty) _idNumber.text = f.idNumber;
      if (f.address.isNotEmpty) _address.text = f.address;
      if ((f.item.isNotEmpty || f.itemDetails.isNotEmpty) &&
          _items.length == 1) {
        final first = _items.first;
        first.description.text = f.item.isNotEmpty ? f.item : f.itemDetails;
        if (f.itemDetails.isNotEmpty && f.itemDetails != f.item) {
          first.purity.text = f.itemDetails;
        }
      }
      // If the slip's customer already exists, select them in the picker.
      if (f.customerName.isNotEmpty) {
        final name = f.customerName.trim().toLowerCase();
        final match = _customers.where((c) =>
            (c['customer_name']?.toString() ?? '').trim().toLowerCase() ==
            name);
        if (match.isNotEmpty) {
          _customerUuid = match.first['client_uuid'] as String?;
          _customerName = match.first['customer_name']?.toString();
          _setBasis(_basis, _customers);
        }
      }
    });
  }

  /// v1.0.9: ID proof on the pawn loan — type, number and front/back images.
  Widget _idProofSection() {
    const types = [
      'Aadhaar',
      'PAN',
      'Voter ID',
      'Driving Licence',
      'Passport',
      'Other',
    ];
    return SectionCard(title: 'ID proof', children: [
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _idProofType,
            decoration: fieldDecoration('ID proof type'),
            items: types
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => _idProofType = v ?? 'Aadhaar'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: _idNumber,
            decoration: fieldDecoration('ID number'),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      // ID front / back — camera + gallery symbols only (no text labels).
      Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          PhotoIconPicker(
            path: _idFront,
            onPicked: (p) => setState(() => _idFront = p),
            onCleared: () => setState(() => _idFront = null),
            size: 52,
          ),
          PhotoIconPicker(
            path: _idBack,
            onPicked: (p) => setState(() => _idBack = p),
            onCleared: () => setState(() => _idBack = null),
            size: 52,
          ),
        ],
      ),
    ]);
  }

  @override
  void dispose() {
    _amount.dispose();
    _idNumber.dispose();
    _address.dispose();
    _phone.dispose();
    _customerId.dispose();
    _rate.dispose();
    _customerNameController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _setBasis(String basis, List<Map<String, Object?>> customers) {
    setState(() {
      _basis = basis;
      Map<String, Object?> customer = {};
      for (final c in customers) {
        if (c['client_uuid'] == _customerUuid) {
          customer = c;
          break;
        }
      }
      final override = basis == 'Gold'
          ? customer['gold_interest_rate']
          : (basis == 'Silver'
              ? customer['silver_interest_rate']
              : (customer['gold_interest_rate'] ??
                  customer['silver_interest_rate']));
      final value = Num.toDouble(override);
      _rate.text = (value > 0
              ? value
              : (basis == 'Silver' ? 4 : (basis == 'Gold & Silver' ? 3.5 : 3)))
          .toString();
    });
  }

  Future<void> _pickDate(bool due) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (due ? _dueDate : _loanDate) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (due) {
        _dueDate = picked;
      } else {
        _loanDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Please fill the required fields marked *.')));
      return;
    }
    final state = context.read<AppState>();
    setState(() => _saving = true);
    try {
      if (_customerUuid == null || _customerUuid!.isEmpty) {
        final typedName = (_customerName?.trim().isNotEmpty == true)
            ? _customerName!.trim()
            : _customerNameController.text.trim();
        if (typedName.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Please select or type a customer name')));
          return;
        }
        final newUuidVal = newUuid();
        final newId = await state.claimCustomerId(_customerId.text.trim());
        await state.saveEntity(
          table: 'customers',
          doctype: 'Pawn Customer',
          uuid: newUuidVal,
          data: {
            'customer_name': typedName,
            'customer_id': newId,
            'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            'village':
                _address.text.trim().isEmpty ? null : _address.text.trim(),
            'id_proof_type': _idProofType,
            'id_proof_number':
                _idNumber.text.trim().isEmpty ? null : _idNumber.text.trim(),
            'id_photo_front': _idFront,
            'id_photo_back': _idBack,
            'customer_type': 'General',
          },
        );
        _customerUuid = newUuidVal;
        _customerName = typedName;
      }
      final items = _items.map((e) => e.toMap()).toList();
      double totalGross = 0, totalNet = 0, hallmarked = 0, marketValue = 0;
      for (final item in items) {
        final gross = Num.toDouble(item['gross_weight']);
        final net = Num.toDouble(item['net_weight']);
        totalGross += gross;
        totalNet += net;
        if (item['hallmarked'] == 1) hallmarked += net;
        marketValue += Num.toDouble(item['market_value']);
      }
      final loanAmount = Num.money(parseMoney(_amount.text));
      final parsedRate = parseMoney(_rate.text);
      final rate = parsedRate == 0 ? 3.0 : parsedRate;
      final loanUuid = newUuid();
      final due = _dueDate ?? _loanDate.add(const Duration(days: 90));
      final days = due.difference(_loanDate).inDays;
      final interest = Num.simpleInterest(
          principal: loanAmount, ratePerMonth: rate, days: days);

      // v1.0.9: the Customer ID typed here is the customer's book number — keep
      // the customer's record in step (duplicate IDs are rejected).
      if (_customerUuid != null && _customerId.text.trim().isNotEmpty) {
        // Read the row from the store, not the list loaded when the screen
        // opened: a customer created during this save is not in that list yet,
        // and spreading an empty map used to insert a ghost row with no uuid.
        final customerRow = await state.db.byUuid('customers', _customerUuid!);
        final current = customerRow?['customer_id']?.toString() ?? '';
        final typed = _customerId.text.trim();
        if (customerRow != null && typed.isNotEmpty && typed != current) {
          try {
            final claimed =
                await state.claimCustomerId(typed, excludeUuid: _customerUuid);
            await state.db
                .upsert('customers', {...customerRow, 'customer_id': claimed});
          } on StateError catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(e.message)));
            }
            return;
          }
        }
      }

      await state.savePawnLoan(
        uuid: loanUuid,
        data: {
          'customer': _customerName,
          'customer_name': _customerName,
          // v9: identity is the uuid; the name is only a display cache.
          'customer_uuid': _customerUuid,
          'village': _address.text.trim().isEmpty ? null : _address.text.trim(),
          'status': 'Active',
          'loan_date': _loanDate.toIso8601String().substring(0, 10),
          'interest_basis': _basis,
          'loan_amount': loanAmount,
          'interest_rate': rate,
          'due_date': due.toIso8601String().substring(0, 10),
          'total_gross_weight': Num.round3(totalGross),
          'total_net_weight': Num.round3(totalNet),
          'hallmarked_weight': Num.round3(hallmarked),
          'non_hallmarked_weight': Num.round3(totalNet - hallmarked),
          'total_market_value': Num.money(marketValue),
          // LTV always uses the same 2-decimal rounding (Num.roundPct), so the
          // create screen, an item edit and the server can never disagree.
          'ltv': marketValue > 0
              ? Num.roundPct(loanAmount / marketValue * 100)
              : 0,
          'interest_accrued': interest,
          // v1.1.6: when the shop “closes the date” on a pawn, the actual
          // due date advanced and interest is recalculated from it. Initially
          // the actual column is null and the form falls back to the promised
          // due date, so the profile still shows something useful.
          if (_dueDate == null || _dueDate!.isBefore(_loanDate))
            'pawn_due_actual': _dueDate == null ? null : _iso(_loanDate),
          // v1.0.9: the stored interest runs UP TO the due date, so the accrual
          // anchor starts at the due date. PawnMath adds interest from here on.
          'last_interest_date': due.toIso8601String().substring(0, 10),
          'total_payable': Num.money(loanAmount + interest),
          'amount_paid': 0,
          'balance': Num.money(loanAmount + interest),
          'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          // v1.0.9: ID proof captured on the loan itself.
          'id_proof_type': _idProofType,
          'id_proof_number':
              _idNumber.text.trim().isEmpty ? null : _idNumber.text.trim(),
          'id_front': _idFront,
          'id_back': _idBack,
        },
        items: items,
      );

      // Item photos are stored on the pawn_items rows inside savePawnLoan —
      // no separate photo write needed. (Previously this loop wrote to a
      // non-existent pawn_loans.photo_path column and aborted the whole save.)
      if (mounted) Navigator.pop(context);
    } catch (error) {
      // A failed write must never look like a dead button. Show the reason and
      // keep the form open so nothing typed is lost.
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('Could not save pawn loan: $error'),
            duration: const Duration(seconds: 6),
          ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Pawn Loan'),
        actions: [
          // v1.0.9: slip scanning — symbol only, so the app-bar title stays
          // readable on big-font phones.
          IconButton(
            tooltip: 'Scan slip',
            icon: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: kGold))
                : const Icon(Icons.document_scanner_outlined, color: kGoldDark),
            onPressed: _scanning ? null : _scanSlip,
          ),
          TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kGoldDark))
                  : const Text('SAVE')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SectionCard(title: 'Customer', children: [
              Row(
                children: [
                  Expanded(
                    child: Autocomplete<Map<String, Object?>>(
                      initialValue:
                          TextEditingValue(text: _customerNameController.text),
                      displayStringForOption: (option) =>
                          option['customer_name']?.toString() ?? '',
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        final query =
                            textEditingValue.text.trim().toLowerCase();
                        if (query.isEmpty) {
                          return _customers.take(15);
                        }
                        final matches = _customers.where((c) {
                          final name = (c['customer_name']?.toString() ?? '')
                              .toLowerCase();
                          final phone =
                              (c['phone']?.toString() ?? '').toLowerCase();
                          final id = (c['customer_id']?.toString() ?? '')
                              .toLowerCase();
                          return name.contains(query) ||
                              phone.contains(query) ||
                              id.contains(query);
                        }).toList();
                        if (!matches.any((c) =>
                            (c['customer_name']?.toString() ?? '')
                                .trim()
                                .toLowerCase() ==
                            query)) {
                          return [
                            ...matches,
                            {
                              '_isNew': true,
                              'customer_name': textEditingValue.text.trim(),
                              'client_uuid': '',
                            }
                          ];
                        }
                        return matches;
                      },
                      onSelected: (option) {
                        if (option['_isNew'] == true) {
                          final name =
                              option['customer_name']?.toString() ?? '';
                          _customerNameController.text = name;
                          _onCustomerTyped(name);
                        } else {
                          _onCustomerSelected(option);
                        }
                      },
                      fieldViewBuilder: (context, textController, focusNode,
                          onFieldSubmitted) {
                        textController.addListener(() {
                          if (_customerNameController.text !=
                              textController.text) {
                            _customerNameController.text = textController.text;
                            _customerName = textController.text;
                          }
                        });
                        return TextFormField(
                          controller: textController,
                          focusNode: focusNode,
                          decoration: fieldDecoration(
                            'Customer * (Type name or search)',
                            hint: 'Type letter or name...',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter customer name'
                              : null,
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4.0,
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: 250,
                                maxWidth:
                                    MediaQuery.of(context).size.width - 48,
                              ),
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                shrinkWrap: true,
                                itemCount: options.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final opt = options.elementAt(index);
                                  final isNew = opt['_isNew'] == true;
                                  if (isNew) {
                                    return ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.add_circle,
                                          color: kGoldDark),
                                      title: Text(
                                          '+ Create "${opt['customer_name']}"',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: kGoldDark)),
                                      onTap: () => onSelected(opt),
                                    );
                                  }
                                  final name =
                                      opt['customer_name']?.toString() ?? '';
                                  final id =
                                      opt['customer_id']?.toString() ?? '';
                                  final phone = opt['phone']?.toString() ?? '';
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.person_outline,
                                        size: 20),
                                    title: Text(name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                        [
                                          if (id.isNotEmpty) 'ID $id',
                                          if (phone.isNotEmpty) phone
                                        ].join(' · '),
                                        style: const TextStyle(fontSize: 12)),
                                    onTap: () => onSelected(opt),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  // v1.0.8: add a new customer right here (+).
                  IconButton(
                    tooltip: 'Add new customer (Full KYC form)',
                    icon: const Icon(Icons.add_circle_outline,
                        color: kGoldDark, size: 26),
                    onPressed: _addCustomer,
                  ),
                ],
              ),
              if (_customers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                      'No customers yet — type name or tap + to add one.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8A6D14))),
                ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: fieldDecoration('Mobile no'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _customerId,
                    textCapitalization: TextCapitalization.characters,
                    decoration: fieldDecoration(
                      'Customer ID',
                      hint: 'A01',
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextFormField(
                controller: _address,
                decoration: fieldDecoration('Address'),
              ),
            ]),
            SectionCard(title: 'Loan', children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Interest basis',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: inkOf(context))),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final b in const [
                        'Gold',
                        'Silver',
                        'Gold & Silver'
                      ]) ...[
                        Expanded(
                          child: ChoiceChip(
                            label: Center(
                              child: Text(b,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                            selected: _basis == b,
                            selectedColor: kGold.withValues(alpha: .25),
                            onSelected: (selected) {
                              if (selected) _setBasis(b, _customers);
                            },
                          ),
                        ),
                        if (b != 'Gold & Silver') const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    decoration: fieldDecoration('Loan amount *'),
                    onChanged: (_) => setState(() {}),
                    validator: (v) =>
                        (parseMoney(v) <= 0) ? 'Enter amount' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _rate,
                    keyboardType: TextInputType.number,
                    decoration: fieldDecoration('% / month'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(fmtDate(_loanDate)),
                    onPressed: () => _pickDate(false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 16),
                    label:
                        Text(_dueDate == null ? 'Due date' : fmtDate(_dueDate)),
                    onPressed: () => _pickDate(true),
                  ),
                ),
              ]),
            ]),
            for (var i = 0; i < _items.length; i++) _itemCard(i),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
              onPressed: () => setState(() => _items.add(_ItemEntry())),
            ),
            const SizedBox(height: 12),
            _idProofSection(),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(int index) {
    final item = _items[index];
    return SectionCard(
      title: 'Item ${index + 1}',
      children: [
        TextFormField(
          controller: item.description,
          decoration: fieldDecoration('Description (e.g. Gold chain)'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: item.metalType,
              decoration: fieldDecoration('Metal'),
              items: const ['Gold', 'Silver', 'Other']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => item.metalType = v ?? 'Gold'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: item.purity,
              decoration: fieldDecoration('Purity (22K)'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: TextFormField(
            controller: item.gross,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: fieldDecoration('Gross g'),
          )),
          const SizedBox(width: 8),
          Expanded(
              child: TextFormField(
            controller: item.net,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: fieldDecoration('Net g'),
          )),
          const SizedBox(width: 8),
          Expanded(
              child: TextFormField(
            controller: item.rate,
            keyboardType: TextInputType.number,
            decoration: fieldDecoration('Rate / g'),
          )),
        ]),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hallmarked'),
          value: item.hallmarked,
          onChanged: (v) => setState(() => item.hallmarked = v),
        ),
        PhotoIconPicker(
          path: item.photoPath,
          onPicked: (path) => setState(() => item.photoPath = path),
          onCleared: () => setState(() => item.photoPath = null),
        ),
        if (_items.length > 1)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove'),
              onPressed: () => setState(() {
                _items.removeAt(index).dispose();
              }),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- helpers
/// Admin-password gate for delete / release. [verb] lets the same dialog ask
/// "Are you sure to release …?" for pawn releases.
void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
