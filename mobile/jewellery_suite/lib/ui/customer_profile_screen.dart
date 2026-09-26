import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import '../util/format.dart';
import '../util/ids.dart';
import 'customers_screen.dart';
import 'khata_screen.dart' show loanNextDue;
import 'khatabook_screen.dart';
import 'palette.dart';
import 'widgets.dart';

/// Customer profile (Stitch 04-customer-profile): outstanding hero,
/// SBI-style You Gave / You Got ledger with running balance, sticky
/// Collect / You Gave bar, Call / SMS / WhatsApp / Edit actions
/// and a tappable full-screen avatar.
class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key, this.customer});

  final Map<String, Object?>? customer;

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  Map<String, Object?> _customer = {};
  List<Map<String, Object?>> _loans = [];
  List<Map<String, Object?>> _collections = [];
  List<Map<String, Object?>> _given = [];
  List<Map<String, Object?>> _refinances = [];
  bool _loading = true;

  /// True while a ledger tile is being dragged so the trash bin shows.
  bool _dragActive = false;

  String get _name => _customer['customer_name']?.toString() ?? '-';
  String get _phone => _customer['phone']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _customer = widget.customer ?? {};
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final db = context.read<AppState>().db;
      final uuid = _customer['client_uuid'] as String?;
      if (uuid != null) {
        final fresh = await db.byUuid('customers', uuid);
        if (fresh != null) _customer = fresh;
      }
      final loans = await db.query('khatabook_loans',
          where: 'customer_name = ? OR customer = ?', whereArgs: [_name, uuid],
          orderBy: 'loan_date asc');
      // khatabook_collections has only `customer` (may hold the name or the
      // client uuid); khatabook_given also has `customer_name`.
      final collections = await db.query('khatabook_collections',
          where: 'customer = ? OR customer = ?',
          whereArgs: [uuid, _name],
          orderBy: 'collection_date desc');
      final given = await db.query('khatabook_given',
          where: 'customer = ? OR customer_name = ? OR customer = ?',
          whereArgs: [_name, _name, uuid],
          orderBy: 'given_date desc');
      final refinances = await db.query('khatabook_refinances',
          where: 'customer = ? OR customer = ?',
          whereArgs: [uuid, _name],
          orderBy: 'refinance_date asc');
      if (!mounted) return;
      setState(() {
        _loans = loans;
        _collections = collections;
        _given = given;
        _refinances = refinances;
        _loading = false;
      });
    } catch (error) {
      debugPrint('profile refresh failed: $error');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, Object?>> get _activeLoans =>
      _loans.where((l) => (l['status']?.toString() ?? 'Active') == 'Active').toList();

  double get _outstanding {
    final rows = _ledgerRows();
    // rows are newest-first, so the first row carries the final balance.
    return rows.isEmpty ? 0 : rows.first.balance;
  }
  // What they've paid back = sum of all collections recorded.
  double get _paid => Num.money(
      _collections.fold<double>(0, (s, c) => s + Num.toDouble(c['amount'])));
  // What they owe overall = outstanding + paid (matches the ledger totals).
  double get _total => Num.money(_outstanding + _paid);
  // The invested principal (fresh cash handed over) across active loans.
  double get _principal => Num.money(_activeLoans.fold<double>(
      0, (s, l) => s + Num.toDouble(l['principal_amount'])));

  // ------------------------------------------------------------ contact calls
  Future<void> _call() async {
    final phone = _phone.trim();
    if (phone.isEmpty) {
      _toast('No phone number saved.');
      return;
    }
    final ok = await launchUrl(Uri.parse('tel:$phone'),
        mode: LaunchMode.externalApplication);
    if (!ok) _toast('Could not open dialer.');
  }

  Future<void> _sms() async {
    final phone = _phone.trim();
    if (phone.isEmpty) {
      _toast('No phone number saved.');
      return;
    }
    // Pre-fill the message body (like WhatsApp) — Android reads sms:?body=.
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {
        'body':
            'Namaste $_name 🙏\nYour khata balance is ₹${moneyWhole(_outstanding)}'
                ' (Paid ₹${moneyWhole(_paid)} of ₹${moneyWhole(_total)}).',
      },
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _toast('Could not open SMS.');
  }

  Future<void> _whatsapp() async {
    final phone = _phone.trim();
    if (phone.isEmpty) {
      _toast('No phone number saved.');
      return;
    }
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final message = Uri.encodeComponent(
        'Namaste $_name 🙏\nYour khata balance is ₹${moneyWhole(_outstanding)}'
        ' (Paid ₹${moneyWhole(_paid)} of ₹${moneyWhole(_total)}).');
    final ok = await launchUrl(Uri.parse('https://wa.me/$digits?text=$message'),
        mode: LaunchMode.externalApplication);
    if (!ok) _toast('Could not open WhatsApp.');
  }

  // ------------------------------------------------------------- collection
  Future<void> _collect() async {
    final targets = _activeLoans
        .map((l) => (loan: l, due: loanNextDue(l, DateTime.now())))
        .toList()
      ..sort((a, b) {
        if (a.due == null && b.due == null) return 0;
        if (a.due == null) return 1;
        if (b.due == null) return -1;
        return a.due!.compareTo(b.due!);
      });
    if (targets.isEmpty) {
      _toast('No active loan to collect against.');
      return;
    }
    final loan = targets.first.loan;
    final suggested = (loan['installment_amount'] as num?)?.toDouble() ?? 0;
    final controller = TextEditingController(text: moneyWhole(suggested));
    var picked = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Collect (You Got)'),
              // v1.0.8: mini calendar in the top-right corner — pick any
              // received date (past or future) to drive on-time/late.
              IconButton(
                tooltip: 'Received date',
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: picked,
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2100),
                    helpText: 'Received date (past or future)',
                  );
                  if (d != null) {
                    setDlg(() =>
                        picked = DateTime(d.year, d.month, d.day));
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
              Text('Against: ${loan['customer_name']} · '
                  'balance ₹${moneyWhole(loan['outstanding'] as num?)}'),
              const SizedBox(height: 12),
              TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: fieldDecoration('Amount')),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: picked,
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2100),
                    helpText: 'Received date (past or future)',
                  );
                  if (d != null) {
                    setDlg(() =>
                        picked = DateTime(d.year, d.month, d.day));
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event, size: 16, color: kGoldDark),
                    const SizedBox(width: 6),
                    Text(
                      'Received on ${fmtDate(picked)}'
                      '${picked.toIso8601String().substring(0, 10) == todayIso() ? ' (today)' : ''}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: kGoldDark),
                    ),
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
    if (ok != true) return;
    final value = Num.money(parseMoney(controller.text));
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
        'collection_date': picked.toIso8601String().substring(0, 10),
        'amount': value,
        'payment_mode': 'Cash',
        'is_irregular': 1,
      },
    );
    // Reflect locally without queueing a second push (pull confirms).
    await _syncLoan(loan);
    await state.logEvent('khata', 'collect', 'Collected — $_name',
        amount: value,
        village: loan['village']?.toString(),
        ref: loan['server_name']?.toString());
    if (mounted) _refresh();
  }

  /// Reconciles a loan's saved columns from its actual transactions:
  /// total_collected = sum of its collections, outstanding = payable − paid.
  Future<void> _syncLoan(Map<String, Object?> loan) async {
    final db = context.read<AppState>().db;
    final ref = (loan['server_name'] as String?) ?? loan['client_uuid'];
    final colls = await db.query('khatabook_collections',
        where: 'khatabook_loan = ?', whereArgs: [ref]);
    final collected = Num.money(
        colls.fold<double>(0, (s, c) => s + Num.toDouble(c['amount'])));
    final payable = Num.toDouble(loan['total_payable']);
    final out = Num.money(payable - collected);
    await db.upsert('khatabook_loans', {
      ...loan,
      'total_collected': collected,
      'outstanding': out < 0 ? 0 : out,
      'status': out <= 0 ? 'Closed' : 'Active',
      'dirty': 0,
    });
  }

  Map<String, Object?>? _loanForRef(Object? ref) {
    if (ref == null) return null;
    for (final l in _loans) {
      if (l['server_name'] == ref || l['client_uuid'] == ref) return l;
    }
    return null;
  }

  /// You Gave: with an active loan this adds an amount (principal / late fee /
