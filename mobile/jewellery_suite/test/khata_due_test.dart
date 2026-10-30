import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/features/khata/screens/khata_screen.dart'
    show LoanBucket, loanBucket, loanNextDue;

/// The shop's rule: owing money means DUE. A part-payment never clears it, and
/// only a reminder set in the customer profile changes what the row shows.
void main() {
  final today = DateTime(2026, 9, 28);

  Map<String, Object?> loan({
    double outstanding = 400,
    int paid = 0,
    int count = 4,
    String start = '2026-09-21',
    String freq = 'Weekly',
  }) =>
      {
        'outstanding': outstanding,
        'paid_installments': paid,
        'installment_count': count,
        'start_date': start,
        'collection_frequency': freq,
      };

  test('a part-payment keeps the member in the due list', () {
    // Owes 400 of 800 after paying 400 — still due, on the first instalment,
    // which falls one interval after the start (21 Sep -> 28 Sep).
    final due = loanNextDue(loan(), today);
    expect(due, isNotNull);
    expect(due, DateTime(2026, 9, 28));
  });

  test('nothing owed means no due date', () {
    expect(loanNextDue(loan(outstanding: 0, paid: 4), today), isNull);
    expect(loanBucket(loan(outstanding: 0, paid: 4), today),
        LoanBucket.onSchedule);
  });

  test('a finished schedule with money still out is due today', () {
    // All instalments counted as paid but a balance remains -> chase it now.
    final due = loanNextDue(loan(outstanding: 500, paid: 4, count: 4), today);
    expect(due, DateTime(2026, 9, 28));
    expect(loanBucket(loan(outstanding: 500, paid: 4, count: 4), today),
        LoanBucket.dueToday);
  });

  test('due dates move forward with each instalment paid', () {
    expect(loanNextDue(loan(outstanding: 800, paid: 1), today),
        DateTime(2026, 10, 5));
    expect(loanNextDue(loan(outstanding: 800, paid: 2), today),
        DateTime(2026, 10, 12));
  });

  test('yesterday is overdue, a future date is upcoming', () {
    // Started two weeks ago, first instalment (21 Sep) not yet paid -> late.
    expect(loanBucket(loan(outstanding: 400, start: '2026-09-14'), today),
        LoanBucket.overdue);
    expect(loanNextDue(loan(outstanding: 400, start: '2026-09-14'), today),
        DateTime(2026, 9, 21));

    // Starts today, first instalment due exactly a week out -> upcoming.
    expect(loanBucket(loan(outstanding: 400, start: '2026-09-28'), today),
        LoanBucket.upcoming);
    expect(loanNextDue(loan(outstanding: 400, start: '2026-09-28'), today),
        DateTime(2026, 10, 5));
  });
}
