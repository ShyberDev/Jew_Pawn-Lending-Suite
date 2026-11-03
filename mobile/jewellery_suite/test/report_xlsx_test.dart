import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/util/report_xlsx.dart';

/// #041 — the Excel export must be a workbook a spreadsheet can open: a ZIP of
/// the OOXML parts, with numbers stored as numbers and text stored as text.
void main() {
  final at = DateTime(2026, 11, 2, 9, 30);

  Map<String, Object?> khata({String customer = 'Ravi'}) => {
        'today_col': 1500.0,
        'overdue_count': 1,
        'overdue_rows': [
          {
            'customer_name': customer,
            'amount': 5000.0,
            'outstanding': 12000.0,
          },
        ],
      };

  String sheetOf(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheet = archive.files
        .firstWhere((f) => f.name == 'xl/worksheets/sheet1.xml');
    return utf8.decode(sheet.readBytes()!);
  }

  test('the khata workbook is a zip with a worksheet', () {
    final bytes = khataReportXlsx(khata(), at: at);
    expect(bytes[0], 0x50); // P
    expect(bytes[1], 0x4B); // K
    final names = ZipDecoder().decodeBytes(bytes).files.map((f) => f.name);
    expect(names, contains('xl/workbook.xml'));
    expect(names, contains('xl/worksheets/sheet1.xml'));
  });

  test('text is inline and amounts stay numeric', () {
    final sheet = sheetOf(khataReportXlsx(khata(), at: at));
    expect(sheet, contains('Ravi'));
    expect(sheet, contains('<v>1500.0</v>'));
    expect(sheet, contains('<v>5000.0</v>'));
  });

  test('a Tamil customer name is written as typed', () {
    final sheet = sheetOf(khataReportXlsx(khata(customer: 'தமிழ்'), at: at));
    expect(sheet, contains('தமிழ்'));
  });

  test('file names are timestamped and end in .xlsx', () {
    expect(khataReportXlsxFileName(at),
        'jewellery_suite_khata_2026-11-02_09-30.xlsx');
    expect(pawnReportXlsxFileName(at),
        'jewellery_suite_pawn_2026-11-02_09-30.xlsx');
  });

  test('the pawn sheet holds all nine columns in one row', () {
    final bytes = pawnReportXlsx({
      'active': 1,
      'rows': [
        {
          'customer_name': 'Ravi',
          'customer_id': 'A01',
          'loan_date': '02-11-26',
          'loan_amount': 20000.0,
          'interest_rate': 3.0,
          'amount_paid': 0.0,
        },
      ],
    }, at: at);
    final sheet = sheetOf(bytes);
    expect(sheet, contains('A01'));
    expect(sheet, contains('02-11-26'));
    expect(sheet, contains('r="I'));
  });
}
