import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/migration_v11.dart';
import '../data/migration_v12.dart';
import '../state/app_state.dart';
import 'admin_guard.dart';
import 'refinance_sheet.dart';
import '../util/format.dart';
import '../util/ids.dart';
import '../util/khata_alloc.dart';
import '../util/khata_loan_state.dart';
import '../util/khata_math.dart';
import '../util/khata_schedule.dart';
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
  List<Map<String, Object?>> _periods = [];
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
    // Read the store once, above every await below. AppState outlives this
    // widget, so the reload still completes if the user navigates away.
    final state = context.read<AppState>();
    try {
      final db = state.db;
      final uuid = _customer['client_uuid'] as String?;
      if (uuid != null) {
        final fresh = await db.byUuid('customers', uuid);
        if (fresh != null) _customer = fresh;
      }
      final loans = await db.query('khatabook_loans',
          where: 'customer_name = ? OR customer = ?',
          whereArgs: [_name, uuid],
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
      // Interest-period rows for interest-only loans, so the schedule sheet
      // shows billed periods instead of a synthetic count.
      var periods = const <Map<String, Object?>>[];
      for (final l in loans) {
        if (MigrationV11.isInterestOnly(l)) {
          periods = [
            ...periods,
            ...await state.ensureInterestPeriods(l),
          ];
        }
      }
      if (!mounted) return;
      setState(() {
        _loans = loans;
        _collections = collections;
        _given = given;
        _refinances = refinances;
        _periods = periods;
        _loading = false;
      });
    } catch (error) {
      debugPrint('profile refresh failed: $error');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, Object?>> get _activeLoans =>
      _loans.where((l) => isActiveKhataStatus(l['status'])).toList();

  /// What the customer still owes. This is the single figure shown on the
  /// profile, in the schedule strip, on the khata tile, in Reports AND in the
  /// SMS/WhatsApp message, so it must be ONE definition.
  ///
  /// It used to be the ledger's running balance, which counts the refinanced
  /// cash twice (the new loan's principal already includes it, and the
  /// refinance "You Gave" row adds it again) — the shopkeeper then quoted the
  /// customer a balance ₹1,000 too high. It is now the loans' own figure.
  double get _outstanding => Num.rupees(_activeLoans.fold<double>(
      0, (s, l) => s + Num.toDouble(l['outstanding'])));
  // What they've paid back = sum of all collections recorded.
  double get _paid => Num.rupees(
      _collections.fold<double>(0, (s, c) => s + Num.toDouble(c['amount'])));
  // The invested principal (fresh cash handed over) across active loans.
  double get _principal => Num.rupees(_activeLoans.fold<double>(
      0, (s, l) => s + Num.toDouble(l['principal_amount'])));
  // All charges on top of principal (interest + late fee + other You Gave
  // amounts) = what the loan asks for beyond the cash handed over.
  double get _interest => Num.rupees(_activeLoans.fold<double>(
      0,
      (s, l) =>
          s +
          Num.toDouble(l['total_payable']) -
          Num.toDouble(l['principal_amount'])));

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
            'Namaste $_name 🙏\nYour khata balance is ₹${moneyWholeDown(_outstanding)}'
                ' (Paid ₹${moneyWholeDown(_paid)}).',
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
        'Namaste $_name 🙏\nYour khata balance is ₹${moneyWholeDown(_outstanding)}'
        ' (Paid ₹${moneyWholeDown(_paid)}).');
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
    final state = context.read<AppState>();
    var loan = targets.first.loan;
    final isIO = MigrationV11.isInterestOnly(loan);
    List<Map<String, Object?>> periods = const [];
    if (isIO) {
      periods = await state.ensureInterestPeriods(loan);
      final fresh = await state.db
          .byUuid('khatabook_loans', loan['client_uuid']?.toString() ?? '');
      if (fresh != null) loan = fresh;
    }
    final suggested = (loan['installment_amount'] as num?)?.toDouble() ?? 0;
    // v1.0.11: the amount box starts EMPTY — the shopkeeper types what was
    // actually handed over. The instalment amount is only a hint.
    final controller = TextEditingController();
    var picked = DateTime.now();
    String kind = 'normal';
    int? futurePeriod;
    int nextUnbilled = periods.isEmpty
        ? 1
        : ((periods.last['installment_number'] as num?)?.toInt() ?? 0) + 1;
    // The interest-period rebuild above is async; the screen may be gone by
    // the time we would open the collect dialog.
    if (!mounted) return;
    String paymentMode = 'Cash';
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
                    setDlg(() => picked = DateTime(d.year, d.month, d.day));
                  }
                },
                icon: const Icon(Icons.calendar_month),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Against: ${loan['customer_name']} · '
                    'balance ₹${moneyWholeDown(loan['outstanding'] as num?)}'),
                const SizedBox(height: 12),
                TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: fieldDecoration('Amount received',
                        hint: suggested > 0
                            ? 'e.g. ${moneyWholeDown(suggested)}'
                            : null)),
                const SizedBox(height: 10),
                Text('Payment Mode',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: inkOf(context))),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final mode in const ['Cash', 'UPI', 'Bank']) ...[
                      ChoiceChip(
                        label:
                            Text(mode, style: const TextStyle(fontSize: 12.5)),
                        selected: paymentMode == mode,
                        selectedColor: kGold.withValues(alpha: .25),
                        onSelected: (_) => setDlg(() => paymentMode = mode),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                // Future interest is EXPLICIT only, and only interest-only
                // loans offer it: normal money never prepays the future.
                if (isIO) ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (v, label) in const [
                        ('normal', 'Normal collection'),
                        ('future', 'Future Interest'),
                      ])
                        ChoiceChip(
                          label: Text(label,
                              style: const TextStyle(fontSize: 12.5)),
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
                            child: Text(
                                'Period ${(p['installment_number'] as num?)?.toInt()} · ${p['due_date']} · ${Num.toDouble(p['remaining_amount']) <= 0 ? 'paid' : 'owes ₹${moneyWholeDown(Num.toDouble(p['remaining_amount']))}'}',
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
                  ],
                  const SizedBox(height: 10),
                ],
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
                      setDlg(() => picked = DateTime(d.year, d.month, d.day));
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
    final value = Num.rupees(parseMoney(controller.text));
    if (value <= 0) return;
    if (isIO && kind == 'future' && futurePeriod == null) {
      _toast('Choose which interest period this prepays.');
      return;
    }
    final collectionUuid = newUuid();
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
        'collection_date': picked.toIso8601String().substring(0, 10),
        'amount': value,
        'payment_mode': paymentMode,
        'is_irregular': 1,
        if (futureBilled != null) 'interest_period': futureBilled,
      },
    );
    // Single writer: same canonical engine as the book screen — allocate
    // interest first, add the payment to the stored total, write components
    // and the allocation ledger. Never recompute from the stale loan map.
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
    await state.recordAllocations(
      loanUuid: loan['client_uuid']?.toString() ?? '',
      collectionUuid: collectionUuid,
      allocation: allocation,
    );
    if (isIO) {
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
    await state.touchActivity(_customer['client_uuid']?.toString());
    await state.logEvent('khata', 'collect', 'Collected — $_name',
        amount: value,
        village: loan['village']?.toString(),
        ref: loan['server_name']?.toString());
    if (mounted) _refresh();
  }

  /// Reconciles a loan's saved columns from its actual collections.
  ///
  /// The stored collected total stays the authority and is never rebuilt from
  /// the rows: a loan can carry a collected figure with no matching collection
  /// row (loan creation seeds it directly), so summing rows would drop those
  /// earlier payments and make the balance jump back up. See
  /// `KhataMath.addToCollected` — [KhataMath.totals] remains the rule for a
  /// full rebuild from a complete ledger, such as during migration.
  Future<void> _syncLoan(Map<String, Object?> loan) async {
    final db = context.read<AppState>().db;
    final payable = Num.toDouble(loan['total_payable']);
    final collected = Num.toDouble(loan['total_collected']);
    final out = KhataMath.outstanding(payable, collected);
    await db.upsert('khatabook_loans', {
      ...loan,
      'outstanding': out,
      'paid_installments': KhataMath.paidInstallments(
        collected: collected,
        totalPayable: payable,
        count: (loan['installment_count'] as num?)?.toInt() ?? 0,
      ),
      'status': KhataMath.status(out),
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
    // Hoisted above every await: a collect must never be abandoned because the
    // screen changed while the write was in flight.
    final state = context.read<AppState>();
    if (_activeLoans.isEmpty) {
      await _addLoan();
      return;
    }
    final loan = _activeLoans.first;
    final amountCtl = TextEditingController();
    final noteCtl = TextEditingController();
    String type = 'late_fee';
    var givenOn = DateTime.now();
    String paymentMode = 'Cash';
    String? amountError;
    // v1.0.23: returns the chosen TYPE and PAYMENT MODE. "Refinance" is not an
    // amount added inside this dialog - it is a different dialog entirely.
    final picked = await showDialog<({String type, String paymentMode})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('You Gave'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_youGaveHint(loan, type),
                    style: TextStyle(fontSize: 12, color: mutedOf(context))),
                const SizedBox(height: 12),
                TextField(
                    controller: amountCtl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    onChanged: (_) {
                      if (amountError != null) {
                        setDlg(() => amountError = null);
                      }
                    },
                    decoration: fieldDecoration('Amount')),
                if (amountError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(amountError!,
                        style: const TextStyle(fontSize: 11.5, color: kRed)),
                  ),
                const SizedBox(height: 10),
                Text('Payment Mode',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: inkOf(context))),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final mode in const ['Cash', 'UPI', 'Bank']) ...[
                      ChoiceChip(
                        label:
                            Text(mode, style: const TextStyle(fontSize: 12.5)),
                        selected: paymentMode == mode,
                        selectedColor: kGold.withValues(alpha: .25),
                        onSelected: (_) => setDlg(() => paymentMode = mode),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
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
                      setDlg(() => givenOn = DateTime(d.year, d.month, d.day));
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
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: inkOf(context))),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (value, label) in const [
                        ('principal', 'Principal'),
                        ('late_fee', 'Late fee'),
                        ('interest', 'Interest'),
                        ('unpaid', 'Unpaid'),
                        ('unavailable', 'Unavailable'),
                        ('refinance', 'Refinance'),
                      ]) ...[
                        ChoiceChip(
                          label: Text(label,
                              style: const TextStyle(fontSize: 12.5)),
                          selected: type == value,
                          selectedColor: kGold.withValues(alpha: .25),
                          onSelected: (_) {
                            // Nothing on this form applies to a refinance: it carries its own
                            // previous-outstanding / fresh-cash / new-interest fields. Close this
                            // dialog and open that one straight away, instead of leaving the
                            // shopkeeper to type an amount here that would be ignored.
                            if (value == 'refinance') {
                              Navigator.pop(ctx, (
                                type: 'refinance',
                                paymentMode: paymentMode
                              ));
                              return;
                            }
                            setDlg(() => type = value);
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: noteCtl,
                    decoration: fieldDecoration('Note (e.g. Late fee)')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  final needsAmount = type != 'unpaid' &&
                      type != 'unavailable' &&
                      type != 'refinance';
                  if (needsAmount && parseMoney(amountCtl.text) <= 0) {
                    setDlg(
                        () => amountError = 'Enter an amount greater than 0.');
                    return;
                  }
                  Navigator.pop(ctx, (type: type, paymentMode: paymentMode));
                },
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (picked == null) return;
    type = picked.type;
    paymentMode = picked.paymentMode;
    try {
      if (type == 'refinance') {
        // One shared dialog + one shared writer, so refinance can never mean
        // something different here than on the loan sheet. Reached by tapping
        // the Refinance chip, which closed the You Gave dialog and handed over.
        if (!mounted) return;
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
        if (mounted) _refresh();
        return;
      }
      // Unpaid / Unavailable markers carry NO money: a red history rectangle
      // plus an auto-reminder for tomorrow (only when none is set). Balances,
      // To Collect math and the schedule never see them.
      if (type == 'unpaid' || type == 'unavailable') {
        await state.saveEntity(
          table: 'khatabook_given',
          doctype: 'Khatabook Given',
          uuid: newUuid(),
          data: {
            'customer': loan['customer_name'],
            'customer_name': loan['customer_name'],
            'customer_uuid': loan['customer_uuid'],
            'village': loan['village'],
            'khatabook_loan': loan['server_name'] ?? loan['client_uuid'],
            'given_date': givenOn.toIso8601String().substring(0, 10),
            'amount': 0,
            'given_type': type,
            'payment_mode': paymentMode,
            'note': noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
          },
        );
        final reminder = (_customer['reminder_date']?.toString() ?? '').trim();
        final customerUuid = _customer['client_uuid']?.toString() ?? '';
        if (reminder.isEmpty && customerUuid.isNotEmpty) {
          final tomorrow = DateTime.now().add(const Duration(days: 1));
          await state.saveEntity(
            table: 'customers',
            doctype: 'Pawn Customer',
            uuid: customerUuid,
            data: {
              ..._customer,
              'reminder_date': '${tomorrow.year.toString().padLeft(4, '0')}-'
                  '${tomorrow.month.toString().padLeft(2, '0')}-'
                  '${tomorrow.day.toString().padLeft(2, '0')}',
            },
          );
        }
        await state.touchActivity(_customer['client_uuid']?.toString());
        await state.logEvent('khata', 'marker', 'Marked $type — $_name',
            village: loan['village']?.toString(),
            ref: loan['server_name']?.toString());
        if (mounted) _refresh();
        return;
      }
      final amount = Num.rupees(parseMoney(amountCtl.text));
      if (amount <= 0) return;
      await state.saveEntity(
        table: 'khatabook_given',
        doctype: 'Khatabook Given',
        uuid: newUuid(),
        data: {
          'customer': loan['customer_name'],
          'customer_name': loan['customer_name'],
          'customer_uuid': loan['customer_uuid'],
          'village': loan['village'],
          'khatabook_loan': loan['server_name'] ?? loan['client_uuid'],
          'given_date': givenOn.toIso8601String().substring(0, 10),
          'amount': amount,
          'given_type': type,
          'payment_mode': paymentMode,
          'note': noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
        },
      );
      // A principal "You Gave" is fresh cash handed over; a late-fee / interest
      // one adds to what they owe. Both raise the amount to recover.
      final updated = Map<String, Object?>.from(loan);
      updated['total_payable'] =
          Num.rupees(Num.toDouble(loan['total_payable']) + amount);
      if (type == 'principal') {
        updated['principal_amount'] =
            Num.rupees(Num.toDouble(loan['principal_amount']) + amount);
      }
      await _syncLoan(updated);
      await state.touchActivity(_customer['client_uuid']?.toString() ??
          loan['customer_uuid']?.toString());
      await state.logEvent('khata', 'given', 'You Gave — $_name ($type)',
          amount: amount,
          village: loan['village']?.toString(),
          ref: loan['server_name']?.toString());
      if (mounted) _refresh();
    } catch (error) {
      // A failed write must never look like a dead button.
      if (mounted) {
        _toast('Could not save You Gave entry: $error');
      }
    }
  }

  String _youGaveHint(Map<String, Object?> loan, String type) {
    switch (type) {
      case 'principal':
        return 'Fresh cash given — this becomes part of the principal.';
      case 'interest':
        return 'Interest added on top of the balance.';
      case 'unpaid':
        return 'No money moves. Marks today unpaid and reminds tomorrow.';
      case 'unavailable':
        return 'No money moves. Marks the customer unavailable, reminds tomorrow.';
      case 'refinance':
        return 'Freezes this loan and opens a fresh one: previous outstanding '
            '+ fresh cash + new interest. History stays intact.';
      default:
        return 'Late fee / penalty — adds to the balance. '
            'Balance ₹${moneyWholeDown(Num.toDouble(loan['outstanding']))}';
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
    // Transfer tiles derive from refinance records; they are display-only.
    if (r.kind == 'transfer') return;
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
    final pCtl = TextEditingController(
        text: moneyWholeDown(Num.toDouble(loan['principal_amount'])));
    final iCtl = TextEditingController(
        text: moneyWholeDown(Num.toDouble(loan['interest_amount'])));
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
                '₹${moneyWholeDown(Num.toDouble(parseMoney(pCtl.text)) + Num.toDouble(parseMoney(iCtl.text)))}',
                style: TextStyle(fontSize: 12, color: mutedOf(context))),
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
    final np = Num.rupees(parseMoney(pCtl.text));
    final ni = Num.rupees(parseMoney(iCtl.text));
    if (np <= 0 || ni < 0) return;
    // Keep the fee/You-Gave part of total_payable intact, replace P + I.
    final fees = Num.toDouble(loan['total_payable']) -
        Num.toDouble(loan['principal_amount']) -
        Num.toDouble(loan['interest_amount']);
    final updated = Map<String, Object?>.from(loan)
      ..['principal_amount'] = np
      ..['interest_amount'] = ni
      ..['total_payable'] = Num.rupees(np + ni + fees);
    await state.db.upsert('khatabook_loans', {
      ...updated,
      'dirty': 0,
    });
    await _syncLoan(updated);
    await state.touchActivity(_customer['client_uuid']?.toString() ??
        loan['customer_uuid']?.toString());
    await state.logEvent('khata', 'loan_edit', 'Loan edited — $_name',
        amount: Num.toDouble(updated['total_payable']),
        village: _customer['village']?.toString(),
        ref: updated['server_name']?.toString());
    if (mounted) _refresh();
  }

  Future<void> _editCollection(Map<String, Object?> c) async {
    final controller =
        TextEditingController(text: moneyWholeDown(Num.toDouble(c['amount'])));
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
                    setDlg(() => picked = DateTime(d.year, d.month, d.day));
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
    final amount = Num.rupees(parseMoney(controller.text));
    if (amount <= 0) return;
    final loan = _loanForRef(c['khatabook_loan']);
    // Reverse the old payment out of every balance first, then apply the new
    // amount through the canonical engine — otherwise the edit leaves the
    // old money in the totals and the new money piles on top of it.
    var oldI = 0.0, oldL = 0.0, oldO = 0.0, oldP = 0.0, oldU = 0.0;
    try {
      final oldAllocs = await state.db.query('khatabook_allocations',
          where: 'khatabook_collection = ?', whereArgs: [c['client_uuid']]);
      for (final a in oldAllocs) {
        final v = Num.toDouble(a['amount']);
        switch ('${a['component']}') {
          case 'INTEREST':
            oldI += v;
          case 'LATE_FEE':
            oldL += v;
          case 'OTHER_CHARGE':
            oldO += v;
          case 'PRINCIPAL':
            oldP += v;
          case 'UNAPPLIED_CREDIT':
            oldU += v;
        }
      }
      await state.db.delete('khatabook_allocations',
          where: 'khatabook_collection = ?', whereArgs: [c['client_uuid']]);
    } catch (_) {/* table absent before v10 */}
    await state.db.upsert('khatabook_collections', {
      ...c,
      'amount': amount,
      'collection_date': picked.toIso8601String().substring(0, 10),
      'dirty': 1,
    });
    if (loan != null) {
      final before = KhataLoanState.fromRow(loan);
      final reversedTotal =
          Num.toDouble(loan['total_collected']) - Num.toDouble(c['amount']);
      final reversed = before.copyWith(
        principalRecovered:
            (before.principalRecovered - oldP).clamp(0, double.infinity),
        interestOutstanding: before.interestOutstanding + oldI,
        lateFeeOutstanding: before.lateFeeOutstanding + oldL,
        otherChargeOutstanding: before.otherChargeOutstanding + oldO,
        unappliedCredit:
            (before.unappliedCredit - oldU).clamp(0, double.infinity),
      );
      final allocation = KhataAlloc.allocate(
        payment: amount,
        interestDue: reversed.interestOutstanding,
        lateFeeDue: reversed.lateFeeOutstanding,
        otherChargeDue: reversed.otherChargeOutstanding,
        principalDue: reversed.investment,
      );
      final after = KhataLoanState.apply(reversed, allocation);
      final collected = KhataMath.addToCollected(
        already: reversedTotal < 0 ? 0 : reversedTotal,
        payment: amount,
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
      await state.recordAllocations(
        loanUuid: loan['client_uuid']?.toString() ?? '',
        collectionUuid: c['client_uuid']?.toString() ?? '',
        allocation: allocation,
      );
      if (MigrationV11.isInterestOnly(loan)) {
        // Rebuild replays every remaining INTEREST slice (pinned ones to
        // their period, the rest oldest-first), so the rows end exactly where
        // the money says — no separate marking needed here.
        await state
            .rebuildInterestPeriods(loan['client_uuid']?.toString() ?? '');
      }
    }
    await state.logEvent('khata', 'collect_edit', 'Collection edited — $_name',
        amount: amount,
        village: _customer['village']?.toString(),
        ref: loan?['server_name']?.toString());
    if (mounted) _refresh();
  }

  Future<void> _editGiven(Map<String, Object?> g) async {
    final amountCtl =
        TextEditingController(text: moneyWholeDown(Num.toDouble(g['amount'])));
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
        text: moneyWholeDown(Num.toDouble(refi?['new_interest_amount'])));
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
                    ('unpaid', 'Unpaid'),
                    ('unavailable', 'Unavailable'),
                    ('refinance', 'Refinance'),
                  ])
                    ChoiceChip(
                      label:
                          Text(label, style: const TextStyle(fontSize: 12.5)),
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
    final amount = Num.rupees(parseMoney(amountCtl.text));
    final interest = Num.rupees(parseMoney(interestCtl.text));
    if (amount <= 0 && !(type == 'refinance' && interest > 0)) return;
    final loan = _loanForRef(g['khatabook_loan']);
    final old = Num.toDouble(g['amount']);
    final oldType = g['given_type']?.toString() ?? 'late_fee';
    if (loan != null) {
      var updated = Map<String, Object?>.from(loan);
      if (type == 'refinance') {
        // Refinance rows store fresh cash in `amount` and the new interest in
        // the refinance record — correct both together.
        updated['principal_amount'] = Num.rupees(
            Num.toDouble(updated['principal_amount']) + (amount - old));
        updated['interest_amount'] = interest;
        updated['total_payable'] =
            Num.rupees(Num.toDouble(updated['principal_amount']) + interest);
        final count = (updated['installment_count'] as num?)?.toInt() ?? 12;
        updated['installment_amount'] =
            Num.rupees(Num.toDouble(updated['total_payable']) / count);
        await _syncLoan(updated);
        await state.touchActivity(_customer['client_uuid']?.toString() ??
            loan['customer_uuid']?.toString());
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
            Num.rupees(Num.toDouble(updated['total_payable']) - old);
        if (oldType == 'principal') {
          updated['principal_amount'] =
              Num.rupees(Num.toDouble(updated['principal_amount']) - old);
        }
        updated['total_payable'] =
            Num.rupees(Num.toDouble(updated['total_payable']) + amount);
        if (type == 'principal') {
          updated['principal_amount'] =
              Num.rupees(Num.toDouble(updated['principal_amount']) + amount);
        }
        await _syncLoan(updated);
        await state.touchActivity(_customer['client_uuid']?.toString() ??
            loan['customer_uuid']?.toString());
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
        return ''; // Other: legacy rows only, no longer offered. Note only.
      case 'unpaid':
        return 'Unpaid';
      case 'unavailable':
        return 'Unavailable';
      case 'refinance':
        return 'Refinance';
      default:
        return 'Late fee';
    }
  }

  // ---------------------------------------------------------------- reminder
  Widget _reminderChip() {
    final reminder = _customer['reminder_date']?.toString() ?? '';
    final label = reminder.isEmpty
        ? 'Remind: not set'
        : 'Remind ${fmtReminder(reminder)}';
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
            Flexible(
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: kGoldDark)),
            ),
          ],
        ),
      ),
    );
  }

  /// Today / Next week / Next month / Calendar. Defaults from the active
  /// loan's collection frequency; the shopkeeper can always change it.
  Future<void> _setReminder() async {
    final state = context.read<AppState>();
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
                  style: TextStyle(fontSize: 12.5, color: mutedOf(context))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (value, label) in const [
                    ('today', 'Today'),
                    ('tomorrow', 'Tomorrow'),
                    ('next_week', 'Next week'),
                    ('next_month', 'Next month'),
                  ])
                    ChoiceChip(
                      label:
                          Text(label, style: const TextStyle(fontSize: 12.5)),
                      selected: selection == value,
                      selectedColor: kGold.withValues(alpha: .25),
                      onSelected: (_) {
                        setDlg(() {
                          selection = value;
                          if (value == 'today') picked = now;
                          if (value == 'tomorrow') {
                            picked = now.add(const Duration(days: 1));
                          }
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
                    setDlg(() => selection = '');
                  }
                },
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

  /// Moves the customer to the Loss Khata — or back out of it.
  ///
  /// Only the village changes; loans, collections, IDs and history are
  /// untouched, and normal collection keeps working wherever they live.
  Future<void> _moveCustomer() async {
    final state = context.read<AppState>();
    final inLoss = MigrationV12.isLossKhata(_customer['village']?.toString());
    if (inLoss) {
      // Move back: pick the village explicitly.
      final villages =
          await state.db.query('villages', orderBy: 'village_name asc');
      final names = villages
          .map((v) => v['village_name']?.toString() ?? '')
          .where((n) => n.isNotEmpty && !MigrationV12.isLossKhata(n))
          .toList();
      if (!mounted) return;
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Move back to village'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final n in names)
                  ListTile(
                    dense: true,
                    title: Text(n),
                    onTap: () => Navigator.pop(ctx, n),
                  ),
                ListTile(
                  dense: true,
                  title: const Text('General (no village)'),
                  onTap: () => Navigator.pop(ctx, ''),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
          ],
        ),
      );
      if (picked == null) return;
      await state.moveCustomerFromLoss(
          _customer, picked.isEmpty ? null : picked);
      if (mounted) _refresh();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure you want to move to Loss Account?'),
        content: Text('$_name will move to the Loss Khata with all loans, '
            'collections and history intact.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    // Admin password guards the move, exactly like a delete. The password
    // check is case-insensitive and optional per the Password Settings.
    if (!mounted) return;
    final granted = await askPasswordIfEnabled(context, state,
        actionId: 'move_to_loss', action: 'move to Loss', detail: _name);
    if (!granted) {
      _toast('Move cancelled / wrong password.');
      return;
    }
    await state.moveCustomerToLoss(_customer);
    if (mounted) _refresh();
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
      backgroundColor: bgOf(context),
      appBar: AppBar(
        title: const Text('Customer'),
        // One overflow action keeps the title readable on a 320 dp phone.
        // Call / SMS / WhatsApp / Move / Edit are all secondary to the
        // Collect and You Gave buttons pinned at the bottom.
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More actions',
            onSelected: (value) async {
              switch (value) {
                case 'call':
                  _call();
                  break;
                case 'sms':
                  _sms();
                  break;
                case 'whatsapp':
                  _whatsapp();
                  break;
                case 'move':
                  _moveCustomer();
                  break;
                case 'edit':
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CustomerForm(existing: _customer)),
                  );
                  if (mounted) _refresh();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'call',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.phone_outlined),
                  title: Text('Call'),
                ),
              ),
              const PopupMenuItem(
                value: 'sms',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sms_outlined),
                  title: Text('SMS'),
                ),
              ),
              const PopupMenuItem(
                value: 'whatsapp',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ImageIcon(AssetImage('assets/whatsapp.png')),
                  title: Text('WhatsApp'),
                ),
              ),
              const PopupMenuItem(
                value: 'move',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.swap_horiz_outlined),
                  title: Text('Move to another khata'),
                ),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                ),
              ),
            ],
          ),
        ],
      ),
      // Sticky bottom bar: You Gave / Collect are always visible.
      bottomNavigationBar: _loading
          ? null
          : Container(
              color: surfaceOf(context),
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
                      _tile(
                          Icons.calendar_month_outlined,
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
        color: surfaceOf(context),
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
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: inkOf(context))),
                    ),
                    if ((_customer['customer_id']?.toString() ?? '')
                        .isNotEmpty) ...[
                      const SizedBox(width: 8),
                      // Khata customer ID (order-wise A01…).
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: .22),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: kGold.withValues(alpha: .5)),
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
                  style: TextStyle(fontSize: 12.5, color: mutedOf(context)),
                ),
                const SizedBox(height: 5),
                // v1.0.11: the rating pill is gone; only the collection reminder
                // (tap to set or change the promised date) stays. NOTE: no
                // Flexible here — it is only valid inside a Flex, and using it
                // inside an Align broke this whole screen.
                Align(
                  alignment: Alignment.centerLeft,
                  child: _reminderChip(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _outstandingCard() {
    // Three sections: invested Principal | INTEREST (interest + late fee +
    // other "You Gave" charges) | Outstanding still to collect. Paid line
    // below, no Total Payable (it duplicated Outstanding and confused).
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
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('₹${moneyWholeDown(_principal)}',
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 22,
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
                    const Text('INTEREST',
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: .8,
                            color: Color(0xFFE7D48B))),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('₹${moneyWholeDown(_interest)}',
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
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
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text('₹${moneyWholeDown(_outstanding)}',
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Paid ₹${moneyWholeDown(_paid)}',
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
            color: surfaceOf(context), borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ledgerHeader(),
            const SizedBox(height: 12),
            Center(
              child: Text(
                  'No transactions yet. Tap "You Gave" to start a loan.',
                  style: TextStyle(fontSize: 12.5, color: mutedOf(context))),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
          color: surfaceOf(context), borderRadius: BorderRadius.circular(18)),
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
    // Ordering uses updated_at (date + time, seconds precision) so a
    // transaction entered 1 sec earlier sits below the newer one.
    for (final l in _loans) {
      final raw = l['loan_date']?.toString() ?? l['updated_at']?.toString();
      final upd = l['updated_at']?.toString();
      final lr = ledgerWhen(businessDate: raw, entryAt: upd);
      final when = lr.when;
      final principal = Num.toDouble(l['principal_amount']);
      final interest = Num.toDouble(l['interest_amount']);
      entries.add((
        when: when,
        stamp: lr.stamp,
        gave: Num.rupees(principal + interest),
        got: 0,
        delta: principal + interest,
        isGave: true,
        kind: 'loan',
        source: l,
      ));
    }

    // "You Gave" fee / late-interest additions: red, add their amount only.
    // The stamp shows GIVEN date + entry time (v1.0.8 back-datable picker).
    // Refinance markers are SKIPPED: since refinance became a split (old loan
    // frozen + new loan carrying previous + fresh + interest), the marker's
    // fresh cash is already inside the new loan's total — counting it again
    // inflated the balance (the ₹38,400 bug).
    for (final g in _given) {
      if ('${g['given_type']}' == 'refinance') continue;
      final graw = g['given_date']?.toString() ?? g['updated_at']?.toString();
      final gupd = g['updated_at']?.toString();
      final gr = ledgerWhen(businessDate: graw, entryAt: gupd);
      final amount = Num.toDouble(g['amount']);
      entries.add((
        when: gr.when,
        stamp: gr.stamp,
        gave: amount,
        got: 0,
        delta: amount,
        isGave: true,
        kind: 'given',
        source: g,
      ));
    }

    // Refinance transfers: the old loan's outstanding moves into the new loan,
    // it is not paid. Without this credit the old loan's debit and the new
    // loan's debit would both stand and the balance would double-count.
    for (final r in _refinances) {
      final rraw =
          r['refinance_date']?.toString() ?? r['updated_at']?.toString();
      final moved = Num.toDouble(r['old_outstanding']);
      if (moved <= 0) continue;
      // The transfer happens one instant BEFORE the new loan opens. The new
      // loan row carries the refinance timestamp, so subtracting a second here
      // makes newest-first display put ₹63,000 (new loan) above the ₹33,000
      // moved-out line instead of the other way round.
      final movedAt = parseIso(rraw) ?? DateTime.now();
      entries.add((
        when: movedAt.subtract(const Duration(seconds: 1)),
        stamp: fmtDateTime(rraw ?? ''),
        gave: 0,
        got: moved,
        delta: -moved,
        isGave: false,
        kind: 'transfer',
        source: r,
      ));
    }

    // Collections: green, subtract their amount. The stamp shows RECEIVED
    // date + entry time (v1.0.8 date picker), so back-dated payments sit
    // truthfully and same-day entries order by seconds.
    for (final c in _collections) {
      final raw =
          c['collection_date']?.toString() ?? c['updated_at']?.toString();
      final cupd = c['updated_at']?.toString();
      final cr = ledgerWhen(businessDate: raw, entryAt: cupd);
      entries.add((
        when: cr.when,
        stamp: cr.stamp,
        gave: 0,
        got: Num.toDouble(c['amount']),
        delta: -Num.toDouble(c['amount']),
        isGave: false,
        kind: 'collection',
        source: c,
      ));
    }

    entries.sort((a, b) {
      final byTime = a.when.compareTo(b.when);
      if (byTime != 0) return byTime;
      return (a.source['client_uuid']?.toString() ?? '')
          .compareTo(b.source['client_uuid']?.toString() ?? '');
    });

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
        balance: Num.rupees(balance),
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
    final isRefinance =
        r.kind == 'given' && r.source['given_type']?.toString() == 'refinance';
    // Unpaid / Unavailable markers carry no money: a red rectangle with the
    // date, the balance at marking time and the label — history, not a debt.
    final givenType = r.source['given_type']?.toString() ?? '';
    final isMarker = r.kind == 'given' &&
        (givenType == 'unpaid' || givenType == 'unavailable');
    // A transfer is neither cash given nor cash received: old outstanding
    // moved into the new loan. Gold tile, explicit label, never red/green.
    final isTransfer = r.kind == 'transfer';
    // Refinance display: the new-loan row above already carries the full
    // ₹63,000 (previous outstanding + fresh cash + new interest). This transfer
    // tile sits directly below it and headlines the amount that actually moved
    // (₹33,000) — never ₹63,000 again — so the two figures cannot be confused.
    final movedOut =
        isTransfer ? Num.toDouble(r.source['old_outstanding']) : 0.0;
    final newPrincipal =
        isTransfer ? Num.toDouble(r.source['new_principal']) : 0.0;
    final newInterest =
        isTransfer ? Num.toDouble(r.source['new_interest_amount']) : 0.0;
    final newLoanTotal =
        newPrincipal > 0 ? Num.rupees(newPrincipal + newInterest) : r.got;
    final freshCash =
        newPrincipal > movedOut ? Num.rupees(newPrincipal - movedOut) : 0.0;
    final color = isTransfer ? kGoldDark : (isGave ? kRed : kGreen);
    // You-Gave rows show why: "Late fee — Hello". The note always shows;
    // for type "Other" only the note is shown (no type word).
    String? note;
    if (isTransfer) {
      note = 'Refinance transfer — moved, not paid';
    } else if (r.kind == 'given') {
      final typeLabel = _givenTypeLabel(r.source['given_type']?.toString());
      final noteText = (r.source['note']?.toString() ?? '').trim();
      note = typeLabel.isEmpty
          ? (noteText.isEmpty ? null : noteText)
          : noteText.isEmpty
              ? typeLabel
              : '$typeLabel — $noteText';
      // #046: the mode the money actually moved by (Cash / UPI / Bank).
      final mode = (r.source['payment_mode']?.toString() ?? '').trim();
      if (mode.isNotEmpty) {
        final label = mode.toUpperCase();
        note = note == null ? label : '$note · $label';
      }
    }
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      // v1.0.8: refinance is a full gold rectangle tile for fast spotting —
      // identical in shape to the payment-schedule refinance rectangle.
      // Unpaid / Unavailable markers use the same rectangle in red.
      decoration: isRefinance || isTransfer
          ? BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3A2E0E), Color(0xFF6B5417)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            )
          : isMarker
              ? BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4A1510), Color(0xFF8A2A1E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                )
              : BoxDecoration(
                  color: color.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: color.withValues(alpha: .18), width: 1),
                ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (isRefinance || isTransfer) ...[
                      const Icon(Icons.change_history,
                          size: 15, color: Colors.white),
                      const SizedBox(width: 4),
                    ],
                    if (isMarker) ...[
                      const Icon(Icons.event_busy,
                          size: 15, color: Colors.white),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(r.stamp,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: (isRefinance || isMarker || isTransfer)
                                  ? Colors.white.withValues(alpha: .9)
                                  : kInk.withValues(alpha: .7))),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 94,
                child: Text(
                  // Markers carry no money: the label below says it all.
                  isMarker
                      ? (givenType == 'unpaid' ? 'UNPAID' : 'UNAVAILABLE')
                      : isGave
                          ? '₹${moneyWholeDown(r.gave)}'
                          : '',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: (isRefinance || isMarker) ? 15.5 : 15,
                      fontWeight: FontWeight.w800,
                      color: (isRefinance || isMarker)
                          ? Colors.white
                          : isGave
                              ? color
                              : Colors.transparent),
                ),
              ),
              SizedBox(
                width: 94,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      !isGave
                          ? '₹${moneyWholeDown(isTransfer ? movedOut : r.got)}'
                          : '',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: isGave
                              ? Colors.transparent
                              : isTransfer
                                  ? Colors.white
                                  : color),
                    ),
                    if (isTransfer)
                      Text('refinanced',
                          style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: .75))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          if (isTransfer)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'New loan ₹${moneyWholeDown(newLoanTotal)}'
                '${freshCash > 0 ? '  •  Fresh cash ₹${moneyWholeDown(freshCash)}' : ''}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFFE082)),
              ),
            ),
          // Daily outstanding balance — money lent out, always red, left.
          // Markers show the balance frozen at marking time (history, not live).
          Text('Bal ₹${moneyWholeDown(r.balance)}',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isTransfer
                      ? const Color(0xFFFFE082)
                      : isRefinance
                          ? const Color(0xFFFFE082)
                          : isMarker
                              ? Colors.white.withValues(alpha: .9)
                              : kRed)),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(note,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: (isRefinance || isMarker || isTransfer)
                          ? Colors.white.withValues(alpha: .85)
                          : color.withValues(alpha: .85))),
            ),
        ],
      ),
    );
    // Drag-to-delete: long-press lifts the tile; dropping it on the bottom
    // bin removes the entry (password only if enabled in Password Settings).
    // A long-press alone never deletes.
    return DragToDeleteTile(
      onDragChanged: (v) => setState(() => _dragActive = v),
      payload: DeletePayload(
        drop: () async {
          final granted = await askPasswordIfEnabled(
              context, context.read<AppState>(),
              actionId: 'ledger_delete',
              action: 'delete',
              detail: 'this ledger row');
          if (!granted) return false;
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
    // Transfer tiles derive from refinance records; there is nothing to
    // delete — removing one would corrupt the ledger it explains.
    if (r.kind == 'transfer') {
      if (mounted) _refresh();
      return;
    }
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
            upd['principal_amount'] =
                Num.rupees(Num.toDouble(upd['principal_amount']) - old);
            upd['total_payable'] = Num.rupees(
                Num.toDouble(upd['principal_amount']) +
                    Num.toDouble(upd['interest_amount']));
          } else {
            upd['total_payable'] =
                Num.rupees(Num.toDouble(upd['total_payable']) - old);
            if (oldType == 'principal') {
              upd['principal_amount'] =
                  Num.rupees(Num.toDouble(upd['principal_amount']) - old);
            }
          }
          await _syncLoan(upd);
          await state.touchActivity(_customer['client_uuid']?.toString());
        }
        await state.deleteCashbookFor(
            [r.source['client_uuid']?.toString() ?? '']);
        await db.delete('khatabook_given',
            where: 'client_uuid = ?', whereArgs: [r.source['client_uuid']]);
        if (r.source['given_type']?.toString() == 'refinance') {
          await db.delete('khatabook_refinances',
              where: 'khatabook_loan = ? AND refinance_date = ?',
              whereArgs: [r.source['khatabook_loan'], r.source['given_date']]);
        }
        await state.logEvent('khata', 'given_delete', 'Given removed — $_name',
            amount: Num.toDouble(r.source['amount']),
            village: _customer['village']?.toString());
      } else if (r.kind == 'collection') {
        final loan = _loanForRef(r.source['khatabook_loan']);
        final collectionUuid = r.source['client_uuid']?.toString() ?? '';
        await state.deleteCashbookFor([collectionUuid]);
        // Legacy rows referenced the loan rather than the collection.
        final loanRef = r.source['khatabook_loan']?.toString() ?? '';
        final collectionDay =
            AppState.businessDay(r.source['collection_date'], DateTime.now());
        if (loanRef.isNotEmpty && collectionUuid.isNotEmpty) {
          await db.deleteCashbookMatching(
            category: 'KHATA_COLLECTION',
            referenceId: loanRef,
            amount: Num.toDouble(r.source['amount']),
            date: collectionDay,
          );
        }
        await db.delete('khatabook_collections',
            where: 'client_uuid = ?', whereArgs: [r.source['client_uuid']]);
        // Its allocation slices die with it — otherwise any later rebuild
        // would replay money that no longer exists.
        try {
          await db.delete('khatabook_allocations',
              where: 'khatabook_collection = ?',
              whereArgs: [r.source['client_uuid']]);
        } catch (_) {/* table absent before v10 */}
        if (loan != null) {
          // Reverse the payment out of the stored total; _syncLoan recomputes
          // from whatever total it is handed, so handing it the stale total
          // would leave the balance unchanged after a delete.
          final reversedTotal = Num.toDouble(loan['total_collected']) -
              Num.toDouble(r.source['amount']);
          final reversed = Map<String, Object?>.from(loan)
            ..['total_collected'] =
                reversedTotal < 0 ? 0 : Num.rupees(reversedTotal);
          await _syncLoan(reversed);
          if (MigrationV11.isInterestOnly(loan)) {
            await state
                .rebuildInterestPeriods(loan['client_uuid']?.toString() ?? '');
          }
          await state.touchActivity(_customer['client_uuid']?.toString());
        }
        await state.logEvent(
            'khata', 'collect_delete', 'Collection removed — $_name',
            amount: Num.toDouble(r.source['amount']),
            village: _customer['village']?.toString());
      } else if (r.kind == 'loan') {
        final ref =
            (r.source['server_name'] as String?) ?? r.source['client_uuid'];
        await state.deleteCashbookForLoan({
          ref?.toString() ?? '',
          r.source['client_uuid']?.toString() ?? '',
        });
        await db.delete('khatabook_given',
            where: 'khatabook_loan = ?', whereArgs: [ref]);
        await db.delete('khatabook_collections',
            where: 'khatabook_loan = ?', whereArgs: [ref]);
        await db.delete('khatabook_refinances',
            where: 'khatabook_loan = ?', whereArgs: [ref]);
        await db.delete('khatabook_loans',
            where: 'client_uuid = ?', whereArgs: [r.source['client_uuid']]);
        await state.touchActivity(_customer['client_uuid']?.toString());
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
        color: surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: kGoldDark),
          title: Text(title,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: inkOf(context))),
          subtitle: Text(subtitle,
              style: TextStyle(fontSize: 11, color: mutedOf(context))),
          trailing: Icon(Icons.chevron_right, color: inkOf(context)),
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
    final p = moneyWholeDown(Num.toDouble(l['principal_amount']));
    final i = moneyWholeDown(Num.toDouble(MigrationV11.isInterestOnly(l)
        ? (l['current_interest'] ?? l['interest_amount'])
        : l['interest_amount']));
    final o = moneyWholeDown(Num.toDouble(l['outstanding']));
    return 'Principal ₹$p · Interest ₹$i · Outstanding ₹$o';
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
    final p = moneyWholeDown(Num.toDouble(loan['principal_amount']));
    // Interest-only loans show the CURRENT per-period interest, which the
    // shopkeeper may change; the stored interest_amount is only the first.
    final i = moneyWholeDown(Num.toDouble(MigrationV11.isInterestOnly(loan)
        ? (loan['current_interest'] ?? loan['interest_amount'])
        : loan['interest_amount']));
    final out = moneyWholeDown(Num.toDouble(loan['outstanding']));
    var rows = _instalmentsFor(loan);
    // Installment loans with no rows yet: a single next-due row instead of
    // all 12/6 settlement tiles. (Interest-only loans always have rows.)
    final effCount = (loan['installment_count'] as num?)?.toInt() ?? 0;
    if (rows.isEmpty && effCount <= 0 && !MigrationV11.isInterestOnly(loan)) {
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
            refinancePrevOut: 0,
            refinanceFresh: 0,
          ),
        ];
      }
    }
    final paidCount = rows.where((r) => r.paid != null).length;
    final onTime = rows.where((r) => r.paid != null && r.lateDays <= 0).length;
    // v1.0.8: label the settlement tiles by the chosen frequency — a monthly
    // loan shows "Month 1/12", biweekly "Fortnight 1/12", weekly "Week 1/12".
    final f = (loan['collection_frequency']?.toString() ?? '').toLowerCase();
    final unit = f.contains('month')
        ? 'Month'
        : f.contains('bi')
            ? 'Fortnight'
            : 'Week';
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
              Expanded(child: _schedStat('OUTSTANDING', '₹$out', end: true)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Expanded(
                child: Text('Settlements — ${loan['collection_frequency']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: mutedOf(context))),
              ),
              if (paidCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: onTime == paidCount
                        ? greenSoftOf(context)
                        : const Color(0xFFFDEBD2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('ON-TIME $onTime/$paidCount',
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
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: end ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(value,
              maxLines: 1,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ),
      ],
    );
  }

  /// Scheduled installments for a loan, split into periods by refinances:
  /// every previous period keeps its full set of week rows (marked by the
  /// collections that happened before the refinance date), then a gold
  /// REFINANCE divider, then a fresh period from each refinance date.
  List<_SchedRow> _instalmentsFor(Map<String, Object?> loan) {
    final today = _dayD(DateTime.now());
    // Interest-only loans show their billed period rows: one row per interest
    // period with its own paid state, so a prepaid future month shows paid and
    // a missed month shows red — never a synthetic count.
    if (MigrationV11.isInterestOnly(loan)) {
      final ref = (loan['server_name'] as String?) ?? loan['client_uuid'];
      final rows = <_SchedRow>[];
      var slot = 0;
      final loanPeriods = _periods
          .where((p) =>
              p['khatabook_loan'] == ref ||
              p['khatabook_loan'] == loan['client_uuid'])
          .toList()
        ..sort((a, b) => ((a['installment_number'] as num?)?.toInt() ?? 0)
            .compareTo((b['installment_number'] as num?)?.toInt() ?? 0));
      for (final p in loanPeriods) {
        final due = _dayD(parseIso(p['due_date']) ?? today);
        final scheduled = Num.toDouble(p['scheduled_amount']);
        final paidAmt = Num.toDouble(p['paid_amount']);
        final hasPaid = paidAmt > 0;
        rows.add(_SchedRow(
          due: due,
          paid: hasPaid ? due : null,
          paidAmount: paidAmt,
          amount: scheduled,
          lateDays: hasPaid ? 0 : today.difference(due).inDays,
          index: slot++,
          refinance: false,
          refinancePrevOut: 0,
          refinanceFresh: 0,
        ));
      }
      return rows;
    }
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
    final colls = _collections.where((c) => c['khatabook_loan'] == ref).toList()
      ..sort((a, b) => (parseIso(a['collection_date']) ?? today)
          .compareTo(parseIso(b['collection_date']) ?? today));
    final refis = _refinances.where((r) => r['khatabook_loan'] == ref).toList()
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
        // Installment i+1 falls one interval after the previous: the first
        // week is due a full week out, never on the start day itself.
        final due = segmentStart.add(Duration(days: (i + 1) * step));
        final inPeriod = collPtr < colls.length &&
            _dayD(parseIso(colls[collPtr]['collection_date']) ?? today)
                .isBefore(refiDay);
        final paid =
            inPeriod ? parseIso(colls[collPtr]['collection_date']) : null;
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
            refinance: false,
            refinancePrevOut: 0,
            refinanceFresh: 0));
        if (paid != null) collPtr++;
      }
      final refiPrevOut = Num.toDouble(refi['old_outstanding']);
      final refiNewPrincipal = Num.toDouble(refi['new_principal']);
      rows.add(_SchedRow.withRefinance(
          due: refiDay,
          // New obligation = previous rolled + fresh cash + new interest, so
          // fresh = new principal − previous outstanding.
          amount: refiNewPrincipal,
          paidAmount: Num.toDouble(refi['new_interest_amount']),
          refinancePrevOut: refiPrevOut,
          refinanceFresh:
              (refiNewPrincipal - refiPrevOut).clamp(0, double.infinity),
          index: slot++,
          refinanceNote: refi['new_interest_note']?.toString()));
      segmentStart = refiDay;
    }
    // Current period — a fresh `count` installments from the latest start.
    for (var i = 0; i < count; i++) {
      final due = segmentStart.add(Duration(days: (i + 1) * step));
      final paid = collPtr < colls.length
          ? parseIso(colls[collPtr]['collection_date'])
          : null;
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
          refinance: false,
          refinancePrevOut: 0,
          refinanceFresh: 0));
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
                ? (greenSoftOf(context), kGreen, 'ON TIME')
                : (const Color(0xFFFDEBD2), const Color(0xFFB26A00), 'PARTIAL'))
            : (
                const Color(0xFFFDEBD2),
                const Color(0xFFB26A00),
                unit == 'Week'
                    ? weeksLateWording(r.lateDays).toUpperCase()
                    : '${r.lateDays} DAY${r.lateDays == 1 ? '' : 'S'} LATE'
              ))
        : r.due.isAfter(today)
            ? (
                blueSoftOf(context),
                kBlue,
                r.due.difference(today).inDays <= 7 ? 'NEXT WEEK' : 'UPCOMING'
              )
            : r.due == today
                ? (kGold.withValues(alpha: .18), kGoldDark, 'DUE TODAY')
                : (
                    redSoftOf(context),
                    kRed,
                    'DUE ${today.difference(r.due).inDays} '
                        'DAY${today.difference(r.due).inDays == 1 ? '' : 'S'} AGO'
                  );
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
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: inkOf(context))),
                const SizedBox(height: 2),
                Text(
                    'Due ${fmtDate(r.due.toIso8601String())} | '
                    'Paid ${r.paid == null ? '—' : fmtDate(r.paid!.toIso8601String())}',
                    style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
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
                        'Received ₹${moneyWholeDown(r.paidAmount)} of '
                        '₹${moneyWholeDown(r.amount)}',
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
              Text('₹${moneyWholeDown(r.amount)}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: inkOf(context))),
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(6)),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w800, color: fg)),
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
          const Icon(Icons.change_history, color: Color(0xFFE7D48B), size: 20),
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
                // Three components, exactly as entered: previous rolled +
                // fresh cash given now + new interest = new obligation.
                Text(
                    'Prev ₹${moneyWholeDown(r.refinancePrevOut)} + '
                    'Fresh ₹${moneyWholeDown(r.refinanceFresh)} + '
                    'Int ₹${moneyWholeDown(r.paidAmount)}',
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
          Text('₹${moneyWholeDown(r.amount + r.paidAmount)}',
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
    required this.refinancePrevOut,
    required this.refinanceFresh,
  }) : refinanceNote = null;

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

  /// Refinance breakdown: previous outstanding rolled + fresh cash given now.
  /// New obligation = prevOut + fresh + interest (in paidAmount).
  final double refinancePrevOut;
  final double refinanceFresh;

  const _SchedRow.withRefinance({
    required this.due,
    required this.amount,
    required this.paidAmount,
    required this.refinancePrevOut,
    required this.refinanceFresh,
    required this.index,
    this.refinanceNote,
  })  : paid = null,
        lateDays = 0,
        refinance = true;
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
