import 'package:flutter_test/flutter_test.dart';

import 'package:jewellery_suite/util/jewellery_bill_text.dart';

/// #087: the bill text shared from the invoice sheet must match the figures
/// the sheet itself shows — same dates, same whole-rupee grouping.
void main() {
  Map<String, Object?> item({
    required String desc,
    required num weight,
    required num lineTotal,
  }) => {
        'description': desc,
        'net_weight': weight,
        'purity': 92,
        'rate_per_gram': 7200,
        'billing_basis': 'kdm',
        'wastage_pct': 8,
        'making_charge': 1500,
        'making_mode': 'none',
        'making_value': 0,
        'additional_cost': 0,
        'discount': 0,
        'total': lineTotal,
      };

  test('a sale bill carries party, doc, lines and balance', () {
    final text = buildJewelleryBillText(
      invoice: {
        'party_name': 'Ravi Kumar',
        'doc_no': 'SAL-20261106-0001',
        'doc_type': 'SALE',
        'metal': 'GOLD',
        'invoice_date': '2026-11-06T10:00:00.000',
        'total': 79260,
        'amount_paid': 40000,
        'outstanding': 39260,
        'late_fee_total': 0,
        'status': 'Active',
      },
      items: [
        item(desc: 'Gold chain', weight: 10, lineTotal: 79260),
      ],
      payments: const [],
    );

    expect(text, contains('Ravi Kumar'));
    expect(text, contains('SAL-20261106-0001'));
    expect(text, contains('06-11-26'));
    expect(text, contains('Gold chain'));
    expect(text, contains('10.000 g'));
    expect(text, contains('Payable ₹79,260'));
    expect(text, contains('Received ₹40,000'));
    expect(text, contains('Balance ₹39,260'));
  });

  test('a purchase bill says Paid, not Received', () {
    final text = buildJewelleryBillText(
      invoice: {
        'party_name': 'Raj Supplier',
        'doc_no': 'PUR-20261106-0001',
        'doc_type': 'PURCHASE',
        'metal': 'GOLD',
        'invoice_date': '2026-11-06T10:00:00.000',
        'total': 50000,
        'amount_paid': 50000,
        'outstanding': 0,
        'late_fee_total': 0,
        'status': 'Active',
      },
      items: const [],
      payments: const [],
    );

    expect(text, contains('Purchase'));
    expect(text, contains('Paid ₹50,000'));
    expect(text, isNot(contains('Received')));
  });

  test('late fee and payments are stated on the bill', () {
    final text = buildJewelleryBillText(
      invoice: {
        'party_name': 'Ravi Kumar',
        'doc_no': 'SAL-20261106-0001',
        'doc_type': 'SALE',
        'metal': 'GOLD',
        'invoice_date': '2026-11-06T10:00:00.000',
        'total': 79260,
        'amount_paid': 40000,
        'outstanding': 39760,
        'late_fee_total': 500,
        'status': 'Active',
      },
      items: [
        item(desc: 'Gold chain', weight: 10, lineTotal: 79260),
      ],
      payments: const [
        {'pay_date': '2026-11-06T11:00:00.000', 'payment_mode': 'CASH', 'amount': 40000},
      ],
    );

    expect(text, contains('Late fee ₹500'));
    expect(text, contains('CASH'));
  });
}
