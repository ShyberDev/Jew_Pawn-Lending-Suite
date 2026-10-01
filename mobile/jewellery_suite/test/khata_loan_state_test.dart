import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/format.dart';
import 'package:jewellery_suite/util/khata_alloc.dart';
import 'package:jewellery_suite/util/khata_loan_state.dart';
import 'package:jewellery_suite/util/khata_schedule.dart';

/// The Investment vs Outstanding Balance distinction — the defect this fixes.
///
/// Before: Home summed `SUM(principal_amount)`, the original principal, so
/// "Khata investment" could only ever rise and never meant capital deployed.
/// After: Investment is Principal Outstanding, which falls as principal comes
/// back.
void main() {
  KhataLoanState loan({
    double principal = 10000,
    double interest = 2000,
  }) =>
      KhataLoanState.fresh(principal: principal, interest: interest);

  Allocation pay(double amount, {double interestDue = 0, double principalDue = 0}) =>
      KhataAlloc.allocate(
        payment: amount,
        interestDue: interestDue,
        lateFeeDue: 0,
        otherChargeDue: 0,
        principalDue: principalDue,
      );

  group('investment is capital deployed, not original principal', () {
    test('a fresh loan has the whole principal deployed', () {
      expect(loan().investment, 10000);
    });

    test('paying only interest does NOT reduce investment', () {
      final s = KhataLoanState.apply(loan(), pay(2000, interestDue: 2000));
      expect(s.interestOutstanding, 0);
      expect(s.investment, 10000,
          reason: 'no capital came back, so none is recovered');
    });

    test('paying principal DOES reduce investment', () {
      final s = KhataLoanState.apply(
          loan(), pay(6000, interestDue: 2000, principalDue: 10000));
      expect(s.principalRecovered, 4000);
      expect(s.investment, 6000);
      expect(s.capitalRecoveryPercent, 40);
    });

    test('recovering everything takes investment to zero', () {
      var s = loan();
      s = KhataLoanState.apply(
          s, pay(12000, interestDue: 2000, principalDue: 10000));
      expect(s.investment, 0);
      expect(s.settled, isTrue);
      expect(s.status, LoanStatus.completed);
    });
  });

  group('investment falls over a sequence of payments', () {
    test('₹1,000 weekly for twelve weeks empties the principal', () {
      var s = loan(principal: 10000, interest: 0);
      for (var i = 0; i < 10; i++) {
        s = KhataLoanState.apply(
            s, pay(1000, principalDue: Num.toDouble(s.investment)));
      }
      expect(s.investment, 0, reason: 'capital recovered falls to nothing');
      expect(s.status, LoanStatus.completed);
    });

    test('a partial week reduces investment only by what was paid', () {
      var s = loan(principal: 4000, interest: 0);
      s = KhataLoanState.apply(s, pay(600, principalDue: 4000));
      expect(s.investment, 3400);
      expect(s.status, LoanStatus.active, reason: 'still owes, so not completed');
    });
  });

  group('outstanding balance', () {
    test('is principal deployed plus interest and fees', () {
      final s = KhataLoanState(
        originalPrincipal: 10000,
        principalRecovered: 4000,
        interestOutstanding: 500,
        lateFeeOutstanding: 100,
        otherChargeOutstanding: 50,
      );
      expect(s.investment, 6000);
      expect(s.outstandingBalance, 6650);
    });

    test('held credit reduces what is collectable but not what is owed', () {
      final s = KhataLoanState(
        originalPrincipal: 1000,
        principalRecovered: 1000,
        unappliedCredit: 250,
      );
      expect(s.outstandingBalance, 0);
      expect(s.netOutstanding, 0);
      expect(s.unappliedCredit, 250,
          reason: 'surplus is credit, never a negative balance');
    });

    test('investment clamps at zero, but interest still counts', () {
      // More recovered than the original principal (only reachable from corrupt
      // data): investment floors at zero and never goes negative, while the
      // interest that is genuinely still owed keeps the balance honest.
      final s = KhataLoanState(
        originalPrincipal: 1000,
        principalRecovered: 5000,
        interestOutstanding: 500,
      );
      expect(s.investment, 0);
      expect(s.outstandingBalance, 500);
      expect(s.netOutstanding, 500);
    });
  });

  group('status is never claimed early', () {
    test('a loan with a balance stays ACTIVE', () {
      final s = KhataLoanState.apply(
          loan(), pay(100, interestDue: 2000, principalDue: 10000));
      expect(s.toRow()['status'], 'ACTIVE');
      expect(s.outstandingBalance, greaterThan(0));
    });

    test('a fully settled loan becomes COMPLETED', () {
      final s = KhataLoanState.apply(
          loan(), pay(12000, interestDue: 2000, principalDue: 10000));
      expect(s.toRow()['status'], 'COMPLETED');
      expect(s.toRow()['outstanding'], 0);
    });
  });

  group('reading a loan row written by any app version', () {
    test('a v10 row round-trips', () {
      final row = KhataLoanState(
        originalPrincipal: 10000,
        principalRecovered: 4000,
        interestOutstanding: 1000,
      ).toRow();
      final back = KhataLoanState.fromRow({
        ...row,
        'principal_amount': 10000.0,
        'status': 'ACTIVE',
      });
      expect(back.investment, 6000);
      expect(back.interestOutstanding, 1000);
    });

    test('a pre-v10 row does not invent principal recovery', () {
      // No component columns at all. Recovery is unknown, so it must be zero —
      // an upper bound on investment, never a guess.
      final back = KhataLoanState.fromRow({
        'principal_amount': 10000.0,
        'outstanding': 12000.0,
        'total_payable': 12000.0,
        'status': 'Active',
      });
      expect(back.principalRecovered, 0);
      expect(back.investment, 10000);
      expect(back.interestOutstanding, 2000);
    });
  });

  group('capital recovery view is a report, not an accounting method', () {
    test('it never alters the balances', () {
      final s = KhataLoanState.apply(
          loan(), pay(6000, interestDue: 2000, principalDue: 10000));
      final beforeOutstanding = s.outstandingBalance;
      // Reading the recovery percentage must be pure.
      expect(s.capitalRecoveryPercent, 40);
      expect(s.capitalRecoveryPercent, 40);
      expect(s.outstandingBalance, beforeOutstanding,
          reason: 'reporting must not move a balance');
    });
  });
}
