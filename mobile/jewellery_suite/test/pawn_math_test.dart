import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/util/pawn_math.dart';

/// Money must be provably right. These tests are the shopkeeper's guarantee that
/// one label means one amount everywhere.
void main() {
  // A loan of 100,000 at 3%/month, first period interest already stored for
  // the 90-day first term, due date 90 days after the loan date.
  Map<String, Object?> loan({
    double principal = 100000,
    double storedInterest = 9000,
    double paid = 0,
    String? anchor,
    String? due,
  }) =>
      {
        'loan_amount': principal,
        'interest_accrued': storedInterest,
        'amount_paid': paid,
        'interest_rate': 3.0,
        'loan_date': '2026-01-01',
        'due_date': due ?? '2026-04-01',
        'last_interest_date': anchor,
        'status': 'Active',
      };

  test('interest accrues from the anchor, not from the loan date', () {
    final l = loan(anchor: '2026-04-01'); // due date reached, nothing paid yet
    // 30 days later at 3%/month on 100,000 = 3,000
    final due = PawnMath.interestDue(l, DateTime(2026, 5, 1));
    expect(due, 12000); // 9,000 stored + 3,000 fresh
  });

  test('fresh interest uses a 30-day month', () {
    final l = loan(anchor: '2026-04-01');
    expect(PawnMath.freshInterest(l, DateTime(2026, 4, 11)), 1000);
    expect(PawnMath.freshInterest(l, DateTime(2026, 5, 1)), 3000);
  });

  test('no interest before the anchor date', () {
    final l = loan(anchor: '2026-04-01');
    expect(PawnMath.freshInterest(l, DateTime(2026, 3, 1)), 0);
    expect(PawnMath.interestDue(l, DateTime(2026, 3, 20)), 9000);
  });

  test('outstanding = principal + interest due - received', () {
    final l = loan();
    // legacy loan: no last_interest_date -> anchor is the due date
    expect(PawnMath.outstanding(l, DateTime(2026, 4, 1)), 109000);
    final paid = loan(paid: 40000, anchor: '2026-04-01');
    expect(PawnMath.outstanding(paid, DateTime(2026, 4, 1)), 69000);
  });

  test('an idle loan keeps growing outstanding (the bug we fixed)', () {
    final l = loan(anchor: '2026-04-01');
    final april = PawnMath.outstanding(l, DateTime(2026, 4, 1));
    // 01-Apr to 01-Jul is 91 days = 3.03 thirty-day months, so the interest is
    // 100,000 x 3% x 91/30 = 9,100 (day-count from the anchor, not 90 days).
    final july = PawnMath.outstanding(l, DateTime(2026, 7, 1));
    expect(april, 109000);
    expect(july, 118100);
    expect(july, greaterThan(april));
  });

  test('a released loan is settled and never accrues', () {
    final l = {...loan(paid: 109000, anchor: '2026-04-01'), 'status': 'Released'};
    expect(PawnMath.isSettled(l, DateTime(2026, 9, 1)), isTrue);
    expect(PawnMath.outstanding(l, DateTime(2026, 9, 1)), 0);
  });

  test('totals sum the same per-loan figures the screens show', () {
    final loans = [
      loan(anchor: '2026-04-01'),
      loan(principal: 50000, storedInterest: 4500, paid: 10000,
          anchor: '2026-04-01'),
    ];
    final t = PawnMath.totals(loans, DateTime(2026, 4, 1));
    expect(t.investment, 150000);
    expect(t.interest, 13500);
    // 109,000 (first loan) + 44,500 (50,000 + 4,500 - 10,000 paid)
    expect(t.outstanding, 153500);
    expect(t.count, 2);
  });

  test('settled() writes back exactly what the screen showed', () {
    final l = loan(anchor: '2026-04-01');
    final s = PawnMath.settled(l, DateTime(2026, 5, 1));
    expect(s['interest_accrued'], 12000);
    expect(s['balance'], 112000);
    expect(s['last_interest_date'], '2026-05-01');
  });

  test('totals agree with per-loan outstanding (no double counting)', () {
    final loans = [
      loan(principal: 100000, storedInterest: 9000, paid: 50000,
          anchor: '2026-04-01'),
      loan(principal: 20000, storedInterest: 1800, paid: 0,
          anchor: '2026-04-01'),
    ];
    final t = PawnMath.totals(loans, DateTime(2026, 4, 11));
    var manual = 0.0;
    for (final l in loans) {
      manual += PawnMath.outstanding(l, DateTime(2026, 4, 11));
    }
    expect(t.outstanding, manual);
  });
}
