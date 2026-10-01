import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/util/format.dart';
import 'package:jewellery_suite/util/khata_loan_state.dart';

/// v1.0.20 — Reports used to show `received - given` under the label
/// "Interest earned". That is Capital Recovery with the wrong name, and it
/// prints a NEGATIVE number whenever less has been collected than lent out
/// (give 10,00,000, collect 1,00,000 → "Interest earned ₹-9,00,000").
///
/// The correct figure is the interest the loans actually earned:
///   interest charged for the whole term  −  interest still owed
/// which can never fall below zero.
double interestEarned(List<Map<String, Object?>> loans) {
  double charged = 0, owed = 0;
  for (final l in loans) {
    charged += Num.toDouble(l['interest_amount']);
    owed += KhataLoanState.fromRow(l).interestOutstanding;
  }
  return Num.money(charged - owed);
}

Map<String, Object?> loan({
  double principal = 10000,
  double interest = 2000,
  double principalRecovered = 0,
  double interestOutstanding = 2000,
}) =>
    {
      'principal_amount': principal,
      'interest_amount': interest,
      'original_principal': principal,
      'principal_recovered': principalRecovered,
      'principal_outstanding': principal - principalRecovered,
      'interest_outstanding': interestOutstanding,
      'status': 'ACTIVE',
    };

void main() {
  group('interest earned can never be negative', () {
    test('fresh loan with nothing collected yet', () {
      // Charged 2000, still owed 2000 → nothing earned yet.
      expect(interestEarned([loan()]), 0);
    });

    test('partial collection of principal is NOT counted as interest', () {
      final loans = [
        loan(principalRecovered: 1000, interestOutstanding: 2000),
      ];
      // Principal recovered must not inflate "interest earned".
      expect(interestEarned(loans), 0);
    });

    test('once the interest itself is collected, it shows as earned', () {
      final loans = [
        loan(
            principalRecovered: 1000,
            interestOutstanding: 0), // 2000 of interest recovered
      ];
      expect(interestEarned(loans), 2000);
    });

    test('the old formula produced a negative number where this must not', () {
      const given = 1000000.0;
      const received = 100000.0;
      // This is precisely what Reports used to print.
      expect(Num.money(received - given), -900000);
      // The replacement for the same situation never goes below zero.
      final loans = [
        loan(principal: given, interest: 0, interestOutstanding: 0),
      ];
      expect(interestEarned(loans), 0);
      expect(interestEarned(loans) >= 0, isTrue);
    });

    test('sums across several loans', () {
      final loans = [
        loan(interest: 2000, interestOutstanding: 500),
        loan(interest: 1000, interestOutstanding: 1000),
      ];
      expect(interestEarned(loans), 1500); // 1500 + 0
    });

    test('an over-collected interest cannot make the total negative', () {
      // Defensive: more interest recovered than was ever charged.
      final loans = [loan(interest: 1000, interestOutstanding: -500)];
      final v = interestEarned(loans);
      expect(v >= 0, isTrue, reason: 'interest earned is never negative');
    });
  });

  group('Reports money formatting', () {
    // NOTE: moneyWhole's doc comment says "Indian digit grouping" but it
    // actually groups in threes from the right (Western: 8,333,500), not by
    // lakh/crore (Indian: 83,33,500). Asserted here as-is so the app cannot
    // drift silently; switching to lakh grouping is an OPEN DECISION because
    // it changes every rupee figure on every screen.
    test('whole rupees with grouping, no fake paise', () {
      // The bug printed "₹8333500.0" — ungrouped AND with a decimal.
      expect(moneyWhole(8333500), '8,333,500');
      expect(moneyWhole(0), '0');
      expect(moneyWhole(100002000), '100,002,000');
    });

    test('never renders a decimal point', () {
      for (final v in [0.0, 8333500.0, 100002000.0, 91668500.0, 1.0]) {
        expect(moneyWhole(v), isNot(contains('.')),
            reason: 'rupee figures must not show paise');
      }
    });
  });

  group('plural helper', () {
    test('one khata vs many', () {
      expect(_plural(0, 'khata'), '0 khatas');
      expect(_plural(1, 'khata'), '1 khata');
      expect(_plural(2, 'khata'), '2 khatas');
    });
  });
}

String _plural(int n, String one) => n == 1 ? '$n $one' : '$n ${one}s';
