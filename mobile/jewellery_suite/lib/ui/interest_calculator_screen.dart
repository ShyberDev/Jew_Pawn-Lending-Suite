import 'package:flutter/material.dart';

import '../util/format.dart';
import 'palette.dart';
import 'widgets.dart';

/// More → Interest Calculator. Quick khata / pawn interest estimate:
/// amount × rate (% / month) × period.
class InterestCalculatorScreen extends StatefulWidget {
  const InterestCalculatorScreen({super.key});

  @override
  State<InterestCalculatorScreen> createState() =>
      _InterestCalculatorScreenState();
}

class _InterestCalculatorScreenState extends State<InterestCalculatorScreen> {
  final _principal = TextEditingController();
  final _rate = TextEditingController(text: '3');
  final _period = TextEditingController(text: '1');
  String _unit = 'Months';

  double? _interest;
  double? _total;

  @override
  void dispose() {
    _principal.dispose();
    _rate.dispose();
    _period.dispose();
    super.dispose();
  }

  void _calculate() {
    final p = parseMoney(_principal.text);
    final r = parseMoney(_rate.text);
    final pv = parseMoney(_period.text);
    if (p <= 0 || r <= 0 || pv <= 0) {
      setState(() {
        _interest = null;
        _total = null;
      });
      return;
    }
    final days = _unit == 'Months' ? (pv * 30).round() : pv.round();
    final interest =
        Num.simpleInterest(principal: p, ratePerMonth: r, days: days);
    setState(() {
      _interest = interest;
      _total = p + interest;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Interest Calculator'),
        actions: [
          TextButton(onPressed: _calculate, child: const Text('CALCULATE')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(title: 'Loan details', children: [
            TextFormField(
              controller: _principal,
              keyboardType: TextInputType.number,
              decoration: fieldDecoration('Amount (₹)'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _rate,
                  keyboardType: TextInputType.number,
                  decoration: fieldDecoration('Rate (% / month)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _period,
                  keyboardType: TextInputType.number,
                  decoration: fieldDecoration('Period'),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButtonFormField<String>(
                initialValue: _unit,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const ['Months', 'Days']
                    .map((v) =>
                        DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => _unit = v ?? 'Months'),
              ),
            ]),
          ]),
          if (_interest != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _row('Interest due', '₹${moneyWhole(_interest!)}',
                      color: kGoldDark),
                  const SizedBox(height: 6),
                  _row('Total to pay', '₹${moneyWhole(_total!)}',
                      color: kInk, bold: true),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Enter amount, rate and period, then tap CALCULATE.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8A6D14), fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? color, bool bold = false}) {
    return Row(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: Theme.of(context).hintColor)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: color ?? kInk)),
      ],
    );
  }
}