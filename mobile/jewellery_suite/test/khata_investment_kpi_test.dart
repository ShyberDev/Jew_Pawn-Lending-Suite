import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/util/format.dart';
import 'package:jewellery_suite/util/khata_alloc.dart';
import 'package:jewellery_suite/util/khata_loan_state.dart';

/// The defect behind "Khata investment is wrong".
///
/// Before v10 the Home KPI summed `SUM(principal_amount)` — the ORIGINAL
/// principal — so it could only ever rise and never represented the capital the
/// shop still had out. These tests pin the corrected behaviour: investment falls
/// as principal is recovered, and it never falls to zero while principal is
/// genuinely still deployed.
void main() {
  // Reaching the private static through the public surface keeps this honest:
  // if the helper is removed the test fails to compile rather than silently
  // passing against a different implementation.
  double kpi(List<Map<String, Object?>> loans) =>
      AppState.khataInvestmentForTest(loans);

  group('investment is capital deployed', () {
    test('a loan with nothing recovered deploys its whole principal', () {
      expect(kpi([
        {'principal_amount': 10000.0, 'principal_outstanding': 10000.0},
      ]), 10000);
    });

    test('it FALLS as principal is recovered', () {
      expect(kpi([
        {'principal_amount': 10000.0, 'principal_outstanding': 10000.0},
      ]), 10000);
      expect(kpi([
        {'principal_amount': 10000.0, 'principal_outstanding': 6000.0},
      ]), 6000);
      expect(kpi([
        {'principal_amount': 10000.0, 'principal_outstanding': 0.0},
      ]), 0);
    });

    test('the old behaviour would have stayed at 10,000 all the way', () {
      // This is exactly what the old SUM(principal_amount) reported — the bug.
      final loan = {'principal_amount': 10000.0, 'principal_outstanding': 0.0};
      final oldSum = Num.money(loan['principal_amount'] as double);
      expect(oldSum, 10000, reason: 'the old figure never falls');
      expect(kpi([loan]), 0, reason: 'the new figure correctly reaches zero');
    });

    test('totals several loans', () {
      expect(
        kpi([
          {'principal_amount': 10000.0, 'principal_outstanding': 6000.0},
          {'principal_amount': 5000.0, 'principal_outstanding': 5000.0},
          {'principal_amount': 3000.0, 'principal_outstanding': 0.0},
        ]),
        11000,
      );
    });

    test('an empty book is zero, not a crash', () {
      expect(kpi([]), 0);
    });
  });

  group('a pre-v10 loan is an upper bound, never a guess', () {
    test('no principal_outstanding falls back to the principal', () {
      // Nothing is known about recovery, so the safest reading is that the full
      // principal is still out. Assuming recovery would understate the money the
      // shop actually has deployed.
      expect(kpi([
        {'principal_amount': 10000.0},
      ]), 10000);
    });

    test('a mixed set uses each row on its own merits', () {
      expect(
        kpi([
          {'principal_amount': 10000.0, 'principal_outstanding': 4000.0},
          {'principal_amount': 2000.0}, // legacy
        ]),
        6000,
      );
    });
  });

  group('the KPI and the loan state agree', () {
    test('after real allocations, Home equals the sum of live loans', () {
      var a = KhataLoanState.fresh(principal: 10000, interest: 2000);
      var b = KhataLoanState.fresh(principal: 5000, interest: 0);

      // Pay ₹6,000 on the first: ₹2,000 interest then ₹4,000 principal.
      a = KhataLoanState.apply(
          a,
          KhataAlloc.allocate(
            payment: 6000,
            interestDue: 2000,
            lateFeeDue: 0,
            otherChargeDue: 0,
            principalDue: 10000,
          ));
      // Pay ₹5,000 on the second — all principal.
      b = KhataLoanState.apply(
          b,
          KhataAlloc.allocate(
            payment: 5000,
            interestDue: 0,
            lateFeeDue: 0,
            otherChargeDue: 0,
            principalDue: 5000,
          ));

      final fromState = Num.money(a.investment + b.investment);
      final fromRows = kpi([
        {
          'principal_amount': 10000.0,
          'principal_outstanding': a.investment,
        },
        {
          'principal_amount': 5000.0,
          'principal_outstanding': b.investment,
        },
      ]);
      expect(fromRows, fromState);
      expect(fromRows, 6000, reason: 'only the first loan still has capital out');
    });

    test('recovering everything leaves zero deployed', () {
      var s = KhataLoanState.fresh(principal: 8000, interest: 2000);
      s = KhataLoanState.apply(
          s,
          KhataAlloc.allocate(
            payment: 10000,
            interestDue: 2000,
            lateFeeDue: 0,
            otherChargeDue: 0,
            principalDue: 8000,
          ));
      expect(s.investment, 0);
      expect(kpi([
        {'principal_amount': 8000.0, 'principal_outstanding': s.investment}
      ]), 0);
    });
  });
}
