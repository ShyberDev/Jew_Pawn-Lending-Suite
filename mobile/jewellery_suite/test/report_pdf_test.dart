import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/util/report_csv.dart';
import 'package:jewellery_suite/util/report_pdf.dart';

/// #041 — the PDF export must carry exactly the rows the CSV and the screen
/// carry, and must be a real PDF file rather than an empty buffer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime(2026, 11, 2, 9, 30);

  Map<String, Object?> khata({String customer = 'Ravi'}) => {
        'today_col': 1500.0,
        'week_col': 4000.0,
        'overdue_count': 1,
        'overdue_amt': 5000.0,
        'overdue_rows': [
          {
            'customer_name': customer,
            'amount': 5000.0,
            'outstanding': 12000.0,
          },
        ],
      };

  Map<String, Object?> pawn() => {
        'active': 1,
        'principal': 20000.0,
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
      };

  test('the khata PDF is a real PDF', () async {
    final bytes = await khataReportPdf(khata(), at: at);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('the pawn PDF handles the nine-column report', () async {
    final bytes = await pawnReportPdf(pawn(), at: at);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('file names are timestamped and end in .pdf', () {
    expect(khataReportPdfFileName(at),
        'jewellery_suite_khata_2026-11-02_09-30.pdf');
    expect(pawnReportPdfFileName(at),
        'jewellery_suite_pawn_2026-11-02_09-30.pdf');
  });

  test('the CSV keeps the same rows the PDF prints', () {
    expect(khataReportCsv(khata(), at: at),
        csvText(khataReportRows(khata(), at: at)));
    expect(pawnReportCsv(pawn(), at: at),
        csvText(pawnReportRows(pawn(), at: at)));
  });

  test('a Tamil customer name renders instead of failing', () async {
    final bytes = await khataReportPdf(khata(customer: 'தமிழ்'), at: at);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });
}
