import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/khata_alloc.dart';

/// Written from the acceptance criteria in the ChatGPT specification, BEFORE
/// the implementation, so the module has to satisfy the specification rather
/// than the other way round.
///
/// These cases are deliberately lifted verbatim from the spec (AC-001 …) so a
/// disagreement about a rule shows up as a failing test rather than as a
/// silently different number in someone's account.
void main() {
  group('AC-001 — interest is allocated before principal', () {
    test('₹6,000 against ₹2,000 interest and ₹10,000 principal', () {
      final r = KhataAlloc.allocate(
        payment: 6000,
        interestDue: 2000,
        lateFeeDue: 0,
        otherChargeDue: 0,
        principalDue: 10000,
      );
      expect(r.interest, 2000);
      expect(r.principal, 4000);
      expect(r.interestRemaining, 0);
      expect(r.principalRemaining, 6000);
    });
  });

  group('AC-002 — payment smaller than interest', () {
    test('₹400 leaves ₹200 of interest and touches no principal', () {
      final r = KhataAlloc.allocate(
        payment: 400,
        interestDue: 600,
        lateFeeDue: 0,
        otherChargeDue: 0,
        principalDue: 10000,
      );
      expect(r.interest, 400);
      expect(r.principal, 0);
      expect(r.interestRemaining, 200);
      expect(r.principalRemaining, 10000,
          reason: 'a part-payment must never reduce principal');
    });
  });

  group('AC-003 — payment exactly equals interest', () {
    test('₹600 clears interest and nothing else', () {
      final r = KhataAlloc.allocate(
        payment: 600,
        interestDue: 600,
        lateFeeDue: 0,
        otherChargeDue: 0,
        principalDue: 10000,
      );
      expect(r.interest, 600);
      expect(r.principal, 0);
      expect(r.interestRemaining, 0);
    });
  });

  group('AC-004 — payment exceeds interest', () {
    test('₹1,000 splits into ₹600 interest and ₹400 principal', () {
      final r = KhataAlloc.allocate(
        payment: 1000,
        interestDue: 600,
        lateFeeDue: 0,
        otherChargeDue: 0,
        principalDue: 10000,
      );
      expect(r.interest, 600);
      expect(r.principal, 400);
    });
  });

  group('AC-005 — fees are paid after interest', () {
    test('₹1,000 clears ₹300 interest, ₹200 fee, then ₹500 principal', () {
      final r = KhataAlloc.allocate(
        payment: 1000,
        interestDue: 300,
        lateFeeDue: 200,
        otherChargeDue: 0,
        principalDue: 10000,
      );
      expect(r.interest, 300);
      expect(r.lateFee, 200);
      expect(r.principal, 500);
    });
  });

  group('AC-006 — fees cannot consume money before interest', () {
    test('₹200 pays all interest even though a fee is outstanding', () {
      final r = KhataAlloc.allocate(
        payment: 200,
        interestDue: 300,
        lateFeeDue: 500,
        otherChargeDue: 0,
        principalDue: 10000,
      );
      expect(r.interest, 200);
      expect(r.lateFee, 0, reason: 'interest has priority over fees');
      expect(r.principal, 0);
    });
  });

  group('AC-007 / AC-008 — allocation totals', () {
    test('every rupee is either allocated or held as credit', () {
      // A payment larger than everything owed does not "allocate" past the
      // dues — the surplus becomes credit. So the invariant is
      // allocated + unapplied == payment, never allocated == payment.
      for (final payment in [
        0.0,
        1.0,
        399.5,
        500.0,
        999.99,
        6000.0,
        100000.0
      ]) {
        final r = KhataAlloc.allocate(
          payment: payment,
          interestDue: 2000,
          lateFeeDue: 300,
          otherChargeDue: 200,
          principalDue: 10000,
        );
        expect((r.total + r.unapplied - payment).abs(), lessThan(0.000001),
            reason: 'payment $payment was created or lost');
      }
    });

    test('a payment within the dues is allocated in full', () {
      final r = KhataAlloc.allocate(
        payment: 6000,
        interestDue: 2000,
        lateFeeDue: 300,
        otherChargeDue: 200,
        principalDue: 10000,
      );
      expect(r.total, 6000);
      expect(r.unapplied, 0);
    });

    test('allocation never exceeds the payment', () {
      final r = KhataAlloc.allocate(
        payment: 700,
        interestDue: 600,
        lateFeeDue: 400,
        otherChargeDue: 300,
        principalDue: 10000,
      );
      expect(r.total, lessThanOrEqualTo(700));
    });
  });

  group('AC-009 — a negative payment is rejected', () {
    test('throws rather than allocating negative money', () {
      expect(
        () => KhataAlloc.allocate(
          payment: -100,
          interestDue: 600,
          lateFeeDue: 0,
          otherChargeDue: 0,
          principalDue: 10000,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('negative dues are rejected too', () {
      expect(
        () => KhataAlloc.allocate(
          payment: 100,
          interestDue: -1,
          lateFeeDue: 0,
          otherChargeDue: 0,
          principalDue: 10000,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('AC-010 / AC-011 / AC-012 — principal recovery', () {
    test('principal recovered is exactly the principal allocation', () {
      final r = KhataAlloc.allocate(
        payment: 6000,
        interestDue: 2000,
        lateFeeDue: 0,
        otherChargeDue: 0,
        principalDue: 10000,
      );
      expect(r.principalRecovered, r.principal);
      expect(r.principalRecovered, 4000);
    });

    test('paying interest only leaves principal untouched', () {
      final r = KhataAlloc.allocate(
        payment: 2000,
        interestDue: 2000,
        lateFeeDue: 0,
        otherChargeDue: 0,
        principalDue: 10000,
      );
      expect(r.principalRecovered, 0);
      expect(r.principalRemaining, 10000);
    });
  });

  group('overpayment — the cascade the user chose', () {
    test('more than everything due leaves the surplus unapplied', () {
      final r = KhataAlloc.allocate(
        payment: 20000,
        interestDue: 2000,
        lateFeeDue: 0,
        otherChargeDue: 0,
        principalDue: 10000,
      );
      expect(r.interest, 2000);
      expect(r.principal, 10000);
      expect(r.unapplied, 8000,
          reason: 'surplus is credit, not a negative balance');
      expect(r.principalRemaining, 0);
      expect(r.fullySettled, isTrue);
    });

    test('the surplus never makes a balance negative', () {
      final r = KhataAlloc.allocate(
        payment: 99999,
        interestDue: 500,
        lateFeeDue: 0,
        otherChargeDue: 0,
        principalDue: 1000,
      );
      expect(r.interestRemaining, 0);
      expect(r.lateFeeRemaining, 0);
      expect(r.otherChargeRemaining, 0);
      expect(r.principalRemaining, 0);
    });
  });

  group('obligation priority — level 1', () {
    // Overdue obligations are served before current ones, and future ones last.
    Obligation ob(int n, String due, {double amount = 1000}) => Obligation(
          installmentNumber: n,
          dueDate: DateTime.parse(due),
          scheduledAmount: amount,
          remainingAmount: amount,
        );

    test('overdue comes before current, current before future', () {
      final order = KhataAlloc.obligationOrder([
        ob(3, '2026-10-06'), // future
        ob(1, '2026-09-01'), // overdue
        ob(2, '2026-09-29'), // current
      ], today: DateTime(2026, 9, 29));
      expect(order.map((o) => o.installmentNumber), [1, 2, 3]);
    });

    test('two overdue installments are ordered by earliest due date', () {
      final order = KhataAlloc.obligationOrder([
        ob(2, '2026-09-15'),
        ob(1, '2026-09-01'),
      ], today: DateTime(2026, 9, 29));
      expect(order.map((o) => o.installmentNumber), [1, 2],
          reason: 'earliest due date first');
    });

    test('a fully settled obligation is skipped', () {
      final order = KhataAlloc.obligationOrder([
        ob(1, '2026-09-01', amount: 0), // nothing owed
        ob(2, '2026-09-15'),
      ], today: DateTime(2026, 9, 29));
      expect(order.map((o) => o.installmentNumber), [2]);
    });
  });

  group('cascade across installments', () {
    test('a payment too big for one installment moves to the next', () {
      final obligations = [
        Obligation(
            installmentNumber: 1,
            dueDate: DateTime.parse('2026-09-01'),
            scheduledAmount: 1000,
            remainingAmount: 1000),
        Obligation(
            installmentNumber: 2,
            dueDate: DateTime.parse('2026-09-08'),
            scheduledAmount: 1000,
            remainingAmount: 1000),
      ];
      final r = KhataAlloc.allocateAcross(
        payment: 1500,
        obligations: obligations,
        today: DateTime(2026, 9, 29),
      );
      expect(r.perObligation[1]!.principal, 1000);
      expect(r.perObligation[1]!.fullySettled, isTrue);
      expect(r.perObligation[2]!.principal, 500);
      expect(r.totalPrincipal, 1500);
      expect(r.unapplied, 0);
    });

    test('a part-payment does not move to the next installment', () {
      final obligations = [
        Obligation(
            installmentNumber: 1,
            dueDate: DateTime.parse('2026-09-01'),
            scheduledAmount: 1000,
            remainingAmount: 1000),
        Obligation(
            installmentNumber: 2,
            dueDate: DateTime.parse('2026-09-08'),
            scheduledAmount: 1000,
            remainingAmount: 1000),
      ];
      final r = KhataAlloc.allocateAcross(
        payment: 600,
        obligations: obligations,
        today: DateTime(2026, 9, 29),
      );
      expect(r.perObligation[1]!.principal, 600);
      expect(r.perObligation.containsKey(2), isFalse,
          reason: 'the shortfall stays on installment 1');
    });

    test('an obligation is settled in full before money reaches the next', () {
      // The specification is explicit that obligation priority comes FIRST and
      // component priority applies only WITHIN the selected obligation. So the
      // earliest-due obligation takes its own interest then its own principal,
      // and the next obligation is untouched until this one is clear.
      final obligations = [
        Obligation(
            installmentNumber: 1,
            dueDate: DateTime.parse('2026-09-01'),
            scheduledAmount: 1000,
            remainingAmount: 1000,
            interestDue: 300),
        Obligation(
            installmentNumber: 2,
            dueDate: DateTime.parse('2026-09-08'),
            scheduledAmount: 1000,
            remainingAmount: 1000,
            interestDue: 300),
      ];
      final r = KhataAlloc.allocateAcross(
        payment: 700,
        obligations: obligations,
        today: DateTime(2026, 9, 29),
      );
      expect(r.perObligation[1]!.interest, 300);
      expect(r.perObligation[1]!.principal, 400);
      expect(r.perObligation.containsKey(2), isFalse,
          reason: 'obligation 1 was not fully settled');
      expect(r.totalPrincipal, 400);
      expect(r.unapplied, 0);
    });

    test('once the first obligation clears, the payment carries on', () {
      final obligations = [
        Obligation(
            installmentNumber: 1,
            dueDate: DateTime.parse('2026-09-01'),
            scheduledAmount: 1000,
            remainingAmount: 400,
            interestDue: 0),
        Obligation(
            installmentNumber: 2,
            dueDate: DateTime.parse('2026-09-08'),
            scheduledAmount: 1000,
            remainingAmount: 1000,
            interestDue: 0),
      ];
      final r = KhataAlloc.allocateAcross(
        payment: 1000,
        obligations: obligations,
        today: DateTime(2026, 9, 29),
      );
      expect(r.perObligation[1]!.principal, 400);
      expect(r.perObligation[1]!.fullySettled, isTrue);
      expect(r.perObligation[2]!.principal, 600);
      expect(r.totalPrincipal, 1000);
    });
  });

  group('rounding', () {
    test('allocations sum exactly to the payment on awkward amounts', () {
      for (final payment in [0.01, 0.1, 1.07, 33.33, 99.99, 1234.57]) {
        final r = KhataAlloc.allocate(
          payment: payment,
          interestDue: 33.33,
          lateFeeDue: 11.11,
          otherChargeDue: 7.77,
          principalDue: 999.99,
        );
        expect((r.total + r.unapplied - payment).abs(), lessThan(0.000001),
            reason: 'payment $payment leaked or lost money');
      }
    });

    test('a payment exactly covering the dues leaves no credit', () {
      final r = KhataAlloc.allocate(
        payment: 1052.20,
        interestDue: 33.33,
        lateFeeDue: 11.11,
        otherChargeDue: 7.77,
        principalDue: 999.99,
      );
      expect(r.unapplied, 0);
      expect(r.fullySettled, isTrue);
    });
  });
}
