import 'format.dart';

/// Khatabook installment schedule generation and status rules.
///
/// Khata only — pawn has its own accrual model and shares none of this.
///
/// ## Calendar months
///
/// Monthly schedules use **calendar-month increments**, not a flat 30 days.
/// A schedule starting 31 January therefore lands on 28/29 February, 31 March,
/// 30 April and so on. Clamping to the last valid day of the month is what
/// keeps a schedule from drifting permanently earlier in the month.
/// `KhataMath.interval` still reports 30 for `Monthly` because that value is
/// used for interest *accrual*; schedule *dates* are computed here.
class KhataSchedule {
  const KhataSchedule._();

  static const frequencies = ['Weekly', 'Biweekly', 'Monthly'];

  /// The collection interval in days. `Monthly` returns 30 because that is the
  /// interest convention, not a date offset — use [dueDate] for scheduling.
  static int intervalDays(String frequency) => switch (frequency) {
        'Weekly' => 7,
        'Biweekly' => 14,
        'Monthly' => 30,
        _ => 30,
      };

  /// The due date of installment [n] (1-based) for a schedule that starts on
  /// [start] and repeats every [frequency].
  ///
  /// The first installment is due one full interval after the start: a loan
  /// given 30-09 weekly is first due 07-10, monthly 30-10. Collecting on day
  /// zero must never already show a due week.
  static DateTime dueDate(DateTime start, String frequency, int n) {
    final steps = n;
    return switch (frequency) {
      'Weekly' => start.add(Duration(days: 7 * steps)),
      'Biweekly' => start.add(Duration(days: 14 * steps)),
      'Monthly' => _addMonths(start, steps),
      _ => _addMonths(start, steps),
    };
  }

  /// Calendar-month addition, clamped to the last day of the target month so a
  /// 31st-of-the-month start does not skip a month.
  static DateTime _addMonths(DateTime start, int months) {
    final target = DateTime(start.year, start.month + months, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(
        target.year, target.month, start.day <= lastDay ? start.day : lastDay);
  }

  /// Generates the full schedule.
  ///
  /// The installments always sum to **exactly** [expectedRepayment]: the first
  /// `count - 1` get the even share and the final one absorbs the rounding
  /// remainder, so no paisa is created or lost. No payment is ever implied —
  /// every installment starts unpaid.
  static List<ScheduleRow> generate({
    required DateTime start,
    required String frequency,
    required int count,
    required double expectedRepayment,
  }) {
    if (count <= 0) {
      throw ArgumentError.value(count, 'count', 'must be at least 1');
    }
    if (expectedRepayment < 0) {
      throw ArgumentError.value(
          expectedRepayment, 'expectedRepayment', 'must not be negative');
    }

    final totalPaise = (expectedRepayment * 100).round();
    final evenPaise = count == 0 ? 0 : totalPaise ~/ count;

    final rows = <ScheduleRow>[];
    var handedOut = 0;
    for (var n = 1; n <= count; n++) {
      final isLast = n == count;
      final amount = isLast ? totalPaise - handedOut : evenPaise;
      handedOut += amount;
      rows.add(ScheduleRow(
        installmentNumber: n,
        dueDate: dueDate(start, frequency, n),
        scheduledAmount: amount / 100.0,
      ));
    }
    return rows;
  }

  /// Even per-installment share, for display before the schedule is built.
  static double installmentAmount(double expectedRepayment, int count) {
    if (count <= 0) return 0;
    return (expectedRepayment * 100).round() / count / 100.0;
  }

  /// What should actually be collected on a loan today: the remaining due on
  /// every installment whose date has arrived, including all arrears.
  ///
  /// Outstanding is NEVER the answer — a ₹12,000 balance with a ₹1,000 weekly
  /// due means ₹1,000 today, not ₹12,000. Collected money is applied
  /// oldest-first, so a part-payment leaves its remainder on its own
  /// installment and an advance quietly shrinks a future one (which stays
  /// invisible until its date arrives — future weeks are never pre-marked).
  ///
  /// Pure derivation from stored fields; nothing is written. A loan with no
  /// usable schedule (no start date or no count) falls back to its
  /// outstanding when it is due, preserving the old behavior for that edge.
  static double dueRemaining({
    required double expectedRepayment,
    required double collected,
    required int count,
    required DateTime? start,
    required String frequency,
    required DateTime today,
    double? fallbackOutstanding,
  }) {
    var duePaise = 0;
    for (final r in scheduleRemaining(
      expectedRepayment: expectedRepayment,
      collected: collected,
      count: count,
      start: start,
      frequency: frequency,
    )) {
      final dueDate = r.dueDate;
      final day = DateTime(today.year, today.month, today.day);
      if (r.remainingPaise > 0 &&
          !DateTime(dueDate.year, dueDate.month, dueDate.day).isAfter(day)) {
        duePaise += r.remainingPaise;
      }
    }
    if (duePaise == 0 && (start == null || count <= 0)) {
      return fallbackOutstanding ?? 0;
    }
    return duePaise / 100.0;
  }

  /// Every installment with its remaining paise after applying [collected]
  /// oldest-first. An advance quietly shrinks a future week without marking
  /// it paid. Empty when there is no usable schedule.
  static List<({DateTime dueDate, int remainingPaise})> scheduleRemaining({
    required double expectedRepayment,
    required double collected,
    required int count,
    required DateTime? start,
    required String frequency,
  }) {
    if (start == null || count <= 0) return const [];
    final rows = generate(
      start: start,
      frequency: frequency,
      count: count,
      expectedRepayment: expectedRepayment,
    );
    var leftPaise = (collected * 100).round();
    final out = <({DateTime dueDate, int remainingPaise})>[];
    for (final row in rows) {
      final scheduledPaise = (row.scheduledAmount * 100).round();
      final paidPaise = leftPaise < scheduledPaise ? leftPaise : scheduledPaise;
      leftPaise -= paidPaise;
      out.add(
          (dueDate: row.dueDate, remainingPaise: scheduledPaise - paidPaise));
    }
    return out;
  }
}

/// One generated installment, before any payment touches it.
class ScheduleRow {
  final int installmentNumber;
  final DateTime dueDate;

