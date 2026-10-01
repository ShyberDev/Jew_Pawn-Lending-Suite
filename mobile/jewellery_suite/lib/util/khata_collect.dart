import 'format.dart';
import 'khata_alloc.dart';
import 'khata_loan_state.dart';
import 'khata_schedule.dart';

/// What one payment did, in a form a screen can render and a test can assert.
/// What one payment did, in a form a screen can render and a test can assert.
class Outcome {
  final KhataLoanState before;
  final KhataLoanState after;

  /// Per installment number, how much landed there.
  final Map<int, Allocation> perInstallment;

  /// Instalments left fully settled, for the schedule's green blocks.
  final Map<int, double> remainingByInstallment;
  final Map<int, double> scheduledByInstallment;

  /// Money past every obligation, held as credit.
  final double unapplied;

  const Outcome({
    required this.before,
    required this.after,
    required this.perInstallment,
    required this.remainingByInstallment,
    required this.scheduledByInstallment,
    required this.unapplied,
  });

  double get collected => Num.money(after.principalRecovered);

  int get paidInstallments =>
      remainingByInstallment.entries.where((e) => e.value <= 0).length;
}

/// The single writer for a khatabook payment.
///
/// This exists because the same payment was once recorded by two independent
/// code paths — the book screen went through the allocation engine and the
/// customer profile did not — so a collection made from the profile silently
/// failed to reduce principal. One writer removes that whole class of bug.
///
/// ## Per-installment interest
///
/// Each installment carries **its own share of the interest**, not the loan's
/// interest applied in one step at the end. That is what makes the schedule
/// honest: collecting ₹2,000 clears one week's obligation and shows one green
/// block, because that is genuinely what the money paid for. Loan-level
/// interest would paint week 1 "on time" while the money really covered three
/// weeks.
class KhataCollect {
  const KhataCollect._();

  /// Builds the per-installment obligations for a loan.
  ///
  /// ## Interest is a LOAN-LEVEL obligation, not a per-installment one
  ///
  /// Khatabook interest is **fixed**: charged once on the agreed principal for
  /// the whole agreed term. It is therefore one ₹2,000 obligation on the loan,
  /// settled before any principal — not six ₹333 weekly charges.
  ///
  /// That distinction is load-bearing. Splitting the interest across
  /// installments would make a ₹2,000 payment settle ₹333 of interest and
  /// ₹1,666 of **principal**, which would wrongly shrink the shop's capital
  /// deployed for money that only ever paid interest.
  ///
  /// Principal is what amortises: ₹10,000 across the schedule, each installment
  /// recovering its own share, so a block turns green only when that week's
  /// principal has actually come back.
  static List<Obligation> obligationsFor({
    required double principalAmount,
    required int count,
    required DateTime start,
    required String frequency,
    required double principalAlreadyRecovered,
  }) {
    final n = count <= 0 ? 1 : count;
    final schedule = KhataSchedule.generate(
      start: start,
      frequency: frequency,
      count: n,
      expectedRepayment: principalAmount,
    );
    final recoveredPaise = (principalAlreadyRecovered * 100).round();

    final rows = <Obligation>[];
    var recoveredHanded = 0;

    for (final row in schedule) {
      final scheduledPaise = (row.scheduledAmount * 100).round();
      // Oldest principal is recovered first.
      final settledPaise =
          (recoveredPaise - recoveredHanded).clamp(0, scheduledPaise);
      recoveredHanded += settledPaise;

      rows.add(Obligation(
        installmentNumber: row.installmentNumber,
        dueDate: row.dueDate,
        scheduledAmount: row.scheduledAmount,
        remainingAmount: (scheduledPaise - settledPaise) / 100.0,
        // Interest is NOT carried per installment — see the note above.
        interestDue: 0,
      ));
    }
    return rows;
  }

  /// Allocates [payment] across a loan's installments and returns the new state.
  ///
  /// Pure: it performs no I/O, so the whole rule is testable without a database.
  static Outcome allocate({
    required double payment,
    required List<Obligation> obligations,
    required DateTime today,
    required KhataLoanState before,
    double lateFeeDue = 0,
    double otherChargeDue = 0,
  }) {
    // LEVEL 1 for interest: the fixed interest is ONE loan-level obligation and
    // has priority over every installment, so it is settled before any
    // principal is touched.
    var left = Num.money(payment);
    final interestOwed = before.interestOutstanding;
    final interest =
        left < interestOwed ? left : interestOwed;
    left = Num.money(left - interest);

    // Fees sit between interest and principal.
    var lateFee = 0.0, otherCharge = 0.0;
    if (left > 0 && lateFeeDue > 0) {
      lateFee = left < lateFeeDue ? left : lateFeeDue;
      left = Num.money(left - lateFee);
    }
    if (left > 0 && otherChargeDue > 0) {
      otherCharge = left < otherChargeDue ? left : otherChargeDue;
      left = Num.money(left - otherCharge);
    }

    // Principal then goes to the installments, oldest first.
    final cascade = KhataAlloc.allocateAcross(
      payment: left,
      obligations: obligations,
      today: today,
    );
    final principal = cascade.totalPrincipal;
    left = Num.money(left - principal);

    final after = before
        .copyWith(
          principalRecovered: Num.money(before.principalRecovered + principal),
          interestOutstanding: Num.money(before.interestOutstanding - interest),
          lateFeeOutstanding: Num.money(before.lateFeeOutstanding - lateFee),
          otherChargeOutstanding:
              Num.money(before.otherChargeOutstanding - otherCharge),
          unappliedCredit: Num.money(before.unappliedCredit + left),
        )
        .withSettledStatus();

    // Each installment simply keeps what it started with, less what landed on
    // it — so a block goes green exactly when its own balance reaches zero.
    final remaining = <int, double>{};
    final scheduled = <int, double>{};
    for (final o in obligations) {
      scheduled[o.installmentNumber] = o.scheduledAmount;
      final allocated = cascade.perObligation[o.installmentNumber];
      remaining[o.installmentNumber] =
          Num.money(o.remainingAmount - (allocated?.total ?? 0));
    }

    return Outcome(
      before: before,
      after: after,
      perInstallment: cascade.perObligation,
      remainingByInstallment: remaining,
      scheduledByInstallment: scheduled,
      unapplied: left,
    );
  }
}
