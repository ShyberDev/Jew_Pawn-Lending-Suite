import 'format.dart';

/// One scheduled obligation (an installment, or the loan-level balance) and
/// what is still owed on it.
///
/// Part of the canonical khata allocation engine. This is **khata only** —
/// pawn is a different product with a different interest model and must never
/// share this code.
class Obligation {
  final int installmentNumber;
  final DateTime dueDate;

  /// What was originally scheduled. Never rewritten by a payment.
  final double scheduledAmount;

  /// What is still owed on this obligation.
  final double remainingAmount;

  /// Interest accrued on this obligation, and any fees charged to it.
  final double interestDue;
  final double lateFeeDue;
  final double otherChargeDue;

  /// Everything this obligation still owes.
  double get owed =>
      remainingAmount + interestDue + lateFeeDue + otherChargeDue;

  Obligation({
    required this.installmentNumber,
    required DateTime dueDate,
    required this.scheduledAmount,
    required this.remainingAmount,
    this.interestDue = 0,
    this.lateFeeDue = 0,
    this.otherChargeDue = 0,
  }) : dueDate = DateTime(dueDate.year, dueDate.month, dueDate.day);

  @override
  String toString() => 'Obligation #$installmentNumber due $dueDate, '
      'owed ${owed.toStringAsFixed(2)}';
}

/// The outcome of allocating a payment against one set of dues.
class Allocation {
  final double interest;
  final double lateFee;
  final double otherCharge;
  final double principal;
  final double unapplied;

  final double interestRemaining;
  final double lateFeeRemaining;
  final double otherChargeRemaining;
  final double principalRemaining;

  const Allocation({
    required this.interest,
    required this.lateFee,
    required this.otherCharge,
    required this.principal,
    required this.unapplied,
    required this.interestRemaining,
    required this.lateFeeRemaining,
    required this.otherChargeRemaining,
    required this.principalRemaining,
  });

  /// Everything the payment was split into, excluding unapplied credit.
  ///
  /// A plain sum, deliberately **not** `Num.money`: each component is already
  /// an exact paise value, so re-applying the money ceiling to the total could
  /// inflate it by a paisa and manufacture money out of a sum.
  double get total => interest + lateFee + otherCharge + principal;

  /// Principal actually recovered — what reduces the shop's capital deployed.
  double get principalRecovered => principal;

  /// Nothing is owed any more, even if there is surplus credit.
  bool get fullySettled =>
      interestRemaining == 0 &&
      lateFeeRemaining == 0 &&
      otherChargeRemaining == 0 &&
      principalRemaining == 0;
}

/// The outcome of allocating a payment across several obligations.
class CascadeResult {
  final Map<int, Allocation> perObligation;
  final double unapplied;

  const CascadeResult(this.perObligation, this.unapplied);

  /// Summed in whole paise, never as a float fold with the money ceiling —
  /// adding 2-dp doubles and then ceilinging can inflate the total by a paisa,
  /// which would manufacture principal recovery that never happened.
  double get totalInterest =>
      perObligation.values.fold<int>(0, (s, a) => s + (a.interest * 100).round()) /
      100.0;

  double get totalPrincipal =>
      perObligation.values.fold<int>(0, (s, a) => s + (a.principal * 100).round()) /
      100.0;

  /// The same obligations with every balance reduced by what was allocated.
  Map<int, Obligation> remainingBalances(Map<int, Obligation> before) {
    final out = <int, Obligation>{};
    before.forEach((n, o) {
      final a = perObligation[n];
      if (a == null) {
        out[n] = o;
        return;
      }
      out[n] = Obligation(
        installmentNumber: n,
        dueDate: o.dueDate,
        scheduledAmount: o.scheduledAmount,
        remainingAmount: Num.money(o.remainingAmount - a.total),
        interestDue: a.interestRemaining,
        lateFeeDue: a.lateFeeRemaining,
        otherChargeDue: a.otherChargeRemaining,
      );
    });
    return out;
  }
}

/// Khatabook payment allocation — the canonical engine, implemented from the
/// specification's acceptance criteria (AC-001 … AC-025).
///
/// Pure functions with no database and no UI, so every rule can be tested
/// exhaustively before a single row is written.
///
/// ## Two levels of priority
///
/// The specification is explicit that these are two separate concepts and must
/// not be mixed:
///
/// 1. **Obligation priority** — which installment receives the money:
///    `OVERDUE → CURRENT DUE → FUTURE SCHEDULED`, earliest `due_date` first.
/// 2. **Component priority** — within that obligation:
///    `INTEREST → LATE_FEE → OTHER_CHARGE → PRINCIPAL`.
///
/// ## The rule that matters most
///
/// Principal is never reduced while anything of higher priority is unpaid. A
/// ₹400 payment against ₹600 of interest recovers **zero** principal, so the
/// capital the shop has deployed does not appear to shrink when in fact no
/// capital came back.
///
/// ## Money
///
/// Rupees, and every allocation sums to exactly the payment. Rounding is
/// `Num.money` (ceiling to 2 dp) applied to each component, so nothing is
/// created or lost.
class KhataAlloc {
  const KhataAlloc._();

  /// The four components an obligation can carry, in the order money is applied.
  static const componentOrder = [
    'INTEREST',
    'LATE_FEE',
    'OTHER_CHARGE',
    'PRINCIPAL',
  ];

