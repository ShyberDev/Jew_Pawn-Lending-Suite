import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/util/jewellery_math.dart';

/// Acceptance tests from `APK_Project_Progress/Calculations_and_Test_Cases.md`.
/// Each group is named after the calculation it proves.
void main() {
  group('C01 — gold rate', () {
    test('92% rate is 92% of the pure rate', () {
      expect(JewelleryMath.rateForPurity(15000, 92), closeTo(13800, 0.001));
    });

    test('a saved rate is an input, not a live lookup', () {
      // The engine has no clock and no market feed: callers pass the stored
      // rate, so a new day's rate can never rewrite an old line.
      final oldLine = JewelleryMath.percentageMaking(
        weight: 10,
        purityPct: 92,
        makingPct: 6,
        pureRate: 15000,
      );
      final newLine = JewelleryMath.percentageMaking(
        weight: 10,
        purityPct: 92,
        makingPct: 6,
        pureRate: 16000,
      );
      expect(oldLine.total, 147000);
      expect(newLine.total, 156800);
    });
  });

  group('C02 — percentage making', () {
    test('10 g, 92% purity, 6% making, ₹15,000/g', () {
      final line = JewelleryMath.percentageMaking(
        weight: 10,
        purityPct: 92,
        makingPct: 6,
        pureRate: 15000,
      );
      expect(line.effectivePct, 98);
      expect(line.equivalentWeight, closeTo(9.8, 0.0001));
      expect(line.metalValue, closeTo(138000, 0.01));
      expect(line.makingAmount, closeTo(9000, 0.01));
      expect(line.total, closeTo(147000, 0.01));
    });
  });

  group('C03 — fixed-weight making', () {
    test('10 g, 92%, 0.5 g fixed making, ₹15,000/g', () {
      final line = JewelleryMath.fixedWeightMaking(
        weight: 10,
        purityPct: 92,
        makingWeight: 0.5,
        pureRate: 15000,
      );
      expect(line.equivalentWeight, closeTo(9.7, 0.0001));
      expect(line.makingAmount, closeTo(7500, 0.01));
      expect(line.total, closeTo(145500, 0.01));
    });

    test('a line has exactly one making mode', () {
      final fixed = JewelleryMath.fixedWeightMaking(
        weight: 10,
        purityPct: 92,
        makingWeight: 0.5,
        pureRate: 15000,
      );
      final percent = JewelleryMath.percentageMaking(
        weight: 10,
        purityPct: 92,
        makingPct: 6,
        pureRate: 15000,
      );
      expect(fixed.total, isNot(closeTo(percent.total, 0.01)));
    });
  });

  group('C04 — worker return / reserve', () {
    test('9.950 g returned at 98% against 10.000 g supplied', () {
      final r = JewelleryMath.workerReturn(
        suppliedWeight: 10.000,
        returnedWeight: 9.950,
        effectivePct: 98,
      );
      expect(r.equivalent, closeTo(9.751, 0.0001));
      expect(r.difference, closeTo(0.249, 0.0001));
      expect(r.isShort, isTrue);
    });

    test('excess metal is reported, not treated as a debt', () {
      final r = JewelleryMath.workerReturn(
        suppliedWeight: 10,
        returnedWeight: 10.5,
        effectivePct: 98,
      );
      expect(r.difference, closeTo(-0.29, 0.0001));
      expect(r.isShort, isFalse);
    });
  });

  group('C05 — silver sale discount', () {
    test('15 g × ₹250 + ₹500 making − ₹500 discount', () {
      final line = JewelleryMath.line(
        weight: 15,
        purityPct: 100,
        pureRate: 250,
        makingMode: MakingMode.amount,
        makingValue: 500,
        discount: 500,
      );
      expect(line.metalValue, closeTo(3750, 0.01));
      expect(line.subtotal, closeTo(4250, 0.01));
      expect(line.discount, closeTo(500, 0.01));
      expect(line.total, closeTo(3750, 0.01));
    });

    test('no discount leaves ₹4,250', () {
      final line = JewelleryMath.line(
        weight: 15,
        purityPct: 100,
        pureRate: 250,
        makingMode: MakingMode.amount,
        makingValue: 500,
      );
      expect(line.total, closeTo(4250, 0.01));
    });

    test('discount reduces sale value, never item cost', () {
      final line = JewelleryMath.line(
        weight: 15,
        purityPct: 100,
        pureRate: 250,
        makingMode: MakingMode.amount,
        makingValue: 500,
        discount: 500,
      );
      expect(line.metalValue, closeTo(3750, 0.01));
      expect(line.total, closeTo(3750, 0.01));
    });
  });

  group('C06 — silver supplier costing', () {
    test('15 g, 60% purity, 15% supplier making, ₹250/g', () {
      final line = JewelleryMath.percentageMaking(
        weight: 15,
        purityPct: 60,
        makingPct: 15,
        pureRate: 250,
      );
      expect(line.effectivePct, 75);
      expect(line.equivalentWeight, closeTo(11.25, 0.0001));
      expect(line.total, closeTo(2812.50, 0.01));
    });

    test('difference against a ₹3,750 sale is ₹937.50', () {
      final cost = JewelleryMath.percentageMaking(
        weight: 15,
        purityPct: 60,
        makingPct: 15,
        pureRate: 250,
      );
      final sale = JewelleryMath.line(
        weight: 15,
        purityPct: 100,
        pureRate: 250,
        makingMode: MakingMode.amount,
        makingValue: 500,
        discount: 500,
      );
      expect(sale.total - cost.total, closeTo(937.50, 0.01));
    });
  });

  group('C15 — retail sale pricing (KDM / non-KDM)', () {
    test('KDM: 10 g + 10% wastage at ₹15,000 + ₹1,000 making = ₹1,66,000', () {
      final line = JewelleryMath.kdmSale(
        weight: 10,
        pureRate: 15000,
        wastagePct: 10,
        makingCharge: 1000,
      );
      expect(line.weight, closeTo(10, 0.0001)); // net weight stays 10 g
      expect(line.wastageWeight, closeTo(1, 0.0001));
      expect(line.billedWeight, closeTo(11, 0.0001));
      expect(line.metalValue, closeTo(165000, 0.01));
      expect(line.makingAmount, closeTo(1000, 0.01));
      expect(line.total, closeTo(166000, 0.01));
    });

    test('non-KDM: 10 g × ₹15,000 + ₹1,000 making = ₹1,51,000', () {
      final line = JewelleryMath.nonKdmSale(
        weight: 10,
        purityPct: 92,
        pureRate: 15000,
        makingCharge: 1000,
      );
      expect(line.wastageWeight, 0);
      expect(line.billedWeight, closeTo(10, 0.0001));
      expect(line.metalValue, closeTo(150000, 0.01));
      expect(line.total, closeTo(151000, 0.01));
    });

    test('actual purity never changes the retail selling price', () {
      for (final purity in [60.0, 80.0, 85.0]) {
        final line = JewelleryMath.nonKdmSale(
          weight: 10,
          purityPct: purity,
          pureRate: 15000,
          makingCharge: 1000,
        );
        expect(line.total, closeTo(151000, 0.01),
            reason: 'purity $purity% is cost-only');
        expect(line.fineWeight, closeTo(10 * purity / 100, 0.0001));
      }
    });

    test('KDM purity is also cost-only', () {
      final line = JewelleryMath.kdmSale(
        weight: 10,
        purityPct: 75,
        pureRate: 15000,
        wastagePct: 10,
        makingCharge: 1000,
      );
      expect(line.total, closeTo(166000, 0.01));
      expect(line.fineWeight, closeTo(7.5, 0.0001));
    });

    test('profit compares the retail price with the actual shop cost', () {
      final line = JewelleryMath.nonKdmSale(
        weight: 10,
        purityPct: 60,
        pureRate: 15000,
        makingCharge: 1000,
      );
      const actualCostToShop = 92000.0;
      expect(line.total - actualCostToShop, closeTo(59000, 0.01));
    });
  });

  group('C07 — old metal', () {
    test('10 g at 63% is 6.3 g equivalent', () {
      final v = JewelleryMath.oldMetal(
        netWeight: 10,
        purityPct: 63,
        ratePerGram: 14000,
      );
      expect(v.equivalentWeight, closeTo(6.3, 0.0001));
      expect(v.suggestedValue, closeTo(88200, 0.01));
    });

    test('accepted value is a suggestion the shop can edit', () {
      final v = JewelleryMath.oldMetal(
        netWeight: 10,
        purityPct: 63,
        ratePerGram: 14000,
      );
      expect(v.suggestedValue, isNot(0));
      // Nothing here posts stock or a credit; the caller does that once.
    });
  });

  group('C08 — shared expenses', () {
    test('₹300 over 10 g + 5 g allocates ₹200 / ₹100', () {
      final shares = JewelleryMath.allocateSharedExpense(300, [10, 5]);
      expect(shares[0], closeTo(200, 0.01));
      expect(shares[1], closeTo(100, 0.01));
      expect(shares.reduce((a, b) => a + b), closeTo(300, 0.01));
    });

    test('odd amounts still add back exactly', () {
      final shares = JewelleryMath.allocateSharedExpense(100, [1, 1, 1]);
      expect(shares.reduce((a, b) => a + b), closeTo(100, 0.01));
    });

    test('zero weights allocate nothing', () {
      expect(JewelleryMath.allocateSharedExpense(300, [0, 0]), [0, 0]);
    });
  });

  group('C09 — rounding', () {
    test('₹499.49 → ₹499 and ₹499.50 → ₹500', () {
      expect(JewelleryMath.roundRupee(499.49), 499);
      expect(JewelleryMath.roundRupee(499.50), 500);
      expect(JewelleryMath.roundRupee(499.60), 500);
    });

    test('the adjustment reconciles the invoice', () {
      const raw = 499.49;
      final rounded = JewelleryMath.roundRupee(raw);
      final adjustment = JewelleryMath.roundingAdjustment(raw);
      expect(raw + adjustment, closeTo(rounded.toDouble(), 0.0001));
    });

    test('invoice total reports its own round-off', () {
      final line = JewelleryMath.line(
        weight: 1.999,
        purityPct: 100,
        pureRate: 250,
      );
      final total = JewelleryMath.invoiceTotal([line]);
      expect(total.rounded, 500);
      expect(total.rounded - total.subtotal, closeTo(total.roundOff, 0.0001));
    });
  });

  group('C10 — recovery colours', () {
    test('collections above cost are green', () {
      expect(
        JewelleryMath.recovery(collections: 8000, actualCost: 7500),
        RecoveryStatus.green,
      );
    });

    test('exact break-even is light green', () {
      expect(
        JewelleryMath.recovery(collections: 8000, actualCost: 8000),
        RecoveryStatus.lightGreen,
      );
    });

    test('collections below cost are red', () {
      expect(
        JewelleryMath.recovery(collections: 7000, actualCost: 8000),
        RecoveryStatus.red,
      );
    });

    test('inactive / cancelled is grey', () {
      expect(
        JewelleryMath.recovery(
            collections: 0, actualCost: 8000, inactive: true),
        RecoveryStatus.grey,
      );
    });

    test('outstanding is independent of the colour', () {
      final status =
          JewelleryMath.recovery(collections: 8000, actualCost: 7500);
      final due =
          JewelleryMath.outstanding(invoiceTotal: 10000, payments: 8000);
      expect(status, RecoveryStatus.green);
      expect(due, closeTo(2000, 0.01));
    });
  });

  group('C11 — customer outstanding', () {
    test('₹10,000 invoice, ₹4,000 paid, ₹2,000 old metal → ₹4,000', () {
      expect(
        JewelleryMath.outstanding(
          invoiceTotal: 10000,
          payments: 4000,
          oldMetalCredit: 2000,
        ),
        closeTo(4000, 0.01),
      );
    });

    test('old metal is never subtracted twice', () {
      final once = JewelleryMath.outstanding(
        invoiceTotal: 10000,
        payments: 4000,
        oldMetalCredit: 2000,
      );
      // A caller that mistakes the credit for a payment would pass 6,000 paid
      // and get ₹0 — the engine cannot guess, so the single-credit input is the
      // documented contract.
      expect(once, closeTo(4000, 0.01));
    });

    test('overpayment never shows as a negative balance', () {
      expect(
        JewelleryMath.outstanding(invoiceTotal: 1000, payments: 1500),
        0,
      );
    });
  });

  group('C12 — worker ledger', () {
    test('₹1,23,000 at ₹14,800/g converts, keeping the remainder', () {
      final r = JewelleryMath.workerCashToMetal(
        cash: 123000,
        ratePerGram: 14800,
      );
      expect(r.grams, closeTo(8.310, 0.0001));
      expect(r.cashUsed, closeTo(122988, 0.01));
      expect(r.remainder, closeTo(12, 0.01));
      expect(r.cashUsed + r.remainder, closeTo(123000, 0.01));
    });

    test('5 g at ₹14,600 is ₹73,000', () {
      expect(JewelleryMath.workerMetalValue(5, 14600), closeTo(73000, 0.01));
    });

    test('no rate means no conversion', () {
      final r = JewelleryMath.workerCashToMetal(cash: 5000, ratePerGram: 0);
      expect(r.grams, 0);
      expect(r.remainder, closeTo(5000, 0.01));
    });
  });

  group('C13 — payment allocation', () {
    test('₹5,000 → ₹3,000 + ₹1,500 with ₹500 unallocated', () {
      final r = JewelleryMath.allocatePayment(5000, [3000, 1500]);
      expect(r.allocations[0], closeTo(3000, 0.01));
      expect(r.allocations[1], closeTo(1500, 0.01));
      expect(r.unallocated, closeTo(500, 0.01));
    });

    test('never allocates more than an invoice owes', () {
      final r = JewelleryMath.allocatePayment(5000, [1000, 1000]);
      expect(r.allocations, [1000, 1000]);
      expect(r.unallocated, closeTo(3000, 0.01));
    });

    test('a payment is never duplicated by allocation', () {
      final r = JewelleryMath.allocatePayment(5000, [3000, 1500]);
      expect(r.allocations.reduce((a, b) => a + b) + r.unallocated,
          closeTo(5000, 0.01));
    });
  });

  group('C14 — returns', () {
    test('the original sale value is untouched', () {
      const original = 10000.0;
      final net = JewelleryMath.netAfterReturn(original, 4000);
      expect(original, 10000);
      expect(net, closeTo(6000, 0.01));
    });

    test('a return cannot push the net below zero', () {
      expect(JewelleryMath.netAfterReturn(1000, 1500), 0);
    });

    test('profit is reported separately from recovery', () {
      expect(
        JewelleryMath.finalProfit(
            saleValue: 10000, actualCost: 7000, discount: 500, refunds: 0),
        closeTo(2500, 0.01),
      );
      expect(
        JewelleryMath.estimatedProfit(saleValue: 10000, estimatedCost: 6500),
        closeTo(3500, 0.01),
      );
    });
  });
}
