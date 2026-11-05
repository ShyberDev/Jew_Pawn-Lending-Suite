import 'dart:math' as math;

// THE single place where jewellery money and weight are calculated.
//
// The rules come from `APK_Project_Progress/CALCULATIONS.md`
// (C01–C14) and `SPEC_JEWELLERY.md`:
//
// * Metal value uses the **pure-metal rate** and the item's purity:
//   `weight × purity% ÷ 100 × pureRate`.
// * Making charges are either a **percentage of weight** (added to purity, the
//   owner's selected purchase formula) or a **fixed weight in grams**. Only one
//   mode applies to a line — they are never added together.
// * Discounts reduce the **sale value**, never the item cost.
// * Old metal is counted **once**: its accepted value is an invoice deduction,
//   and its weight is a separate stock receipt.
// * Bill totals round to whole rupees half-up; the adjustment is recorded so
//   the invoice still reconciles.
// * A worker's gold/cash reserve is an asset position, never a loss or debt.
//   Weight differences from a return are **suggestions** until the shop
//   confirms how to classify them.

/// How a line is priced.
///
/// * [raw] — a raw-metal purchase: `weight × purity% ÷ 100 × rate`.
/// * [kdm] — a retail KDM sale: `(net + wastage%) × rate + flat making`.
///   Purity is **not** applied to the selling price; it is kept for cost/profit.
/// * [nonKdm] — a retail non-KDM sale: `net × rate + flat making`. Purity is
///   again cost-only, because the shop sells the piece as it is.
enum BillingBasis { raw, kdm, nonKdm }

/// How a making charge is expressed on a **raw purchase** line. Retail sale
/// lines always use a flat rupee making charge.
enum MakingMode {
  /// No making charge (plain metal value).
  none,

  /// Percentage added to the purity (`purity + making`), the purchase formula
  /// the owner confirmed: `weight × (purity% + making%) ÷ 100 × pureRate`.
  percentage,

  /// Fixed weight in grams added to the equivalent pure weight.
  weight,

  /// Flat rupee making charge. Used by silver sales where the shop quotes a
  /// single amount rather than a percentage or grams (C05).
  amount,
}

/// Metal recovery indicator (spec §6). This is **not** profit.
enum RecoveryStatus {
  /// Collections are above the item's actual cost.
  green,

  /// Collections equal the item's actual cost (break-even).
  lightGreen,

  /// Collections are below the item's actual cost.
  red,

  /// Inactive / cancelled / not applicable.
  grey,
}

/// One calculated sale or purchase line, with every intermediate figure kept.
typedef JewelleryLine = ({
  double weight,
  double purityPct,
  double pureRate,
  BillingBasis billingBasis,
  double wastagePct,
  MakingMode makingMode,
  double makingValue,
  double effectivePct,
  double equivalentWeight,
  double wastageWeight,
  double totalEquivalentWeight,
  double billedWeight,
  double fineWeight,
  double metalValue,
  double makingAmount,
  double additionalCost,
  double discount,
  double subtotal,
  double total,
});

/// Pure jewellery arithmetic. No database, no widgets — every screen and test
/// calls these so one formula cannot drift between modules.
class JewelleryMath {
  const JewelleryMath._();

  /// Tolerance for "equal" money comparisons (half a paise).
  static const _epsilon = 0.005;

  /// ₹/g for a given purity, e.g. pure gold ₹15,000 and 92% → ₹13,800 (C01).
  static double rateForPurity(num pureRate, num purityPct) =>
      _clean(pureRate.toDouble() * purityPct.toDouble() / 100.0);

  /// Pure-metal value of [weight] grams at [purityPct] and [pureRate].
  static double metalValue({
    required num weight,
    required num purityPct,
    required num pureRate,
  }) =>
      _clean(weight.toDouble() *
          purityPct.toDouble() /
          100.0 *
          pureRate.toDouble());

