import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../data/slip_ocr.dart';
import '../state/app_state.dart';
import '../util/format.dart';
import '../util/ids.dart';
import 'customers_screen.dart';
import 'palette.dart';
import 'pawn_dashboard_screen.dart';
import 'reports_screen.dart';
import 'widgets.dart';

class PawnScreen extends StatefulWidget {
  const PawnScreen({super.key, this.filter});

  /// 'active' | 'released' | 'old' | 'recent' | 'interest'
  final String? filter;

  @override
  State<PawnScreen> createState() => _PawnScreenState();
}

class _PawnScreenState extends State<PawnScreen> {
  String _search = '';
  late String _filter = widget.filter ?? 'All';
  String _metal = 'all'; // all | gold | silver | mixed
  bool _dragActive = false;
  /// Loan uuid -> customer book ID, for display only. Kept OUT of the row map
  /// so it can never leak into a db.upsert() of pawn_loans.
  final Map<String, String> _customerIdByLoan = {};

  /// loan_uuid -> list of normalised metals found on its items.
  Future<Map<String, List<String>>> _metalIndex() async {
    final items = await context.read<AppState>().db.query('pawn_items',
        columns: ['loan_uuid', 'metal_type']);
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

  bool _matchesMetal(Map<String, List<String>> idx, String uuid,
      String basis, String metal) {
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
        break;
      default:
        break;
    }
    if (_search.trim().isNotEmpty) {
      final term = '%${_search.trim()}%';
      where = where == null
          ? 'customer_name LIKE ? OR phone LIKE ?'
          : '($where) AND (customer_name LIKE ? OR phone LIKE ?)';
      args.addAll([term, term]);
    }
    final order = _filter == 'interest'
        ? 'interest_accrued desc'
        : 'loan_date desc';
    var rows = await db.query('pawn_loans',
        where: where,
        whereArgs: args,
        orderBy: order,
        limit: _filter == 'recent' ? 10 : null);
    // Metal filter (Gold / Silver / Mixed) based on the loan's pawn items.
    if (_metal != 'all') {
      final idx = await _metalIndex();
      rows = rows
          .where((r) => _matchesMetal(idx,
              r['client_uuid']?.toString() ?? '',
              r['interest_basis']?.toString() ?? '', _metal))
          .toList();
    }
    // Attach the customer's book ID for display (kept in a side map, never in
    // the row itself — the row is spread into db.upsert('pawn_loans') by the
    // release / edit flows, and an unknown column would abort the write).
    final customers =
        await db.query('customers', columns: ['customer_name', 'customer_id']);
    final idByName = <String, String>{
      for (final c in customers)
        (c['customer_name']?.toString() ?? ''):
            (c['customer_id']?.toString() ?? '')
    };
    _customerIdByLoan.clear();
    for (final r in rows) {
      _customerIdByLoan[r['client_uuid']?.toString() ?? ''] =
          idByName[r['customer_name']?.toString() ?? ''] ?? '';
    }
    return rows;
  }

