import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/util/format.dart';

/// v1.0.24 — every ledger row (loan, you-gave charge, collection) used to show
/// and sort by `updated_at`, the moment the shopkeeper TYPED the entry. A
/// payment back-dated to last week therefore appeared as — and sorted as —
/// today, which put the running balance in the wrong order and told the
/// shopkeeper a lie about when the money moved.
void main() {
  group('ledger row timing', () {
    test('a back-dated entry shows its business date, not today', () {
      final r = ledgerWhen(
        businessDate: '2026-09-26',
        entryAt: '2026-10-01T19:47:12.345',
      );
      // Sorted and displayed as the day the money actually moved.
      expect(r.when, DateTime(2026, 9, 26));
      expect(r.stamp, isNot(contains('7:47')),
          reason: 'the typing time must not stand in for the payment date');
      expect(r.stamp, contains('26'));
    });

    test('an entry made on the same day keeps its time for ordering', () {
      final r = ledgerWhen(
        businessDate: '2026-10-01',
        entryAt: '2026-10-01T19:47:12.345',
      );
      expect(r.when, DateTime(2026, 10, 1));
      // Same day: the clock is what separates two entries, so it is kept.
      expect(r.stamp, contains('47'));
    });

    test('falls back to the entry time when there is no business date', () {
      final r = ledgerWhen(businessDate: null, entryAt: '2026-10-01T09:05:00.0');
      // With no business date the entry timestamp IS the truth, time and all.
      expect(r.when, DateTime(2026, 10, 1, 9, 5));
      expect(r.stamp, isNotEmpty);
    });

    test('no dates at all must not crash', () {
      final r = ledgerWhen(businessDate: null, entryAt: null);
      expect(r.stamp, isNotNull);
    });

    test('ordering puts a back-dated payment before a today payment', () {
      final old_ = ledgerWhen(
              businessDate: '2026-09-26', entryAt: '2026-10-01T19:47:00.0')
          .when;
      final now_ = ledgerWhen(
              businessDate: '2026-10-01', entryAt: '2026-10-01T09:05:00.0')
          .when;
      expect(old_.isBefore(now_), isTrue,
          reason: 'the ledger runs newest-first, so the truth depends on this');
    });

    test('hand-written transactions keep their own dates', () {
      // The seeded samples type each transaction on its own date; nothing may
      // collapse them onto one timestamp.
      final dates = ['2026-09-26', '2026-09-11', '2026-08-26'];
      final stamps = dates
          .map((d) => ledgerWhen(
                businessDate: d,
                entryAt: '2026-10-01T19:47:00.0',
              ).stamp)
          .toList();
      expect(stamps.toSet().length, 3,
          reason: 'three hand-typed transactions must not share one stamp');
    });
  });

  group('format helpers used by the ledger', () {
    test('fmtDate gives a day-level stamp', () {
      expect(fmtDate('2026-09-26'), contains('26'));
      expect(fmtDate('2026-09-26'), isNot(contains(':')));
    });
    test('parseIso reads a plain date', () {
      expect(parseIso('2026-09-26'), DateTime(2026, 9, 26));
    });
  });
}
