import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
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
/// Text is drawn with the Noto Sans fonts bundled under `assets/fonts/`:
/// Latin/Sanskrit-transliteration names, Tamil names and Devanagari names all
/// print as typed. The PDF package's built-in Helvetica covers Latin-1 only and
/// would have to write `?` for those names. If an asset cannot be loaded the
/// document still renders with the built-in font rather than failing.

String _stamp(DateTime at) => DateFormat('yyyy-MM-dd_HH-mm').format(at);
String _when(DateTime at) => DateFormat('yyyy-MM-dd HH:mm').format(at);

String khataReportPdfFileName(DateTime at) =>
    'jewellery_suite_khata_${_stamp(at)}.pdf';

String pawnReportPdfFileName(DateTime at) =>
    'jewellery_suite_pawn_${_stamp(at)}.pdf';

/// Loaded once per process; the byte data is reused by every export.
class _PdfFonts {
  static pw.Font? base;
  static pw.Font? tamil;
  static pw.Font? devanagari;
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    base = await _tryFont('assets/fonts/NotoSans-Regular.ttf');
    tamil = await _tryFont('assets/fonts/NotoSansTamil-Regular.ttf');
    devanagari = await _tryFont('assets/fonts/NotoSansDevanagari-Regular.ttf');
  }

  static Future<pw.Font?> _tryFont(String asset) async {
    try {
      return pw.Font.ttf(await rootBundle.load(asset));
    } catch (_) {
      return null;
    }
  }

  /// `null` means "use the built-in font".
  static pw.ThemeData? theme() {
    final main = base;
    if (main == null) return null;
    return pw.ThemeData.withFont(
      base: main,
      bold: main,
      italic: main,
      boldItalic: main,
      fontFallback: [
        if (tamil != null) tamil!,
        if (devanagari != null) devanagari!,
      ],
    );
  }
}

Future<Uint8List> khataReportPdf(Map<String, Object?> r,
        {required DateTime at}) =>
    _build('Jewellery Suite - Khata report', khataReportRows(r, at: at), at);

Future<Uint8List> pawnReportPdf(Map<String, Object?> r, {required DateTime at}) =>
    _build('Jewellery Suite - Pawn report', pawnReportRows(r, at: at), at);

Future<Uint8List> _build(
    String title, List<List<Object?>> rows, DateTime at) async {
  await _PdfFonts.load();
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      theme: _PdfFonts.theme(),
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
      row.map((cell) => cell == null ? '' : '$cell').join('   '),
      style: pw.TextStyle(
        fontSize: row.length == 1 ? 10 : 8.5,
        fontWeight:
            row.length == 1 ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}
