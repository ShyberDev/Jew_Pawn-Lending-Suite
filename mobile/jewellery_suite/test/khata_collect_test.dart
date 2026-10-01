import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/khata_alloc.dart';
import 'package:jewellery_suite/util/khata_collect.dart';
import 'package:jewellery_suite/util/khata_loan_state.dart';
import 'package:jewellery_suite/util/khata_schedule.dart';

/// The exact scenario the shopkeeper ran, which exposed the bug: a 10,000
/// principal + 2,000 interest loan, collected 2,000, then 5,000, then 1,000.
///
/// The load-bearing assertion is that the FIRST 2,000 recovers ZERO principal —
/// it pays interest, so no capital came back and Investment must not move. That
/// is the rule the old code broke.
void main() {
  final start = DateTime(2026, 9, 1);
  final today = DateTime(2026, 9, 29);

  KhataLoanState fresh() =>
      KhataLoanState.fresh(principal: 10000, interest: 2000);

  List<Obligation> obligationsFor({double recovered = 0}) =>
      KhataCollect.obligationsFor(
        principalAmount: 10000,
        count: 6,
        start: start,
        frequency: 'Weekly',
        principalAlreadyRecovered: recovered,
      );

  test('the schedule splits 10,000 of PRINCIPAL into six weekly blocks', () {
    final obs = obligationsFor();
    expect(obs.length, 6);
    // 1000000 paise ~/ 6 = 166666 paise each, remainder on last.
    expect(obs.first.scheduledAmount, 1666.66);
    final total =
        obs.fold<double>(0, (s, o) => s + o.scheduledAmount);
    expect((total * 100).round(), 1000000, reason: 'exactly 10,000');
  });

  test('interest is NOT carried per installment — it is one loan debt', () {
    // Khatabook interest is fixed: charged once for the whole term. Splitting
    // it weekly would make a 2,000 payment recover principal for money that
    // only ever paid interest.
    for (final o in obligationsFor()) {
      expect(o.interestDue, 0);
    }
  });

  group('the shopkeeper sequence', () {
    test('C1: paying 2,000 clears interest and recovers NO principal', () {
      final out = KhataCollect.allocate(
        payment: 2000,
        obligations: obligationsFor(),
        today: today,
        before: fresh(),
      );
      expect(out.after.principalRecovered, 0,
          reason: 'the money paid interest, so no capital came back');
      expect(out.after.investment, 10000,
          reason: 'Investment must NOT move on an interest-only payment');
      expect(out.after.interestOutstanding, 0);
      expect(out.after.outstandingBalance, 10000);
    });

    test('C1 clears NO block — the money all went to interest', () {
      final out = KhataCollect.allocate(
        payment: 2000,
        obligations: obligationsFor(),
        today: today,
        before: fresh(),
      );
      expect(out.paidInstallments, 0,
          reason: '2,000 cleared interest; no principal came back');
    });

    test('C2: 5,000 more recovers 5,000 of principal', () {
      final c1 = KhataCollect.allocate(
        payment: 2000,
        obligations: obligationsFor(),
        today: today,
        before: fresh(),
      );
      final out = KhataCollect.allocate(
        payment: 5000,
        obligations: obligationsFor(recovered: c1.after.principalRecovered),
        today: today,
        before: c1.after,
      );
      expect(out.after.principalRecovered, 5000);
      expect(out.after.investment, 5000);
      expect(out.after.outstandingBalance, 5000,
          reason: '12,000 payable minus 7,000 collected');
    });

    test('C3: 1,000 more leaves 4,000 invested and 4,000 owed', () {
      var state = fresh();
      var paid = 0.0;
      for (final amount in [2000.0, 5000.0, 1000.0]) {
        final out = KhataCollect.allocate(
          payment: amount,
          obligations: obligationsFor(recovered: paid),
          today: today,
          before: state,
        );
        state = out.after;
        paid += amount;
      }
      expect(paid, 8000);
      expect(state.principalRecovered, 6000);
      expect(state.investment, 4000);
      expect(state.outstandingBalance, 4000,
          reason: '12,000 payable minus 8,000 collected');
      expect(state.status, LoanStatus.active, reason: 'still owes money');
    });

    test('four blocks are paid after 8,000 collected, not six', () {
      var state = fresh();
      var paid = 0.0;
      for (final amount in [2000.0, 5000.0, 1000.0]) {
        final out = KhataCollect.allocate(
          payment: amount,
          obligations: obligationsFor(recovered: paid),
          today: today,
          before: state,
        );
        state = out.after;
        paid += amount;
        if (amount < 1000) continue;
      }
      final out = KhataCollect.allocate(
        payment: 0,
        obligations: obligationsFor(recovered: paid),
        today: today,
        before: state,
      );
      expect(out.paidInstallments, 4,
          reason: '8,000 of 12,000 is four weekly blocks');
    });

    test('a part-payment does NOT clear a block', () {
      // 600 clears the 600 of interest, leaving nothing for principal.
      final out = KhataCollect.allocate(
        payment: 600,
        obligations: obligationsFor(),
        today: today,
        before: fresh(),
      );
      expect(out.paidInstallments, 0);
      expect(out.after.investment, 10000);
    });

    test('once interest is clear, principal clears blocks', () {
      final interestClear = KhataCollect.allocate(
        payment: 2000,
        obligations: obligationsFor(),
        today: today,
        before: fresh(),
      );
      final out = KhataCollect.allocate(
        payment: 1666.67,
        obligations: obligationsFor(),
        today: today,
        before: interestClear.after,
      );
      expect(out.paidInstallments, 1,
          reason: 'one week of principal (1,666.67) is fully recovered');
    });

    test('paying 12,000 in full settles the loan', () {
      final out = KhataCollect.allocate(
        payment: 12000,
        obligations: obligationsFor(),
        today: today,
        before: fresh(),
      );
      expect(out.after.outstandingBalance, 0);
      expect(out.after.investment, 0);
      expect(out.after.status, LoanStatus.completed);
      expect(out.paidInstallments, 6);
    });
  });

  group('money is never invented', () {
    test('allocating the same payment twice in one row is idempotent-ish', () {
      final a = KhataCollect.allocate(
        payment: 2000,
        obligations: obligationsFor(),
        today: today,
        before: fresh(),
      );
      final b = KhataCollect.allocate(
        payment: 0,
        obligations: obligationsFor(recovered: 2000),
        today: today,
        before: a.after,
      );
      expect(b.after.investment, a.after.investment);
      expect(b.after.outstandingBalance, a.after.outstandingBalance);
    });

    test('an overpayment becomes credit, never a negative balance', () {
      final out = KhataCollect.allocate(
        payment: 15000,
        obligations: obligationsFor(),
        today: today,
        before: fresh(),
      );
      expect(out.after.outstandingBalance, 0);
      expect(out.after.investment, 0);
      expect(out.unapplied, 3000);
      expect(out.after.unappliedCredit, 3000);
    });
  });

  test('loan status never claims completion while money is owed', () {
    final out = KhataCollect.allocate(
      payment: 2000,
      obligations: obligationsFor(),
      today: today,
      before: fresh(),
    );
    expect(out.after.settled, isFalse);
    expect(out.after.toRow()['status'], 'ACTIVE');
  });
}
