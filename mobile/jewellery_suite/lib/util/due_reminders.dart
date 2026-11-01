import 'format.dart';
import 'khata_schedule.dart';

/// Who is due today, and by how much — the arithmetic behind the due reminders
/// (#040).
///
/// This is a **pure** function of the loan rows and "today": no database, no
/// plugin, no clock. That is deliberate — the notification itself needs an
/// Android channel and permission, which cannot run under `flutter test`, but
/// the question "who should we remind about, and for how much" must be
/// testable.
///
/// Rules, matching the rest of the app:
///
/// * only **active** khata loans count (`isActiveKhataStatus`), so a settled,
///   cancelled or refinanced loan never produces a reminder;
/// * the amount is what is **collectable today**, not the whole outstanding —
///   the same `KhataSchedule.dueRemaining` rule the profile and Reports use, so
///   the notification can never disagree with the screen it opens;
/// * a loan is **overdue** when its earliest unpaid installment is in the past.
class DueReminder {
  const DueReminder({
    required this.loanUuid,
    required this.customerName,
    required this.dueNow,
    required this.overdueDays,
  });

  final String loanUuid;
  final String customerName;

  /// What should be collected today, including arrears. Never the outstanding.
  final double dueNow;

  /// Days past the earliest unpaid installment; 0 when it is due today or the
  /// schedule has no past installment.
  final int overdueDays;

  bool get overdue => overdueDays > 0;

  @override
  String toString() => '$customerName due ₹${dueNow.toStringAsFixed(2)}'
      '${overdue ? ' ($overdueDays d overdue)' : ''}';
}

/// Every member worth a reminder today, biggest debt first.
class DueReminderPlan {
  const DueReminderPlan(this.reminders);

  static const empty = DueReminderPlan(<DueReminder>[]);

  final List<DueReminder> reminders;

  bool get isEmpty => reminders.isEmpty;
  int get count => reminders.length;
  int get overdueCount => reminders.where((r) => r.overdue).length;

  double get totalDue => reminders.fold<double>(0, (sum, r) => sum + r.dueNow);

  /// "3 accounts due today" / "1 account overdue" — what the phone shows when
  /// the shade is pulled down.
  String get title {
    if (reminders.isEmpty) return 'No collections due';
    if (overdueCount == reminders.length) {
      return overdueCount == 1
          ? '1 account overdue'
          : '$overdueCount accounts overdue';
    }
    return count == 1 ? '1 account due today' : '$count accounts due today';
  }

  /// A short body listing the first few names — the details live in the app.
  String get body {
    if (reminders.isEmpty) return 'Nothing to collect today.';
    final head = reminders.take(3).map((r) {
      final tag = r.overdue ? ' (${r.overdueDays} d late)' : '';
      return '${r.customerName} ₹${moneyWhole(r.dueNow)}$tag';
    }).join(' · ');
    final rest = reminders.length > 3 ? ' · +${reminders.length - 3} more' : '';
    return '$head$rest — total ₹${moneyWhole(totalDue)}';
  }
}

/// Builds the reminder plan from raw `khatabook_loans` rows.
///
/// [today] is passed in rather than read from the clock so the result is
/// reproducible in tests and identical for every member on a given day.
DueReminderPlan planDueReminders({
  required List<Map<String, Object?>> loans,
  required DateTime today,
}) {
  final day = DateTime(today.year, today.month, today.day);
  final out = <DueReminder>[];

  for (final loan in loans) {
    if (!isActiveKhataStatus(loan['status'])) continue;
    final uuid = loan['client_uuid']?.toString() ?? '';
    if (uuid.isEmpty) continue;

    final totalPayable = Num.toDouble(loan['total_payable']);
    final collected = Num.toDouble(loan['total_collected']);
    final count = (loan['installment_count'] as num?)?.toInt() ?? 0;
    final frequency = loan['collection_frequency']?.toString() ?? 'Monthly';
    final start = parseIso(loan['start_date'] ?? loan['loan_date']);

    final rows = KhataSchedule.scheduleRemaining(
      expectedRepayment: totalPayable,
      collected: collected,
      count: count,
      start: start,
      frequency: frequency,
    );
    if (rows.isEmpty) continue;

    var duePaise = 0;
    DateTime? earliestUnpaid;
    for (final row in rows) {
      if (row.remainingPaise <= 0) continue;
      final due =
          DateTime(row.dueDate.year, row.dueDate.month, row.dueDate.day);
      if (!due.isAfter(day)) duePaise += row.remainingPaise;
      if (due.isBefore(day) &&
          (earliestUnpaid == null || due.isBefore(earliestUnpaid))) {
        earliestUnpaid = due;
      }
    }
    if (duePaise <= 0) continue;

    out.add(DueReminder(
      loanUuid: uuid,
      customerName: (loan['customer_name'] ?? 'Customer').toString(),
      dueNow: duePaise / 100.0,
      overdueDays:
          earliestUnpaid == null ? 0 : day.difference(earliestUnpaid).inDays,
    ));
  }

  out.sort((a, b) => b.dueNow.compareTo(a.dueNow));
  return DueReminderPlan(out);
}