/// interest) chosen by the shopkeeper, with a note explaining why. Without an
/// active loan it opens the loan form (each person gets one loan).
  Future<void> _youGave() async {
    if (_activeLoans.isEmpty) {
      await _addLoan();
      return;
    }
    final loan = _activeLoans.first;
    final amountCtl = TextEditingController();
    final interestCtl = TextEditingController();
    final noteCtl = TextEditingController();
    String type = 'late_fee';
    var givenOn = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('You Gave'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_youGaveHint(loan, type),
                  style:
                      TextStyle(fontSize: 12, color: kInk.withValues(alpha: .7))),
              const SizedBox(height: 12),
              TextField(
                  controller: amountCtl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: fieldDecoration('Amount')),
              const SizedBox(height: 10),
              // v1.0.8: back-datable "given on" date.
              GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: givenOn,
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2100),
                    helpText: 'Date the amount was given',
                  );
                  if (d != null) {
                    setDlg(() =>
                        givenOn = DateTime(d.year, d.month, d.day));
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event, size: 16, color: kGoldDark),
                    const SizedBox(width: 6),
                    Text('Given on ${fmtDate(givenOn)}',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: kGoldDark)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text('Type',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: kInk)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (value, label) in const [
                    ('principal', 'Principal'),
                    ('late_fee', 'Late fee'),
                    ('interest', 'Interest'),
                    ('other', 'Other'),
                    ('refinance', 'Refinance'),
                  ])
                    ChoiceChip(
                      label: Text(label,
                          style: const TextStyle(fontSize: 12.5)),
                      selected: type == value,
                      selectedColor: kGold.withValues(alpha: .25),
                      onSelected: (_) => setDlg(() => type = value),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (type == 'refinance') ...[
                TextField(
                    controller: interestCtl,
                    keyboardType: TextInputType.number,
                    decoration: fieldDecoration('New interest')),
                const SizedBox(height: 8),
              ],
              TextField(
                  controller: noteCtl,
                  decoration: fieldDecoration(type == 'refinance'
                      ? 'Note (reason)'
                      : 'Note (e.g. Late fee)')),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (type == 'refinance') {
      await _refinanceLoan(loan, amountCtl, interestCtl, noteCtl);
      return;
    }
    final amount = Num.money(parseMoney(amountCtl.text));
    if (amount <= 0) return;
    final state = context.read<AppState>();
    await state.saveEntity(
      table: 'khatabook_given',
      doctype: 'Khatabook Given',
      uuid: newUuid(),
      data: {
        'customer': loan['customer_name'],
        'customer_name': loan['customer_name'],
        'village': loan['village'],
        'khatabook_loan': loan['server_name'] ?? loan['client_uuid'],
        'given_date': givenOn.toIso8601String().substring(0, 10),
        'amount': amount,
        'given_type': type,
        'note': noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
      },
    );
    // A principal "You Gave" is fresh cash handed over; a late-fee / interest
    // one adds to what they owe. Both raise the amount to recover.
    final updated = Map<String, Object?>.from(loan);
    updated['total_payable'] = Num.money(Num.toDouble(loan['total_payable']) + amount);
    if (type == 'principal') {
      updated['principal_amount'] =
          Num.money(Num.toDouble(loan['principal_amount']) + amount);
    }
    await _syncLoan(updated);
    await state.logEvent('khata', 'given', 'You Gave — $_name ($type)',
        amount: amount,
        village: loan['village']?.toString(),
        ref: loan['server_name']?.toString());
    if (mounted) _refresh();
  }

  /// Refinance: rolls the outstanding balance into a fresh principal, adds any
  /// fresh cash + new interest, restarts the schedule from today. Previous
  /// installments stay visible in the payment schedule (on-time / partial).
  Future<void> _refinanceLoan(
      Map<String, Object?> loan,
      TextEditingController amountCtl,
      TextEditingController interestCtl,
      TextEditingController noteCtl) async {
    final state = context.read<AppState>();
    final fresh = Num.money(parseMoney(amountCtl.text));
    final interest = Num.money(parseMoney(interestCtl.text));
    final note = noteCtl.text.trim();
    if (fresh <= 0 && interest <= 0) {
      _toast('Enter a refinance amount or new interest.');
      return;
    }
    final db = state.db;
    final ref = (loan['server_name'] as String?) ?? loan['client_uuid'];
    final oldOut = Num.toDouble(loan['outstanding']);
    final newPrincipal = Num.money(oldOut + fresh);
    final newTotal = Num.money(newPrincipal + interest);
    final count = (loan['installment_count'] as num?)?.toInt() ?? 12;
    final f = (loan['collection_frequency']?.toString() ?? '').toLowerCase();
    final step = f.contains('bi') ? 14 : f.contains('month') ? 30 : 7;
    final today = DateTime.now();
    final updated = Map<String, Object?>.from(loan)
      ..['principal_amount'] = newPrincipal
      ..['interest_amount'] = interest
      ..['total_payable'] = newTotal
      ..['installment_amount'] = Num.money(newTotal / count)
      ..['start_date'] = today.toIso8601String()
      ..['end_date'] = today.add(Duration(days: step * count)).toIso8601String()
      ..['paid_installments'] = 0
      ..['updated_at'] = today.toIso8601String()
      ..['dirty'] = 1;
    await db.upsert('khatabook_loans', updated);
    // Ledger marker row (gold "Refinance" tile).
    await db.upsert('khatabook_given', {
      'client_uuid': newUuid(),
      'server_name': null,
      'dirty': 1,
      'customer': loan['customer'],
      'customer_name': _name,
      'village': loan['village'],
      'khatabook_loan': ref,
      'given_date': today.toIso8601String(),
      'amount': fresh,
      'given_type': 'refinance',
      'note': note.isEmpty ? null : note,
      'updated_at': today.toIso8601String(),
    });
    // Refinance record — the schedule builder uses it to keep the previous
    // period's instalment rows (on-time / partial / no payment).
    await db.upsert('khatabook_refinances', {
      'client_uuid': newUuid(),
      'server_name': null,
      'dirty': 1,
      'khatabook_loan': ref,
      'customer': loan['customer'],
      'refinance_date': today.toIso8601String(),
      'old_outstanding': oldOut,
      'new_principal': newPrincipal,
      'new_interest_amount': interest,
      'new_installment_count': count,
      'new_interest_note': note,
      'new_loan': null,
      'remarks': note,
      'updated_at': today.toIso8601String(),
    });
    await _syncLoan(updated);
    await state.logEvent('khata', 'refinance', 'Refinance — $_name',
        amount: fresh + interest,
        village: loan['village']?.toString(),
        ref: ref?.toString());
    if (mounted) _refresh();
  }

  String _youGaveHint(Map<String, Object?> loan, String type) {
    switch (type) {
      case 'principal':
        return 'Fresh cash given — this becomes part of the principal.';
      case 'interest':
        return 'Interest added on top of the balance.';
      case 'other':
        return 'Any other amount — shows the note, no type word.';
      case 'refinance':
        return 'Rolls the outstanding into a fresh loan: new principal = '
            'outstanding + amount, plus new interest. Schedule restarts.';
      default:
        return 'Late fee / penalty — adds to the balance. '
            'Balance ₹${moneyWhole(Num.toDouble(loan['outstanding']))}';
    }
  }

  Future<void> _addLoan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KhatabookLoanForm(
          initialCustomerUuid: _customer['client_uuid'] as String?,
          initialCustomerName: _name,
          initialVillage: _customer['village']?.toString(),
        ),
      ),
    );
    if (mounted) _refresh();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------- row editing
  /// Tapping a ledger tile: loans open the "You Gave" detail sheet,
  /// collections / You-Gave rows open an edit dialog to fix a wrong amount.
  Future<void> _editRow(_LedgerRow r) async {
    if (r.kind == 'loan') {
      await _editLoan(r.source);
      return;
    }
    if (r.kind == 'collection') {
      await _editCollection(r.source);
    } else {
      await _editGiven(r.source);
    }
  }

  Future<void> _editLoan(Map<String, Object?> loan) async {
    final pCtl =
        TextEditingController(text: moneyWhole(Num.toDouble(loan['principal_amount'])));
    final iCtl =
        TextEditingController(text: moneyWhole(Num.toDouble(loan['interest_amount'])));
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit loan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
                controller: pCtl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: fieldDecoration('Principal')),
            const SizedBox(height: 10),
            TextField(
                controller: iCtl,
                keyboardType: TextInputType.number,
                decoration: fieldDecoration('Interest')),
            const SizedBox(height: 8),
            Text(
                'Total: '
                '₹${moneyWhole(Num.toDouble(parseMoney(pCtl.text)) + Num.toDouble(parseMoney(iCtl.text)))}',
                style: TextStyle(
                    fontSize: 12, color: kInk.withValues(alpha: .6))),
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
    final np = Num.money(parseMoney(pCtl.text));
    final ni = Num.money(parseMoney(iCtl.text));
    if (np <= 0 || ni < 0) return;
    // Keep the fee/You-Gave part of total_payable intact, replace P + I.
    final fees = Num.toDouble(loan['total_payable']) -
        Num.toDouble(loan['principal_amount']) -
        Num.toDouble(loan['interest_amount']);
    final updated = Map<String, Object?>.from(loan)
      ..['principal_amount'] = np
      ..['interest_amount'] = ni
      ..['total_payable'] = Num.money(np + ni + fees);
    await state.db.upsert('khatabook_loans', {
      ...updated,
      'dirty': 0,
    });
    await _syncLoan(updated);
    await state.logEvent('khata', 'loan_edit', 'Loan edited — $_name',
        amount: Num.toDouble(updated['total_payable']),
        village: _customer['village']?.toString(),
        ref: updated['server_name']?.toString());
    if (mounted) _refresh();
  }

  Future<void> _editCollection(Map<String, Object?> c) async {
    final controller =
        TextEditingController(text: moneyWhole(Num.toDouble(c['amount'])));
    final state = context.read<AppState>();
    var picked = parseIso(c['collection_date']) ?? DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Edit collection'),
              IconButton(
                tooltip: 'Received date',
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: picked,
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2100),
                    helpText: 'Received date (past or future)',
                  );
                  if (d != null) {
                    setDlg(() =>
                        picked = DateTime(d.year, d.month, d.day));
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
                  decoration: fieldDecoration('Amount received')),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: picked,
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2100),
                    helpText: 'Received date (past or future)',
                  );
                  if (d != null) {
                    setDlg(() =>
                        picked = DateTime(d.year, d.month, d.day));
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event, size: 16, color: kGoldDark),
                    const SizedBox(width: 6),
                    Text('Received on ${fmtDate(picked)}',
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
    if (ok != true) return;
    final amount = Num.money(parseMoney(controller.text));
    if (amount <= 0) return;
    await state.db.upsert('khatabook_collections', {
      ...c,
      'amount': amount,
      'collection_date': picked.toIso8601String().substring(0, 10),
      'dirty': 1,
    });
    final loan = _loanForRef(c['khatabook_loan']);
    if (loan != null) await _syncLoan(loan);
    await state.logEvent('khata', 'collect_edit', 'Collection edited — $_name',
        amount: amount,
        village: _customer['village']?.toString(),
        ref: loan?['server_name']?.toString());
    if (mounted) _refresh();
  }

  Future<void> _editGiven(Map<String, Object?> g) async {
    final amountCtl =
        TextEditingController(text: moneyWhole(Num.toDouble(g['amount'])));
    final noteCtl =
        TextEditingController(text: (g['note']?.toString() ?? '').trim());
    String type = (g['given_type']?.toString() ?? 'late_fee');
    final state = context.read<AppState>();
    // v1.0.8 fix: the refinance edit dialog was missing its Interest box.
    // Find the matching refinance record so it opens pre-filled.
    Map<String, Object?>? refi;
    for (final r in _refinances) {
      if (r['khatabook_loan'] == g['khatabook_loan'] &&
          r['refinance_date'] == g['given_date']) {
        refi = r;
        break;
      }
    }
    final interestCtl = TextEditingController(
        text: moneyWhole(Num.toDouble(refi?['new_interest_amount'])));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Edit You Gave'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                  controller: amountCtl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: fieldDecoration('Amount')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (value, label) in const [
                    ('principal', 'Principal'),
                    ('late_fee', 'Late fee'),
                    ('interest', 'Interest'),
                    ('other', 'Other'),
                    ('refinance', 'Refinance'),
                  ])
                    ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12.5)),
                      selected: type == value,
                      selectedColor: kGold.withValues(alpha: .25),
                      onSelected: (_) => setDlg(() => type = value),
                    ),
                ],
              ),
              if (type == 'refinance') ...[
                const SizedBox(height: 8),
                TextField(
                    controller: interestCtl,
                    keyboardType: TextInputType.number,
                    decoration: fieldDecoration('New interest')),
              ],
              const SizedBox(height: 8),
              TextField(
                  controller: noteCtl,
                  decoration: fieldDecoration('Note (why you gave)')),
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
    final amount = Num.money(parseMoney(amountCtl.text));
    final interest = Num.money(parseMoney(interestCtl.text));
    if (amount <= 0 && !(type == 'refinance' && interest > 0)) return;
    final loan = _loanForRef(g['khatabook_loan']);
    final old = Num.toDouble(g['amount']);
    final oldType = g['given_type']?.toString() ?? 'late_fee';
    if (loan != null) {
      var updated = Map<String, Object?>.from(loan);
      if (type == 'refinance') {
        // Refinance rows store fresh cash in `amount` and the new interest in
        // the refinance record — correct both together.
        updated['principal_amount'] = Num.money(
            Num.toDouble(updated['principal_amount']) + (amount - old));
        updated['interest_amount'] = interest;
        updated['total_payable'] = Num.money(
            Num.toDouble(updated['principal_amount']) + interest);
        final count = (updated['installment_count'] as num?)?.toInt() ?? 12;
        updated['installment_amount'] =
            Num.money(Num.toDouble(updated['total_payable']) / count);
        await _syncLoan(updated);
        if (refi != null) {
          await state.db.upsert('khatabook_refinances', {
            ...refi,
            'new_principal': updated['principal_amount'],
            'new_interest_amount': interest,
            'dirty': 1,
          });
        }
      } else {
        // Undo the old effect, then apply the corrected one.
        updated['total_payable'] =
            Num.money(Num.toDouble(updated['total_payable']) - old);
        if (oldType == 'principal') {
          updated['principal_amount'] = Num.money(
              Num.toDouble(updated['principal_amount']) - old);
        }
        updated['total_payable'] =
            Num.money(Num.toDouble(updated['total_payable']) + amount);
        if (type == 'principal') {
          updated['principal_amount'] = Num.money(
              Num.toDouble(updated['principal_amount']) + amount);
        }
        await _syncLoan(updated);
      }
    }
    await state.db.upsert('khatabook_given', {
      ...g,
      'amount': amount,
      'given_type': type,
      'note': noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
      'dirty': 1,
    });
    await state.logEvent('khata', 'given_edit', 'You Gave edited — $_name',
        amount: amount,
        village: _customer['village']?.toString(),
        ref: loan?['server_name']?.toString());
    if (mounted) _refresh();
  }

  String _givenTypeLabel(String? type) {
    switch (type ?? 'late_fee') {
      case 'principal':
        return 'Principal';
      case 'interest':
        return 'Interest';
      case 'other':
        return ''; // Other: no type word in the ledger, note only.
      case 'refinance':
        return 'Refinance';
      default:
        return 'Late fee';
    }
  }

  // ---------------------------------------------------------------- reminder
  Widget _reminderChip() {
    final reminder = _customer['reminder_date']?.toString() ?? '';
    final label =
        reminder.isEmpty ? 'Remind: not set' : 'Remind ${fmtReminder(reminder)}';
    return GestureDetector(
      onTap: _setReminder,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: kGold.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_outlined,
                size: 14, color: kGoldDark),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: kGoldDark)),
          ],
        ),
      ),
    );
  }

  /// Today / Next week / Next month / Calendar. Defaults from the active
  /// loan's collection frequency; the shopkeeper can always change it.
  Future<void> _setReminder() async {
    final freq = _activeLoans.isEmpty
        ? ''
        : (_activeLoans.first['collection_frequency']?.toString() ?? '');
    final now = DateTime.now();
    final f = freq.toLowerCase();
    var selection = 'next_week';
    var picked = now.add(const Duration(days: 7));
    if (f.contains('month')) {
      selection = 'next_month';
      picked = DateTime(now.year, now.month + 1, now.day);
    } else if (f.contains('daily')) {
      selection = 'today';
      picked = now;
    }
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Collection reminder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Remind to collect on:',
                  style: TextStyle(
                      fontSize: 12.5, color: kInk.withValues(alpha: .7))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (value, label) in const [
                    ('today', 'Today'),
                    ('next_week', 'Next week'),
                    ('next_month', 'Next month'),
                    ('calendar', 'Calendar…'),
                  ])
                    ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12.5)),
                      selected: selection == value,
                      selectedColor: kGold.withValues(alpha: .25),
                      onSelected: (_) async {
                        if (value == 'calendar') {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: picked,
                            firstDate: now,
                            lastDate: DateTime(now.year + 2, 12, 31),
                          );
                          if (d != null) {
                            picked = d;
                            setDlg(() => selection = 'calendar');
                          }
                          return;
                        }
                        setDlg(() {
                          selection = value;
                          if (value == 'today') picked = now;
                          if (value == 'next_week') {
                            picked = now.add(const Duration(days: 7));
                          }
                          if (value == 'next_month') {
                            picked = DateTime(now.year, now.month + 1, now.day);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                icon: const Icon(Icons.calendar_month, size: 18),
                label: const Text('Pick date'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: picked,
                    firstDate: now,
                    lastDate: DateTime(now.year + 2, 12, 31),
                  );
                  if (d != null) {
                    picked = d;
                    setDlg(() => selection = 'calendar');
                  }
                },
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: kGold.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('Remind ${fmtReminder(_dateOnly(picked))}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kGoldDark)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, _dateOnly(picked)),
                child: const Text('Set reminder')),
          ],
        ),
      ),
    );
    if (saved == null) return;
    final state = context.read<AppState>();
    await state.saveEntity(
      table: 'customers',
      doctype: 'Pawn Customer',
      uuid: (_customer['client_uuid'] as String?) ?? newUuid(),
      data: {..._customer, 'reminder_date': saved},
    );
    if (mounted) _refresh();
  }

  String _dateOnly(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$dd';
  }

  // ------------------------------------------------------------------ sheets
  void _openSheet(Widget child) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => child,
    );
  }

  /// Full-screen avatar — tap to expand (social-media style, pinch to zoom).
  void _expandPhoto() {
    final photo = _customer['photo_path'] as String?;
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
                  child: (photo != null && photo.isNotEmpty)
                      ? Image.file(File(photo))
                      : Container(
                          width: 160,
                          height: 160,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: kGold.withValues(alpha: .2),
                            shape: BoxShape.circle,
                          ),
                          child: Text(_name.characters.first.toUpperCase(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Customer'),
        actions: [
          IconButton(
            tooltip: 'Call',
            icon: const Icon(Icons.phone_outlined),
            onPressed: _call,
          ),
          IconButton(
            tooltip: 'SMS',
            icon: const Icon(Icons.sms_outlined),
            onPressed: _sms,
          ),
          IconButton(
            tooltip: 'WhatsApp',
            icon: Image.asset('assets/whatsapp.png',
                width: 20, height: 20, fit: BoxFit.contain),
            onPressed: _whatsapp,
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CustomerForm(existing: _customer)),
              );
              if (mounted) _refresh();
            },
          ),
        ],
      ),
      // Sticky bottom bar: You Gave / Collect are always visible.
      bottomNavigationBar: _loading
          ? null
          : Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SafeArea(
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _youGave,
                      icon: const Icon(Icons.north_east, size: 18),
                      label: const Text('You Gave'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        foregroundColor: kRed,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _collect,
                      icon: const Icon(Icons.south_west, size: 18),
                      label: const Text('Collect'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: kGold,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : Stack(
              children: [
                RefreshIndicator(
                  color: kGold,
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
                    children: [
                      _headerCard(),
                      const SizedBox(height: 12),
                      _outstandingCard(),
                      const SizedBox(height: 12),
                      _ledgerCard(),
                      const SizedBox(height: 14),
                      _tile(Icons.calendar_month_outlined,
                          'Payment schedule',
                          _scheduleSummary(),
                          () => _openSheet(_scheduleSheet())),
                      const SizedBox(height: 20),
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

  // ------------------------------------------------------------------- widgets
  Widget _headerCard() {
    final photo = _customer['photo_path'] as String?;
    final hasPhoto = photo != null && photo.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _expandPhoto,
            child: CircleAvatar(
              radius: 30,
              backgroundColor: kGold.withValues(alpha: .16),
              foregroundImage: hasPhoto ? FileImage(File(photo)) : null,
              child: hasPhoto
                  ? null
                  : Text(_name.characters.first.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: kGoldDark)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(_name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: kInk)),
                    ),
                    if ((_customer['customer_id']?.toString() ?? '')
                        .isNotEmpty) ...[
                      const SizedBox(width: 8),
                      // v1.0.8: khata customer ID (order-wise A-01…).
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: .22),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: kGold.withValues(alpha: .5)),
                        ),
                        child: Text(
                          _customer['customer_id'].toString(),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: kGoldDark),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _phone.isEmpty ? 'No phone saved' : _phone,
                  style: TextStyle(
                      fontSize: 12.5, color: kInk.withValues(alpha: .6)),
                ),
                const SizedBox(height: 5),
                Row(children: [
                  _ratingTag(_customer['rating']?.toString() ?? 'New'),
                  const SizedBox(width: 6),
                  Flexible(child: _reminderChip()),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingTag(String rating) {
    final Color fg = rating.toLowerCase() == 'good'
        ? kGreen
        : rating.toLowerCase() == 'bad'
            ? kRed
            : kGoldDark;
    final Color bg = rating.toLowerCase() == 'good'
        ? kGreenSoft
        : rating.toLowerCase() == 'bad'
            ? kRedSoft
            : kGold.withValues(alpha: .18);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text('Rating: $rating',
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _outstandingCard() {
    // Three sections: invested Principal | full TOTAL PAYABLE (principal +
    // interest + late fee + other "You Gave" amounts) | Outstanding still to
    // collect. Paid-of-total line below, no extra wording.
    return Container(
      padding: const EdgeInsets.all(18),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PRINCIPAL',
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: .8,
                            color: Color(0xFFE7D48B))),
                    const SizedBox(height: 4),
                    Text('₹${moneyWhole(_principal)}',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TOTAL PAYABLE',
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: .8,
                            color: Color(0xFFE7D48B))),
                    const SizedBox(height: 4),
                    Text('₹${moneyWhole(_total)}',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('OUTSTANDING',
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: .8,
                            color: Color(0xFFE7D48B))),
                    const SizedBox(height: 4),
                    Text('₹${moneyWhole(_outstanding)}',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Paid ₹${moneyWhole(_paid)} of ₹${moneyWhole(_total)}',
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: .85))),
        ],
      ),
    );
  }

  // --------------------------------------------------- SBI-style ledger
  Widget _ledgerCard() {
    final rows = _ledgerRows();
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ledgerHeader(),
            const SizedBox(height: 12),
            Center(
              child: Text('No transactions yet. Tap "You Gave" to start a loan.',
                  style: TextStyle(
                      fontSize: 12.5, color: kInk.withValues(alpha: .6))),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ledgerHeader(),
          const SizedBox(height: 6),
          for (final r in rows) _ledgerRow(r),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _ledgerHeader() {
    return const Row(
      children: [
        Expanded(child: SizedBox()),
        SizedBox(
          width: 94,
          child: Text('YOU GAVE',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: kRed)),
        ),
        SizedBox(
          width: 94,
          child: Text('YOU GOT',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: kGreen)),
        ),
      ],
    );
  }

  /// Chronologically-sorted ledger rows with running balance (newest last in
  /// this list; displayed reversed). Balance == amount to recover
  /// (outstanding): a loan debits principal + interest, "You Gave" fees debit
  /// their amount, collections credit their amount.
  List<_LedgerRow> _ledgerRows() {
    final entries = <({
      DateTime when,
      String stamp,
      double gave,
      double got,
      double delta,
      bool isGave,
      String kind,
      Map<String, Object?> source,
    })>[];

    // Loans: red "You Gave" shows the FULL amount to recover handed over
    // (principal + interest); the running balance jumps by the same total.
    for (final l in _loans) {
      final raw = l['loan_date']?.toString() ?? l['updated_at']?.toString();
      final when = parseIso(raw) ?? DateTime.now();
      final principal = Num.toDouble(l['principal_amount']);
      final interest = Num.toDouble(l['interest_amount']);
      entries.add((
        when: when,
        stamp: fmtDateTime(raw),
        gave: Num.money(principal + interest),
        got: 0,
        delta: principal + interest,
        isGave: true,
        kind: 'loan',
        source: l,
      ));
    }

    // "You Gave" fee / late-interest additions: red, add their amount only.
    // The stamp is the GIVEN date (v1.0.8 back-datable picker).
    for (final g in _given) {
      final graw = g['given_date']?.toString() ?? g['updated_at']?.toString();
      final amount = Num.toDouble(g['amount']);
      entries.add((
        when: parseIso(graw) ?? DateTime.now(),
        stamp: fmtDateTime(graw),
        gave: amount,
        got: 0,
        delta: amount,
        isGave: true,
        kind: 'given',
        source: g,
      ));
    }

    // Collections: green, subtract their amount. The stamp is the RECEIVED
    // date (v1.0.8 date picker), so back-dated payments sit truthfully.
    for (final c in _collections) {
      final raw = c['collection_date']?.toString() ?? c['updated_at']?.toString();
      entries.add((
        when: parseIso(raw) ?? DateTime.now(),
        stamp: fmtDateTime(raw),
        gave: 0,
        got: Num.toDouble(c['amount']),
        delta: -Num.toDouble(c['amount']),
        isGave: false,
        kind: 'collection',
        source: c,
      ));
    }

    entries.sort((a, b) => a.when.compareTo(b.when));

    // Running balance: what the customer owes at that point.
    final rows = <_LedgerRow>[];
    double balance = 0;
    for (final e in entries) {
      balance += e.delta;
      if (balance < 0) balance = 0;
      rows.add(_LedgerRow(
        stamp: e.stamp,
        gave: e.gave,
        got: e.got,
        balance: Num.money(balance),
        isGave: e.isGave,
        kind: e.kind,
        source: e.source,
      ));
    }
    // Show newest first.
    return rows.reversed.toList();
  }

  Widget _ledgerRow(_LedgerRow r) {
    final isGave = r.isGave;
    final isRefinance = r.kind == 'given' &&
        r.source['given_type']?.toString() == 'refinance';
    final color = isGave ? kRed : kGreen;
    // You-Gave rows show why: "Late fee — Hello". The note always shows;
    // for type "Other" only the note is shown (no type word).
    String? note;
    if (r.kind == 'given') {
      final typeLabel = _givenTypeLabel(r.source['given_type']?.toString());
      final noteText = (r.source['note']?.toString() ?? '').trim();
      note = typeLabel.isEmpty
          ? (noteText.isEmpty ? null : noteText)
          : noteText.isEmpty
              ? typeLabel
              : '$typeLabel — $noteText';
    }
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      // v1.0.8: refinance is a full gold rectangle tile for fast spotting —
      // identical in shape to the payment-schedule refinance rectangle.
      decoration: isRefinance
          ? BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3A2E0E), Color(0xFF6B5417)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            )
          : BoxDecoration(
              color: color.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: color.withValues(alpha: .18), width: 1),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (isRefinance) ...[
                      const Icon(Icons.change_history,
                          size: 15, color: Colors.white),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(r.stamp,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isRefinance
                                  ? Colors.white.withValues(alpha: .9)
                                  : kInk.withValues(alpha: .7))),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 94,
                child: Text(
                  isGave ? '₹${moneyWhole(r.gave)}' : '',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: isRefinance ? 15.5 : 15,
                      fontWeight: FontWeight.w800,
                      color: isRefinance
                          ? Colors.white
                          : isGave
                              ? color
                              : Colors.transparent),
                ),
              ),
              SizedBox(
                width: 94,
                child: Text(
                  !isGave ? '₹${moneyWhole(r.got)}' : '',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isGave ? Colors.transparent : color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          // Daily outstanding balance — money lent out, always red, left.
          Text('bal ₹${moneyWhole(r.balance)}',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isRefinance
                      ? const Color(0xFFFFE082)
                      : kRed)),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(note,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: isRefinance
                          ? Colors.white.withValues(alpha: .85)
                          : color.withValues(alpha: .85))),
            ),
        ],
      ),
    );
    // v1.0.8 drag-to-delete: long-press lifts the tile; dropping it on the
    // bottom bin removes the entry (no confirm for ledger rows). A long-press
    // alone never deletes.
    return DragToDeleteTile(
      onDragChanged: (v) => setState(() => _dragActive = v),
      payload: DeletePayload(
        drop: () async {
          await _deleteLedgerRow(r);
          return true;
        },
      ),
      child: GestureDetector(
        onTap: () => _editRow(r),
        child: tile,
      ),
    );
  }

  /// Removes a ledger row (no confirmation). Loan rows delete their
  /// collections / givens / refinances too; balances are reconciled after.
  Future<void> _deleteLedgerRow(_LedgerRow r) async {
    final state = context.read<AppState>();
    final db = state.db;
    try {
      if (r.kind == 'given') {
        final loan = _loanForRef(r.source['khatabook_loan']);
        if (loan != null) {
          final old = Num.toDouble(r.source['amount']);
          final oldType = r.source['given_type']?.toString() ?? 'late_fee';
          final upd = Map<String, Object?>.from(loan);
          if (oldType == 'refinance') {
            // Roll the fresh cash back out of the principal and rebuild
            // total_payable so the loan stays consistent.
            upd['principal_amount'] = Num.money(
                Num.toDouble(upd['principal_amount']) - old);
            upd['total_payable'] = Num.money(Num.toDouble(upd['principal_amount']) +
                Num.toDouble(upd['interest_amount']));
          } else {
            upd['total_payable'] =
                Num.money(Num.toDouble(upd['total_payable']) - old);
            if (oldType == 'principal') {
              upd['principal_amount'] =
                  Num.money(Num.toDouble(upd['principal_amount']) - old);
            }
          }
          await _syncLoan(upd);
        }
        await db.delete('khatabook_given',
            where: 'client_uuid = ?', whereArgs: [r.source['client_uuid']]);
        if (r.source['given_type']?.toString() == 'refinance') {
          await db.delete('khatabook_refinances',
              where: 'khatabook_loan = ? AND refinance_date = ?',
              whereArgs: [
                r.source['khatabook_loan'],
                r.source['given_date']
              ]);
        }
        await state.logEvent('khata', 'given_delete',
            'Given removed — $_name',
            amount: Num.toDouble(r.source['amount']),
            village: _customer['village']?.toString());
      } else if (r.kind == 'collection') {
        final loan = _loanForRef(r.source['khatabook_loan']);
        await db.delete('khatabook_collections',
            where: 'client_uuid = ?', whereArgs: [r.source['client_uuid']]);
        if (loan != null) await _syncLoan(loan);
        await state.logEvent('khata', 'collect_delete',
            'Collection removed — $_name',
            amount: Num.toDouble(r.source['amount']),
            village: _customer['village']?.toString());
      } else if (r.kind == 'loan') {
        final ref =
            (r.source['server_name'] as String?) ?? r.source['client_uuid'];
        await db.delete('khatabook_given',
            where: 'khatabook_loan = ?', whereArgs: [ref]);
        await db.delete('khatabook_collections',
            where: 'khatabook_loan = ?', whereArgs: [ref]);
        await db.delete('khatabook_refinances',
            where: 'khatabook_loan = ?', whereArgs: [ref]);
        await db.delete('khatabook_loans',
            where: 'client_uuid = ?', whereArgs: [r.source['client_uuid']]);
        await state.logEvent('khata', 'loan_delete', 'Loan deleted — $_name',
            amount: Num.toDouble(r.source['total_payable']),
            village: _customer['village']?.toString());
      }
    } catch (error) {
      debugPrint('delete ledger row failed: $error');
    }
    if (mounted) _refresh();
  }

  Widget _tile(
      IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: kGoldDark),
          title: Text(title,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: kInk)),
          subtitle: Text(subtitle,
              style: TextStyle(fontSize: 11, color: kInk.withValues(alpha: .55))),
          trailing: const Icon(Icons.chevron_right, color: kInk),
          onTap: onTap,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ sheets
  Widget _sheetHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
    );
  }

  String _scheduleSummary() {
    if (_activeLoans.isEmpty) return 'No active loans';
    final l = _activeLoans.first;
    final p = moneyWhole(Num.toDouble(l['principal_amount']));
    final i = moneyWhole(Num.toDouble(l['interest_amount']));
    final t = moneyWhole(Num.toDouble(l['total_payable']));
    return 'Principal ₹$p · Interest ₹$i · Total ₹$t';
  }

  Widget _scheduleSheet() {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          _sheetHeader('Payment schedule — $_name'),
          if (_activeLoans.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24), child: Text('No active loans.')),
          for (final l in _activeLoans) _scheduleLoanCard(l),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Principal / Interest / Outstanding strip + per-installment rows with
  /// scheduled date, actual paid date, paid-late wording and on-time count.
  Widget _scheduleLoanCard(Map<String, Object?> loan) {
    final p = moneyWhole(Num.toDouble(loan['principal_amount']));
    final i = moneyWhole(Num.toDouble(loan['interest_amount']));
    final out = moneyWhole(Num.toDouble(loan['outstanding']));
    var rows = _instalmentsFor(loan);
    // Interest-only loans (no fixed installment count): a single next-due row
    // instead of all 12/6 settlement tiles.
    final effCount = (loan['installment_count'] as num?)?.toInt() ?? 0;
    if (rows.isEmpty && effCount <= 0) {
      final nd = loanNextDue(loan, DateTime.now());
      if (nd != null) {
        rows = [
          _SchedRow(
            due: _dayD(nd),
            paid: null,
            amount: Num.toDouble(loan['installment_amount']) > 0
                ? Num.toDouble(loan['installment_amount'])
                : Num.toDouble(loan['interest_amount']),
            lateDays: 0,
            index: 0,
            refinance: false,
          ),
        ];
      }
    }
    final paidCount = rows.where((r) => r.paid != null).length;
    final onTime = rows.where((r) => r.paid != null && r.lateDays <= 0).length;
    // v1.0.8: label the settlement tiles by the chosen frequency — a monthly
    // loan shows "Month 1/12", biweekly "Fortnight 1/12", weekly "Week 1/12".
    final f = (loan['collection_frequency']?.toString() ?? '').toLowerCase();
    final unit =
        f.contains('month') ? 'Month' : f.contains('bi') ? 'Fortnight' : 'Week';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              Expanded(child: _schedStat('PRINCIPAL', '₹$p')),
              Expanded(child: _schedStat('INTEREST', '₹$i')),
              Expanded(
                  child: _schedStat('OUTSTANDING', '₹$out', end: true)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Text('Settlements — ${loan['collection_frequency']}',
                  style: TextStyle(
                      fontSize: 12, color: kInk.withValues(alpha: .6))),
              const Spacer(),
              if (paidCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: onTime == paidCount
                        ? kGreenSoft
                        : const Color(0xFFFDEBD2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                      'ON-TIME $onTime/$paidCount',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: onTime == paidCount
                              ? kGreen
                              : const Color(0xFFB26A00))),
                ),
            ],
          ),
        ),
        for (final r in rows) _schedTile(r, rows.length, unit),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _schedStat(String label, String value, {bool end = false}) {
    return Column(
      crossAxisAlignment:
          end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10, letterSpacing: .8, color: Color(0xFFE7D48B))),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
      ],
    );
  }

  /// Scheduled installments for a loan, split into periods by refinances:
  /// every previous period keeps its full set of week rows (marked by the
  /// collections that happened before the refinance date), then a gold
  /// REFINANCE divider, then a fresh period from each refinance date.
  List<_SchedRow> _instalmentsFor(Map<String, Object?> loan) {
    final today = _dayD(DateTime.now());
    final count = (loan['installment_count'] as num?)?.toInt() ?? 12;
    final f = (loan['collection_frequency']?.toString() ?? '').toLowerCase();
    final step = f.contains('bi')
        ? 14
        : f.contains('month')
            ? 30
            : 7;
    final start = parseIso(loan['start_date'] ?? loan['loan_date']);
    final ref = (loan['server_name'] as String?) ?? loan['client_uuid'];
    if (start == null || count <= 0) return const [];
    final colls = _collections
        .where((c) => c['khatabook_loan'] == ref)
        .toList()
      ..sort((a, b) => (parseIso(a['collection_date']) ?? today)
          .compareTo(parseIso(b['collection_date']) ?? today));
    final refis = _refinances
        .where((r) => r['khatabook_loan'] == ref)
        .toList()
      ..sort((a, b) => (parseIso(a['refinance_date']) ?? today)
          .compareTo(parseIso(b['refinance_date']) ?? today));
    final amount = Num.toDouble(loan['installment_amount']) > 0
        ? Num.toDouble(loan['installment_amount'])
        : Num.toDouble(loan['total_payable']) / count;
    final rows = <_SchedRow>[];
    var segmentStart = _dayD(start);
    var slot = 0;
    var collPtr = 0;
    for (final refi in refis) {
      final refiDay = _dayD(parseIso(refi['refinance_date']) ?? today);
      // Previous period — full `count` weeks, marked by pre-refinance
      // collections (on-time / partial shows the received share).
      for (var i = 0; i < count; i++) {
        final due = segmentStart.add(Duration(days: i * step));
        final inPeriod = collPtr < colls.length &&
            _dayD(parseIso(colls[collPtr]['collection_date']) ?? today)
                .isBefore(refiDay);
        final paid = inPeriod ? parseIso(colls[collPtr]['collection_date']) : null;
        final paidAmt =
            paid != null ? Num.toDouble(colls[collPtr]['amount']) : 0.0;
        final late = paid == null ? 0 : _dayD(paid).difference(due).inDays;
        rows.add(_SchedRow(
            due: due,
            paid: paid,
            paidAmount: paidAmt,
            amount: amount,
            lateDays: late,
            index: slot++,
            refinance: false));
        if (paid != null) collPtr++;
      }
      rows.add(_SchedRow(
          due: refiDay,
          paid: null,
          paidAmount: Num.toDouble(refi['new_interest_amount']),
          amount: Num.toDouble(refi['new_principal']),
          lateDays: 0,
          index: slot++,
          refinance: true,
          refinanceNote: refi['new_interest_note']?.toString()));
      segmentStart = refiDay;
    }
    // Current period — a fresh `count` installments from the latest start.
    for (var i = 0; i < count; i++) {
      final due = segmentStart.add(Duration(days: i * step));
      final paid =
          collPtr < colls.length ? parseIso(colls[collPtr]['collection_date']) : null;
      final paidAmt =
          paid != null ? Num.toDouble(colls[collPtr]['amount']) : 0.0;
      final late = paid == null ? 0 : _dayD(paid).difference(due).inDays;
      rows.add(_SchedRow(
          due: due,
          paid: paid,
          paidAmount: paidAmt,
          amount: amount,
          lateDays: late,
          index: slot++,
          refinance: false));
      if (paid != null) collPtr++;
    }
    return rows;
  }

  Widget _schedTile(_SchedRow r, int total, String unit) {
    if (r.refinance) return _refinanceTile(r);
    final today = _dayD(DateTime.now());
    // Share of the instalment actually received — drives the green/red split.
    final share =
        r.paid == null ? 0.0 : (r.paidAmount / r.amount).clamp(0.0, 1.0);
    final (Color bg, Color fg, String label) = r.paid != null
        ? (r.lateDays <= 0
            ? (share >= 0.999
                ? (kGreenSoft, kGreen, 'ON TIME')
                : (const Color(0xFFFDEBD2), const Color(0xFFB26A00), 'PARTIAL'))
            : (const Color(0xFFFDEBD2), const Color(0xFFB26A00),
                unit == 'Week'
                    ? weeksLateWording(r.lateDays).toUpperCase()
                    : '${r.lateDays} DAY${r.lateDays == 1 ? '' : 'S'} LATE'))
        : r.due.isAfter(today)
            ? (kBlueSoft, kBlue,
                r.due.difference(today).inDays <= 7 ? 'NEXT WEEK' : 'UPCOMING')
            : r.due == today
                ? (kGold.withValues(alpha: .18), kGoldDark, 'DUE TODAY')
                : (kRedSoft, kRed,
                    'DUE ${today.difference(r.due).inDays} '
                    'DAY${today.difference(r.due).inDays == 1 ? '' : 'S'} AGO');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$unit ${r.index + 1}/$total',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: kInk)),
                const SizedBox(height: 2),
                Text(
                    'Due ${fmtDate(r.due.toIso8601String())} | '
                    'Paid ${r.paid == null ? '—' : fmtDate(r.paid!.toIso8601String())}',
                    style: TextStyle(
                        fontSize: 10.5, color: kInk.withValues(alpha: .55))),
                if (r.paid != null && r.lateDays > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: fg)),
                  ),
                if (r.paid != null && share < 0.999)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                        'Received ₹${moneyWhole(r.paidAmount)} of '
                        '₹${moneyWhole(r.amount)}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${moneyWhole(r.amount)}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: kInk)),
              const SizedBox(height: 3),
              // Green = paid share, red = shortfall (half red + half green on
              // a partial payment; full red on no payment).
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 84,
                  height: 6,
                  child: LinearProgressIndicator(
                    value: share,
                    backgroundColor: kRed.withValues(alpha: .5),
                    valueColor: const AlwaysStoppedAnimation(kGreen),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(6)),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: fg)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Gold divider row between the previous period and the refinanced one.
  Widget _refinanceTile(_SchedRow r) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A3A10), Color(0xFF8A6D1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.change_history,
              color: Color(0xFFE7D48B), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('REFINANCE',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: Color(0xFFE7D48B))),
                const SizedBox(height: 2),
                Text(
                    '${fmtDate(r.due.toIso8601String())} · '
                    '₹${moneyWhole(r.amount)}',
                    style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: .9))),
                if (r.refinanceNote?.isNotEmpty ?? false)
                  Text(r.refinanceNote!,
                      style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: Colors.white.withValues(alpha: .7))),
              ],
            ),
          ),
          Text('₹${moneyWhole(r.amount + r.paidAmount)}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

DateTime _dayD(DateTime d) => DateTime(d.year, d.month, d.day);

/// One scheduled installment row in the payment-schedule sheet.
class _SchedRow {
  const _SchedRow({
    required this.due,
    required this.paid,
    required this.amount,
    required this.lateDays,
    required this.index,
    required this.refinance,
    this.paidAmount = 0,
    this.refinanceNote,
  });

  final int index;
  final DateTime due;
  final DateTime? paid;

  /// Instalment amount due for this week.
  final double amount;

  /// How much was actually received for this instalment (0 when unpaid).
  final double paidAmount;

  /// Days the payment arrived after its due date (0 when on time / unpaid).
  final int lateDays;

  /// True for the gold REFINANCE divider rows between payment periods.
  final bool refinance;
  final String? refinanceNote;
}

class _LedgerRow {
  const _LedgerRow({
    required this.stamp,
    required this.gave,
    required this.got,
    required this.balance,
    required this.isGave,
    required this.kind,
    required this.source,
  });

  final String stamp;
  final double gave;
  final double got;
  final double balance;
  final bool isGave;

  /// 'loan' | 'given' | 'collection' — decides what tapping the tile edits.
  final String kind;
  final Map<String, Object?> source;
}