  /// What is scheduled for this installment. Never rewritten by a payment.
  final double scheduledAmount;

  double paidAmount = 0;

  /// What is still owed here. A shortfall stays on its own installment.
  double remainingAmount = 0;

  InstallmentStatus status = InstallmentStatus.pending;

  ScheduleRow({
    required this.installmentNumber,
    required DateTime dueDate,
    required this.scheduledAmount,
  })  : dueDate = DateTime(dueDate.year, dueDate.month, dueDate.day),
        remainingAmount = scheduledAmount;

  /// Recomputes `remainingAmount` and `status` from the amounts paid.
  void settle() {
    paidAmount = Num.money(paidAmount);
    remainingAmount = Num.money(scheduledAmount - paidAmount);
    if (remainingAmount <= 0) {
      remainingAmount = 0;
      status = InstallmentStatus.paid;
    } else if (paidAmount > 0) {
      status = InstallmentStatus.partiallyPaid;
    } else {
      status = InstallmentStatus.pending;
    }
  }

  /// An unpaid installment whose date has passed is overdue. Called by the
  /// screens, never stored — otherwise "overdue" would be frozen in the past.
  InstallmentStatus statusOn(DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    if (status == InstallmentStatus.cancelled) return status;
    if (status == InstallmentStatus.paid) return status;
    if (remainingAmount > 0 && dueDate.isBefore(day)) {
      return InstallmentStatus.overdue;
    }
    return status;
  }

  @override
  String toString() => '#$installmentNumber $dueDate '
      'sched=${scheduledAmount.toStringAsFixed(2)} '
      'left=${remainingAmount.toStringAsFixed(2)}';
}

/// The five installment states.
enum InstallmentStatus {
  pending,
  partiallyPaid,
  paid,
  overdue,
  cancelled;

