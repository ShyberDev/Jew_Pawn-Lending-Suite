import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/format.dart';
import '../util/ids.dart';
import 'widgets.dart';

class PawnScreen extends StatefulWidget {
  const PawnScreen({super.key});

  @override
  State<PawnScreen> createState() => _PawnScreenState();
}

class _PawnScreenState extends State<PawnScreen> {
  String _search = '';

  Future<List<Map<String, Object?>>> _load() {
    final db = context.read<AppState>().db;
    if (_search.trim().isEmpty) {
      return db.query('pawn_loans', orderBy: 'loan_date desc');
    }
    final term = '%${_search.trim()}%';
    return db.query('pawn_loans',
        where: 'customer_name LIKE ? OR phone LIKE ?',
        whereArgs: [term, term],
        orderBy: 'loan_date desc');
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
      appBar: AppBar(title: const Text('Pawn Loans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('New Loan'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
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
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return const Center(child: Text('No pawn loans yet.'));
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
                            ? Colors.green.shade100
                            : Colors.amber.shade100,
                        child: Icon(released ? Icons.check : Icons.lock_clock,
                            size: 20),
                      ),
                      title: Text(row['customer_name']?.toString() ?? '-'),
                      subtitle: Text(
                          '${row['loan_date'] ?? ''} · ${row['interest_basis'] ?? ''} · ₹${moneyText(row['loan_amount'] as num?)}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(status,
                              style: TextStyle(
                                  color: released
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.primary,
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
    double interest = Num.toDouble(loan['interest_accrued']);
    if (interest <= 0) {
      interest = Num.simpleInterest(
          principal: loanAmount, ratePerMonth: rate, days: days);
    }
    if (balance > 0 && interest > balance) interest = balance;
    final principalDue = balance > 0
        ? Num.money(balance - interest)
        : Num.money(loanAmount - paid);

    final principalController =
        TextEditingController(text: principalDue.toStringAsFixed(2));
    final interestController =
        TextEditingController(text: interest.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release pawn'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Days: $days  ·  Rate: $rate%/month'),
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
            _kv('Loan date', loan['loan_date']?.toString() ?? '-'),
            _kv('Due date', loan['due_date']?.toString() ?? '-'),
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
                    value: _customerUuid,
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
                    value: _basis,
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
                        label: Text(_loanDate.toIso8601String().substring(0, 10)),
                        onPressed: () => _pickDate(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event, size: 16),
                        label: Text(_dueDate == null
                            ? 'Due date'
                            : _dueDate!.toIso8601String().substring(0, 10)),
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
              value: item.metalType,
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
