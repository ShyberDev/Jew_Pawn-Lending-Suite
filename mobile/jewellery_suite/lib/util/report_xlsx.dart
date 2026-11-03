import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import 'report_csv.dart';

/// #041 (third slice) — Excel export of the Reports screens.
///
/// Written by hand rather than with a spreadsheet package: every package that
/// writes .xlsx wants `archive 3.x`, and this app's backups run on `archive 4.x`.
/// An .xlsx file is a ZIP of a handful of XML parts, so the rows the CSV and PDF
/// already build are laid into one worksheet here — no new dependency and no
/// downgrade of the backup engine.
///
/// Text is stored as an inline string (so Tamil/Devanagari names survive) and
/// amounts are stored as numbers, so a spreadsheet can total them.

String _stamp(DateTime at) => DateFormat('yyyy-MM-dd_HH-mm').format(at);

String khataReportXlsxFileName(DateTime at) =>
    'jewellery_suite_khata_${_stamp(at)}.xlsx';

String pawnReportXlsxFileName(DateTime at) =>
    'jewellery_suite_pawn_${_stamp(at)}.xlsx';

Uint8List khataReportXlsx(Map<String, Object?> r, {required DateTime at}) =>
    buildXlsx('Khata', khataReportRows(r, at: at));

Uint8List pawnReportXlsx(Map<String, Object?> r, {required DateTime at}) =>
    buildXlsx('Pawn', pawnReportRows(r, at: at));

/// A single-sheet .xlsx workbook holding [rows] verbatim.
Uint8List buildXlsx(String sheetName, List<List<Object?>> rows) {
  final archive = Archive();

  void add(String name, String content) {
    archive.addFile(ArchiveFile.bytes(name, utf8.encode(content)));
  }

  add('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
''');
  add('_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
''');
  add('xl/workbook.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="${_xml(sheetName)}" sheetId="1" r:id="rId1"/></sheets>
</workbook>
''');
  add('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
''');
  add('xl/worksheets/sheet1.xml', _sheetXml(rows));

  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

String _sheetXml(List<List<Object?>> rows) {
  final out = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>');
  for (var r = 0; r < rows.length; r++) {
    out.write('<row r="${r + 1}">');
    final row = rows[r];
    for (var c = 0; c < row.length; c++) {
      final ref = '${_column(c)}${r + 1}';
      final value = row[c];
      if (value is num) {
        out.write('<c r="$ref"><v>$value</v></c>');
      } else {
        final text = value == null ? '' : '$value';
        out.write('<c r="$ref" t="inlineStr"><is>'
            '<t xml:space="preserve">${_xml(text)}</t>'
            '</is></c>');
      }
    }
    out.write('</row>');
  }
  out.write('</sheetData></worksheet>');
  return out.toString();
}

/// A, B, … Z, AA, AB, …
String _column(int index) {
  var n = index + 1;
  final letters = StringBuffer();
  while (n > 0) {
    final rem = (n - 1) % 26;
    letters.writeCharCode(65 + rem);
    n = (n - 1) ~/ 26;
  }
  return letters.toString().split('').reversed.join();
}

/// XML text escaping, plus a strip of control characters XML forbids.
String _xml(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    switch (rune) {
      case 0x26:
        out.write('&amp;');
      case 0x3C:
        out.write('&lt;');
      case 0x3E:
        out.write('&gt;');
      case 0x22:
        out.write('&quot;');
      case 0x27:
        out.write('&apos;');
      default:
        if (rune == 0x09 || rune == 0x0A || rune == 0x0D ||
            (rune >= 0x20 && rune != 0xFFFE && rune != 0xFFFF)) {
          out.writeCharCode(rune);
        }
    }
  }
  return out.toString();
}
