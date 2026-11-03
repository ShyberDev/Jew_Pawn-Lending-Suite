import 'package:intl/intl.dart';

/// #041 (first slice) — CSV export of the Reports screens.
///
/// Deliberately **text only**: no PDF/Excel package is available in this
/// machine's offline pub cache, and a spreadsheet the shop can open in Google
/// Sheets beats a button that cannot be built. The figures are the ones the
/// screen already computed (`_r`), so the export cannot disagree with it.
///
/// Amounts are written as plain numbers (no `₹`, no thousands separators) so a
/// spreadsheet treats them as money instead of text.

/// One CSV cell, quoted per RFC 4180 when it contains a comma, quote or break.
String csvCell(Object? value) {
  final text = value == null ? '' : '$value';
  if (text.contains(RegExp(r'[",\r\n]'))) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

/// Rows joined with CRLF, ending with one, so Excel on Android opens it cleanly.
String csvText(List<List<Object?>> rows) =>
    '${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n';

String _stamp(DateTime at) => DateFormat('yyyy-MM-dd_HH-mm').format(at);
String _when(DateTime at) => DateFormat('yyyy-MM-dd HH:mm').format(at);

String khataReportFileName(DateTime at) =>
    'jewellery_suite_khata_${_stamp(at)}.csv';

String pawnReportFileName(DateTime at) =>
    'jewellery_suite_pawn_${_stamp(at)}.csv';

/// The Khata tab: the summary card first, then the lists behind its rows.
String khataReportCsv(Map<String, Object?> r, {required DateTime at}) {
  final overdue = (r['overdue_rows'] as List? ?? const [])
      .cast<Map<String, Object?>>();
  final villages =
      (r['village_rows'] as List? ?? const []).cast<Map<String, Object?>>();
  final customers =
      (r['customer_rows'] as List? ?? const []).cast<Map<String, Object?>>();
  final today =
      (r['today_rows'] as List? ?? const []).cast<Map<String, Object?>>();

  final rows = <List<Object?>>[
    ['Jewellery Suite — Khata report'],
    ['Generated', _when(at)],
    [],
    ['Summary', 'Amount'],
    ["Today's collection", r['today_col']],
    ['This week (7 days)', r['week_col']],
    ['This month (30 days)', r['month_col']],
    ['Total given (all time)', r['total_given']],
    ['Total received (all time)', r['total_received']],
    ['Interest earned', r['interest_earned']],
    ['Outstanding (active)', r['outstanding']],
    [],
    ['Overdue accounts', r['overdue_count']],
    ['Collectable today', r['overdue_amt']],
    ['Bad-credit customers', r['bad_credit']],
    ['Blocked / inactive', r['blocked']],
    [],
    ['Overdue — customer', 'Collectable now', 'Balance'],
    for (final o in overdue)
      [
        o['customer_name'] ?? o['customer'] ?? '-',
        o['amount'],
        o['outstanding'],
      ],
    [],
    ["Today's collections — customer", 'Amount', 'Date'],
    for (final c in today)
      [c['customer'] ?? c['customer_name'] ?? '-', c['amount'], c['collection_date']],
    [],
    ['Village', 'Active loans', 'Outstanding'],
    for (final v in villages) [v['name'], v['count'], v['amount']],
    [],
    ['Customer', 'Outstanding'],
    for (final c in customers) [c['name'], c['amount']],
  ];
  return csvText(rows);
}

/// The Pawn tab: the metric cards, then every loan the filters left in view.
String pawnReportCsv(Map<String, Object?> r, {required DateTime at}) {
  final loans = (r['rows'] as List? ?? const []).cast<Map<String, Object?>>();
  final rows = <List<Object?>>[
    ['Jewellery Suite — Pawn report'],
    ['Generated', _when(at)],
    [],
    ['Summary', 'Value'],
    ['Active loans in view', r['active']],
    ['Principal outstanding', r['principal']],
    ['Interest due', r['interest']],
    ['Receivable', r['receivable']],
    ['Gold reserve (g)', r['gold_reserve']],
    ['Silver reserve (g)', r['silver_reserve']],
    ['Released loans', r['released_count']],
    ['Interest realised', r['realised']],
    [],
    [
      'Customer',
      'Book ID',
      'Loan date',
      'Due date',
      'Item',
      'Status',
      'Loan amount',
      'Interest %',
      'Paid',
    ],
    for (final l in loans)
      [
        l['customer_name'] ?? '-',
        l['customer_id'] ?? '',
        l['loan_date'] ?? '',
        l['due_date'] ?? '',
        l['interest_basis'] ?? '',
        l['status'] ?? 'Active',
        l['loan_amount'],
        l['interest_rate'],
        l['amount_paid'],
      ],
  ];
  return csvText(rows);
}
