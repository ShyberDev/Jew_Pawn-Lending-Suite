import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/util/report_csv.dart';
import 'package:jewellery_suite/util/report_pdf.dart';

/// #090 — the jewellery bill PDF must be a real PDF carrying the same figures
/// as the plain-text bill (#087), with a timestamped file name.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime(2026, 11, 8, 9, 30);

  Map<String, Object?> invoice({String party = 'Ravi Kumar'}) => {
        'party_name': party,
        'doc_no': 'SAL-20261106-0001',
        'doc_type': 'SALE',
        'metal': 'GOLD',
        'invoice_date': '2026-11-06T10:00:00.000',
        'total': 79260,
        'amount_paid': 40000,
        'outstanding': 39760,
        'late_fee_total': 500,
        'status': 'Active',
      };

  List<Map<String, Object?>> items() => [
        {
          'description': 'Gold chain',
          'net_weight': 10,
          'purity': 92,
          'rate_per_gram': 7200,
          'billing_basis': 'kdm',
          'wastage_pct': 8,
          'making_charge': 1500,
          'making_mode': 'none',
          'making_value': 0,
          'additional_cost': 0,
          'discount': 0,
        },
      ];

  test('the bill PDF is a real PDF', () async {
    final bytes = await jewelleryBillPdf(invoice(), items(), [],
        at: at);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('file names carry the doc number and end in .pdf', () {
    expect(
        jewelleryBillPdfFileName('SAL-20261106-0001', at),
        'jewellery_suite_bill_SAL-20261106-0001_2026-11-08_09-30.pdf');
  });

  test('the CSV keeps the same rows the PDF prints', () {
    expect(
        jewelleryBillCsv(invoice(), items(), [], at: at),
        csvText(jewelleryBillRows(invoice(), items(), [], at: at)));
  });

  test('a Tamil customer name renders instead of failing', () async {
    final bytes =
        await jewelleryBillPdf(invoice(party: 'தமிழ்'), items(), [], at: at);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });
}
