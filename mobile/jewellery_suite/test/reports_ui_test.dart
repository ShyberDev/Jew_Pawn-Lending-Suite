import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jewellery_suite/data/local_db.dart';
import 'package:jewellery_suite/features/reports/screens/reports_screen.dart';
import 'package:jewellery_suite/state/app_state.dart';

/// 2026-11-04 report feedback:
/// * the Khata tab reads like the Pawn tab — filters and metric cards, not a
///   long list of tappable rows — with the collections themselves listed;
/// * one share button opens a file-type chooser (PDF / Excel / CSV) before
///   Android asks which app or device should receive it.
void main() {
  late LocalDb local;
  late AppState state;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('js_reports_ui_');
    local = LocalDb();
    await local.init(pathOverride: p.join(dir.path, 'reports_ui.db'));
    state = AppState(local);
  });

  tearDown(() async {
    await local.db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> pumpReports(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: ReportsScreen()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  testWidgets('the Khata tab uses filters and metric cards', (tester) async {
    await pumpReports(tester);

    expect(find.text('PERIOD'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'This month'), findsOneWidget);
    expect(find.text('Collected in view'), findsOneWidget);
    expect(find.text('Collectable now'), findsOneWidget);
    expect(find.text('COLLECTIONS IN VIEW'), findsOneWidget);
    // The old screen's headline rows are gone.
    expect(find.text('Outstanding overall'), findsNothing);
    expect(find.text('Village-wise'), findsNothing);
  });

  testWidgets('Overdue switches the list to the loans behind the figure',
      (tester) async {
    await pumpReports(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Overdue'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('OVERDUE LOANS'), findsOneWidget);
    expect(find.text('COLLECTIONS IN VIEW'), findsNothing);
  });

  testWidgets('one share button, then PDF / Excel / CSV', (tester) async {
    await pumpReports(tester);

    expect(find.byKey(const ValueKey('reports-export')), findsOneWidget);
    expect(find.byKey(const ValueKey('export-pdf')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('reports-export')));
    await tester.pumpAndSettle();

    expect(find.text('Share Khata report'), findsOneWidget);
    expect(find.byKey(const ValueKey('export-pdf')), findsOneWidget);
    expect(find.byKey(const ValueKey('export-xlsx')), findsOneWidget);
    expect(find.byKey(const ValueKey('export-csv')), findsOneWidget);

    // Dismissing the chooser leaves the report untouched.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('export-pdf')), findsNothing);
    expect(find.text('Collected in view'), findsOneWidget);
  });
}
