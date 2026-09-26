import 'dart:math' as math;

import 'package:intl/intl.dart';

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

  /// Compound interest: principal × ((1 + rate/100)^periods − 1), money ceil.
  /// [periods] may be fractional (e.g. days/30 for monthly compounding).
  static double compoundInterest({
    required double principal,
    required double rate,
    required double periods,
  }) {
    if (periods <= 0) return 0;
    return money(
        principal * (math.pow(1 + rate / 100.0, periods) - 1));
  }

  /// Calendar difference between [from] and [to] as (years, months, days).
  static (int, int, int) diffYmdParts(DateTime from, DateTime to) {
    if (to.isBefore(from)) return (0, 0, 0);
    var years = to.year - from.year;
    var months = to.month - from.month;
    var days = to.day - from.day;
    if (days < 0) {
      months -= 1;
      days += DateTime(to.year, to.month, 0).day;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    return (years, months, days);
  }

  /// "1 Y - 2 M - 3 D" — always shows all three units, zeros included.
  static String diffYmd(DateTime from, DateTime to) {
    final (years, months, days) = diffYmdParts(from, to);
    return '$years Y - $months M - $days D';
  }

  /// Whole months between two dates (used to mirror the server's monthly basis).
  static int monthsBetween(DateTime from, DateTime to) {
    var months = (to.year - from.year) * 12 + (to.month - from.month);
    if (to.day < from.day) months -= 1;
    return math.max(months, 0);
  }
}

// ---------------------------------------------------------------------------
// Display helpers (khata-style: DD-MM-YY dates, whole rupees, Indian grouping)
// ---------------------------------------------------------------------------

/// Whole rupees with Indian digit grouping, no paise — e.g. 1600 -> "1,600".
String moneyWhole(num? value) {
  final d = (Num.toDouble(value)).round();
  final negative = d < 0;
  final s = d.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
    buffer.write(s[i]);
  }
  return '${negative ? '-' : ''}${buffer.toString()}';
}

/// "₹1,600" — whole rupees with Indian grouping.
String inr(num? value) => '₹${moneyWhole(value)}';

/// "16-08-26" — DD-MM-YY for ISO date/datetime strings.
String fmtDate(Object? value) {
  final dt = parseIso(value);
  if (dt == null) return value?.toString() ?? '';
  return DateFormat('dd-MM-yy').format(dt);
}

/// "23 Sep 26 08:03 PM" — compact date + time used in the SBI-style ledger.
/// Date-only values format as "23 Sep 26" (no time).
String fmtDateTime(Object? value) {
  final dt = parseIso(value);
  if (dt == null) return value?.toString() ?? '';
  final s = value.toString().trim();
  final hasTime = s.length > 10;
  return DateFormat(hasTime ? 'dd MMM yy h:mm a' : 'dd MMM yy').format(dt);
}

/// "23 Sep 26" — compact date (no time), used in ledger fallbacks.
String fmtDateLong(Object? value) {
  final dt = parseIso(value);
  if (dt == null) return value?.toString() ?? '';
  return DateFormat('dd MMM yy').format(dt);
}

/// "25-10-26 Mon" — reminder chip format (DD-MM-YY + weekday).
String fmtReminder(Object? value) {
  final dt = parseIso(value);
  if (dt == null) return '-';
  return DateFormat('dd-MM-yy EEE').format(dt);
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// "Due Today" / "Due Next Week" / "Due 5 Days Ago" / "Due 25-10-26".
String dueWording(DateTime due, DateTime today) {
  final late = _dayOnly(today).difference(_dayOnly(due)).inDays;
  if (late > 0) return 'Due $late Day${late == 1 ? '' : 's'} Ago';
  if (late == 0) return 'Due Today';
  if (late >= -7) return 'Due Next Week';
  return 'Due ${DateFormat('dd-MM-yy').format(due)}';
}

/// Lateness for the payment schedule: "13 Weeks Due",
/// "3 Months 1 Week Due", "1 Week Due".
String weeksLateWording(int days) {
  if (days <= 0) return 'On Time';
  final w = days ~/ 7;
  if (w == 0) return '$days Day${days == 1 ? '' : 's'} Due';
  if (w < 4) return '$w Week${w == 1 ? '' : 's'} Due';
  final months = w ~/ 4;
  final rem = w % 4;
  if (rem == 0) return '$months Month${months == 1 ? '' : 's'} Due';
  return '$months Month${months == 1 ? '' : 's'}'
      ' $rem Week${rem == 1 ? '' : 's'} Due';
}

/// Parses an amount the way shopkeepers type it: strips ₹ and commas from
/// Indian grouping ("10,000" -> 10000.0). Returns 0.0 when unparseable.
/// Prevents silent save failures on pre-filled edit fields.
double parseMoney(Object? value) {
  final s = value?.toString().replaceAll(RegExp(r'[₹,\s]'), '');
  return double.tryParse(s ?? '') ?? 0;
}

/// Parse ISO date ("2026-08-16") or datetime ("2026-08-16T08:03:00") strings.
DateTime? parseIso(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  // Date-only: "2026-08-16" -> local midnight so toIso8601String() keeps the day.
  if (s.length == 10 && s.contains('-')) {
    final parsed = DateTime.tryParse('${s}T00:00:00');
    return parsed;
  }
  return DateTime.tryParse(s);
}
