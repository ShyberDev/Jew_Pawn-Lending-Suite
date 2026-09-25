import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/format.dart';
import '../util/ids.dart';
import 'widgets.dart';

class KhatabookScreen extends StatefulWidget {
  const KhatabookScreen({super.key});

  @override
  State<KhatabookScreen> createState() => _KhatabookScreenState();
}

class _KhatabookScreenState extends State<KhatabookScreen> {
  Future<void> _openForm() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const KhatabookLoanForm()));
    if (mounted) setState(() {});
  }

  Future<void> _openDetail(Map<String, Object?> loan) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _KhatabookDetail(loan: loan),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppState>().db;
    return Scaffold(
      appBar: AppBar(title: const Text('Khatabook')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('New Loan'),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: db.query('khatabook_loans', orderBy: 'loan_date desc'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('No khatabook loans yet.'));
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = rows[index];
              final closed = (row['status']?.toString() ?? 'Active') != 'Active';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      closed ? Colors.green.shade100 : Colors.blue.shade100,
                  child: Icon(closed ? Icons.check : Icons.menu_book, size: 20),
                ),
                title: Text(row['customer_name']?.toString() ?? '-'),
                subtitle: Text(
                    '${row['collection_frequency'] ?? ''} · ${row['installment_count'] ?? 0} × ₹${moneyWhole(row['installment_amount'] as num?)}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${moneyWhole(row['outstanding'] as num?)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(row['status']?.toString() ?? 'Active',
                        style: TextStyle(
                            fontSize: 12,
                            color: closed ? Colors.green : Colors.grey)),
                  ],
                ),
                onTap: () => _openDetail(row),
              );
            },
          );
        },
      ),
    );
  }
}

class _KhatabookDetail extends StatefulWidget {
  const _KhatabookDetail({required this.loan});

  final Map<String, Object?> loan;

  @override
  State<_KhatabookDetail> createState() => _KhatabookDetailState();
}

class _KhatabookDetailState extends State<_KhatabookDetail> {
  List<Map<String, Object?>> _collections = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await context.read<AppState>().db.query('khatabook_collections',
        where: 'khatabook_loan = ?',
        whereArgs: [widget.loan['server_name'] ?? widget.loan['client_uuid']],
        orderBy: 'collection_date desc');
    if (mounted) setState(() => _collections = rows);
  }

  Future<void> _collect() async {
    final loan = widget.loan;
    final amount = TextEditingController(
        text: moneyWhole(Num.toDouble(loan['installment_amount'])));
    final irregular = ValueNotifier<bool>(false);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add collection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: fieldDecoration('Amount')),
            const SizedBox(height: 8),
            ValueListenableBuilder<bool>(
              valueListenable: irregular,
              builder: (_, value, __) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Irregular payment'),
                value: value,
                onChanged: (v) => irregular.value = v ?? false,
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
    );
    if (ok != true) return;
    final value = Num.money(double.tryParse(amount.text) ?? 0);
    if (value <= 0) return;
    final state = context.read<AppState>();
    await state.saveEntity(
      table: 'khatabook_collections',
      doctype: 'Khatabook Collection',
      uuid: newUuid(),
      data: {
        'khatabook_loan': loan['server_name'] ?? loan['client_uuid'],
        'customer': loan['customer_name'],
        'village': loan['village'],
        'collection_date': todayIso(),
        'amount': value,
        'payment_mode': 'Cash',
        'is_irregular': irregular.value ? 1 : 0,
      },
    );
    // The server applies the collection to the loan's installments on submit;
    // reflect it locally without queueing a second push (pull will confirm).
    final collected = Num.money(Num.toDouble(loan['total_collected']) + value);
    final outstanding = Num.money(Num.toDouble(loan['outstanding']) - value);
    await state.db.upsert('khatabook_loans', {
      ...loan,
      'total_collected': collected,
      'outstanding': outstanding < 0 ? 0 : outstanding,
      'paid_installments': (loan['paid_installments'] as int? ?? 0) + 1,
      'status': outstanding <= 0 ? 'Closed' : 'Active',
      'dirty': 0,
    });
    if (mounted) Navigator.pop(context);
  }

  Future<void> _refinance() async {
    final loan = widget.loan;
    final outstanding = Num.toDouble(loan['outstanding']);
    final principal =
        TextEditingController(text: moneyWhole(outstanding));
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refinance balance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Old outstanding: ₹${moneyWhole(outstanding)}'),
            const SizedBox(height: 12),
            TextField(
                controller: principal,
                keyboardType: TextInputType.number,
                decoration: fieldDecoration('New principal')),
            const SizedBox(height: 10),
            TextField(
                controller: note,
                decoration: fieldDecoration('Interest note (e.g. 200 per 1000)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Refinance')),
        ],
      ),
    );
    if (ok != true) return;
    final state = context.read<AppState>();
    final newPrincipal = Num.money(double.tryParse(principal.text) ?? 0);
    if (newPrincipal <= 0) return;
    final installments = loan['installment_count'] as int? ?? 12;
    final newInterest = Num.money(newPrincipal * 0.2);
    await state.saveEntity(
      table: 'khatabook_refinances',
      doctype: 'Khatabook Refinance',
      uuid: newUuid(),
      data: {
        'khatabook_loan': loan['server_name'] ?? loan['client_uuid'],
        'customer': loan['customer_name'],
        'refinance_date': todayIso(),
        'old_outstanding': outstanding,
        'new_principal': newPrincipal,
        'new_interest_amount': newInterest,
        'new_installment_count': installments,
        'new_interest_note': note.text.trim(),
      },
    );
    // The server closes the old loan and creates the new one on submit;
    // reflect the closure locally without queueing a second push.
    await state.db.upsert('khatabook_loans', {
      ...loan,
      'status': 'Closed',
      'dirty': 0,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          Text(loan['customer_name']?.toString() ?? '-',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('${loan['village'] ?? ''}  ${loan['phone'] ?? ''}'),
          const Divider(height: 24),
          _kv('Principal', '₹${moneyWhole(loan['principal_amount'] as num?)}'),
          _kv('Interest', '₹${moneyWhole(loan['interest_amount'] as num?)}'),
          _kv('Total payable', '₹${moneyWhole(loan['total_payable'] as num?)}'),
          _kv('Collected', '₹${moneyWhole(loan['total_collected'] as num?)}'),
          _kv('Outstanding', '₹${moneyWhole(loan['outstanding'] as num?)}'),
          _kv('Installments',
              '${loan['paid_installments'] ?? 0} / ${loan['installment_count'] ?? 0}'),
          _kv('Frequency', loan['collection_frequency']?.toString() ?? '-'),
          _kv('Rating', loan['customer_rating']?.toString() ?? '-'),
          const Divider(height: 24),
          Text('Collections', style: Theme.of(context).textTheme.titleMedium),
          if (_collections.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No collections yet.'),
            ),
          for (final c in _collections)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.payments_outlined),
              title: Text('₹${moneyWhole(c['amount'] as num?)}'),
              subtitle: Text(
                  '${c['collection_date']}${c['is_irregular'] == 1 ? ' · irregular' : ''}'),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _collect,
                icon: const Icon(Icons.add),
                label: const Text('Collect'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _refinance,
                icon: const Icon(Icons.autorenew),
                label: const Text('Refinance'),
              ),
            ),
          ]),
          const SizedBox(height: 24),
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

