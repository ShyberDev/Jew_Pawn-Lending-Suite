import '../util/format.dart';
import 'slip_ocr_fields.dart';

/// Maps the raw text of a pawn slip onto the New Pawn Loan form fields:
/// ID Number, Customer Name, Item, Loan amount, Date, Item details and
/// Customer Address. The parser is deliberately forgiving — anything it is
/// unsure about is simply left blank for the shopkeeper to confirm on screen.
SlipFields parseSlipText(String raw) {
  final lines = raw
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return SlipFields(rawText: raw);

  // ------------------------------------------------------------ customer name
  final name = _afterLabel(lines, [
    RegExp(r'^(customer\s*name|name\s*of\s*customer|customer)\s*[:\-]?\s*(.+)$',
        caseSensitive: false),
  ], takeGroup: 2);

  // ------------------------------------------------------------- ID number
  var id = '';
  final idRe = RegExp(
      r'\b(id\s*(no\.?|num(ber)?)?|aad?haar|aadhaar|pan|voter|licen[cs]e|passport)\b'
      r'.*?([A-Z]{0,4}\s*[- ]?\s*\d{4,10})',
      caseSensitive: false);
  for (final line in lines) {
    final m = idRe.firstMatch(line);
    if (m != null) {
      final candidate =
          m.group(2)!.replaceAll(RegExp(r'\s+'), '').replaceAll('--', '-');
      // A bare run of digits is usually not an ID — keep letters or a dash.
      if (candidate.contains('-') || RegExp(r'[A-Z]').hasMatch(candidate)) {
        id = candidate;
        break;
      }
    }
  }

  // ------------------------------------------------------------ loan amount
  double? amount;
    final moneyRe = RegExp(r'(?:₹|rs\.?\s*)?(\d[\d,]*\.?\d*)', caseSensitive: false);
  final moneyKeywords =
      RegExp(r'(loan|amount|amt|advance|given|sanction|principal|total)',
          caseSensitive: false);
  final candidates = <double>[];
  for (final line in lines) {
    if (!moneyKeywords.hasMatch(line)) continue;
    for (final m in moneyRe.allMatches(line)) {
      final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (v == null || v <= 0) continue;
      // Skip dates / weights / small numbers — a loan amount is substantial.
      if (v < 100) continue;
      if (RegExp(r'\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}').hasMatch(m.group(0)!)) continue;
      candidates.add(v);
    }
  }
  if (candidates.isEmpty) {
    for (final line in lines) {
      for (final m in moneyRe.allMatches(line)) {
        final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v != null && v >= 1000) candidates.add(v);
      }
    }
  }
  if (candidates.isNotEmpty) {
    amount = candidates.reduce((a, b) => a > b ? a : b);
  }

  // ------------------------------------------------------------------- date
  DateTime? date;
  final dateRe = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b');
  for (final line in lines) {
    final m = dateRe.firstMatch(line);
    if (m == null) continue;
    var a = int.parse(m.group(1)!);
    var b = int.parse(m.group(2)!);
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    // Indian slips are normally day-first; fall back to month-first only when
    // the first number cannot be a day.
    var day = a;
    var month = b;
    if (a > 12 && b <= 12) {
      day = a;
      month = b;
    } else if (b > 12 && a <= 12) {
      day = b;
      month = a;
    }
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      date = DateTime(y, month, day);
    }
    if (date != null) break;
  }

  // ------------------------------------------------------------------- item
  final item = _afterLabel(lines, [
    RegExp(r'^\s*item\s*(name)?\s*[:\-]?\s*(.+)$', caseSensitive: false),
  ], takeGroup: 2);
  var details = _afterLabel(lines, [
    RegExp(r'^\s*item\s*details?\s*[:\-]?\s*(.+)$', caseSensitive: false),
    RegExp(r'^\s*(details?|description|particulars)\s*[:\-]\s*(.+)$',
        caseSensitive: false),
  ], takeGroup: 2);
  if (details.isEmpty) details = item;

  // ---------------------------------------------------------------- address
  var address = _afterLabel(lines, [
    RegExp(r'^\s*(customer\s*address|address)\s*[:\-]?\s*(.+)$', caseSensitive: false),
  ], takeGroup: 2);
  if (address.isEmpty) {
    for (final line in lines) {
      if (RegExp(r'\b\d{6}\b').hasMatch(line) ||
          RegExp(r'\b(village|vill|dist|district|post|pin)\b', caseSensitive: false)
              .hasMatch(line)) {
        address = line;
        break;
      }
    }
  }

  return SlipFields(
    idNumber: id,
    customerName: name,
    item: item,
    itemDetails: details,
    amount: amount == null ? '' : Num.moneyText(amount),
    date: date,
    address: address,
    rawText: raw,
  );
}

/// Returns the text of the first line matching [patterns]. When [takeGroup] is
/// given the parser's value is taken from that capture group, otherwise the
/// whole matched text. If a label line has no value, the next line is used.
String _afterLabel(List<String> lines, List<RegExp> patterns,
    {int? takeGroup}) {
  for (var i = 0; i < lines.length; i++) {
    for (final re in patterns) {
      final m = re.firstMatch(lines[i]);
      if (m == null) continue;
      final value = (takeGroup != null && m.groupCount >= takeGroup)
          ? (m.group(takeGroup) ?? '').trim()
          : m.group(0)!.trim();
      if (value.isNotEmpty) return value;
      // Label on its own line — the value is on the next one.
      if (i + 1 < lines.length) return lines[i + 1];
    }
  }
  return '';
}