  /// Allocates [payment] against a single set of dues, interest first.
  ///
  /// Throws [ArgumentError] for a negative payment or negative dues (AC-009) —
  /// a negative amount must never silently allocate backwards.
  ///
  /// ## Why this works in whole paise
  ///
  /// All the arithmetic is done in **integer paise** and only converted back to
  /// rupees at the very end. Doing it in floating point with the money ceiling
  /// was a real defect: each intermediate `left = money(left - take)` rounds a
  /// binary-float subtraction *up*, so a ₹1,234.57 payment against four dues
  /// came to ₹1,234.61 — four paise that never existed. Integers cannot drift,
  /// so `allocated + unapplied` is always exactly the payment.
  static Allocation allocate({
    required double payment,
    required double interestDue,
    required double lateFeeDue,
    required double otherChargeDue,
    required double principalDue,
  }) {
    if (payment < 0) {
      throw ArgumentError.value(payment, 'payment', 'must not be negative');
    }
    final dues = <String, double>{
      'interest': interestDue,
      'lateFee': lateFeeDue,
      'otherCharge': otherChargeDue,
      'principal': principalDue,
    };
    for (final e in dues.entries) {
      if (e.value < 0) {
        throw ArgumentError.value(e.value, e.key, 'must not be negative');
      }
    }

    var left = _paise(payment);
    final due = <String, int>{
      for (final e in dues.entries) e.key: _paise(e.value),
    };
    final took = <String, int>{};

    for (final name in componentOrder.map(_key)) {
      final owed = due[name]!;
      if (owed <= 0) {
        took[name] = 0;
        continue;
      }
      final take = left < owed ? left : owed;
      took[name] = take;
      left -= take; // exact: integers, so nothing drifts
    }

    return Allocation(
      interest: _rupees(took['interest']!),
      lateFee: _rupees(took['lateFee']!),
      otherCharge: _rupees(took['otherCharge']!),
      principal: _rupees(took['principal']!),
      // Surplus is credit held against the customer, never a negative balance.
      unapplied: _rupees(left < 0 ? 0 : left),
      interestRemaining: _rupees(due['interest']! - took['interest']!),
      lateFeeRemaining: _rupees(due['lateFee']! - took['lateFee']!),
      otherChargeRemaining: _rupees(due['otherCharge']! - took['otherCharge']!),
      principalRemaining: _rupees(due['principal']! - took['principal']!),
    );
  }

  /// Rupees to whole paise, rounding half-up. Dues and payments are stored
  /// money (already 2 dp), so this is lossless in practice.
  static int _paise(double rupees) => (rupees * 100).round();

  static double _rupees(int paise) => paise / 100.0;

  /// Allocates [payment] across [obligations] in obligation-priority order:
  /// overdue, then current, then future, earliest due date first within each.
  ///
  /// Money carries to the next obligation only once this one is fully settled.
  /// A part-payment does **not** cascade — the shortfall stays put, so a short
  /// week is never silently forgiven by the next one (AC-016).
  static CascadeResult allocateAcross({
    required double payment,
    required List<Obligation> obligations,
    required DateTime today,
  }) {
    if (payment < 0) {
      throw ArgumentError.value(payment, 'payment', 'must not be negative');
    }
    final per = <int, Allocation>{};
    var left = _paise(payment);

    for (final o in obligationOrder(obligations, today: today)) {
      if (left <= 0) break;
      final owed = _paise(o.owed);
      if (owed <= 0) continue;

      // Cap the payment at what this obligation owes, so any surplus carries on
      // to the next one instead of being stranded as credit here.
      final here = left < owed ? left : owed;
      per[o.installmentNumber] = allocate(
        payment: _rupees(here),
        interestDue: o.interestDue,
        lateFeeDue: o.lateFeeDue,
        otherChargeDue: o.otherChargeDue,
        principalDue: o.remainingAmount,
      );
      left -= here; // exact in paise
    }

    return CascadeResult(per, _rupees(left < 0 ? 0 : left));
  }

  /// Obligations in the order money must reach them: OVERDUE, then CURRENT DUE,
  /// then FUTURE SCHEDULED; earliest due date first inside each group.
  /// Obligations with nothing owed are dropped.
  static List<Obligation> obligationOrder(
    List<Obligation> obligations, {
    required DateTime today,
  }) {
    final day = DateTime(today.year, today.month, today.day);
    int bucket(Obligation o) {
      if (o.dueDate.isBefore(day)) return 0; // overdue
      if (o.dueDate == day) return 1; // current
      return 2; // future
    }

    final open = obligations.where((o) => o.owed > 0).toList();
    open.sort((a, b) {
      final ba = bucket(a), bb = bucket(b);
      if (ba != bb) return ba - bb;
      final byDate = a.dueDate.compareTo(b.dueDate);
      if (byDate != 0) return byDate;
      return a.installmentNumber.compareTo(b.installmentNumber);
    });
    return open;
  }

  static String _key(String component) => switch (component) {
        'INTEREST' => 'interest',
        'LATE_FEE' => 'lateFee',
        'OTHER_CHARGE' => 'otherCharge',
        _ => 'principal',
      };
}
