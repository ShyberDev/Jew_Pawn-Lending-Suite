import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/overdue_orders.dart';

/// #088: the dashboard banner counts overdue orders with the same rule the
/// Orders list uses — Pending/Ready, promised date before today.
void main() {
  Map<String, Object?> order(String status, String? promised) => {
        'status': status,
        'promised_date': promised,
      };

  final today = DateTime(2026, 11, 8);

  test('a pending order promised yesterday is overdue', () {
    expect(
        countOverdueOrders([order('Pending', '2026-11-07')], now: today), 1);
  });

  test('ready orders count; promised today or later do not', () {
    expect(
        countOverdueOrders(
            [order('Ready', '2026-11-08'), order('Pending', '2026-11-20')],
            now: today),
        0);
  });

  test('delivered, cancelled and date-less orders are never overdue', () {
    expect(
        countOverdueOrders(
            [
              order('Delivered', '2026-11-01'),
              order('Cancelled', '2026-11-01'),
              order('Pending', ''),
            ],
            now: today),
        0);
  });
}