class KhatabookLoanForm extends StatefulWidget {
  const KhatabookLoanForm(
      {super.key,
      this.initialCustomerUuid,
      this.initialCustomerName,
      this.initialVillage});

  final String? initialCustomerUuid;
  final String? initialCustomerName;
  final String? initialVillage;

  @override
  State<KhatabookLoanForm> createState() => _KhatabookLoanFormState();
}

class _KhatabookLoanFormState extends State<KhatabookLoanForm> {
  final _formKey = GlobalKey<FormState>();
  final _principal = TextEditingController();
  final _interest = TextEditingController();
  final _installments = TextEditingController(text: '12');
  String _frequency = 'Weekly';
  String _rating = 'New';
  String? _customerUuid;
  String? _customerName;
  String? _village;

  @override
  void initState() {
    super.initState();
    _customerUuid = widget.initialCustomerUuid;
    _customerName = widget.initialCustomerName;
    _village = widget.initialVillage;
  }

  @override
  void dispose() {
    _principal.dispose();
    _interest.dispose();
    _installments.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_customerUuid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a customer first')));
      return;
    }
    final state = context.read<AppState>();
    final principal = Num.money(double.tryParse(_principal.text) ?? 0);
    final interest = Num.money(double.tryParse(_interest.text) ?? 0);
    final installments = int.tryParse(_installments.text) ?? 12;
    final total = Num.money(principal + interest);
    await state.saveEntity(
      table: 'khatabook_loans',
      doctype: 'Khatabook Loan',
      uuid: newUuid(),
      data: {
        'customer': _customerName,
        'customer_name': _customerName,
        'village': _village,
        'status': 'Active',
        'loan_date': todayIso(),
        'principal_amount': principal,
        'interest_amount': interest,
        'total_payable': total,
        'installment_count': installments,
        'installment_amount':
            Num.money(installments > 0 ? total / installments : total),
        'collection_frequency': _frequency,
        'customer_rating': _rating,
        'total_collected': 0,
        'paid_installments': 0,
        'outstanding': total,
      },
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppState>().db;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Khatabook Loan'),
        actions: [TextButton(onPressed: _save, child: const Text('SAVE'))],
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
                        _village = customer['village']?.toString();
                      });
                    },
                  ),
                ]),
                SectionCard(title: 'Loan terms', children: [
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                      controller: _principal,
                      keyboardType: TextInputType.number,
                      decoration: fieldDecoration('Principal *'),
                      validator: (v) =>
                          (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Required' : null,
                    )),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextFormField(
                      controller: _interest,
                      keyboardType: TextInputType.number,
                      decoration: fieldDecoration('Total interest'),
                    )),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                      controller: _installments,
                      keyboardType: TextInputType.number,
                      decoration: fieldDecoration('Installments'),
                    )),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _frequency,
                        decoration: fieldDecoration('Frequency'),
                        items: const ['Weekly', 'Biweekly', 'Monthly']
                            .map((v) =>
                                DropdownMenuItem(value: v, child: Text(v)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _frequency = v ?? _frequency),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _rating,
                    decoration: fieldDecoration('Customer rating'),
                    items: const ['New', 'Good', 'Bad']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => setState(() => _rating = v ?? _rating),
                  ),
                ]),
                const SizedBox(height: 60),
              ],
            ),
          );
        },
      ),
    );
  }
}
