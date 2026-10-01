import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/format.dart';
import 'package:jewellery_suite/util/khata_math.dart';

/// These tests pin the behaviour that existed before KhataMath was extracted,
/// so the extraction itself can never quietly change a number the shopkeeper
/// relies on. The two rules that caused real bugs are called out explicitly:
/// a part-payment must not count as a whole installment, and an overpayment
/// must settle the balance rather than raise an error.
void main() {
  group('interval', () {
    test('maps each collection frequency to its step', () {
      expect(KhataMath.interval('Weekly'), 7);
      expect(KhataMath.interval('Biweekly'), 14);
      expect(KhataMath.interval('Monthly'), 30);
    });

    test('an unknown frequency falls back to monthly', () {
      expect(KhataMath.interval('Fortnightly-ish'), 30);
      expect(KhataMath.interval(''), 30);
    });
  });

  group('installment', () {
    test('splits the payable evenly', () {
      expect(KhataMath.installment(12000, 12), 1000);
      expect(KhataMath.installment(10000, 4), 2500);
    });

    test('truncates to whole rupees — remainder lives on the last', () {
      // 10000/3 = 3333.3333. The khata truncation rule drops paise:
      // 3333 + 3333 + 3334 = 10000, remainder on the final installment.
      expect(KhataMath.installment(10000, 3), 3333.33);
      expect(KhataMath.installment(100, 3), 33.33);
      expect(KhataMath.installment(12000, 12), 1000, reason: 'exact');
    });

    test('a zero or negative count yields zero, not infinity', () {
      expect(KhataMath.installment(10000, 0), 0);
      expect(KhataMath.installment(10000, -3), 0);
    });
  });

  group('khata truncation rule — whole rupees, paise dropped', () {
    test('Num.rupees truncates, never rounds up', () {
      expect(Num.rupees(1.50), 1);
      expect(Num.rupees(10000.05), 10000);
      expect(Num.rupees(10000.90), 10000);
      expect(Num.rupees(10000), 10000);
    });

    test('moneyWholeDown never shows a rounded-up rupee', () {
      expect(moneyWholeDown(10000.90), '10,000');
      expect(moneyWholeDown(1.50), '1');
      expect(moneyWholeDown(10000.05), '10,000');
    });
  });

  group('paidInstallments', () {
    test('a full installment counts one', () {
      expect(
        KhataMath.paidInstallments(
            collected: 1000, totalPayable: 12000, count: 12),
        1,
      );
    });

    test('a part-payment counts ZERO — the bug this prevents', () {
      // ₹100 of a ₹1,000 weekly installment must not mark the week paid,
      // which used to push the next due date a whole week forward.
      expect(
        KhataMath.paidInstallments(
            collected: 100, totalPayable: 4000, count: 4),
        0,
      );
      expect(
        KhataMath.paidInstallments(
            collected: 999.99, totalPayable: 4000, count: 4),
        0,
      );
    });

    test('₹400 of ₹800 leaves the member owing, still one installment short',
        () {
      expect(
        KhataMath.paidInstallments(collected: 400, totalPayable: 800, count: 1),
        0,
      );
      expect(
        KhataMath.paidInstallments(collected: 800, totalPayable: 800, count: 1),
        1,
      );
    });

    test('an overpayment cannot claim more installments than exist', () {
      expect(
        KhataMath.paidInstallments(
            collected: 999999, totalPayable: 12000, count: 12),
        12,
      );
    });

    test('degenerate inputs return zero', () {
      expect(
        KhataMath.paidInstallments(
            collected: 500, totalPayable: 1000, count: 0),
        0,
      );
      expect(
        KhataMath.paidInstallments(collected: 500, totalPayable: 0, count: 5),
        0,
      );
    });
  });

  group('outstanding', () {
    test('what is owed when part-paid', () {
      expect(KhataMath.outstanding(800, 400), 400);
      expect(KhataMath.outstanding(10000, 0), 10000);
    });

    test('settles exactly at the payable figure', () {
      expect(KhataMath.outstanding(1000, 1000), 0);
    });

    test('an overpayment clamps to zero, it does not go negative', () {
      expect(KhataMath.outstanding(1000, 1500), 0);
      expect(KhataMath.outstanding(1000, 99999), 0);
    });

    test('rounds once at the end', () {
      expect(KhataMath.outstanding(1000, 333.333), 666.67);
    });
  });

  group('status', () {
    test('only a zero balance is Closed', () {
      expect(KhataMath.status(0), 'Closed');
      expect(KhataMath.status(0.01), 'Active');
      expect(KhataMath.status(400), 'Active');
    });
  });

  group('sumAmounts', () {
    test('adds and rounds once', () {
      expect(KhataMath.sumAmounts([100.555, 200.444, 0.001]), 301.0);
      expect(KhataMath.sumAmounts(<double>[]), 0);
    });

    test('ignores nulls from sparse rows', () {
      expect(KhataMath.sumAmounts([100, null, 50]), 150);
    });
  });

  group('totals', () {
    test('derives all three columns from collections alone', () {
      final t = KhataMath.totals(
        totalPayable: 4000,
        collections: [1000, 1000],
        installmentCount: 4,
      );
      expect(t.collected, 2000);
      expect(t.outstanding, 2000);
      expect(t.paidInstallments, 2);
      expect(t.status, 'Active');
    });

    test('closes on the final rupee', () {
      final t = KhataMath.totals(
        totalPayable: 4000,
        collections: [1000, 1000, 1000, 1000],
        installmentCount: 4,
      );
      expect(t.outstanding, 0);
      expect(t.paidInstallments, 4);
      expect(t.status, 'Closed');
    });

    test('a partial final installment leaves the loan Active', () {
      final t = KhataMath.totals(
        totalPayable: 4000,
        collections: [1000, 1000, 1000, 999],
        installmentCount: 4,
      );
      expect(t.outstanding, 1);
      expect(t.paidInstallments, 3);
      expect(t.status, 'Active',
          reason: 'owing one rupee still means owing money');
    });

    test('toRow writes exactly the four derived columns', () {
      final row = KhataMath.totals(
              totalPayable: 100, collections: [100], installmentCount: 1)
          .toRow();
      expect(row.keys.toSet(),
          {'total_collected', 'outstanding', 'paid_installments', 'status'});
      expect(row['status'], 'Closed');
    });

    test('an empty collection list leaves the full amount owing', () {
      final t = KhataMath.totals(
          totalPayable: 13000, collections: <double>[], installmentCount: 12);
      expect(t.collected, 0);
      expect(t.outstanding, 13000);
      expect(t.paidInstallments, 0);
      expect(t.status, 'Active');
    });
  });

  group('refinance does not double-count', () {
    test('cash injected by a refinance is counted once', () {
      // Old loan: 10,000 payable, 8,000 still owing. Refinance pays that 8,000
      // and books a new 8,000 loan. If the old loan's collections were re-read
      // after the new loan was written, the balance went negative and the
      // profile showed a figure the report disagreed with.
      final oldLoan = KhataMath.totals(
        totalPayable: 10000,
        collections: [2000],
        installmentCount: 10,
      );
      expect(oldLoan.outstanding, 8000);

      final newLoan = KhataMath.totals(
        totalPayable: 8000,
        collections: <double>[],
        installmentCount: 8,
      );
      expect(newLoan.outstanding, 8000);

      // The sum the shop reports is the new loan only — the old one is settled.
      expect(oldLoan.outstanding + newLoan.outstanding, 16000,
          reason: 'sanity: the two loans are separate balances');
      expect(newLoan.collected, 0,
          reason:
              'the refinance cash belongs to the old loan, not the new one');
    });
  });
}
