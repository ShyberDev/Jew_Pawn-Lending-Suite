import 'format.dart';
import 'khata_alloc.dart';
import 'khata_schedule.dart';

/// The canonical khatabook loan state: component balances, derived investment,
/// and the allocation of a payment onto them.
///
/// This is the single place the specification's Investment vs Outstanding
/// Balance distinction is implemented, so Home, the khata list, the profile and
/// the reports cannot disagree.
///
/// * **Investment** = `Principal Outstanding` — the capital still deployed with
///   this customer. It *falls* as principal is recovered, which is the whole
///   point: the old figure summed original principal and could only rise.
/// * **Outstanding Balance** = principal outstanding + interest + fees. This is
///   what the customer owes.
///
/// Khata only. Pawn has its own model and never shares this code.
class KhataLoanState {
  final double originalPrincipal;
  final double principalRecovered;
  final double interestOutstanding;
  final double lateFeeOutstanding;
  final double otherChargeOutstanding;
  final double unappliedCredit;
  final LoanStatus status;

  const KhataLoanState({
    this.originalPrincipal = 0,
    this.principalRecovered = 0,
    this.interestOutstanding = 0,
    this.lateFeeOutstanding = 0,
    this.otherChargeOutstanding = 0,
    this.unappliedCredit = 0,
    this.status = LoanStatus.active,
  });

  /// Capital currently deployed — what the shop can call its own money.
  double get investment =>
      Num.money(originalPrincipal - principalRecovered).clamp(0, double.infinity);

  /// Everything the customer still owes, ignoring held credit.
  double get outstandingBalance => Num.money(
      investment + interestOutstanding + lateFeeOutstanding + otherChargeOutstanding);

  /// Outstanding less any credit already in hand — what is actually collectable.
  double get netOutstanding =>
      Num.money(outstandingBalance - unappliedCredit).clamp(0, double.infinity);

  /// How much of the original capital has come back, as a percentage.
  double get capitalRecoveryPercent {
    if (originalPrincipal <= 0) return 0;
    final pct = principalRecovered / originalPrincipal * 100;
    return pct < 0 ? 0 : (pct > 100 ? 100 : Num.roundPct(pct));
  }

  bool get settled => outstandingBalance <= 0;

  /// A copy that is COMPLETED once nothing is owed. Applied by the collector
  /// so a settled loan is never left showing as merely "closed".
  KhataLoanState withSettledStatus() =>
      outstandingBalance <= 0 && status == LoanStatus.active
          ? copyWith(status: LoanStatus.completed)
          : this;

  KhataLoanState copyWith({
    double? principalRecovered,
    double? interestOutstanding,
    double? lateFeeOutstanding,
    double? otherChargeOutstanding,
    double? unappliedCredit,
    LoanStatus? status,
  }) =>
      KhataLoanState(
        originalPrincipal: originalPrincipal,
        principalRecovered: principalRecovered ?? this.principalRecovered,
        interestOutstanding: interestOutstanding ?? this.interestOutstanding,
        lateFeeOutstanding: lateFeeOutstanding ?? this.lateFeeOutstanding,
        otherChargeOutstanding:
            otherChargeOutstanding ?? this.otherChargeOutstanding,
        unappliedCredit: unappliedCredit ?? this.unappliedCredit,
        status: status ?? this.status,
      );

  /// The columns this state owns on `khatabook_loans`.
  ///
  /// `status` is only advanced to COMPLETED when nothing is left owing — the
  /// application never claims a loan is closed while a balance remains.
  Map<String, Object?> toRow() {
    final out = outstandingBalance;
    return {
      'principal_recovered': Num.money(principalRecovered),
      'principal_outstanding': investment,
      'interest_outstanding': Num.money(interestOutstanding),
      'late_fee_outstanding': Num.money(lateFeeOutstanding),
      'other_charge_outstanding': Num.money(otherChargeOutstanding),
      'unapplied_credit': Num.money(unappliedCredit),
      'outstanding': out,
      'status': settled && status == LoanStatus.active
          ? LoanStatus.completed.wire
          : status.wire,
    };
  }

  /// Applies one allocation to this state.
  static KhataLoanState apply(
    KhataLoanState before,
    Allocation a, {
    LoanStatus? status,
  }) {
    final recovered = Num.money(before.principalRecovered + a.principal);
    final interest = Num.money(before.interestOutstanding - a.interest);
    final lateFee = Num.money(before.lateFeeOutstanding - a.lateFee);
    final other = Num.money(before.otherChargeOutstanding - a.otherCharge);
    final credit = Num.money(before.unappliedCredit + a.unapplied);

    final next = KhataLoanState(
      originalPrincipal: before.originalPrincipal,
      principalRecovered: recovered,
      interestOutstanding: interest < 0 ? 0 : interest,
      lateFeeOutstanding: lateFee < 0 ? 0 : lateFee,
      otherChargeOutstanding: other < 0 ? 0 : other,
      unappliedCredit: credit,
      status: status ?? before.status,
    );

    // Everything owed is gone -> the loan is completed, not merely "closed".
    if (next.outstandingBalance <= 0 && next.status == LoanStatus.active) {
      return next.copyWith(status: LoanStatus.completed);
    }
    return next;
  }

  /// Builds the starting state for a brand-new loan: nothing is recovered, the
  /// whole principal is deployed, and the whole interest is outstanding.
  factory KhataLoanState.fresh({
    required double principal,
    required double interest,
    double lateFee = 0,
    double otherCharge = 0,
    double interestCollected = 0,
  }) {
    return KhataLoanState(
      originalPrincipal: Num.money(principal),
      principalRecovered: 0,
      interestOutstanding:
          Num.money(interest - interestCollected).clamp(0, double.infinity),
      lateFeeOutstanding: Num.money(lateFee),
      otherChargeOutstanding: Num.money(otherCharge),
      status: LoanStatus.active,
    );
  }

  /// Reads a loan row written by any version of the app.
  ///
  /// A row from before v10 has no component columns, so principal recovery is
  /// unknown. It is treated as **zero** rather than guessed, which makes the
  /// Investment figure an upper bound instead of a fabrication.
  factory KhataLoanState.fromRow(Map<String, Object?> loan) {
    final principal = Num.toDouble(loan['principal_amount']);
    final storedOutstanding = loan['principal_outstanding'];
    return KhataLoanState(
      originalPrincipal: Num.toDouble(
          loan['original_principal'] ?? principal),
      principalRecovered: Num.toDouble(loan['principal_recovered']),
      // A pre-v10 row has no separate interest, so whatever is outstanding
      // beyond the principal is treated as interest.
      interestOutstanding: Num.toDouble(
          loan['interest_outstanding'] ?? Num.toDouble(loan['outstanding']) - (storedOutstanding != null ? Num.toDouble(storedOutstanding) : principal)),
      lateFeeOutstanding: Num.toDouble(loan['late_fee_outstanding']),
      otherChargeOutstanding: Num.toDouble(loan['other_charge_outstanding']),
      unappliedCredit: Num.toDouble(loan['unapplied_credit']),
      status: LoanStatus.parse('${loan['status'] ?? ''}'),
    );
  }
}
