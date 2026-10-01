import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/ui/khata_screen.dart'
    show memberIsDue, reminderIsLater;

/// The rule the shop reported as wrong: a reminder set to TODAY must stay RED
/// (due today). Only a FUTURE promised date turns the row blue.
void main() {
  final today = DateTime(2026, 9, 28);

  test('reminder set to today -> still due (red), not blue', () {
    expect(reminderIsLater(today, today), isFalse);
    expect(memberIsDue(0, true), isTrue, reason: 'due today');
  });

  test('reminder set to yesterday -> still due (red)', () {
    expect(reminderIsLater(today.subtract(const Duration(days: 1)), today),
        isFalse);
    expect(memberIsDue(1, false), isTrue, reason: 'late');
  });

  test('reminder set to a future date -> promised (blue)', () {
    expect(reminderIsLater(today.add(const Duration(days: 1)), today), isTrue);
    expect(reminderIsLater(today.add(const Duration(days: 7)), today), isTrue);
    expect(reminderIsLater(DateTime(2026, 10, 28), today), isTrue);
  });

  test('no reminder at all -> not promised', () {
    expect(reminderIsLater(null, today), isFalse);
  });

  test('time of day does not matter — only the day', () {
    expect(reminderIsLater(DateTime(2026, 9, 28, 23, 30), today), isFalse);
    expect(reminderIsLater(DateTime(2026, 9, 29, 0, 5), today), isTrue);
  });

  test('due means owing money with the date arrived', () {
    expect(memberIsDue(0, false), isFalse, reason: 'nothing due');
    expect(memberIsDue(3, false), isTrue);
    expect(memberIsDue(0, true), isTrue);
  });
}
