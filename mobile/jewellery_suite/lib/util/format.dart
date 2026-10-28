import 'dart:math' as math;

import 'package:intl/intl.dart';

/// Rounding contract mirrored from the server (`pawn_shop/utils.py`):
///   * money   -> ceiling to 2 decimals
///   * weights -> round half-up to 3 decimals
///   * percent -> 2 decimals
class Num {
  /// Ceiling a money value to 2 decimals (never under-charges).
  ///
  /// PAWN-ONLY since the truncation rule: khata writes must use [rupees].
  static double money(num value) {
    final scaled = value * 100.0;
    final ceiled = scaled.ceilToDouble();
    return ceiled / 100.0;
  }

  /// Truncate to whole rupees, dropping paise (1.50 → 1, 10000.90 → 10000).
  ///
  /// KHATA-ONLY rule: paise precision is not needed and every intermediate
  /// paise figure was a source of phantom fractions. Pawn keeps [money].
  static double rupees(num value) => value.truncateToDouble();

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
    return money(principal * (math.pow(1 + rate / 100.0, periods) - 1));
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

/// Whole rupees with Indian digit grouping, no paise — e.g. 1600 -> "1,600",
/// 8333500 -> "83,33,500".
String moneyWhole(num? value) {
  final d = (Num.toDouble(value)).round();
  return _groupedRupees(d);
}

/// "₹1,600" — whole rupees with Indian grouping.
String inr(num? value) => '₹${moneyWhole(value)}';

/// Whole rupees with Indian digit grouping, TRUNCATED (10000.90 → "10,000").
///
/// KHATA-ONLY display: matches the truncate-on-write rule so a legacy paise
/// row can never render a rupee that was rounded up. Pawn keeps [moneyWhole].
String moneyWholeDown(num? value) {
  final d = Num.toDouble(value).truncate();
  return _groupedRupees(d);
}

/// Lakh/crore grouping: the last three digits stay together, then every two
/// digits gets a comma (83,33,500 — not Western 8,333,500).
String _groupedRupees(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  if (digits.length <= 3) return '${negative ? '-' : ''}$digits';

  final last3 = digits.substring(digits.length - 3);
  var head = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (head.length > 2) {
    parts.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) parts.insert(0, head);
  return '${negative ? '-' : ''}${parts.join(',')},$last3';
}

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

/// "1 sec ago" … "12 min ago" … "24 hours ago" … "3 days ago".
///
/// Recency of real money movement (member rows). Empty string when [value] is
/// null, unparseable, or in the future — never show a recency the data cannot
/// prove. Unit-tested in `test/format_test.dart` via the member display.
/// Grey in the UI: deliberately none of red/blue/green/gold.
String timeAgo(Object? value, {DateTime? now}) {
  if (value == null) return '';
  final dt = parseIso(value);
  if (dt == null) return '';
  final at = now ?? DateTime.now();
  final secs = at.difference(dt).inSeconds;
  if (secs < 0) return '';
  if (secs < 60) return '$secs sec ago';
  final mins = secs ~/ 60;
  if (mins < 60) return '$mins min ago';
  final hours = mins ~/ 60;
  if (hours < 48) return '$hours hour${hours == 1 ? '' : 's'} ago';
  final days = hours ~/ 24;
  return '$days day${days == 1 ? '' : 's'} ago';
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

/// The stamp shown on a ledger row, and nothing else.
///
/// v1.0.24: both the loan rows and the money rows used to prefer
/// `updated_at` — the moment the shopkeeper TYPED the entry. A payment
/// back-dated to last week was therefore displayed, and sorted, as today.
/// The ledger has to say when the money actually moved, so the business date
/// wins; the clock time is only worth showing when the entry was made on the
/// very day it happened (that is also the only case where it orders
/// same-day entries).
({DateTime when, String stamp}) ledgerWhen({
  required Object? businessDate,
  required Object? entryAt,
}) {
  final b = parseIso(businessDate);
  final e = parseIso(entryAt);
  if (b == null) {
    return (when: e ?? DateTime.now(), stamp: fmtDateTime(entryAt));
  }
  if (e != null && e.year == b.year && e.month == b.month && e.day == b.day) {
    // Same business day: the clock time is the only thing that can separate
    // two rows, so it drives the order. Returning midnight here made every
    // same-day entry tie and sort by uuid — which put a refinance transfer
    // ABOVE the new loan it created, instead of directly below it.
    return (when: e, stamp: fmtDateTime(entryAt));
  }
  return (when: b, stamp: fmtDate(businessDate));
}
