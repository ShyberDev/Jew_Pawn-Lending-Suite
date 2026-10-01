import 'package:flutter/material.dart';
import 'package:jewellery_suite/util/format.dart';

import '../data/migration_v11.dart';
import 'palette.dart';
import 'widgets.dart';

/// The one refinance dialog for the whole app.
///
/// Both the customer profile and the loan detail sheet open this, so a
/// refinance can never again mean two different things on two screens.
///
/// Frozen rules:
/// - Previous Outstanding is automatic and read-only.
/// - Fresh Cash is physical money handed over now — never the old balance.
/// - Interest starts BLANK; the previous interest shows as reference text.
/// - Interest Only hides Installments.
/// - Collection amount defaults to obligation ÷ installments and stays
///   editable; blank means the default.
Future<RefinanceParams?> showRefinanceDialog(
    BuildContext context, Map<String, Object?> loan) {
  final prevOut = Num.rupees(Num.toDouble(loan['outstanding']));
  final prevInterest = Num.rupees(Num.toDouble(loan['interest_amount']));
  final freshCtl = TextEditingController();
  final interestCtl = TextEditingController();
  final installmentsCtl = TextEditingController(text: '12');
  final collectionCtl = TextEditingController();
  final noteCtl = TextEditingController();
  var paymentType =
      MigrationV11.isInterestOnly(loan) ? 'Interest Only' : 'Installment';
  var frequency = '${loan['collection_frequency'] ?? 'Weekly'}';
  if (!['Weekly', 'Biweekly', 'Monthly'].contains(frequency)) {
    frequency = 'Weekly';
  }

  return showDialog<RefinanceParams>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) {
        final isIO = paymentType == 'Interest Only';
        final fresh = Num.rupees(parseMoney(freshCtl.text));
        final interest = Num.rupees(parseMoney(interestCtl.text));
        final newPrincipal = Num.rupees(prevOut + fresh);
        final newTotal =
            Num.rupees(isIO ? newPrincipal : newPrincipal + interest);
        final count =
            isIO ? 0 : (int.tryParse(installmentsCtl.text) ?? 12);
        final fallback =
            (isIO || count <= 0) ? interest : Num.rupees(newTotal / count);
        return AlertDialog(
          title: const Text('Refinance'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                      color: kGold.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                      'Previous Outstanding: ₹${moneyWholeDown(prevOut)} (fixed)',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kGoldDark)),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: freshCtl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: fieldDecoration('New Amount — cash given now'),
                    onChanged: (_) => setDlg(() {})),
                const SizedBox(height: 10),
                TextField(
                    controller: interestCtl,
                    keyboardType: TextInputType.number,
                    decoration: fieldDecoration('Interest (blank = none)'),
                    onChanged: (_) => setDlg(() {})),
                if (prevInterest > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                        'Previous interest was ₹${moneyWholeDown(prevInterest)} — enter a new amount above.',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF8A6D14))),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in const ['Installment', 'Interest Only'])
                      ChoiceChip(
                        label: Text(t,
                            style: const TextStyle(fontSize: 12.5)),
                        selected: paymentType == t,
                        selectedColor: kGold.withValues(alpha: .25),
                        onSelected: (_) => setDlg(() => paymentType = t),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(children: [
                  if (!isIO)
                    Expanded(
                        child: TextFormField(
                      controller: installmentsCtl,
                      keyboardType: TextInputType.number,
                      decoration:
                          fieldDecoration('Installments'),
                      onChanged: (_) => setDlg(() {}),
                    )),
                  if (!isIO) const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: frequency,
                      decoration: fieldDecoration('Frequency'),
                      items: const ['Weekly', 'Biweekly', 'Monthly']
                          .map((v) => DropdownMenuItem(
                              value: v, child: Text(v)))
                          .toList(),
                      onChanged: (v) =>
                          setDlg(() => frequency = v ?? frequency),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                if (!isIO)
                  TextField(
                      controller: collectionCtl,
                      keyboardType: TextInputType.number,
                      decoration: fieldDecoration('Collection amount',
                          hint:
                              'Default ₹${moneyWholeDown(fallback)}'),
                      onChanged: (_) => setDlg(() {})),
                const SizedBox(height: 6),
                TextField(
                    controller: noteCtl,
                    decoration:
                        fieldDecoration('Note (reason)')),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                      color: kGreen.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                      'New: ₹${moneyWholeDown(prevOut)} + ₹${moneyWholeDown(fresh)} + ₹${moneyWholeDown(interest)} = ₹${moneyWholeDown(newTotal)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kGreen)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  if (fresh <= 0 && interest <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text(
                            'Enter fresh cash, interest, or both.')));
                    return;
                  }
                  final collection =
                      Num.rupees(parseMoney(collectionCtl.text));
                  Navigator.pop(
                      ctx,
                      RefinanceParams(
                        fresh: fresh,
                        interest: interest,
                        paymentType: isIO ? 'INTEREST_ONLY' : 'INSTALLMENT',
                        frequency: frequency,
                        count: count,
                        collectionAmount:
                            collection > 0 ? collection : fallback,
                        note: noteCtl.text.trim().isEmpty
                            ? null
                            : noteCtl.text.trim(),
                      ));
                },
                child: const Text('Refinance'),
              ),
            ],
        );
      },
    ),
  );
}

/// Validated refinance terms, ready for `AppState.executeRefinance`.
class RefinanceParams {
  final double fresh;
  final double interest;
  final String paymentType;
  final String frequency;
  final int count;
  final double collectionAmount;
  final String? note;

  const RefinanceParams({
    required this.fresh,
    required this.interest,
    required this.paymentType,
    required this.frequency,
    required this.count,
    required this.collectionAmount,
    this.note,
  });
}