  /// One line's full breakdown.
  ///
  /// For a **raw purchase** ([billingBasis] `raw`), [purityPct] and
  /// [makingValue] keep their original meanings: purity is applied to the
  /// metal value, and making is a percentage, grams or rupees according to
  /// [makingMode].
  ///
  /// For a **retail sale** (`kdm` / `nonKdm`), purity is **not** applied to the
  /// selling price. The shop sells `net + wastage` (KDM) or `net` (non-KDM)
  /// grams at [pureRate], then adds a flat [makingCharge]. Purity is still
  /// returned as [fineWeight] so cost/profit can use the actual metal content.
  static JewelleryLine line({
    required double weight,
    required double purityPct,
    required double pureRate,
    MakingMode makingMode = MakingMode.none,
    double makingValue = 0,
    double additionalCost = 0,
    double discount = 0,
    BillingBasis billingBasis = BillingBasis.raw,
    double wastagePct = 0,
    double makingCharge = 0,
  }) {
    final safeWeight = weight < 0 ? 0.0 : weight;
    final safePurity = purityPct < 0 ? 0.0 : purityPct;
    final safeRate = pureRate < 0 ? 0.0 : pureRate;
    final safeAdditional = additionalCost < 0 ? 0.0 : additionalCost;
    final safeDiscount = discount < 0 ? 0.0 : discount;
    final safeWastage = wastagePct < 0 ? 0.0 : wastagePct;
    final safeMakingCharge = makingCharge < 0 ? 0.0 : makingCharge;

    // Actual metal content. Cost/profit uses this; a retail sale price does
    // not, because the customer is buying the finished piece by weight.
    final fineWeight = _clean(safeWeight * safePurity / 100.0);

    double metalValue;
    double makingAmount;
    double wastageWeight;
    double equivalentWeight;
    double billedWeight;
    double effectivePct = safePurity;
    var appliedMakingMode = makingMode;
    var appliedMakingValue = math.max(0.0, makingValue);

    if (billingBasis == BillingBasis.raw) {
      // Raw purchase: metal is purity-adjusted, then making is added in the
      // mode the supplier quote used.
      final strictMetal = _clean(fineWeight * safeRate);
      metalValue = strictMetal;
      switch (makingMode) {
        case MakingMode.percentage:
          effectivePct = safePurity + math.max(0, makingValue);
          equivalentWeight = _clean(safeWeight * effectivePct / 100.0);
          makingAmount = _clean(equivalentWeight * safeRate - strictMetal);
          wastageWeight = _clean(safeWeight * math.max(0, makingValue) / 100.0);
        case MakingMode.weight:
          final extra = math.max(0.0, makingValue);
          equivalentWeight = _clean(fineWeight + extra);
          makingAmount = _clean(extra * safeRate);
          wastageWeight = _clean(extra);
        case MakingMode.amount:
          equivalentWeight = fineWeight;
          makingAmount = _clean(math.max(0, makingValue));
          wastageWeight = safeRate > 0 ? _clean(makingAmount / safeRate) : 0.0;
        case MakingMode.none:
          equivalentWeight = fineWeight;
          makingAmount = 0;
          wastageWeight = 0;
      }
      billedWeight = equivalentWeight;
      // A flat rupee charge is shown as its metal equivalent so a purchase
      // line can also be read as "weight × rate".
      if (makingMode == MakingMode.amount) {
        billedWeight = _clean(equivalentWeight + wastageWeight);
      }
    } else {
      // Retail sale. KDM adds wastage on the full net weight; non-KDM sells
      // the net weight as it is. Purity never changes the selling price.
      final extra = billingBasis == BillingBasis.kdm
          ? _clean(safeWeight * safeWastage / 100.0)
          : 0.0;
      billedWeight = _clean(safeWeight + extra);
      metalValue = _clean(billedWeight * safeRate);
      makingAmount = safeMakingCharge;
      wastageWeight = extra;
      equivalentWeight = billedWeight;
      effectivePct =
          billingBasis == BillingBasis.kdm ? _clean(100 + safeWastage) : 100;
      appliedMakingMode = MakingMode.amount;
      appliedMakingValue = safeMakingCharge;
    }

    final subtotal = _clean(metalValue + makingAmount + safeAdditional);
    final total = _clean(subtotal - safeDiscount);

    return (
      weight: safeWeight,
      purityPct: safePurity,
      pureRate: safeRate,
      billingBasis: billingBasis,
      wastagePct: safeWastage,
      makingMode: appliedMakingMode,
      makingValue: appliedMakingValue,
      effectivePct: _clean(effectivePct),
      equivalentWeight: _clean(equivalentWeight),
      wastageWeight: _clean(wastageWeight),
      totalEquivalentWeight: _clean(billedWeight),
      billedWeight: _clean(billedWeight),
      fineWeight: fineWeight,
      metalValue: metalValue,
      makingAmount: makingAmount,
      additionalCost: safeAdditional,
      discount: safeDiscount,
      subtotal: subtotal,
      total: total,
    );
  }

