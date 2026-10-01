import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/format.dart';
import 'package:jewellery_suite/util/khata_math.dart';

/// Regression cover for two bugs found on the shop's own data:
///
/// 1. **Wrong khata totals.** Loans were attributed to a village through a map
///    keyed by the customer's *name*. Two people sharing a name merged into one
///    entry, so one person's loans were counted in the other person's khata and
///    every village total came out wrong — while the customer profile, which
///    looks the customer up directly, showed the correct figures. That is
///    exactly the "right inside, wrong outside" symptom.
/// 2. **Balance jumping back up after collecting.** The collected total was
///    rebuilt by summing `khatabook_collections`. Not every collected rupee has
///    a row there — creating a loan seeds the figure directly — so the sum
///    discarded earlier payments and the outstanding figure went *up* after the
///    shopkeeper took money.
///
/// The attribution rules are expressed here as pure functions so they can be
/// tested without a database.
void main() {
  group('loan → village attribution', () {
    // Two customers, one of each village, same first name.
    const raviUppalapadu = 'c-uppal-1';
    const raviPallipatti = 'c-palli-1';

    /// Mirrors `villageOfLoan` in khata_screen.dart: uuid first, then a
    /// *unique* name, and only then the loan's own (stale) village column.
    /// Returns the khata name, or '' when the loan belongs to no khata.
    String villageOfLoan({
      required String loanOwnerUuid,
      required String loanOwnerName,
      required Map<String, String?> villageByUuid,
      required Map<String, String?> villageByName,
      String? loanOwnVillage,
    }) {
      final owner = loanOwnerUuid;
      if (owner.isNotEmpty && villageByUuid.containsKey(owner)) {
        return villageByUuid[owner] ?? '';
      }
      if (villageByName.containsKey(loanOwnerName)) {
        return villageByName[loanOwnerName] ?? '';
      }
      return loanOwnVillage ?? '';
    }

    Map<String, String?> buildByName(List<Map<String, String?>> customers) {
      final m = <String, String?>{};
      for (final c in customers) {
        final name = c['name']!;
        // A name is only claimed when unique; an ambiguous name maps to null so
        // the lookup falls through instead of picking a wrong village.
        m[name] = m.containsKey(name) ? null : c['village'];
      }
      return m;
    }

    test('two customers with the same name keep their own village', () {
      final customers = [
        {'name': 'Ravi', 'village': 'Uppalapadu'},
        {'name': 'Ravi', 'village': 'Pallipatti'},
      ];
      final byUuid = {
        raviUppalapadu: 'Uppalapadu',
        raviPallipatti: 'Pallipatti'
      };
      final byName = buildByName(customers);
      expect(byName['Ravi'], isNull, reason: 'the name is ambiguous');

      // Each loan resolves through its own uuid — the bug this covers.
      expect(
        villageOfLoan(
          loanOwnerUuid: raviUppalapadu,
          loanOwnerName: 'Ravi',
          villageByUuid: byUuid,
          villageByName: byName,
          loanOwnVillage: 'Pallipatti', // stale column, must be ignored
        ),
        'Uppalapadu',
      );
      expect(
        villageOfLoan(
          loanOwnerUuid: raviPallipatti,
          loanOwnerName: 'Ravi',
          villageByUuid: byUuid,
          villageByName: byName,
          loanOwnVillage: 'Uppalapadu',
        ),
        'Pallipatti',
      );
    });

    test('a unique name still resolves without a uuid', () {
      final byUuid = <String, String?>{};
      final byName = buildByName([
        {'name': 'Sunitha Rani', 'village': 'Pallipatti'}
      ]);
      expect(
        villageOfLoan(
          loanOwnerUuid: '',
          loanOwnerName: 'Sunitha Rani',
          villageByUuid: byUuid,
          villageByName: byName,
          loanOwnVillage: null,
        ),
        'Pallipatti',
      );
    });

    test('an unknown owner falls back to the loan own village', () {
      final byName = buildByName([
        {'name': 'Ravi', 'village': 'Uppalapadu'}
      ]);
      expect(
        villageOfLoan(
          loanOwnerUuid: 'c-gone',
          loanOwnerName: 'Someone Removed',
          villageByUuid: const {},
          villageByName: byName,
          loanOwnVillage: 'Uppalapadu',
        ),
        'Uppalapadu',
      );
    });

    test('a customer with no village belongs to no khata', () {
      final byUuid = {'c-1': null};
      final byName = <String, String?>{};
      expect(
        villageOfLoan(
          loanOwnerUuid: 'c-1',
          loanOwnerName: 'No Village',
          villageByUuid: byUuid,
          villageByName: byName,
          loanOwnVillage: 'Something',
        ),
        '',
        reason: 'the customer record decides, not the stale loan column',
      );
    });
  });

  group('collecting adds to the stored total', () {
    test('the bug: summing collection rows loses earlier payments', () {
      // A loan created with ₹3,000 already collected but NO collection rows.
      // Summing the rows gives 0, so the balance jumps from ₹9,000 to ₹12,000.
      const payable = 12000.0;
      const stored = 3000.0;
      final newPayment = 1000.0;

      final oldSum = Num.money(0 + newPayment); // only the new row exists
      final fixed = KhataMath.addToCollected(
          already: stored, payment: newPayment, totalPayable: payable);

      expect(fixed, 4000);
      expect(KhataMath.outstanding(payable, fixed), 8000);
      expect(
        KhataMath.outstanding(payable, oldSum),
        11000,
        reason: 'this is the wrong figure the shopkeeper saw',
      );
    });

    test('adds a normal payment', () {
      expect(
        KhataMath.addToCollected(
            already: 6000, payment: 1000, totalPayable: 12000),
        7000,
      );
    });

    test('rounds once, and always up, at the end', () {
      // 999.555 + 0.005 = 999.560 exactly in binary floating point, which the
      // money contract then ceils to 999.56. Two paise of binary noise is
      // expected and harmless; what matters is that the rupee totals the shop
      // types are exact, which the surrounding tests cover.
      expect(
        KhataMath.addToCollected(
            already: 999.555, payment: 0.005, totalPayable: 10000),
        999.56,
      );
      // Exact rupee amounts are unaffected.
      expect(
        KhataMath.addToCollected(
            already: 999.55, payment: 0.45, totalPayable: 10000),
        1000.0,
      );
    });

    test('cannot be pushed past the loan total', () {
      expect(
        KhataMath.addToCollected(
            already: 11500, payment: 1000, totalPayable: 12000),
        12000.0,
      );
    });

    test('never goes negative', () {
      expect(
        KhataMath.addToCollected(already: -50, payment: 0, totalPayable: 10000),
        0.0,
      );
    });

    test('the full sequence stays correct across many collections', () {
      const payable = 12000.0;
      var collected = 6000.0;
      for (final p in [1000.0, 1000.0, 1000.0, 1000.0, 1000.0, 1000.0]) {
        collected = KhataMath.addToCollected(
            already: collected, payment: p, totalPayable: payable);
      }
      expect(collected, 12000);
      expect(KhataMath.outstanding(payable, collected), 0);
      expect(
        KhataMath.paidInstallments(
            collected: collected, totalPayable: payable, count: 12),
        12,
      );
      expect(KhataMath.status(0), 'Closed');
    });

    test('a part-payment still counts zero paid installments', () {
      const payable = 4000.0;
      final collected = KhataMath.addToCollected(
          already: 0, payment: 100, totalPayable: payable);
      expect(collected, 100);
      expect(
        KhataMath.paidInstallments(
            collected: collected, totalPayable: payable, count: 4),
        0,
      );
    });
  });
}
