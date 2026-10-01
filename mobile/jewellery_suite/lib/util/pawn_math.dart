import 'dart:math' as math;

import 'format.dart';

/// THE single place where pawn money is calculated.
///
/// Data model on `pawn_loans` (as written by every transaction):
///   * `loan_amount`  = principal still with the customer. It goes **down** when
///                      a payment clears principal and **up** on "Amount
///                      Requesting", so it is the principal outstanding.
///   * `interest_accrued` = interest already calculated and **not yet cleared**.
///   * `amount_paid`  = total received (principal + interest).
///   * `last_interest_date` = the day `interest_accrued` was last brought up to
///                      date (i.e. the day the accrual was "settled").
///
/// Interest runs with the calendar, so a stored column goes stale the moment
/// the next day starts. Every screen must therefore ask this class instead of
/// reading the stored numbers directly — that is what keeps one label meaning
/// exactly one amount everywhere in the app.
class PawnMath {
  /// The day the stored interest was last settled. Older loans have no
  /// `last_interest_date`, and their stored interest already runs up to the due
  /// date, so the due date is the correct fallback.
  static DateTime anchorOf(Map<String, Object?> loan) {
    final raw = loan['last_interest_date']?.toString().trim();
    final last = (raw == null || raw.isEmpty) ? null : DateTime.tryParse(raw);
    if (last != null) return last;
    final due = DateTime.tryParse(loan['due_date']?.toString() ?? '');
    if (due != null) return due;
    final lent = DateTime.tryParse(loan['loan_date']?.toString() ?? '');
    return lent ?? DateTime.now();
  }

  /// Principal still with the customer ("Investment" in pawn).
  static double principalOut(Map<String, Object?> loan) =>
      math.max(0, Num.toDouble(loan['loan_amount']));

  /// True when the loan has been released — a released loan can never accrue
  /// again and owes nothing.
  static bool isReleased(Map<String, Object?> loan) =>
      (loan['status']?.toString() ?? 'Active') == 'Released';

  /// Interest earned since the anchor date (30-day months, the rule the app has
  /// always used, ceiling to 2 decimals). A released loan accrues nothing.
  static double freshInterest(Map<String, Object?> loan, DateTime asOf) {
    if (isReleased(loan)) return 0;
    final days = asOf.difference(anchorOf(loan)).inDays;
    if (days <= 0) return 0;
    return Num.simpleInterest(
      principal: principalOut(loan),
      ratePerMonth: Num.toDouble(loan['interest_rate']),
      days: days,
    );
  }

  /// **Interest due** as of [asOf] = interest already calculated + interest
  /// earned since. This is what the shop has to collect.
  static double interestDue(Map<String, Object?> loan, [DateTime? asOf]) =>
      Num.money(Num.toDouble(loan['interest_accrued']) +
          freshInterest(loan, asOf ?? DateTime.now()));

  /// **Outstanding** = principal + interest due − received. This is the one and
  /// only outstanding figure the app shows (Home KPI, Pawn strip, Pawn
  /// dashboard, reports and the release screen all return this same number).
  static double outstanding(Map<String, Object?> loan, [DateTime? asOf]) {
    final v = principalOut(loan) +
        interestDue(loan, asOf) -
        Num.toDouble(loan['amount_paid']);
    return Num.money(math.max(0, v));
  }

  /// True when there is nothing left to collect.
  static bool isSettled(Map<String, Object?> loan, [DateTime? asOf]) =>
      outstanding(loan, asOf) <= 0.005;

  /// A copy of the loan with interest, total payable, balance and the accrual
  /// anchor brought up to [asOf]. Used before writing a payment or a release so
  /// the money stored is exactly the money the shopkeeper was shown.
  static Map<String, Object?> settled(
      Map<String, Object?> loan, DateTime asOf) {
    if (isReleased(loan)) return {...loan};
    final interest = interestDue(loan, asOf);
    final principal = principalOut(loan);
    return {
      ...loan,
      'interest_accrued': interest,
      'total_payable': Num.money(principal + interest),
      'balance': outstanding(loan, asOf),
      'last_interest_date': isoDate(asOf),
    };
  }

  /// Totals for a list of loans — the figures behind every pawn summary.
  static ({double investment, double interest, double outstanding, int count})
      totals(Iterable<Map<String, Object?>> loans, [DateTime? asOf]) {
    final when = asOf ?? DateTime.now();
    var investment = 0.0, interest = 0.0, out = 0.0, n = 0;
    for (final l in loans) {
      if (l.isEmpty) continue;
      investment += principalOut(l);
      interest += interestDue(l, when);
      out += outstanding(l, when);
      n++;
    }
    return (
      investment: Num.money(investment),
      interest: Num.money(interest),
      outstanding: Num.money(out),
      count: n,
    );
  }

  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