  /// KDM retail sale: `(net + wastage%) × rate + flat making`.
  static JewelleryLine kdmSale({
    required double weight,
    double purityPct = 100,
    required double pureRate,
    double wastagePct = 0,
    double makingCharge = 0,
    double additionalCost = 0,
    double discount = 0,
  }) =>
      line(
        weight: weight,
        purityPct: purityPct,
        pureRate: pureRate,
        billingBasis: BillingBasis.kdm,
        wastagePct: wastagePct,
        makingCharge: makingCharge,
        additionalCost: additionalCost,
        discount: discount,
      );

  /// Non-KDM retail sale: `net × rate + flat making`; purity is cost-only.
  static JewelleryLine nonKdmSale({
    required double weight,
    required double purityPct,
    required double pureRate,
    double makingCharge = 0,
    double additionalCost = 0,
    double discount = 0,
  }) =>
      line(
        weight: weight,
        purityPct: purityPct,
        pureRate: pureRate,
        billingBasis: BillingBasis.nonKdm,
        makingCharge: makingCharge,
        additionalCost: additionalCost,
        discount: discount,
      );

  /// The owner's purchase formula: `weight × (purity% + making%) ÷ 100 ×
  /// pureRate`. C02 (gold) and C06 (silver supplier) exercise it.
  static JewelleryLine percentageMaking({
    required double weight,
    required double purityPct,
    required double makingPct,
    required double pureRate,
    double additionalCost = 0,
  }) =>
      line(
        weight: weight,
        purityPct: purityPct,
        pureRate: pureRate,
        makingMode: MakingMode.percentage,
        makingValue: makingPct,
        additionalCost: additionalCost,
      );

  /// Fixed-weight making: `weight × purity% ÷ 100 + makingWeight`, then × rate.
  /// C03 — percentage making must not also apply.
  static JewelleryLine fixedWeightMaking({
    required double weight,
    required double purityPct,
    required double makingWeight,
    required double pureRate,
    double additionalCost = 0,
  }) =>
      line(
        weight: weight,
        purityPct: purityPct,
        pureRate: pureRate,
        makingMode: MakingMode.weight,
        makingValue: makingWeight,
        additionalCost: additionalCost,
      );

  /// Sum of line totals, then invoice-level discount, then whole-rupee round.
  static ({double subtotal, double discount, double rounded, double roundOff})
      invoiceTotal(
    Iterable<JewelleryLine> lines, {
    double discount = 0,
  }) {
    var subtotal = 0.0;
    for (final l in lines) {
      subtotal += l.total;
    }
    final safeDiscount = discount < 0 ? 0.0 : discount;
    final raw = _clean(subtotal - safeDiscount);
    final rounded = roundRupee(raw);
    return (
      subtotal: _clean(subtotal),
      discount: _clean(safeDiscount),
      rounded: rounded.toDouble(),
      roundOff: _clean(rounded - raw),
    );
  }

  /// Whole-rupee rounding, half-up: ₹499.49 → ₹499, ₹499.50 → ₹500 (C09).
  static int roundRupee(num value) {
    final scaled = value.toDouble();
    return scaled < 0 ? -((-scaled + 0.5).floor()) : (scaled + 0.5).floor();
  }

  /// What rounding added to the invoice (can be negative when rounded down).
  static double roundingAdjustment(num raw) =>
      _clean(roundRupee(raw) - raw.toDouble());

  /// Suggest what a worker still owes/retains from a returned item (C04).
  ///
  /// Returns `equivalent` pure grams at [effectivePct], and `difference` =
  /// supplied − equivalent. A **positive** difference is short metal (the
  /// worker supplied fewer equivalent grams); a negative difference is excess.
  /// Nothing is posted automatically — the shop confirms the classification.
  static ({double equivalent, double difference, bool isShort}) workerReturn({
    required double suppliedWeight,
    required double returnedWeight,
    required double effectivePct,
  }) {
    final equivalent = _clean(returnedWeight * effectivePct / 100.0);
    final difference = _clean(suppliedWeight - equivalent);
    return (
      equivalent: equivalent,
      difference: difference,
      isShort: difference > _epsilon,
    );
  }

  /// Old-metal equivalent pure grams and the suggested credit (C07).
  ///
  /// The value is a **suggestion** — the shop may approve or edit it.
  static ({double equivalentWeight, double suggestedValue}) oldMetal({
    required double netWeight,
    required double purityPct,
    required double ratePerGram,
  }) {
    final equivalent = _clean(netWeight * purityPct / 100.0);
    return (
      equivalentWeight: equivalent,
      suggestedValue: _clean(equivalent * ratePerGram),
    );
  }

