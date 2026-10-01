import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/migration_v11.dart';
import '../state/app_state.dart';
import 'refinance_sheet.dart';
import '../util/format.dart';
import '../util/ids.dart';
import '../util/khata_alloc.dart';
import '../util/khata_loan_state.dart';
import '../util/khata_math.dart';
import '../util/khata_schedule.dart';
import 'palette.dart';
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
              final closed = !isActiveKhataStatus(row['status']);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      closed ? Colors.green.shade100 : Colors.blue.shade100,
                  child: Icon(closed ? Icons.check : Icons.menu_book, size: 20),
                ),
                title: Text(row['customer_name']?.toString() ?? '-'),
                subtitle: Text(
                    '${row['collection_frequency'] ?? ''} · ${row['installment_count'] ?? 0} × ₹${moneyWholeDown(row['installment_amount'] as num?)}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${moneyWholeDown(row['outstanding'] as num?)}',
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
    final rows = await context.read<AppState>().db.query(
        'khatabook_collections',
        where: 'khatabook_loan = ?',
        whereArgs: [widget.loan['server_name'] ?? widget.loan['client_uuid']],
        orderBy: 'collection_date desc');
    if (mounted) setState(() => _collections = rows);
  }

  Future<void> _collect() async {
    final state = context.read<AppState>();
    var loan = widget.loan;
    final isIO = MigrationV11.isInterestOnly(loan);
    // Interest-only loans bill on demand: make sure every elapsed period
    // exists before the dialog, so the period list is complete.
    List<Map<String, Object?>> periods = const [];
    if (isIO) {
      periods = await state.ensureInterestPeriods(loan);
      final fresh = await state.db
          .byUuid('khatabook_loans', loan['client_uuid']?.toString() ?? '');
      if (fresh != null) loan = fresh;
    }
    // v1.0.11: the amount box starts EMPTY — the shopkeeper types what was
    // actually handed over. The instalment amount is only a hint.
    final amount = TextEditingController();
    final instalment = moneyWholeDown(Num.toDouble(loan['installment_amount']));
    final irregular = ValueNotifier<bool>(false);
    String kind = 'normal';
    int? futurePeriod;
    int nextUnbilled = periods.isEmpty
        ? 1
        : ((periods.last['installment_number'] as num?)?.toInt() ?? 0) + 1;
    String periodLabel(Map<String, Object?> p) {
      final n = (p['installment_number'] as num?)?.toInt() ?? 0;
      final due = p['due_date']?.toString() ?? '';
      final rem = Num.toDouble(p['remaining_amount']);
      final st = rem <= 0 ? 'paid' : 'owes ₹${moneyWholeDown(rem)}';
      return 'Period $n · $due · $st';
    }

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Add collection'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: fieldDecoration('Amount received',
                      hint: instalment.isEmpty ? null : 'e.g. $instalment')),
              const SizedBox(height: 8),
              // Future interest is EXPLICIT only: normal money never prepays
              // the future, and only interest-only loans offer the choice.
              if (isIO) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (v, label) in const [
                      ('normal', 'Normal collection'),
                      ('future', 'Future Interest'),
                    ])
                      ChoiceChip(
                        label:
                            Text(label, style: const TextStyle(fontSize: 12.5)),
                        selected: kind == v,
                        selectedColor: kGold.withValues(alpha: .25),
                        onSelected: (_) => setDlg(() => kind = v),
                      ),
                  ],
                ),
                if (kind == 'future') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: futurePeriod,
                    decoration: fieldDecoration('Interest period (month)'),
                    items: [
                      for (final p in periods)
                        DropdownMenuItem(
                          value: (p['installment_number'] as num?)?.toInt(),
                          child: Text(periodLabel(p),
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                      DropdownMenuItem(
                        value: nextUnbilled,
                        child: Text(
                            'Period $nextUnbilled · next (not yet billed)',
                            style: const TextStyle(fontSize: 12.5)),
                      ),
                    ],
                    onChanged: (v) => setDlg(() => futurePeriod = v),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Only the chosen period is marked paid. Extra money follows the normal rules.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8A6D14)),
                  ),
                ],
                const SizedBox(height: 8),
              ],
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
      ),
    );
    if (ok != true) return;
    final value = Num.rupees(parseMoney(amount.text));
    if (value <= 0) return;
    if (isIO && kind == 'future' && futurePeriod == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Choose which interest period this prepays.')));
      }
      return;
    }
    // A collection can never be more than what is owed (the server rejects it,
    // which used to leave the entry stuck in the outbox as an error).
    final owing = Num.toDouble(loan['outstanding']);
    if (value > owing + 0.01) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '₹${moneyWholeDown(value)} is more than the ₹${moneyWholeDown(owing)} due.'),
        backgroundColor: kRed,
      ));
      return;
    }
    final collectionUuid = newUuid();
    // An explicit Future Interest payment bills that period first (if it was
    // not billed yet) so the money has something real to settle.
    int? futureBilled;
    if (isIO && kind == 'future' && futurePeriod != null) {
      periods =
          await state.ensureInterestPeriods(loan, throughPeriod: futurePeriod);
      final fresh = await state.db
          .byUuid('khatabook_loans', loan['client_uuid']?.toString() ?? '');
      if (fresh != null) loan = fresh;
      futureBilled = futurePeriod;
    }
    await state.saveEntity(
      table: 'khatabook_collections',
      doctype: 'Khatabook Collection',
      uuid: collectionUuid,
      data: {
        'khatabook_loan': loan['server_name'] ?? loan['client_uuid'],
        'customer': loan['customer_name'],
        'customer_uuid': loan['customer_uuid'],
        'village': loan['village'],
        'collection_date': todayIso(),
        'amount': value,
        'payment_mode': 'Cash',
        'is_irregular': irregular.value ? 1 : 0,
        if (futureBilled != null) 'interest_period': futureBilled,
      },
    );
    // The server applies the collection to the loan's installments on submit;
    // reflect it locally without queueing a second push (pull will confirm).
    //
    // The stored total is the authority, and this collection is ADDED to it.
    // Recomputing from the khatabook_collections table instead would discard
    // every rupee collected before a collection row existed — and rows are not
    // guaranteed for every rupee (loan creation seeds a collected figure
    // directly), which made a balance jump back UP after collecting.
    // v10: allocate with the canonical engine — interest first, principal only
    // once interest is clear — so the shop can finally see how much capital a
    // payment actually recovered. The ledger rows are written by
    // `_recordAllocations`, keeping "where did each rupee go" auditable.
    final before = KhataLoanState.fromRow(loan);
    final allocation = KhataAlloc.allocate(
      payment: value,
      interestDue: Num.toDouble(loan['interest_outstanding'] ?? 0),
      lateFeeDue: Num.toDouble(loan['late_fee_outstanding'] ?? 0),
      otherChargeDue: Num.toDouble(loan['other_charge_outstanding'] ?? 0),
      principalDue: before.investment,
    );
    final after = KhataLoanState.apply(before, allocation);
    final collected = KhataMath.addToCollected(
      already: Num.toDouble(loan['total_collected']),
      payment: value,
      totalPayable: Num.toDouble(loan['total_payable']),
    );
    await state.db.upsert('khatabook_loans', {
      ...loan,
      ...after.toRow(),
      'total_collected': collected,
      'paid_installments': KhataMath.paidInstallments(
        collected: collected,
        totalPayable: Num.toDouble(loan['total_payable']),
        count: (loan['installment_count'] as num?)?.toInt() ?? 0,
      ),
      'dirty': 0,
    });
    // The permanent ledger: exactly where each rupee of this payment went.
    await state.recordAllocations(
      loanUuid: loan['client_uuid']?.toString() ?? '',
      collectionUuid: collectionUuid,
      allocation: allocation,
    );
    await state.touchActivity(loan['customer_uuid']?.toString());
    if (isIO) {
      // Mark interest periods: the chosen future period first (explicit
      // prepay), then the rest follows the normal oldest-first rules.
      // Principal needs no rows — only interest periods are tracked here.
      var left = allocation.interest;
      if (futureBilled != null && left > 0) {
        left = Num.rupees(left -
            await state.applyPaymentToInterestPeriods(
              loan['client_uuid']?.toString() ?? '',
              left,
              onlyPeriod: futureBilled,
            ));
      }
      if (left > 0) {
        await state.applyPaymentToInterestPeriods(
            loan['client_uuid']?.toString() ?? '', left);
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _refinance() async {
    // Hoisted above the dialog: a refinance is a money movement and must not be
    // dropped just because the user closed the sheet while it was open.
    final state = context.read<AppState>();
    // One shared dialog + one shared writer: identical to the profile path,
    // including an explicit interest figure instead of a fixed 20%.
    final loan = widget.loan;
    final params = await showRefinanceDialog(context, loan);
    if (params == null) return;
    await state.executeRefinance(
      oldLoan: loan,
      fresh: params.fresh,
      interest: params.interest,
      paymentType: params.paymentType,
      frequency: params.frequency,
      count: params.count,
      collectionAmount: params.collectionAmount,
      note: params.note,
    );
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
          _kv('Principal', '₹${moneyWholeDown(loan['principal_amount'] as num?)}'),
          _kv('Interest', '₹${moneyWholeDown(loan['interest_amount'] as num?)}'),
          _kv('Total payable', '₹${moneyWholeDown(loan['total_payable'] as num?)}'),
          _kv('Collected', '₹${moneyWholeDown(loan['total_collected'] as num?)}'),
          _kv('Outstanding', '₹${moneyWholeDown(loan['outstanding'] as num?)}'),
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
              title: Text('₹${moneyWholeDown(c['amount'] as num?)}'),
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
  String _paymentType = 'Installment';

  bool get _isInterestOnly => _paymentType == 'Interest Only';
  String _rating = 'New';
  String? _customerUuid;
  String? _customerName;
  String? _village;

  /// When the loan was actually given — default today, back-datable.
  DateTime _loanDate = DateTime.now();

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
    final principal = Num.rupees(parseMoney(_principal.text));
    final interest = Num.rupees(parseMoney(_interest.text));
    // Interest-only loans have no installment count; the first period's
    // interest is billed at creation and later periods on demand.
    final installments =
        _isInterestOnly ? 0 : (int.tryParse(_installments.text) ?? 12);
    // Interest-only loans start at principal only: the first period is billed
    // by ensureInterestPeriods below. Pre-adding it here would bill twice.
    final total = Num.rupees(_isInterestOnly ? principal : principal + interest);
    final loanUuid = newUuid();
    await state.saveEntity(
      table: 'khatabook_loans',
      doctype: 'Khatabook Loan',
      uuid: loanUuid,
      data: {
        'customer': _customerName,
        'customer_name': _customerName,
        // v9: identity is the uuid, not the name. Two people may share a name,
        // and a name-only link is what put one Ravi's loan in another Ravi's
        // village. customer_name stays as the display cache.
        'customer_uuid': _customerUuid,
        'village': _village,
        'status': 'Active',
        'loan_date': _loanDate.toIso8601String().substring(0, 10),
        'start_date': _loanDate.toIso8601String().substring(0, 10),
        'principal_amount': principal,
        'interest_amount': interest,
        'total_payable': total,
        'installment_count': installments,
        'installment_amount':
            Num.rupees(installments > 0 ? total / installments : interest),
        'collection_frequency': _frequency,
        'customer_rating': _rating,
        'payment_type': _isInterestOnly ? 'INTEREST_ONLY' : 'INSTALLMENT',
        'current_interest': interest,
        'total_collected': 0,
        'paid_installments': 0,
        'outstanding': total,
      },
    );
    // Interest-only loans bill their first period immediately so dues exist
    // from day one; later periods are billed on demand.
    if (_isInterestOnly) {
      final created = await state.db.byUuid('khatabook_loans', loanUuid);
      if (created != null) {
        await state.ensureInterestPeriods(created);
      }
    }
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
                              child:
                                  Text(c['customer_name']?.toString() ?? '-'),
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
                  // Payment type: installment loans amortise a fixed total;
                  // interest-only loans bill one interest period at a time and
                  // need no installment count.
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final t in const ['Installment', 'Interest Only'])
                        ChoiceChip(
                          label:
                              Text(t, style: const TextStyle(fontSize: 12.5)),
                          selected: _paymentType == t,
                          selectedColor: kGold.withValues(alpha: .25),
                          onSelected: (_) => setState(() => _paymentType = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // v1.0.8: back-datable "loan given on" date.
                  Row(children: [
                    const Icon(Icons.event, size: 18, color: kGoldDark),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Given on ${fmtDate(_loanDate)}',
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: kGoldDark),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _loanDate,
                          firstDate: DateTime(2015),
                          lastDate: DateTime(2100),
                          helpText: 'Date the loan was given',
                        );
                        if (d != null) {
                          setState(() =>
                              _loanDate = DateTime(d.year, d.month, d.day));
                        }
                      },
                      icon: const Icon(Icons.calendar_month, size: 18),
                      label: const Text('Change'),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                        child: TextFormField(
                      controller: _principal,
                      keyboardType: TextInputType.number,
                      decoration: fieldDecoration('Principal *'),
                      validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                          ? 'Required'
                          : null,
                    )),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextFormField(
                      controller: _interest,
                      keyboardType: TextInputType.number,
                      decoration: fieldDecoration(_isInterestOnly
                          ? 'Interest per period'
                          : 'Total interest'),
                    )),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    if (!_isInterestOnly)
                      Expanded(
                          child: TextFormField(
                        controller: _installments,
                        keyboardType: TextInputType.number,
                        decoration: fieldDecoration('Installments'),
                      )),
                    if (!_isInterestOnly) const SizedBox(width: 8),
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
