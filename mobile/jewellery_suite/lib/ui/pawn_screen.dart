import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/format.dart';
import '../util/ids.dart';
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

  Future<List<Map<String, Object?>>> _load() {
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
    if (_filter == 'recent') {
      return db.query('pawn_loans',
          where: where,
          whereArgs: args,
          orderBy: 'loan_date desc',
          limit: 10);
    }
    final order =
        _filter == 'interest' ? 'interest_accrued desc' : 'loan_date desc';
    return db.query('pawn_loans',
        where: where, whereArgs: args, orderBy: order);
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
      builder: (_) => _PawnDetail(loan: loan),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              decoration: fieldDecoration('Search customer or phone'),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, Object?>>>(
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
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final status = row['status']?.toString() ?? 'Active';
                    final released = status == 'Released';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: released
                            ? kGreenSoft
                            : kGold.withValues(alpha: .25),
                        child: Icon(
                            released ? Icons.check : Icons.lock_clock,
                            size: 20,
                            color: released ? kGreen : kGoldDark),
                      ),
                      title: Text(row['customer_name']?.toString() ?? '-'),
                      subtitle: Text(
                          '${fmtDate(row['loan_date'])} · ${row['interest_basis'] ?? ''} · ₹${moneyWhole(row['loan_amount'] as num?)}'),
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
                            const Icon(Icons.cloud_upload_outlined, size: 16),
                        ],
                      ),
                      onTap: () => _openDetail(row),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStrip() {
    final db = context.read<AppState>().db;
    return FutureBuilder<Map<String, Object?>>(
      future: () async {
        final loans = await db.query('pawn_loans',
            where: 'status = ? OR status IS NULL', whereArgs: ['Active']);
        double out = 0, intDue = 0;
        for (final l in loans) {
          out += Num.toDouble(l['loan_amount']);
          intDue += Num.toDouble(l['interest_accrued']);
        }
        return {
          'out': Num.money(out),
          'int': Num.money(intDue),
          'n': loans.length,
        };
      }(),
      builder: (context, snap) {
        final r = snap.data ?? const {};
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
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('₹${r['out'] ?? 0}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    Text('Principal out',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: .75))),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('₹${r['int'] ?? 0}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    Text('Interest due',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: .75))),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r['n'] ?? 0}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    Text('Active pawns',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: .75))),
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
}

class _PawnDetail extends StatefulWidget {
  const _PawnDetail({required this.loan});

  final Map<String, Object?> loan;

  @override
  State<_PawnDetail> createState() => _PawnDetailState();
}

class _PawnDetailState extends State<_PawnDetail> {
  List<Map<String, Object?>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await context
        .read<AppState>()
        .itemsFor(widget.loan['client_uuid'] as String);
    if (mounted) setState(() => _items = items);
  }

  Future<void> _release() async {
    final loan = widget.loan;
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
    final pp = Num.money(double.tryParse(principalController.text) ?? 0);
    final ip = Num.money(double.tryParse(interestController.text) ?? 0);
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
    // The server updates the loan when the release is submitted; reflect that
    // locally without queueing a second push.
    await state.db.upsert('pawn_loans', {
      ...loan,
      'status': 'Released',
      'release_date': todayIso(),
      'amount_paid': total,
      'balance': 0,
      'dirty': 0,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final released = (loan['status']?.toString() ?? 'Active') == 'Released';
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text(loan['customer_name']?.toString() ?? '-',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${loan['phone'] ?? ''}  ${loan['village'] ?? ''}'),
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
            for (final item in _items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: (item['photo_path'] != null &&
                        File(item['photo_path'] as String).existsSync())
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(File(item['photo_path'] as String),
                            width: 44, height: 44, fit: BoxFit.cover))
                    : const Icon(Icons.diamond_outlined),
                title: Text(item['item_description']?.toString() ?? '-'),
                subtitle: Text(
                    '${item['metal_type'] ?? ''} · ${item['net_weight'] ?? 0} g · '
                    '${(item['hallmarked'] == 1) ? 'Hallmarked' : 'Non-hallmarked'}'),
              ),
            const SizedBox(height: 16),
            if (!released)
              FilledButton.icon(
                onPressed: _release,
                icon: const Icon(Icons.lock_open),
                label: const Text('Release (principal + interest)'),
              ),
            const SizedBox(height: 24),
          ],
        ),
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
    final netWeight = Num.round3(double.tryParse(net.text) ?? 0);
    final valuationRate = double.tryParse(rate.text) ?? 0;
    return {
      'item_description': description.text.trim(),
      'metal_type': metalType,
      'purity': purity.text.trim().isEmpty ? null : purity.text.trim(),
      'quantity': int.tryParse(quantity.text) ?? 1,
      'gross_weight': Num.round3(double.tryParse(gross.text) ?? 0),
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
  final List<_ItemEntry> _items = [_ItemEntry()];

  @override
  void dispose() {
    _amount.dispose();
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
    final loanAmount = Num.money(double.tryParse(_amount.text) ?? 0);
    final rate = double.tryParse(_rate.text) ?? 3;
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
        'village': null,
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
      },
      items: items,
    );

    // Queue each item photo against the loan document.
    for (final item in items) {
      final photo = item['photo_path'] as String?;
      if (photo != null && photo.isNotEmpty) {
        await state.savePhoto(
            table: 'pawn_loans',
            doctype: 'Pawn Loan',
            uuid: loanUuid,
            path: photo);
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppState>().db;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Pawn Loan'),
        actions: [
          TextButton(onPressed: _save, child: const Text('SAVE')),
        ],
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: db.query('customers', orderBy: 'customer_name asc'),
        builder: (context, snapshot) {
          final customers = snapshot.data ?? const [];
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                SectionCard(title: 'Customer', children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: fieldDecoration('Customer *'),
                    initialValue: _customerUuid,
                    items: customers
                        .map((c) => DropdownMenuItem(
                              value: c['client_uuid'] as String,
                              child: Text(c['customer_name']?.toString() ?? '-'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      final customer = customers.firstWhere(
                          (c) => c['client_uuid'] == value,
                          orElse: () => {});
                      setState(() {
                        _customerUuid = value;
                        _customerName = customer['customer_name']?.toString();
                        final override = _basis == 'Gold'
                            ? customer['gold_interest_rate']
                            : customer['silver_interest_rate'];
                        final v = Num.toDouble(override);
                        _rate.text =
                            (v > 0 ? v : (_basis == 'Gold' ? 3 : 4)).toString();
                      });
                    },
                  ),
                ]),
                SectionCard(title: 'Loan', children: [
                  DropdownButtonFormField<String>(
                    initialValue: _basis,
                    decoration: fieldDecoration('Interest basis'),
                    items: const ['Gold', 'Silver']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => _setBasis(v ?? 'Gold', customers),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _amount,
                        keyboardType: TextInputType.number,
                        decoration: fieldDecoration('Loan amount *'),
                        validator: (v) =>
                            (double.tryParse(v ?? '') ?? 0) <= 0
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
                const SizedBox(height: 60),
              ],
            ),
          );
        },
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
            decoration: fieldDecoration('Gross g'),
          )),
          const SizedBox(width: 8),
          Expanded(
              child: TextFormField(
            controller: item.net,
            keyboardType: TextInputType.number,
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
