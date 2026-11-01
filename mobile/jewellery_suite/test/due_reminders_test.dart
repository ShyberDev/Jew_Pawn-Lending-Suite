import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/due_reminders.dart';

/// #040: the reminder arithmetic, without Android.
///
/// A notification that names the wrong member or the wrong amount is worse
/// than no notification, so the planning half is pinned here: who counts as
/// due, that the figure is collectable-today (never the outstanding), and that
/// closed loans stay silent.
void main() {
  Map<String, Object?> loan({
    String uuid = 'l1',
    String name = 'Ravi',
    String status = 'Active',
    String start = '2026-01-01',
    String frequency = 'Weekly',
    int count = 4,
    double total = 4000,
    double collected = 0,
  }) =>
      {
        'client_uuid': uuid,
        'customer_name': name,
        'status': status,
        'loan_date': start,
        'start_date': start,
        'collection_frequency': frequency,
        'installment_count': count,
        'total_payable': total,
        'total_collected': collected,
        'principal_amount': 3000.0,
        'interest_amount': 1000.0,
      };

  // Installments land on 8, 15, 22 and 29 January (weekly from 1 Jan).
  test('arrears plus the installment that has arrived are due today', () {
    final plan =
        planDueReminders(loans: [loan()], today: DateTime(2026, 1, 23));

    expect(plan.count, 1);
    expect(plan.reminders.first.dueNow, 3000,
        reason: '8, 15 and 22 Jan have arrived — 29 Jan has not');
    expect(plan.reminders.first.overdueDays, 15,
        reason: 'the earliest unpaid installment is 8 Jan, today is 23 Jan');
    expect(plan.reminders.first.overdue, isTrue);
    expect(plan.totalDue, 3000);
    expect(plan.overdueCount, 1);
    expect(plan.title, '1 account overdue');
    expect(plan.body, contains('Ravi'));
  });

  test('collections are applied oldest-first, so only the arrears remain', () {
    final plan = planDueReminders(
        loans: [loan(collected: 2000)], today: DateTime(2026, 1, 23));

    expect(plan.count, 1);
    expect(plan.reminders.first.dueNow, 1000,
        reason:
            '8 and 15 Jan are paid, 22 Jan is the only arrived installment');
    expect(plan.reminders.first.overdueDays, 1);
  });

  test('a loan with nothing due today is not reminded', () {
    // 1 January: the first installment is a week away.
    final plan = planDueReminders(loans: [loan()], today: DateTime(2026, 1, 1));
    expect(plan.isEmpty, isTrue);
    expect(plan.title, 'No collections due');
  });

  test('settled, cancelled and refinanced loans stay silent', () {
    for (final status in const [
      'Completed',
      'CANCELLED',
      'Refinanced',
      'Settled'
    ]) {
      final plan = planDueReminders(
        loans: [loan(uuid: 'x', status: status)],
        today: DateTime(2026, 1, 23),
      );
      expect(plan.isEmpty, isTrue, reason: '$status must not be reminded');
    }
  });

  test('a fully collected loan is not reminded', () {
    final plan = planDueReminders(
        loans: [loan(collected: 4000)], today: DateTime(2026, 1, 30));
    expect(plan.isEmpty, isTrue);
  });

  test('a loan without a usable schedule is skipped, not guessed', () {
    final noCount =
        planDueReminders(loans: [loan(count: 0)], today: DateTime(2026, 1, 23));
    expect(noCount.isEmpty, isTrue);

    final noStart = planDueReminders(
        loans: [loan(start: '')], today: DateTime(2026, 1, 23));
    expect(noStart.isEmpty, isTrue);
  });

  test('the biggest debt leads and the body is capped for the shade', () {
    final plan = planDueReminders(
      loans: [
        loan(uuid: 'a', name: 'Ravi', total: 4000),
        loan(uuid: 'b', name: 'Suresh', total: 12000),
        loan(uuid: 'c', name: 'Arun', total: 8000),
        loan(uuid: 'd', name: 'Kumar', total: 6000),
      ],
      today: DateTime(2026, 1, 23),
    );

    expect(plan.count, 4);
    expect(plan.reminders.first.customerName, 'Suresh',
        reason: '₹9,000 due beats the smaller books');
    expect(plan.body, contains('+1 more'));
    expect(plan.title, '4 accounts overdue',
        reason: 'on 23 Jan every one of the four has an arrived installment');
  });
}
