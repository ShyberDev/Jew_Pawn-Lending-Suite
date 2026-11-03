import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/report_csv.dart';

/// #041 (first slice) — the CSV export must quote safely, write plain numbers
/// for a spreadsheet, and carry exactly the figures the screen computed.
void main() {
  test('cells are quoted only when they need to be', () {
    expect(csvCell('Ravi'), 'Ravi');
    expect(csvCell(null), '');
    expect(csvCell('Ravi, Kumar'), '"Ravi, Kumar"');
    expect(csvCell('say "hi"'), '"say ""hi"""');
    expect(csvCell('line\nbreak'), '"line\nbreak"');
  });

  test('rows become CRLF-terminated CSV', () {
    expect(csvText([['a', 'b'], [1, 2]]), 'a,b\r\n1,2\r\n');
  });

  test('the khata report carries the summary and the overdue list', () {
    final at = DateTime(2026, 11, 2, 9, 30);
    final csv = khataReportCsv({
      'today_col': 1500.0,
      'week_col': 4000.0,
      'month_col': 9000.0,
      'total_given': 50000.0,
      'total_received': 20000.0,
      'interest_earned': 3000.0,
      'outstanding': 30000.0,
      'overdue_count': 1,
      'overdue_amt': 960.0,
      'bad_credit': 0,
      'blocked': 0,
      'overdue_rows': [
        {'customer_name': 'Ravi, Kumar', 'amount': 960.0, 'outstanding': 12000.0},
      ],
      'today_rows': [
        {'customer': 'Suresh', 'amount': 500.0, 'collection_date': '2026-11-02'},
      ],
      'village_rows': [
        {'name': 'Pallipatti', 'count': 2, 'amount': 30000.0},
      ],
      'customer_rows': [
        {'name': 'Ravi', 'amount': 12000.0},
      ],
    }, at: at);

    expect(csv, contains('Jewellery Suite — Khata report'));
    expect(csv, contains('2026-11-02 09:30'));
    expect(csv, contains('Outstanding (active),30000.0'),
        reason: 'amounts stay plain numbers so a spreadsheet reads money');
    expect(csv, contains('"Ravi, Kumar",960.0,12000.0'),
        reason: 'a comma in a name must not break the columns');
    expect(csv, contains('Pallipatti,2,30000.0'));
    expect(
        khataReportFileName(at), 'jewellery_suite_khata_2026-11-02_09-30.csv');
  });

  test('the pawn report lists every loan in view', () {
    final at = DateTime(2026, 11, 2, 9, 30);
    final csv = pawnReportCsv({
      'active': 1,
      'principal': 20000.0,
      'interest': 1800.0,
      'receivable': 21800.0,
      'gold_reserve': 12.5,
      'silver_reserve': 0.0,
      'released_count': 0,
      'realised': 0.0,
      'rows': [
        {
          'customer_name': 'Phone QB',
          'customer_id': 'A04',
          'loan_date': '2026-11-01',
          'due_date': '2026-12-01',
          'interest_basis': 'Gold',
          'loan_amount': 20000.0,
          'interest_rate': 2.0,
          'amount_paid': 0.0,
        },
      ],
    }, at: at);

    expect(csv, contains('Active loans in view,1'));
    expect(csv, contains('Phone QB,A04,2026-11-01,2026-12-01,Gold'));
    expect(pawnReportFileName(at), 'jewellery_suite_pawn_2026-11-02_09-30.csv');
  });
}
