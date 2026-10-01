import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/format.dart';

/// Recency display for member rows: only real money movement stamps the
/// clock, so the text must never invent a time it cannot prove.
void main() {
  final now = DateTime(2026, 9, 30, 12, 0, 0);
  String ago(DateTime dt) => timeAgo(dt.toIso8601String(), now: now);

  group('timeAgo', () {
    test('seconds', () {
      expect(ago(now.subtract(const Duration(seconds: 1))), '1 sec ago');
      expect(ago(now.subtract(const Duration(seconds: 45))), '45 sec ago');
    });

    test('minutes', () {
      expect(ago(now.subtract(const Duration(minutes: 12))), '12 min ago');
      expect(ago(now.subtract(const Duration(minutes: 1))), '1 min ago');
    });

    test('hours keep counting to 47', () {
      expect(ago(now.subtract(const Duration(hours: 5))), '5 hours ago');
      expect(ago(now.subtract(const Duration(hours: 24))), '24 hours ago');
      expect(ago(now.subtract(const Duration(hours: 47))), '47 hours ago');
    });

    test('days continue without hiding', () {
      expect(ago(now.subtract(const Duration(hours: 48))), '2 days ago');
      expect(ago(now.subtract(const Duration(days: 3))), '3 days ago');
    });

    test('unprovable times show nothing', () {
      expect(timeAgo(null, now: now), '');
      expect(timeAgo('', now: now), '');
      expect(timeAgo('not-a-date', now: now), '');
      expect(ago(now.add(const Duration(minutes: 1))), '',
          reason: 'future timestamps show nothing');
    });
  });
}
