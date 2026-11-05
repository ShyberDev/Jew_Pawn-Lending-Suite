import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/features/interest_calculator/screens/interest_calculator_screen.dart';
import 'package:jewellery_suite/features/khata/screens/khata_screen.dart';
import 'package:jewellery_suite/features/reports/screens/reports_screen.dart';
import 'package:jewellery_suite/state/app_state.dart';
import 'package:jewellery_suite/ui/palette.dart';

/// Dark-mode regression (the debt left in the v1.2.8 change log, closed
/// 2026-11-04): several labels were painted with the hard-coded near-black
/// `kInk`, so on the dark surface they read black-on-black. Every one of them
/// must follow the theme — `inkOf(context)` — exactly like the pawn chips
/// fixed in #06L. Light mode must keep the ink it always had.
void main() {
  late LocalDb local;
  late AppState state;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_dark_ink_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'dark_ink.db'));
    state = AppState(local);
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> pump(
      WidgetTester tester, Widget screen, Brightness brightness) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  /// palette.dart's dark ink — off-white, not the light-mode near-black.
  const darkInk = Color(0xFFECECEC);

  testWidgets('report tabs use the dark-aware ink', (tester) async {
    await pump(tester, const ReportsScreen(), Brightness.dark);

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.labelColor, darkInk);
  });

  testWidgets('interest-calculator chips are readable in dark mode',
      (tester) async {
    await pump(tester, const InterestCalculatorScreen(), Brightness.dark);

    final chip = tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Compound'));
    expect(chip.labelStyle!.color, darkInk);
  });

  testWidgets('khata filter chips are readable in dark mode', (tester) async {
    await pump(
      tester,
      const KhataCustomersScreen(khataName: 'Khata', khataType: 'given'),
      Brightness.dark,
    );

    final chip = tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Upcoming'));
    expect(chip.labelStyle!.color, darkInk);
  });

  testWidgets('the same chips stay ink-coloured in light mode', (tester) async {
    await pump(
      tester,
      const KhataCustomersScreen(khataName: 'Khata', khataType: 'given'),
      Brightness.light,
    );

    final chip = tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Upcoming'));
    expect(chip.labelStyle!.color, kInk);
  });
}
