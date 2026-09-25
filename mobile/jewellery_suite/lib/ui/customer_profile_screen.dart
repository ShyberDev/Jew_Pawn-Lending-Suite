import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import '../util/format.dart';
import '../util/ids.dart';
import 'customers_screen.dart';
import 'khata_screen.dart' show LoanBucket, loanBucket, loanNextDue;
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
  bool _loading = true;

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
      if (!mounted) return;
      setState(() {
        _loans = loans;
        _collections = collections;
        _given = given;
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
    final ok = await launchUrl(Uri.parse('sms:$phone'),
        mode: LaunchMode.externalApplication);
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Collect (You Got)'),
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
    final value = Num.money(double.tryParse(controller.text) ?? 0);
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
        'is_irregular': 1,
      },
    );
    // Reflect locally without queueing a second push (pull confirms).
    await _syncLoan(loan);
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
    final noteCtl = TextEditingController();
    String type = 'late_fee';
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
              TextField(
                  controller: noteCtl,
                  decoration: fieldDecoration('Note (e.g. Late fee)')),
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
    final amount = Num.money(double.tryParse(amountCtl.text) ?? 0);
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
        'given_date': todayIso(),
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
    if (mounted) _refresh();
  }

  String _youGaveHint(Map<String, Object?> loan, String type) {
    switch (type) {
      case 'principal':
        return 'Fresh cash given — this becomes part of the principal.';
      case 'interest':
        return 'Interest added on top of the balance.';
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
      _openSheet(_giveDetailSheet(r.source));
      return;
    }
    if (r.kind == 'collection') {
      await _editCollection(r.source);
    } else {
      await _editGiven(r.source);
    }
  }

  Future<void> _editCollection(Map<String, Object?> c) async {
    final controller =
        TextEditingController(text: moneyWhole(Num.toDouble(c['amount'])));
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit collection'),
        content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: fieldDecoration('Amount received')),
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
    final amount = Num.money(double.tryParse(controller.text) ?? 0);
    if (amount <= 0) return;
    await state.db.upsert('khatabook_collections', {
      ...c,
      'amount': amount,
      'dirty': 1,
    });
    final loan = _loanForRef(c['khatabook_loan']);
    if (loan != null) await _syncLoan(loan);
    if (mounted) _refresh();
  }

  Future<void> _editGiven(Map<String, Object?> g) async {
    final amountCtl =
        TextEditingController(text: moneyWhole(Num.toDouble(g['amount'])));
    final noteCtl =
        TextEditingController(text: (g['note']?.toString() ?? '').trim());
    String type = (g['given_type']?.toString() ?? 'late_fee');
    final state = context.read<AppState>();
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
                  ])
                    ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12.5)),
                      selected: type == value,
                      selectedColor: kGold.withValues(alpha: .25),
                      onSelected: (_) => setDlg(() => type = value),
                    ),
                ],
              ),
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
    final amount = Num.money(double.tryParse(amountCtl.text) ?? 0);
    if (amount <= 0) return;
    final loan = _loanForRef(g['khatabook_loan']);
    final old = Num.toDouble(g['amount']);
    final oldType = g['given_type']?.toString() ?? 'late_fee';
    if (loan != null) {
      // Undo the old effect, then apply the corrected one.
      var updated = Map<String, Object?>.from(loan);
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
    await state.db.upsert('khatabook_given', {
      ...g,
      'amount': amount,
      'given_type': type,
      'note': noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
      'dirty': 1,
    });
    if (mounted) _refresh();
  }

  /// Loan tap sheet: Principal, Interest and Principal + Interest, plus any
  /// "You Gave" additions with their notes.
  Widget _giveDetailSheet(Map<String, Object?> loan) {
    final p = moneyWhole(Num.toDouble(loan['principal_amount']));
    final i = moneyWhole(Num.toDouble(loan['interest_amount']));
    final t = moneyWhole(Num.toDouble(loan['total_payable']));
    final ref = (loan['server_name'] as String?) ?? loan['client_uuid'];
    final givens =
        _given.where((g) => g['khatabook_loan'] == ref).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          _sheetHeader('You Gave — $_name'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailLine('Principal', '₹$p'),
                _detailLine('Interest', '₹$i'),
                _detailLine('Total (principal + interest)', '₹$t'),
                if (givens.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Added amounts',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: kInk)),
                  const SizedBox(height: 4),
                ],
                for (final g in givens)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      '₹${moneyWhole(Num.toDouble(g['amount']))} · '
                      '${_givenTypeLabel(g['given_type']?.toString())}'
                      '${(g['note']?.toString() ?? '').isEmpty ? '' : ' — ${g['note']}'}',
                      style: TextStyle(
                          fontSize: 12.5, color: kInk.withValues(alpha: .7)),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13, color: kInk.withValues(alpha: .6)))),
          Text(value,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: kInk)),
        ],
      ),
    );
  }

  String _givenTypeLabel(String? type) {
    switch (type ?? 'late_fee') {
      case 'principal':
        return 'Principal';
      case 'interest':
        return 'Interest';
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
          : RefreshIndicator(
              color: kGold,
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
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
                  const SizedBox(height: 40),
                ],
              ),
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
                Text(_name,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: kInk)),
                const SizedBox(height: 3),
                Text(
                  _phone.isEmpty ? 'No phone saved' : _phone,
                  style: TextStyle(
                      fontSize: 12.5, color: kInk.withValues(alpha: .6)),
                ),
                const SizedBox(height: 5),
                _ratingTag(_customer['rating']?.toString() ?? 'New'),
                const SizedBox(height: 7),
                _reminderChip(),
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
          const Text('OUTSTANDING',
              style: TextStyle(
                  fontSize: 11, letterSpacing: 1, color: Color(0xFFE7D48B))),
          const SizedBox(height: 4),
          Text('₹${moneyWhole(_outstanding)}',
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
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
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('YOU GAVE',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
                color: kRed)),
        SizedBox(width: 10),
        Text('YOU GOT',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
                color: kGreen)),
        SizedBox(width: 2),
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

    // Loans: red "You Gave" shows the cash handed over (principal); the running
    // balance jumps by the full amount to recover (principal + interest).
    for (final l in _loans) {
      final raw = l['updated_at']?.toString() ?? l['loan_date']?.toString();
      final when = parseIso(raw) ?? DateTime.now();
      final principal = Num.toDouble(l['principal_amount']);
      final interest = Num.toDouble(l['interest_amount']);
      entries.add((
        when: when,
        stamp: fmtDateTime(raw),
        gave: principal,
        got: 0,
        delta: principal + interest,
        isGave: true,
        kind: 'loan',
        source: l,
      ));
    }

    // "You Gave" fee / late-interest additions: red, add their amount only.
    for (final g in _given) {
      final graw = g['updated_at']?.toString() ?? g['given_date']?.toString();
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

    // Collections: green, subtract their amount.
    for (final c in _collections) {
      final raw = c['updated_at']?.toString() ?? c['collection_date']?.toString();
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
    final color = isGave ? kRed : kGreen;
    return GestureDetector(
      onTap: () => _editRow(r),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(r.stamp,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: kInk.withValues(alpha: .7))),
                ),
                SizedBox(
                  width: 92,
                  child: Text(
                    isGave ? '₹${moneyWhole(r.gave)}' : '₹${moneyWhole(r.got)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isGave ? kRed : kGreen),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            // Daily outstanding balance — money lent out, shown in red, left
            // side, below the date, inside this tile.
            Row(
              children: [
                Expanded(
                  child: Text('bal ₹${moneyWhole(r.balance)}',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: kRed)),
                ),
                Text(r.kind == 'loan' ? 'details ✎' : 'edit ✎',
                    style: TextStyle(
                        fontSize: 10, color: kInk.withValues(alpha: .35))),
              ],
            ),
          ],
        ),
      ),
    );
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
      initialChildSize: 0.7,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          _sheetHeader('Payment schedule — $_name'),
          if (_activeLoans.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24), child: Text('No active loans.')),
          for (final l in _activeLoans) _scheduleLoanTile(l),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _scheduleLoanTile(Map<String, Object?> loan) {
    final today = DateTime.now();
    final due = loanNextDue(loan, today);
    final bucket = loanBucket(loan, today);
    final chip = bucket == LoanBucket.overdue
        ? const _ChipLocal('OVERDUE', kRedSoft, kRed)
        : bucket == LoanBucket.dueToday
            ? const _ChipLocal('DUE TODAY', kGold, kGoldDark)
            : bucket == LoanBucket.upcoming
                ? const _ChipLocal('UPCOMING', kBlueSoft, kBlue)
                : const _ChipLocal('ON TIME', kGreenSoft, kGreen);
    final paid = (loan['paid_installments'] as num?)?.toInt() ?? 0;
    final count = (loan['installment_count'] as num?)?.toInt() ?? 0;
    final p = moneyWhole(Num.toDouble(loan['principal_amount']));
    final i = moneyWhole(Num.toDouble(loan['interest_amount']));
    final t = moneyWhole(Num.toDouble(loan['total_payable']));
    return ListTile(
      title: Text('₹${moneyWhole(loan['outstanding'] as num?)} outstanding'),
      subtitle: Text(
          'Principal ₹$p · Interest ₹$i · Total ₹$t\n'
          '${loan['collection_frequency']} · $paid/$count installments'
          '${due != null ? ' · next ${fmtDate(due.toIso8601String())}' : ''}'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: chip.bg, borderRadius: BorderRadius.circular(8)),
        child: Text(chip.label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: chip.fg)),
      ),
    );
  }
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

class _ChipLocal {
  const _ChipLocal(this.label, this.bg, this.fg);
  final String label;
  final Color bg;
  final Color fg;
}