import 'format.dart';
import 'jewellery_math.dart';

/// Plain-text bill for a jewellery document, shared from the invoice sheet.
///
/// The figures use the same formatters the sheet shows (`fmtDate`, `inr`), so
/// the text a shopkeeper forwards matches what is on screen. Pure function —
/// the caller shares the returned string; nothing is written to the ledger.
String buildJewelleryBillText({
  required Map<String, Object?> invoice,
  required List<Map<String, Object?>> items,
  required List<Map<String, Object?>> payments,
}) {
  final docType = invoice['doc_type']?.toString() ?? '';
  final isPurchase = docType == 'PURCHASE';
  final isOrder = docType == 'ORDER';
  final label = isPurchase ? 'Purchase' : (isOrder ? 'Order' : 'Sale');
  final total = Num.toDouble(invoice['total'] ?? 0);
  final paid = Num.toDouble(invoice['amount_paid'] ?? 0);
  final outstanding = Num.toDouble(invoice['outstanding'] ?? 0);
  final lateFees = Num.toDouble(invoice['late_fee_total'] ?? 0);
  final status = invoice['status']?.toString() ?? 'Active';

  final lines = <String>[
    '${invoice['party_name'] ?? ''} · ${invoice['doc_no'] ?? ''}',
    '${fmtDate(invoice['invoice_date'])} · $label · ${invoice['metal'] ?? ''}',
    if (isOrder) status,
    '---',
  ];

  for (final item in items) {
    final line = _lineOf(item);
    final desc = item['description']?.toString().trim() ?? '';
    final retail = line.billingBasis != BillingBasis.raw;
    final name = desc.isEmpty ? 'Item' : desc;
    lines.add(
        '$name · ${line.weight.toStringAsFixed(3)} g · ${line.purityPct.toStringAsFixed(2)}% · ₹${moneyWhole(line.pureRate)}/g');
    if (retail) {
      lines.add(line.billingBasis == BillingBasis.kdm
          ? '  KDM · wastage ${line.wastageWeight.toStringAsFixed(3)} g · '
              'billing ${line.billedWeight.toStringAsFixed(3)} g × ₹${moneyWhole(line.pureRate)} = ${inr(line.metalValue)} · '
              'making ${inr(line.makingAmount)}'
          : '  Non-KDM · billing ${line.billedWeight.toStringAsFixed(3)} g × '
              '₹${moneyWhole(line.pureRate)} = ${inr(line.metalValue)} · '
              'making ${inr(line.makingAmount)}');
    } else {
      lines.add(
          '  total ${line.totalEquivalentWeight.toStringAsFixed(3)} g × '
          '₹${moneyWhole(line.pureRate)} = ${inr(line.metalValue + line.makingAmount)}');
    }
    lines.add('  ${inr(line.total)}');
  }

  lines.add('---');
  lines.add('Payable ${inr(total)}');
  lines.add('${isPurchase ? 'Paid' : 'Received'} ${inr(paid)}');
  if (lateFees > 0) lines.add('Late fee ${inr(lateFees)}');
  lines.add('Balance ${inr(outstanding)}');

  if (payments.isNotEmpty) {
    lines.add('---');
    lines.add('Payments');
    for (final p in payments) {
      lines.add(
          '${fmtDate(p['pay_date'])} · ${p['payment_mode'] ?? ''} · ${inr(Num.toDouble(p['amount'] ?? 0))}');
    }
  }
  return lines.join('\n');
}

JewelleryLine _lineOf(Map<String, Object?> item) => JewelleryMath.line(
      weight: Num.toDouble(item['net_weight']),
      purityPct: Num.toDouble(item['purity']),
      pureRate: Num.toDouble(item['rate_per_gram']),
      makingMode: MakingMode.values.firstWhere(
        (m) => m.name == (item['making_mode']?.toString() ?? ''),
        orElse: () => MakingMode.none,
      ),
      makingValue: Num.toDouble(item['making_value']),
      additionalCost: Num.toDouble(item['additional_cost']),
      discount: Num.toDouble(item['discount']),
      billingBasis: BillingBasis.values.firstWhere(
        (b) => b.name == (item['billing_basis']?.toString() ?? ''),
        orElse: () => BillingBasis.raw,
      ),
      wastagePct: Num.toDouble(item['wastage_pct']),
      makingCharge: Num.toDouble(item['making_charge']),
    );