  static InstallmentStatus parse(String? raw) => switch (raw) {
        'PAID' => paid,
        'PARTIALLY_PAID' => partiallyPaid,
        'OVERDUE' => overdue,
        'CANCELLED' => cancelled,
        _ => pending,
      };

  String get wire => switch (this) {
        pending => 'PENDING',
        partiallyPaid => 'PARTIALLY_PAID',
        paid => 'PAID',
        overdue => 'OVERDUE',
        cancelled => 'CANCELLED',
      };
}

/// The seven transaction states, with their legal transitions.
enum LoanStatus {
  active,
  completed,
  settled,
  refinanced,
  writtenOff,
  defaulted,
  cancelled;

  static LoanStatus parse(String? raw) => switch (raw?.toUpperCase()) {
        'COMPLETED' => completed,
        // Legacy writer (KhataMath.status) stored 'Closed' for settled loans.
        'CLOSED' => completed,
        'SETTLED' => settled,
        'REFINANCED' => refinanced,
        'WRITTEN_OFF' => writtenOff,
        'DEFAULTED' => defaulted,
        'CANCELLED' => cancelled,
        _ => active,
      };

  String get wire => switch (this) {
        active => 'ACTIVE',
        completed => 'COMPLETED',
        settled => 'SETTLED',
        refinanced => 'REFINANCED',
        writtenOff => 'WRITTEN_OFF',
        defaulted => 'DEFAULTED',
        cancelled => 'CANCELLED',
      };

  /// Whether [to] is a legal move from this state.
  ///
  /// A settled loan may still be reopened (SETTLED → ACTIVE) because a customer
  /// can come back with more, but a defaulted or written-off loan can also be
  /// reinstated when the money is recovered. Illegal moves are refused rather
  /// than silently applied, so history stays trustworthy.
  bool canTransitionTo(LoanStatus to) {
    const allowed = <LoanStatus, Set<LoanStatus>>{
      LoanStatus.active: {
        LoanStatus.completed,
        LoanStatus.settled,
        LoanStatus.refinanced,
        LoanStatus.defaulted,
        LoanStatus.cancelled,
      },
      LoanStatus.completed: {
        LoanStatus.active,
        LoanStatus.settled,
        LoanStatus.refinanced,
        LoanStatus.writtenOff,
        LoanStatus.defaulted,
        LoanStatus.cancelled,
      },
      LoanStatus.refinanced: {
        LoanStatus.active,
        LoanStatus.completed,
        LoanStatus.settled,
        LoanStatus.writtenOff,
        LoanStatus.defaulted,
        LoanStatus.cancelled,
      },
      LoanStatus.settled: {
        LoanStatus.active,
        LoanStatus.completed,
        LoanStatus.refinanced,
        LoanStatus.writtenOff,
        LoanStatus.defaulted,
        LoanStatus.cancelled,
      },
      LoanStatus.writtenOff: {
        LoanStatus.active,
        LoanStatus.completed,
        LoanStatus.refinanced,
        LoanStatus.settled,
        LoanStatus.defaulted,
      },
      LoanStatus.defaulted: {
        LoanStatus.active,
        LoanStatus.completed,
        LoanStatus.refinanced,
        LoanStatus.settled,
        LoanStatus.writtenOff,
        LoanStatus.cancelled,
      },
      LoanStatus.cancelled: {},
    };
    return allowed[this]!.contains(to);
  }

  /// The money still owed. A written-off or defaulted loan keeps its arithmetic
  /// for the record; only reporting decides how to present it.
  bool get isOpen =>
      this != cancelled && this != writtenOff && this != refinanced;
}

/// True when a khatabook loan row counts as ACTIVE, regardless of which
/// vocabulary wrote its status column ('Active', 'ACTIVE', legacy 'Closed'
/// never counts — it always meant settled).
///
/// Every khata list, member total, dashboard figure and report must use this
/// instead of comparing the raw string, or loans written by one writer vanish
/// from screens owned by another.
bool isActiveKhataStatus(Object? raw) =>
    LoanStatus.parse(raw?.toString()) == LoanStatus.active;
