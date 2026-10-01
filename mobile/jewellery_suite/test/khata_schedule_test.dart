import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/format.dart';
import 'package:jewellery_suite/util/khata_schedule.dart';

/// Schedule generation and the two status machines, from the specification's
/// rules. The two that bite hardest are the calendar-month requirement and the
/// rule that installments must sum to exactly the expected repayment.
void main() {
  group('calendar months, not 30 days', () {
    test('monthly advances by whole calendar months', () {
      // Installment 1 falls one full interval after the start: a loan given
      // 15 Jan is first due 15 Feb, never on the given day itself.
      expect(KhataSchedule.dueDate(DateTime(2026, 1, 15), 'Monthly', 1),
          DateTime(2026, 2, 15));
      expect(KhataSchedule.dueDate(DateTime(2026, 1, 15), 'Monthly', 3),
          DateTime(2026, 4, 15));
    });

    test('a 31st start clamps to the last day of a short month', () {
      // Installment 1 from Jan 31 must be Feb 28/29, and must NOT skip March.
      final feb = KhataSchedule.dueDate(DateTime(2026, 1, 31), 'Monthly', 1);
      expect(feb.month, 2);
      expect(feb.day, lessThanOrEqualTo(28));

      final march = KhataSchedule.dueDate(DateTime(2026, 1, 31), 'Monthly', 2);
      expect(march, DateTime(2026, 3, 31), reason: 'it returns to the 31st');
    });

    test('a leap year February clamps to the 29th', () {
      final d = KhataSchedule.dueDate(DateTime(2028, 1, 31), 'Monthly', 1);
      expect(d, DateTime(2028, 2, 29));
    });

    test('a 30-day month clamps correctly', () {
      final d = KhataSchedule.dueDate(DateTime(2026, 1, 31), 'Monthly', 3);
      expect(d, DateTime(2026, 4, 30));
    });

    test('weekly and biweekly are plain day offsets', () {
      final start = DateTime(2026, 9, 29);
      // Installment 1 is one interval out: 30-09 weekly means 07-10.
      expect(KhataSchedule.dueDate(start, 'Weekly', 1), DateTime(2026, 10, 6));
      expect(KhataSchedule.dueDate(start, 'Weekly', 3), DateTime(2026, 10, 20));
      expect(
          KhataSchedule.dueDate(start, 'Biweekly', 1), DateTime(2026, 10, 13));
    });

    test('the schedule never drifts earlier month after month', () {
      var d = DateTime(2026, 1, 31);
      for (var n = 1; n <= 12; n++) {
        final next = KhataSchedule.dueDate(DateTime(2026, 1, 31), 'Monthly', n);
        expect(next.isAfter(d), isTrue, reason: 'installment $n must advance');
        d = next;
      }
    });
  });

  group('generation', () {
    test('installments sum to exactly the expected repayment', () {
      for (final total in [12000.0, 10000.0, 9300.0, 3333.33, 1.0, 999.99]) {
        for (final count in [1, 2, 3, 7, 12, 13, 100]) {
          final rows = KhataSchedule.generate(
            start: DateTime(2026, 1, 1),
            frequency: 'Weekly',
            count: count,
            expectedRepayment: total,
          );
          expect(rows.length, count);
          // Summed in whole paise, because summing 2-dp doubles and then
          // applying the money ceiling inflates the total by a paisa — the
          // invariant is exact in paise, which is where the rows are stored.
          final paise = rows.fold<int>(
              0, (s, r) => s + (r.scheduledAmount * 100).round());
          expect(paise, (Num.money(total) * 100).round(),
              reason: '$total over $count installments must not lose money');
        }
      }
    });

    test('the final installment absorbs the rounding remainder', () {
      final rows = KhataSchedule.generate(
        start: DateTime(2026, 1, 1),
        frequency: 'Weekly',
        count: 3,
        expectedRepayment: 10000,
      );
      expect(rows[0].scheduledAmount, 3333.33);
      expect(rows[1].scheduledAmount, 3333.33);
      expect(rows[2].scheduledAmount, 3333.34,
          reason: 'the last one makes the whole');
    });

    test('no payment is implied — everything starts unpaid', () {
      final rows = KhataSchedule.generate(
        start: DateTime(2026, 1, 1),
        frequency: 'Monthly',
        count: 4,
        expectedRepayment: 4000,
      );
      for (final r in rows) {
        expect(r.paidAmount, 0);
        expect(r.remainingAmount, r.scheduledAmount);
        expect(r.status, InstallmentStatus.pending);
      }
    });

    test('installment numbers run from 1', () {
      final rows = KhataSchedule.generate(
        start: DateTime(2026, 1, 1),
        frequency: 'Monthly',
        count: 5,
        expectedRepayment: 500,
      );
      expect(rows.map((r) => r.installmentNumber), [1, 2, 3, 4, 5]);
    });

    test('rejects a zero or negative count', () {
      expect(
        () => KhataSchedule.generate(
            start: DateTime(2026, 1, 1),
            frequency: 'Weekly',
            count: 0,
            expectedRepayment: 100),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a single installment takes the whole amount', () {
      final rows = KhataSchedule.generate(
        start: DateTime(2026, 1, 1),
        frequency: 'Weekly',
        count: 1,
        expectedRepayment: 999.99,
      );
      expect(rows.single.scheduledAmount, 999.99);
    });
  });

  group('installment status', () {
    ScheduleRow row(double scheduled) => ScheduleRow(
          installmentNumber: 1,
          dueDate: DateTime(2026, 9, 1),
          scheduledAmount: scheduled,
        );

    test('pending until something is paid', () {
      final r = row(1000);
      expect(r.status, InstallmentStatus.pending);
    });

    test('a part payment is partially paid, never paid', () {
      final r = row(1000);
      r.paidAmount = 600;
      r.settle();
      expect(r.status, InstallmentStatus.partiallyPaid);
      expect(r.remainingAmount, 400);
    });

    test('the exact amount settles it', () {
      final r = row(1000);
      r.paidAmount = 1000;
      r.settle();
      expect(r.status, InstallmentStatus.paid);
      expect(r.remainingAmount, 0);
    });

    test('an overdue installment is derived from the date, never stored', () {
      final r = row(1000);
      expect(r.statusOn(DateTime(2026, 9, 15)), InstallmentStatus.overdue);
      expect(r.statusOn(DateTime(2026, 8, 15)), InstallmentStatus.pending,
          reason: 'not yet due');
    });

    test('a paid installment is never overdue', () {
      final r = row(1000);
      r.paidAmount = 1000;
      r.settle();
      expect(r.statusOn(DateTime(2026, 9, 15)), InstallmentStatus.paid);
    });

    test('a part-paid past installment is overdue', () {
      final r = row(1000);
      r.paidAmount = 400;
      r.settle();
      expect(r.statusOn(DateTime(2026, 9, 15)), InstallmentStatus.overdue);
    });
  });

  group('dueRemaining — To Collect is dues, never the balance', () {
    double due({
      required double total,
      required double collected,
      required int count,
      required DateTime start,
      String frequency = 'Weekly',
      required DateTime today,
    }) =>
        KhataSchedule.dueRemaining(
          expectedRepayment: total,
          collected: collected,
          count: count,
          start: start,
          frequency: frequency,
          today: today,
        );

    test('Test 1 — weekly 1000 on 12000 outstanding means 1000, not 12000', () {
      expect(
        due(
          total: 12000,
          collected: 0,
          count: 12,
          start: DateTime(2026, 9, 22),
          today: DateTime(2026, 9, 29),
        ),
        1000,
      );
    });

    test('Test 2 — two unpaid days plus today carry forward to 3000', () {
      expect(
        due(
          total: 12000,
          collected: 0,
          count: 12,
          start: DateTime(2026, 9, 10),
          today: DateTime(2026, 10, 3),
        ),
        3000,
      );
    });

    test('Test 5 — partial leaves its remainder in To Collect', () {
      // 2000 unpaid, 500 paid against the oldest: 1500 remains + 1000 today.
      expect(
        due(
          total: 12000,
          collected: 500,
          count: 12,
          start: DateTime(2026, 9, 10),
          today: DateTime(2026, 10, 3),
        ),
        2500,
      );
    });

    test('a fully paid week drops out of To Collect', () {
      expect(
        due(
          total: 12000,
          collected: 1000,
          count: 12,
          start: DateTime(2026, 9, 10),
          today: DateTime(2026, 10, 3),
        ),
        2000,
      );
    });

    test('future weeks are never counted', () {
      expect(
        due(
          total: 12000,
          collected: 0,
          count: 12,
          start: DateTime(2026, 10, 10),
          today: DateTime(2026, 10, 3),
        ),
        0,
      );
    });

    test('an advance shrinks a future week but stays invisible until due', () {
      // 1500 on a 1000 week: week 1 clears, week 2 keeps 500 remaining.
      final now = due(
        total: 12000,
        collected: 1500,
        count: 12,
        start: DateTime(2026, 10, 1),
        today: DateTime(2026, 10, 1),
      );
      expect(now, 0, reason: 'week 1 settled, week 2 not yet due');
      // On Oct 8 only the cleared Oct 8 week has arrived: nothing due yet.
      final onOct8 = due(
        total: 12000,
        collected: 1500,
        count: 12,
        start: DateTime(2026, 10, 1),
        today: DateTime(2026, 10, 8),
      );
      expect(onOct8, 0);
      // On Oct 15 the shrunk week arrives: 500, not the full 1000.
      final later = due(
        total: 12000,
        collected: 1500,
        count: 12,
        start: DateTime(2026, 10, 1),
        today: DateTime(2026, 10, 15),
      );
      expect(later, 500,
          reason: 'Oct 8 week cleared, Oct 15 week keeps 500');
    });

    test('no schedule falls back to outstanding when due', () {
      expect(
        KhataSchedule.dueRemaining(
          expectedRepayment: 12000,
          collected: 0,
          count: 0,
          start: null,
          frequency: 'Weekly',
          today: DateTime(2026, 10, 3),
          fallbackOutstanding: 12000,
        ),
        12000,
      );
    });
  });

  group('loan status transitions', () {
    test('ACTIVE can complete, settle, refinance, default or cancel', () {
      for (final to in [
        LoanStatus.completed,
        LoanStatus.settled,
        LoanStatus.refinanced,
        LoanStatus.defaulted,
        LoanStatus.cancelled,
      ]) {
        expect(LoanStatus.active.canTransitionTo(to), isTrue, reason: '$to');
      }
    });

    test('a COMPLETED loan can be reopened', () {
      expect(LoanStatus.completed.canTransitionTo(LoanStatus.active), isTrue);
    });

    test('a CANCELLED loan is terminal', () {
      for (final to in LoanStatus.values) {
        expect(LoanStatus.cancelled.canTransitionTo(to), isFalse,
            reason: '$to');
      }
    });

    test('a WRITTEN_OFF loan can be reinstated when money is recovered', () {
      expect(LoanStatus.writtenOff.canTransitionTo(LoanStatus.active), isTrue);
    });

    test('parse maps the wire values', () {
      expect(LoanStatus.parse('COMPLETED'), LoanStatus.completed);
      expect(LoanStatus.parse('written_off'), LoanStatus.writtenOff);
      expect(LoanStatus.parse(null), LoanStatus.active);
      expect(LoanStatus.parse('ACTIVE'), LoanStatus.active);
    });

    test('legacy Closed reads as completed, never as active', () {
      // KhataMath.status wrote 'Closed' for settled loans; it must keep
      // meaning settled under the unified vocabulary.
      expect(LoanStatus.parse('Closed'), LoanStatus.completed);
      expect(isActiveKhataStatus('Closed'), isFalse);
    });

    test('isActiveKhataStatus accepts every active vocabulary', () {
      expect(isActiveKhataStatus('Active'), isTrue);
      expect(isActiveKhataStatus('ACTIVE'), isTrue);
      expect(isActiveKhataStatus(null), isTrue,
          reason: 'missing status historically meant active');
      expect(isActiveKhataStatus('COMPLETED'), isFalse);
      expect(isActiveKhataStatus('REFINANCED'), isFalse);
      expect(isActiveKhataStatus('Closed'), isFalse);
    });

    test('only open statuses still owe money', () {
      expect(LoanStatus.active.isOpen, isTrue);
      expect(LoanStatus.completed.isOpen, isTrue);
      expect(LoanStatus.cancelled.isOpen, isFalse);
      expect(LoanStatus.writtenOff.isOpen, isFalse);
      expect(LoanStatus.refinanced.isOpen, isFalse);
    });
  });
}
