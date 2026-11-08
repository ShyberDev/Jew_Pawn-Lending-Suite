import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/late_fee_suggest.dart';

/// #089: the late-fee dialog pre-fills from the invoice's own history —
/// the last fee charged on it — instead of always opening blank. No rate is
/// invented; the shopkeeper still edits the field.
void main() {
  test('a previous fee is suggested again, with days since the sale', () {
    final s = suggestLateFee(
      invoiceDate: DateTime(2026, 11, 6, 10),
      lateFeeTotal: 500,
      now: DateTime(2026, 11, 8, 10),
    );
    expect(s.fee, 500);
    expect(s.daysSinceSale, 2);
  });

  test('with no previous fee the field stays blank but age is shown', () {
    final s = suggestLateFee(
      invoiceDate: DateTime(2026, 11, 6, 10),
      lateFeeTotal: 0,
      now: DateTime(2026, 11, 7, 10),
    );
    expect(s.fee, isNull);
    expect(s.daysSinceSale, 1);
  });

  test('a same-day sale is 0 days old, never negative', () {
    final s = suggestLateFee(
      invoiceDate: DateTime(2026, 11, 6, 10),
      lateFeeTotal: 0,
      now: DateTime(2026, 11, 6, 18),
    );
    expect(s.fee, isNull);
    expect(s.daysSinceSale, 0);
  });
}
