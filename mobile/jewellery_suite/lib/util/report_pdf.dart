import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_csv.dart';

/// #041 (second slice) — PDF export of the Reports screens.
///
/// The rows come from `report_csv.dart`, so the PDF, the CSV and the screen all
/// carry the same figures: there is one place that decides what a Khata or Pawn
/// report contains. Rows print one line at a time rather than in a table,
/// because the pawn report has nine columns and a table would not fit A4.
///
/// The built-in Helvetica font covers Latin-1 only, so a character it cannot
/// draw (a Tamil or Devanagari name, say) is written as `?` instead of throwing
/// mid-export. The CSV export keeps the full text.

String _stamp(DateTime at) => DateFormat('yyyy-MM-dd_HH-mm').format(at);
String _when(DateTime at) => DateFormat('yyyy-MM-dd HH:mm').format(at);

String khataReportPdfFileName(DateTime at) =>
    'jewellery_suite_khata_${_stamp(at)}.pdf';

String pawnReportPdfFileName(DateTime at) =>
    'jewellery_suite_pawn_${_stamp(at)}.pdf';

/// Latin-1 safe text for the built-in PDF font.
String pdfSafe(Object? value) {
  final text = value == null ? '' : '$value';
  final out = StringBuffer();
  for (final rune in text.runes) {
    out.writeCharCode(rune <= 0xFF ? rune : 0x3F); // 0x3F = '?'
  }
  return out.toString();
}

Future<Uint8List> khataReportPdf(Map<String, Object?> r,
        {required DateTime at}) =>
    _build('Jewellery Suite - Khata report', khataReportRows(r, at: at), at);

Future<Uint8List> pawnReportPdf(Map<String, Object?> r, {required DateTime at}) =>
    _build('Jewellery Suite - Pawn report', pawnReportRows(r, at: at), at);

Future<Uint8List> _build(
    String title, List<List<Object?>> rows, DateTime at) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey),
        ),
      ),
      build: (context) => [
        pw.Text(title,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text('Generated ${_when(at)}',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
        pw.SizedBox(height: 10),
        for (final row in rows) _line(row),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _line(List<Object?> row) {
  if (row.isEmpty) return pw.SizedBox(height: 6);
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Text(
      row.map(pdfSafe).join('   '),
      style: pw.TextStyle(
        fontSize: row.length == 1 ? 10 : 8.5,
        fontWeight:
            row.length == 1 ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}
