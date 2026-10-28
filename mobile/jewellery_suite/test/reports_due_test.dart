import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/ui/reports_screen.dart';

/// #020: "Overdue accounts" must report what is collectable NOW, not the whole
/// outstanding balance. A loan ₹1,00,000 in size with two ₹1,000 weeks missed
/// is ₹2,000 overdue — not ₹1,00,000.
void main() {
  group('reports overdue uses the To Collect engine', () {
    test('reports only the installments whose date has arrived', () {
      final today = DateTime(2026, 10, 28);
      // 12 weekly installments of ₹1,000 starting four weeks ago: four are
      // due today, nothing has been collected yet.
      final loan = <String, Object?>{
        'payment_type': 'INSTALLMENT',
        'total_payable': 12000.0,
        'total_collected': 0.0,
        'installment_count': 12,
        'collection_frequency': 'Weekly',
        'start_date': '2026-09-30',
      };

      final due = dueNowForReports(
        loan: loan,
        interestPeriods: const [],
        today: today,
        outstanding: 12000.0,
      );

      expect(due, 4000.0,
          reason: '4 due weeks × ₹1,000, not the ₹12,000 balance');
      expect(due, lessThan(12000.0));
    });

    test('collections reduce the overdue figure oldest-first', () {
      final today = DateTime(2026, 10, 28);
      final loan = <String, Object?>{
        'payment_type': 'INSTALLMENT',
        'total_payable': 12000.0,
        'total_collected': 3000.0,
        'installment_count': 12,
        'collection_frequency': 'Weekly',
        'start_date': '2026-09-30',
      };

      final due = dueNowForReports(
        loan: loan,
        interestPeriods: const [],
        today: today,
        outstanding: 9000.0,
      );

      // ₹3,000 cleared the first three due weeks; the fourth ₹1,000 remains.
      expect(due, 1000.0);
    });

    test('a loan with no dues yet reports zero overdue', () {
      final today = DateTime(2026, 10, 28);
      final loan = <String, Object?>{
        'payment_type': 'INSTALLMENT',
        'total_payable': 12000.0,
        'total_collected': 0.0,
        'installment_count': 12,
        'collection_frequency': 'Weekly',
        'start_date': '2026-10-27',
      };

      expect(
        dueNowForReports(
          loan: loan,
          interestPeriods: const [],
          today: today,
          outstanding: 12000.0,
        ),
        0.0,
      );
    });

    test('interest-only loans report only billed periods that are due', () {
      final today = DateTime(2026, 10, 28);
      final loan = <String, Object?>{
        'payment_type': 'INTEREST_ONLY',
        'total_payable': 10000.0,
        'total_collected': 0.0,
        'installment_count': 0,
        'start_date': '2026-09-28',
        'current_interest': 500.0,
      };

      final due = dueNowForReports(
        loan: loan,
        interestPeriods: [
          {'due_date': '2026-10-05', 'remaining_amount': 500.0},
          {'due_date': '2026-10-12', 'remaining_amount': 500.0},
          {'due_date': '2026-11-05', 'remaining_amount': 500.0},
        ],
        today: today,
        outstanding: 10000.0,
      );

      expect(due, 1000.0,
          reason: 'two billed periods are due; the November one is not');
    });
  });
}
