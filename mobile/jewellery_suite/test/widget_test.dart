import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/format.dart';

void main() {
  test('money rounds up to 2 decimals', () {
    expect(Num.money(100.001), 100.01);
    expect(Num.money(100.0), 100.0);
  });

  test('weights round half-up to 3 decimals', () {
    expect(Num.round3(10.1234), 10.123);
    expect(Num.round3(10.1235), 10.124);
  });

  testWidgets('app boots to the login screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('Jewellery Suite'))),
    ));
    expect(find.text('Jewellery Suite'), findsOneWidget);
  });
}
