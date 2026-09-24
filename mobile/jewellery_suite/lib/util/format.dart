import 'dart:math' as math;

/// Rounding contract mirrored from the server (`pawn_shop/utils.py`):
///   * money   -> ceiling to 2 decimals
///   * weights -> round half-up to 3 decimals
///   * percent -> 2 decimals
class Num {
  /// Ceiling a money value to 2 decimals (never under-charges).
  static double money(num value) {
    final scaled = value * 100.0;
    final ceiled = scaled.ceilToDouble();
    return ceiled / 100.0;
  }

  /// Round a weight to 3 decimals, half-up.
  static double round3(num value) {
    final scaled = value * 1000.0;
    final rounded = (scaled + (scaled >= 0 ? 0.5 : -0.5)).floorToDouble();
    return rounded / 1000.0;
  }

  /// Round a percentage to 2 decimals, half-up.
  static double roundPct(num value) {
    final scaled = value * 100.0;
    final rounded = (scaled + (scaled >= 0 ? 0.5 : -0.5)).floorToDouble();
    return rounded / 100.0;
  }

  static double toDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  static String moneyText(num? v) {
    final d = toDouble(v);
    return d.toStringAsFixed(2);
  }

  /// Simple interest for [days] at [rate]% per month (30-day month), money ceil.
  static double simpleInterest({
    required double principal,
    required double ratePerMonth,
    required int days,
  }) {
    final months = days / 30.0;
    return money(principal * ratePerMonth / 100.0 * months);
  }

  /// Whole months between two dates (used to mirror the server's monthly basis).
  static int monthsBetween(DateTime from, DateTime to) {
    var months = (to.year - from.year) * 12 + (to.month - from.month);
    if (to.day < from.day) months -= 1;
    return math.max(months, 0);
  }
}
