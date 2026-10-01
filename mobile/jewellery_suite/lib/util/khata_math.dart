import 'format.dart';

/// Khatabook (passbook) money rules, in one place.
///
/// Khata figures were previously derived independently in the book screen, the
/// customer profile and the ledger. Nothing enforced that they agreed, and a
/// refinance once made the profile's running balance disagree with the loan's
/// own figure. These functions are the single definition, mirroring how
/// `pawn_math.dart` already works for pawn, so a future server can be made to
/// agree with one place rather than three.
///
/// Conventions, matching the pawn side: rupees, percentages, a **30-day
/// month**, and `Num.money` (2 dp, half-up) applied once to a result rather
/// than to intermediate steps.
class KhataMath {
  const KhataMath._();

  /// Days between collections for each frequency.
  static const stepDays = <String, int>{
    'Weekly': 7,
    'Biweekly': 14,
    'Monthly': 30,
  };

  /// Interval in days for [frequency], defaulting to monthly.
  static int interval(String frequency) => stepDays[frequency] ?? 30;

  /// `total_payable / installment_count`, truncated to whole rupees.
  ///
  /// KHATA-ONLY truncation rule: paise are dropped, and the final installment
  /// absorbs the remainder (₹10,000 ÷ 3 → 3333 + 3333 + 3334), so nothing is
  /// lost. This deliberately reverses the old ceiling; pawn keeps its own.
  static double installment(double totalPayable, int count) {
    if (count <= 0) return 0;
    return ((totalPayable * 100).truncate() ~/ count) / 100.0;
  }

  /// Installments actually covered by [collected].
  ///
  /// Deliberately **not** `ceil`: a ₹100 part-payment on a ₹1,000 weekly loan
  /// counts as zero paid, so it cannot mark the week "Paid / On time" and push
  /// the next due date a whole week. Clamped so an overpayment cannot report
  /// more installments than the loan has.
  static int paidInstallments({
    required double collected,
    required double totalPayable,
    required int count,
  }) {
    if (count <= 0 || totalPayable <= 0) return 0;
    final per = installment(totalPayable, count);
    if (per <= 0) return 0;
    final n = (Num.money(collected) / per).floor();
    return n.clamp(0, count);
  }

  /// Adds a payment to the collected total, rounded once.
  ///
  /// The stored total is the authority — it is **not** recomputed from a list of
  /// collection rows. Not every rupee collected is guaranteed to have its own
  /// row: creating a loan seeds a collected figure directly, and older rows
  /// predate the ledger. Summing the rows therefore discards those earlier
  /// payments and the balance jumps back UP after collecting, which is worse
  /// than any rounding question.
  ///
  /// [totalPayable] is accepted only so this stays a single place that knows
  /// the ceiling: a payment can never push the collected total past what the
  /// loan was for.
  static double addToCollected({
    required double already,
    required double payment,
    required double totalPayable,
  }) {
    final sum = Num.money(already + payment);
    if (totalPayable > 0 && sum > totalPayable) return Num.money(totalPayable);
    return sum < 0 ? 0 : sum;
  }

  /// Outstanding on a loan: what is still owed, never negative.
  ///
  /// Overpayments are clamped to 0 rather than rejected — the money was taken,
  /// so the balance is settled and any excess is the shop's problem to handle,
  /// not an error to throw away.
  static double outstanding(double totalPayable, double collected) {
    final out = Num.money(totalPayable - collected);
    return out < 0 ? 0 : out;
  }

  /// Loan status from the balance: settled only at exactly zero.
  static String status(double outstanding) =>
      outstanding <= 0 ? 'Closed' : 'Active';

  /// Sum of collection amounts, rounded once.
  static double sumAmounts(Iterable<Object?> amounts) =>
      Num.money(amounts.fold<double>(0, (s, a) => s + Num.toDouble(a)));

  /// Builds the stored columns of a khata loan from its collections.
  ///
  /// The one function the book screen and the customer profile must both call,
  /// so the figures a member sees, a profile shows and a report prints cannot
  /// drift apart.
  static KhataTotals totals({
    required double totalPayable,
    required Iterable<Object?> collections,
    required int installmentCount,
  }) {
    final collected = sumAmounts(collections);
    final out = outstanding(totalPayable, collected);
    return KhataTotals(
      collected: collected,
      outstanding: out,
      paidInstallments: paidInstallments(
        collected: collected,
        totalPayable: totalPayable,
        count: installmentCount,
      ),
      status: status(out),
    );
  }
}

/// The three derived columns of a khata loan, always produced together.
class KhataTotals {
  final double collected;
  final double outstanding;
  final int paidInstallments;
  final String status;

  const KhataTotals({
    required this.collected,
    required this.outstanding,
    required this.paidInstallments,
    required this.status,
  });

  /// The columns to write back to `khatabook_loans`.
  Map<String, Object?> toRow() => {
        'total_collected': collected,
        'outstanding': outstanding,
        'paid_installments': paidInstallments,
        'status': status,
      };

  @override
  String toString() => 'KhataTotals(collected: $collected, '
      'outstanding: $outstanding, paid: $paidInstallments, status: $status)';
}