  /// Split [total] across [weights] proportionally (C08). The last share takes
  /// the remainder so the parts always add back to the total.
  static List<double> allocateSharedExpense(
      double total, Iterable<double> weights) {
    final list = weights.map((w) => w < 0 ? 0.0 : w).toList();
    if (list.isEmpty) return const [];
    final sum = list.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return List<double>.filled(list.length, 0);
    final safeTotal = total < 0 ? 0.0 : total;
    final out = <double>[];
    var allocated = 0.0;
    for (var i = 0; i < list.length; i++) {
      if (i == list.length - 1) {
        out.add(_clean(safeTotal - allocated));
      } else {
        final share = _clean(safeTotal * list[i] / sum);
        out.add(share);
        allocated += share;
      }
    }
    return out;
  }

  /// Recovery colour from collections vs actual item cost (C10, spec §6).
  static RecoveryStatus recovery({
    required double collections,
    required double actualCost,
    bool inactive = false,
  }) {
    if (inactive) return RecoveryStatus.grey;
    if ((collections - actualCost).abs() <= _epsilon) {
      return RecoveryStatus.lightGreen;
    }
    return collections > actualCost ? RecoveryStatus.green : RecoveryStatus.red;
  }

  /// Customer outstanding after payments and an accepted old-metal credit
  /// (C11). The old-metal value is passed once; callers must never also add it
  /// as a payment.
  static double outstanding({
    required double invoiceTotal,
    double payments = 0,
    double oldMetalCredit = 0,
    double lateFees = 0,
    double refunds = 0,
  }) {
    final value = invoiceTotal +
        math.max(0, lateFees) -
        math.max(0, payments) -
        math.max(0, oldMetalCredit) -
        math.max(0, refunds);
    return _clean(math.max(0, value));
  }

  /// Convert worker cash into metal at an explicitly entered rate (C12).
  ///
  /// Grams are floored to three decimals so the cash used can never exceed the
  /// cash available; the leftover stays as cash instead of being lost. The
  /// caller stores [ratePerGram] and the date with the transaction — the daily
  /// market rate is never fetched or applied later.
  static ({double grams, double cashUsed, double remainder}) workerCashToMetal({
    required double cash,
    required double ratePerGram,
  }) {
    if (cash <= 0 || ratePerGram <= 0) {
      return (grams: 0, cashUsed: 0, remainder: _clean(math.max(0, cash)));
    }
    final rawGrams = cash / ratePerGram;
    final grams = (rawGrams * 1000).floorToDouble() / 1000;
    final used = _clean(grams * ratePerGram);
    return (
      grams: grams,
      cashUsed: used,
      remainder: _clean(cash - used),
    );
  }

  /// Value of worker metal at a chosen rate (a summary only, never a rewrite).
  static double workerMetalValue(double grams, double ratePerGram) =>
      _clean(grams * ratePerGram);

  /// Allocate one receipt across invoice outstandings (C13).
  ///
  /// Each invoice receives at most what it still owes; anything left is
  /// unallocated credit. Never allocates more than the receipt.
  static ({List<double> allocations, double unallocated}) allocatePayment(
    double received,
    Iterable<double> invoiceOutstandings,
  ) {
    final safeReceived = received < 0 ? 0.0 : received;
    var remaining = safeReceived;
    final allocations = <double>[];
    for (final owed in invoiceOutstandings) {
      final amount = owed < 0 ? 0.0 : owed;
      final take = math.min(amount, remaining);
      allocations.add(_clean(take));
      remaining -= take;
    }
    return (
      allocations: allocations,
      unallocated: _clean(math.max(0, remaining)),
    );
  }

  /// Estimated profit at order time: sale value less the order-date cost.
  static double estimatedProfit({
    required double saleValue,
    required double estimatedCost,
  }) =>
      _clean(saleValue - estimatedCost);

  /// Final profit after delivery and settlement: sale value less actual
  /// attributable costs, with discounts/refunds applied once.
  static double finalProfit({
    required double saleValue,
    required double actualCost,
    double discount = 0,
    double refunds = 0,
  }) =>
      _clean(saleValue -
          actualCost -
          math.max(0, discount) -
          math.max(0, refunds));

  /// Sale value after a linked return. The original invoice is never edited;
  /// the caller posts this as a reversal entry (C14).
  static double netAfterReturn(double saleValue, double returnedValue) =>
      _clean(math.max(0, saleValue - math.max(0, returnedValue)));

  /// Remove floating-point noise (12.300000000000001 → 12.3) without losing
  /// real paise/gram precision.
  static double _clean(double value) {
    if (!value.isFinite) return 0;
    return double.parse(value.toStringAsFixed(6));
  }
}
