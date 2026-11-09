import 'package:flutter/foundation.dart' show immutable;

/// Timestamps at the Firestore boundary.
///
/// Two clocks meet here and they must not be compared as strings:
///
/// * **Local rows** keep the app's existing storage format —
///   `DateTime.now().toIso8601String()`, a *local wall clock* string with no
///   zone. String ordering inside one phone stays cheap and correct.
/// * **Firestore documents** are written as UTC ISO-8601 with a `Z`. Two phones
///   in different zones then agree on which edit happened later.
///
/// A plain `>` on those two forms is wrong (`'2026-11-09T11:00:00.000'` sorts
/// after `'2026-11-09T05:30:00.000Z'` even though they are the same instant).
/// Every comparison therefore goes through [instant].
@immutable
class CloudTime {
  const CloudTime._();

  /// The instant to stamp a new Firestore document with.
  static String nowUtcIso() => DateTime.now().toUtc().toIso8601String();

  /// True for the columns whose value is an instant (not a calendar date).
  ///
  /// `movement_date`, `order_date`, `txn_date` and friends are business dates
  /// (`yyyy-MM-dd`), so they are deliberately left alone.
  static bool isStamp(String column) =>
      column == 'created_at' || column == 'updated_at';

  /// Parses a local wall-clock string, a `Z` string or an offset string as an
  /// absolute instant. Returns null when the value is missing or unparseable.
  static DateTime? instant(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is! String) return null;
    final text = value.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  /// Boundary form: UTC ISO-8601 with `Z`, or null when unparseable.
  static String? toBoundary(Object? value) {
    final at = instant(value);
    return at?.toUtc().toIso8601String();
  }

  /// Storage form: local wall clock, no zone — what the rest of the database
  /// writes. Converting a pulled row back keeps local ordering uniform instead
  /// of mixing `Z` and naive strings in the same column.
  static String? toLocalStamp(Object? value) {
    final at = instant(value);
    return at?.toLocal().toIso8601String();
  }

  /// True only when [remote] is strictly later than [local].
  ///
  /// Equal instants are *not* newer: a tie means the local edit already has the
  /// same information and must not be replaced. A missing remote stamp loses; a
  /// missing local stamp is always accepted (the row is new to this phone).
  static bool isNewer(Object? local, Object? remote) {
    final r = instant(remote);
    if (r == null) return false;
    final l = instant(local);
    if (l == null) return true;
    return r.isAfter(l);
  }
}