  Future<void> _openForm() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const PawnLoanForm()));
    if (mounted) setState(() {});
  }

  Future<void> _openDetail(Map<String, Object?> loan) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PawnDetail(
        loan: loan,
        customerId:
            _customerIdByLoan[loan['client_uuid']?.toString() ?? ''] ?? '',
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(
        title: const Text('Pawn Loans'),
        actions: [
          IconButton(
            tooltip: 'Dashboard',
            icon: const Icon(Icons.dashboard_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PawnDashboardScreen())),
          ),
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ReportsScreen(initialTab: 1))),
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
              decoration: fieldDecoration('Search customer or phone'),
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
                        final status = row['status']?.toString() ?? 'Active';
                        final released = status == 'Released';
                        return DragToDeleteTile(
                          onDragChanged: (v) =>
                              setState(() => _dragActive = v),
                          payload: DeletePayload(
                            drop: () => _deleteLoan(row),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: released
                                  ? kGreenSoft
                                  : kGold.withValues(alpha: .25),
                              child: Icon(
                                  released ? Icons.check : Icons.lock_clock,
                                  size: 20,
                                  color: released ? kGreen : kGoldDark),
                            ),
                            title:
                                Text(row['customer_name']?.toString() ?? '-'),
                            subtitle: Text(
                                '${_customerIdByLoan[row['client_uuid']?.toString() ?? '']?.isNotEmpty == true ? 'ID ${_customerIdByLoan[row['client_uuid']?.toString() ?? '']} · ' : ''}${fmtDate(row['loan_date'])} · ${row['interest_basis'] ?? ''} · ₹${moneyWhole(row['loan_amount'] as num?)}'),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(status,
                                    style: TextStyle(
                                        color:
                                            released ? kGreen : kGoldDark,
                                        fontWeight: FontWeight.w600)),
                                if (row['server_name'] == null)
                                  const Icon(Icons.cloud_upload_outlined,
                                      size: 16),
                              ],
                            ),
                            onTap: () => _openDetail(row),
                          ),
                        );
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Whole pawn loan deletion (admin-gated when the Admin setting is on).
  /// Removes the loan plus its items, transactions, releases and payment rows.
  Future<bool> _deleteLoan(Map<String, Object?> row) async {
    final state = context.read<AppState>();
    var granted = true;
    if (state.adminConfirm) {
      granted = await _adminDeleteDialog(
          context, row['customer_name']?.toString() ?? 'pawn loan');
      if (granted != true) {
        _toast(context, 'Delete cancelled / wrong password.');
        return false;
      }
    }
    final db = state.db;
    final uuid = row['client_uuid'] as String?;
    final ref = (row['server_name'] as String?) ?? uuid;
    if (uuid == null) return false;
    await db.delete('pawn_loans',
        where: 'client_uuid = ?', whereArgs: [uuid]);
    await db.delete('pawn_items',
        where: 'loan_uuid = ?', whereArgs: [uuid]);
    await db.delete('pawn_transactions',
        where: 'pawn_loan = ? OR pawn_loan = ?', whereArgs: [ref, uuid]);
    await db.delete('pawn_releases',
        where: 'pawn_loan = ? OR pawn_loan = ?', whereArgs: [ref, uuid]);
    await state.logEvent('pawn', 'delete',
        'Pawn loan deleted — ${row['customer_name'] ?? ''}',
        amount: Num.toDouble(row['loan_amount']));
    if (mounted) setState(() {});
    return true;
  }

  Widget _summaryStrip() {
    final db = context.read<AppState>().db;
    final metal = _metal;
    return FutureBuilder<Map<String, Object?>>(
      future: () async {
        final loans = await db.query('pawn_loans',
            where: 'status = ? OR status IS NULL', whereArgs: ['Active']);
        var filtered = loans;
        if (metal != 'all') {
          final idx = await _metalIndex();
          filtered = loans
              .where((l) => _matchesMetal(idx,
                  l['client_uuid']?.toString() ?? '',
                  l['interest_basis']?.toString() ?? '', metal))
              .toList();
        }
        double out = 0, intDue = 0;
        for (final l in filtered) {
          out += Num.toDouble(l['loan_amount']);
          intDue += Num.toDouble(l['interest_accrued']);
        }
        return {
          'out': Num.money(out),
          'int': Num.money(intDue),
          'total': Num.money(out + intDue),
          'metal': metal,
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
                  stat('₹${r['out'] ?? 0}', 'Investment'),
                  stat('₹${r['int'] ?? 0}', 'Interest due'),
                  stat('₹${r['total'] ?? 0}', 'Outstanding'),
                ],
              ),
              if (caption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_alt_outlined,
                          size: 13, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(caption,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white70)),
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
      ('All', 'All'),
      ('Active', 'active'),
      ('Released', 'released'),
      if (_filter == 'old') ('Old 12M+', 'old'),
      if (_filter == 'recent') ('Recent', 'recent'),
      if (_filter == 'interest') ('Interest due', 'interest'),
    ];
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
                      fontWeight: _filter == value
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: _filter == value
                          ? kGoldDark
                          : kInk.withValues(alpha: .7)),
                  onSelected: (_) =>
                      setState(() => _filter = value),
                ),
              ),
          ],
        ),
      ),
    );
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
                      fontWeight: _metal == value
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: _metal == value ? kGoldDark : kInk.withValues(alpha: .7)),
                  onSelected: (_) => setState(() => _metal = value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PawnDetail extends StatefulWidget {
  const _PawnDetail({required this.loan, this.customerId = ''});

  final Map<String, Object?> loan;
  final String customerId;

  @override
  State<_PawnDetail> createState() => _PawnDetailState();
}

class _PawnDetailState extends State<_PawnDetail> {
  List<Map<String, Object?>> _items = [];
  List<Map<String, Object?>> _transactions = [];
  late Map<String, Object?> _loan;
  bool _dragActive = false;

  @override
  void initState() {
    super.initState();
    _loan = widget.loan;
    _loadItems();
    _loadTransactions();
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
    final tx = await db.query('pawn_transactions',
        where: 'pawn_loan = ?', whereArgs: [ref]);
    final releases = await db.query('pawn_releases',
        where: 'pawn_loan = ?', whereArgs: [ref]);
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
      'pawn_loan':
          (_loan['server_name'] as String?) ?? _loan['client_uuid'],
      'customer': _loan['client_uuid'],
      'customer_name': _loan['customer_name'],
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
    final ok = await confirmDialog(
      context,
      'Remove this item from the pawn? Removing it lowers the collateral.',
      title: 'Remove item',
    );
    if (!ok) return false;
    final state = context.read<AppState>();
    final id = item['id'] as int?;
    if (id == null) return false;
    await state.db.deleteWhere('pawn_items', 'id = ?', [id]);
    final items =
        await state.itemsFor(widget.loan['client_uuid'] as String);
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
        'ltv': mv > 0 ? Num.money(loanAmount / mv * 100) : 0,
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
    final ok = await confirmDialog(
      context,
      'Remove this ledger entry and undo its effect on the loan?',
      title: 'Remove entry',
    );
    if (!ok) return false;
    final state = context.read<AppState>();
    final db = state.db;
    final ref = (_loan['server_name'] as String?) ?? _loan['client_uuid'];

    var np = Num.toDouble(_loan['loan_amount']);
    var ni = Num.toDouble(_loan['interest_accrued']);
    var nPaid = Num.toDouble(_loan['amount_paid']);

    if (type == 'release') {
      await db.delete('pawn_releases',
          where: 'pawn_loan = ?', whereArgs: [ref]);
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
                    setDlg(
                        () => picked = DateTime(d.year, d.month, d.day));
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
                    setDlg(
                        () => picked = DateTime(d.year, d.month, d.day));
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
    final out = Num.toDouble(loan['loan_amount']) +
        Num.toDouble(loan['interest_accrued']);
    final res = await _amountDialog('Amount Paying', 'Amount received', out);
    if (res == null) return;
    final (pay, effective) = res;
    final interestPart = Num.money(
        (Num.toDouble(loan['interest_accrued']) < pay)
            ? Num.toDouble(loan['interest_accrued'])
            : pay);
    final principalPart = Num.money(pay - interestPart);
    final newPrincipal =
        Num.money(Num.toDouble(loan['loan_amount']) - principalPart);
    final newInterest =
        Num.money(Num.toDouble(loan['interest_accrued']) - interestPart);
    final newPaid = Num.money(Num.toDouble(loan['amount_paid']) + pay);
    final total = Num.money(newPrincipal + newInterest);
    final newBalance = Num.money(total - newPaid);
    final overrides = <String, Object?>{
      'loan_amount': newPrincipal,
      'interest_accrued': newInterest,
      'total_payable': total,
      'amount_paid': newPaid,
      'balance': newBalance < 0 ? 0 : newBalance,
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
    final res = await _amountDialog(
        'Amount Requesting', 'New amount given', 0);
    if (res == null) return;
    final (more, effective) = res;
    final rate = Num.toDouble(loan['interest_rate']);
    final anchor = _anchorDate ?? DateTime.now();
    final days = DateTime.now().difference(anchor).inDays;
    final freshInterest = Num.simpleInterest(
        principal: more, ratePerMonth: rate, days: days < 0 ? 0 : days);
    final newPrincipal = Num.money(Num.toDouble(loan['loan_amount']) + more);
    final newInterest = Num.money(
        Num.toDouble(loan['interest_accrued']) + freshInterest);
    final total = Num.money(newPrincipal + newInterest);
    final newBalance =
        Num.money(total - Num.toDouble(loan['amount_paid']));
    await _recordTransaction(
      type: 'requesting',
      amount: more,
      principalPart: more,
      interestPart: freshInterest,
      effective: effective,
    );
    await _applyToLoan({
      'loan_amount': newPrincipal,
      'interest_accrued': newInterest,
      'total_payable': total,
      'balance': newBalance,
    },
        logKind: 'request',
        logTitle: 'Amount requesting — ${loan['customer_name'] ?? ''}',
        logAmount: more);
  }

  /// Interest Paid — the entered amount clears interest first; any excess
  /// reduces principal, exactly like Amount Paying.
  Future<void> _interestPaid() async {
    final loan = _loan;
    final res = await _amountDialog(
        'Interest Paid', 'Interest amount paid', 0);
    if (res == null) return;
    final (amt, effective) = res;
    final accrued = Num.toDouble(loan['interest_accrued']);
    final interestPart = Num.money(accrued < amt ? accrued : amt);
    final principalPart = Num.money(amt - interestPart);
    final newInterest = Num.money(accrued - interestPart);
    final newPrincipal =
        Num.money(Num.toDouble(loan['loan_amount']) - principalPart);
    final newPaid = Num.money(Num.toDouble(loan['amount_paid']) + amt);
    final total = Num.money(newPrincipal + newInterest);
    final newBalance = Num.money(total - newPaid);
    final overrides = <String, Object?>{
      'interest_accrued': newInterest,
      'loan_amount': newPrincipal,
      'total_payable': total,
      'amount_paid': newPaid,
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
    final loan = _loan;
    final loanAmount = Num.toDouble(loan['loan_amount']);
    final paid = Num.toDouble(loan['amount_paid']);
    final balance = Num.toDouble(loan['balance']);
    final loanDate =
        DateTime.tryParse(loan['loan_date']?.toString() ?? '') ?? DateTime.now();
    final days = DateTime.now().difference(loanDate).inDays;
    final rate = Num.toDouble(loan['interest_rate']);
    // Prefer the server's accrued interest/balance so the settlement matches.
    double interestDue = Num.toDouble(loan['interest_accrued']);
    if (interestDue <= 0) {
      interestDue = Num.simpleInterest(
          principal: loanAmount, ratePerMonth: rate, days: days);
    }
    if (balance > 0 && interestDue > balance) interestDue = balance;
    final principalDue = balance > 0
        ? Num.money(balance - interestDue)
        : Num.money(loanAmount - paid);
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
            Text('Days: $days  ·  Rate: $rate%/month'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  sumRow('Principal outstanding', '₹${moneyText(principalDue)}'),
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
                  color:
                      Theme.of(ctx).colorScheme.onSurface.withValues(alpha: .6)),
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

    final state = context.read<AppState>();
    if (state.adminConfirm) {
      final granted = await _adminDeleteDialog(
          context, 'this pawn loan', verb: 'release');
      if (granted != true) {
        _toast(context, 'Release cancelled / wrong password.');
        return;
      }
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
          'release_date': todayIso(),
          'payment_mode': 'Cash',
          'principal_paid': pp,
          'interest_paid': ip,
          'other_charges': 0,
          'total_paid': total,
        },
      );
      // The server updates the loan when the release is submitted; reflect
      // that locally without queueing a second push.
      await state.db.upsert('pawn_loans', {
        ...loan,
        'status': 'Released',
        'release_date': todayIso(),
        'amount_paid': total,
        'balance': 0,
        'dirty': 0,
      });
      // v1.0.8: the release also lands in the pawn ledger with both dates.
      await _recordTransaction(
        type: 'release',
        amount: total,
        principalPart: pp,
        interestPart: ip,
        effective: DateTime.now(),
      );
      await state.logEvent('pawn', 'release',
          'Released — ${loan['customer_name'] ?? ''}',
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
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, controller) => Stack(
          children: [
            ListView(
              controller: controller,
              padding: const EdgeInsets.all(16).copyWith(bottom: 96),
              children: [
                Text(loan['customer_name']?.toString() ?? '-',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text((() {
                  final id = widget.customerId;
                  final phone = (loan['phone'] ?? '') as String;
                  final village = (loan['village'] ?? '') as String;
                  return [
                    if (id.isNotEmpty) 'ID $id',
                    if (phone.isNotEmpty) phone,
                    if (village.isNotEmpty) village,
                  ].join('  ');
                })()),
                const Divider(height: 24),
                _kv('Loan amount', '₹${moneyText(loan['loan_amount'] as num?)}'),
                _kv('Interest basis', loan['interest_basis']?.toString() ?? '-'),
                _kv('Rate', '${loan['interest_rate'] ?? '-'} %/month'),
                _kv('Loan date', fmtDate(loan['loan_date'])),
                _kv('Due date', fmtDate(loan['due_date'])),
                _kv('Status', loan['status']?.toString() ?? 'Active'),
                _kv('Total payable',
                    '₹${moneyText(loan['total_payable'] as num?)}'),
                _kv('Amount paid', '₹${moneyText(loan['amount_paid'] as num?)}'),
                _kv('Balance', '₹${moneyText(loan['balance'] as num?)}'),
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
                      title:
                          Text(item['item_description']?.toString() ?? '-'),
                      subtitle: Text(
                          '${item['metal_type'] ?? ''} · ${item['net_weight'] ?? 0} g · '
                          '${(item['hallmarked'] == 1) ? 'Hallmarked' : 'Non-hallmarked'}'),
                    ),
                  ),
                if (!released) ...[
              const SizedBox(height: 16),
              // v1.0.8: pawn operations — "Amount Paying" / "Amount Requesting"
              // / "Interest Paid", each with a single amount box + a past or
              // future date. Every action also logs a row in the pawn ledger.
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
              OutlinedButton.icon(
                onPressed: _interestPaid,
                icon: const Icon(Icons.percent),
                label: const Text('Interest Paid'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _release,
                icon: const Icon(Icons.lock_open),
                label: const Text('Release (principal + interest)'),
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
                  child: _txRow(t),
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
  Widget _txRow(Map<String, Object?> t) {
    final type = t['tx_type']?.toString() ?? '-';
    final label = switch (type) {
      'paying' => 'Amount Paying',
      'requesting' => 'Amount Requesting',
      'interest_paid' => 'Interest Paid',
      'release' => 'Release',
      _ => type,
    };
    final isOut = type == 'paying' || type == 'interest_paid' || type == 'release';
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
                  style: TextStyle(
                      fontSize: 10.5, color: mutedOf(context)),
                ),
                if (Num.toDouble(t['interest_part']) > 0 ||
                    Num.toDouble(t['principal_part']) > 0)
                  Text(
                    'P ₹${moneyWhole(Num.toDouble(t['principal_part']))} · '
                    'I ₹${moneyWhole(Num.toDouble(t['interest_part']))}',
                    style: TextStyle(
                        fontSize: 10.5, color: mutedOf(context)),
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

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(key, style: const TextStyle(color: Colors.grey)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// New pawn loan
// ---------------------------------------------------------------------------
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
  String? _customerUuid;
  String? _customerName;
  List<Map<String, Object?>> _customers = [];
  final List<_ItemEntry> _items = [_ItemEntry()];
  // v1.0.9: ID proof captured on the pawn loan itself.
  String _idProofType = 'Aadhaar';
  final _idNumber = TextEditingController();
  String? _idFront;
  String? _idBack;
  // v1.0.9: scanned customer address / village from the slip.
  final _address = TextEditingController();
  bool _scanning = false;

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

  /// The "+" beside the customer picker opens the full customer form (photo,
  /// ID proof type/number/front/back), then re-selects the new customer.
  Future<void> _addCustomer() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomerForm(initialType: 'General')),
    );
    await _loadCustomers();
    final newest = await context
        .read<AppState>()
        .db
        .query('customers', orderBy: 'updated_at desc', limit: 1);
    if (newest.isNotEmpty && mounted) {
      setState(() {
        _customerUuid = newest.first['client_uuid'] as String?;
        _customerName = newest.first['customer_name']?.toString();
        _setBasis(_basis, _customers);
      });
    }
  }

  /// v1.0.9: Scan the pawn slip. The camera image is read on-device (ML Kit)
  /// and the form is filled in with whatever the slip carries: ID Number,
  /// Customer Name, Item, Loan amount, Date, Item details and Address.
  Future<void> _scanSlip() async {
    if (_scanning) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: kGoldDark),
              title: const Text('Take a photo of the slip'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library_outlined, color: kGoldDark),
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

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 2000,
    );
    if (picked == null || !mounted) return;

    setState(() => _scanning = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fields = await scanSlipImage(picked.path);
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
        first.description.text =
            f.item.isNotEmpty ? f.item : f.itemDetails;
        if (f.itemDetails.isNotEmpty && f.itemDetails != f.item) {
          first.purity.text = f.itemDetails;
        }
      }
      // If the slip's customer already exists, select them in the picker.
      if (f.customerName.isNotEmpty) {
        final name = f.customerName.trim().toLowerCase();
        final match = _customers.where((c) =>
            (c['customer_name']?.toString() ?? '').trim().toLowerCase() == name);
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
      Row(children: [
        Expanded(
          child: PhotoField(
            path: _idFront,
            label: 'ID front',
            onPicked: (p) => setState(() => _idFront = p),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: PhotoField(
            path: _idBack,
            label: 'ID back',
            onPicked: (p) => setState(() => _idBack = p),
          ),
        ),
      ]),
    ]);
  }

  /// v1.0.9: rate per gram is NOT typed — it is derived automatically from the
  /// loan amount ÷ the item weight (net weight, else gross weight). Example:
  /// 10 g of gold given against ₹1,00,000 shows ₹10,000 per gram.
  Widget _autoRatePerGram() {
    final amount = parseMoney(_amount.text);
    double net = 0, gross = 0;
    for (final e in _items) {
      net += parseMoney(e.net.text);
      gross += parseMoney(e.gross.text);
    }
    final useNet = net > 0;
    final weight = useNet ? net : gross;
    final perGram = (weight > 0 && amount > 0) ? amount / weight : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kGold.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kGold.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calculate_outlined, size: 20, color: kGoldDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rate / gram (auto)',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: kGoldDark)),
                Text(
                  perGram == null
                      ? 'Enter loan amount + item weight'
                      : '₹${moneyWhole(perGram)} per gram  '
                          '(${useNet ? 'net' : 'gross'} weight '
                          '${weight.toStringAsFixed(3)} g)',
                  style: TextStyle(
                      fontSize: 12,
                      color: perGram == null
                          ? const Color(0xFF8A6D14)
                          : kInk.withValues(alpha: .8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _idNumber.dispose();
    _address.dispose();
    _rate.dispose();
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
          : customer['silver_interest_rate'];
      final value = Num.toDouble(override);
      _rate.text = (value > 0 ? value : (basis == 'Gold' ? 3 : 4)).toString();
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
    if (!_formKey.currentState!.validate()) return;
    if (_customerUuid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a customer first')));
      return;
    }
    final state = context.read<AppState>();
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

    await state.savePawnLoan(
      uuid: loanUuid,
      data: {
        'customer': _customerName,
        'customer_name': _customerName,
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
        'ltv': marketValue > 0 ? (loanAmount / marketValue * 100) : 0,
        'interest_accrued': interest,
        'total_payable': Num.money(loanAmount + interest),
        'amount_paid': 0,
        'balance': Num.money(loanAmount + interest),
        // v1.0.9: auto rate/gram + ID proof captured on the loan itself.
        'rate_per_gram': (totalNet > 0 || totalGross > 0)
            ? Num.money(loanAmount / (totalNet > 0 ? totalNet : totalGross))
            : 0,
        'id_proof_type': _idProofType,
        'id_proof_number': _idNumber.text.trim().isEmpty
            ? null
            : _idNumber.text.trim(),
        'id_front': _idFront,
        'id_back': _idBack,
      },
      items: items,
    );

    // Item photos are stored on the pawn_items rows inside savePawnLoan —
    // no separate photo write needed. (Previously this loop wrote to a
    // non-existent pawn_loans.photo_path column and aborted the whole save.)
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Pawn Loan'),
        actions: [
          // v1.0.9: scan the pawn slip — the form fills itself in.
          TextButton.icon(
            onPressed: _scanning ? null : _scanSlip,
            icon: _scanning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: kGold))
                : const Icon(Icons.document_scanner_outlined, size: 18),
            label: const Text('SCAN'),
          ),
          TextButton(onPressed: _save, child: const Text('SAVE')),
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
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: fieldDecoration('Customer *'),
                      initialValue: _customerUuid,
                      items: _customers
                          .map((c) => DropdownMenuItem(
                                value: c['client_uuid'] as String,
                                child:
                                    Text(c['customer_name']?.toString() ?? '-'),
                              ))
                          .toList(),
                      onChanged: (value) {
                        final customer = _customers.firstWhere(
                            (c) => c['client_uuid'] == value,
                            orElse: () => {});
                        setState(() {
                          _customerUuid = value;
                          _customerName = customer['customer_name']?.toString();
                          final override = _basis == 'Gold'
                              ? customer['gold_interest_rate']
                              : customer['silver_interest_rate'];
                          final v = Num.toDouble(override);
                          _rate.text = (v > 0 ? v : (_basis == 'Gold' ? 3 : 4))
                              .toString();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  // v1.0.8: add a new customer right here (+).
                  IconButton(
                    tooltip: 'Add new customer',
                    icon: const Icon(Icons.add_circle_outline,
                        color: kGoldDark, size: 26),
                    onPressed: _addCustomer,
                  ),
                ],
              ),
              if (_customers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('No customers yet — tap + to add one.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8A6D14))),
                ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _address,
                decoration: fieldDecoration('Customer address / village'),
              ),
            ]),
                SectionCard(title: 'Loan', children: [
                  DropdownButtonFormField<String>(
                    initialValue: _basis,
                    decoration: fieldDecoration('Interest basis'),
                    items: const ['Gold', 'Silver']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => _setBasis(v ?? 'Gold', _customers),
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
                            (parseMoney(v) <= 0)
                                ? 'Enter amount'
                                : null,
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
                  _autoRatePerGram(),
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
                        label: Text(_dueDate == null
                            ? 'Due date'
                            : fmtDate(_dueDate)),
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
        PhotoField(
          path: item.photoPath,
          onPicked: (path) => setState(() => item.photoPath = path),
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
Future<bool> _adminDeleteDialog(BuildContext context, String message,
    {String verb = 'delete'}) async {
  final pw = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Are you sure to $verb $message?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: pw,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Type admin password',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, pw.text.trim().toLowerCase() == 'admin'),
            child: Text(verb == 'release' ? 'Release' : 'Delete')),
      ],
    ),
  );
  return ok ?? false;
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
