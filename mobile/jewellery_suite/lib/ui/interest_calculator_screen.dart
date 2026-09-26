import 'package:flutter/material.dart';

import '../util/format.dart';
import 'palette.dart';
import 'widgets.dart';

/// More → Interest Calculator. Simple (normal) or compound interest between a
/// From and To date: days + Years/Months/Days are computed automatically, and
/// the rate applies Monthly or Annually.
class InterestCalculatorScreen extends StatefulWidget {
  const InterestCalculatorScreen({super.key});

  @override
  State<InterestCalculatorScreen> createState() =>
      _InterestCalculatorScreenState();
}

class _InterestCalculatorScreenState extends State<InterestCalculatorScreen> {
  final _principal = TextEditingController();
  final _rate = TextEditingController(text: '3');
  bool _compound = false; // false = Normal (simple), true = Compound
  String _basis = 'Monthly'; // Monthly | Annually
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  double? _interest;
  double? _total;

  @override
  void dispose() {
    _principal.dispose();
    _rate.dispose();
    super.dispose();
  }

  int get _days {
    final diff = _to.difference(_from);
    return diff.inDays < 0 ? 0 : diff.inDays;
  }

  /// Whole calendar months between From and To (27-08-2026 → 27-08-2027 is
  /// exactly 12 months, never 12.1). Real calendar maths, not days ÷ 30.
  int get _months {
    if (_to.isBefore(_from)) return 0;
    var m = (_to.year - _from.year) * 12 + (_to.month - _from.month);
    if (_to.day < _from.day) m -= 1;
    return m < 0 ? 0 : m;
  }

  /// Periods used for the maths, in the selected basis.
  double get _periods =>
      _basis == 'Monthly' ? _months.toDouble() : (_months / 12.0);

  Future<void> _pickDate(bool isFrom) async {
    final current = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: isFrom ? 'From date' : 'To date',
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  void _calculate() {
    final p = parseMoney(_principal.text);
    final r = parseMoney(_rate.text);
    final periods = _periods;
    if (p <= 0 || r <= 0 || periods <= 0) {
      setState(() {
        _interest = null;
        _total = null;
      });
      return;
    }
    final interest = _compound
        ? Num.compoundInterest(principal: p, rate: r, periods: periods)
        : Num.money(p * r / 100.0 * periods);
    setState(() {
      _interest = interest;
      _total = p + interest;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(
        title: const Text('Interest Calculator'),
        actions: [
          TextButton(onPressed: _calculate, child: const Text('CALCULATE')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SectionCard(
            title: 'Mode',
            children: [
              Row(children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Normal (simple)'),
                    selected: !_compound,
                    selectedColor: kGold.withValues(alpha: .3),
                    labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: !_compound ? FontWeight.w700 : FontWeight.w500,
                        color: !_compound ? kGoldDark : kInk),
                    onSelected: (_) => setState(() => _compound = false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Compound'),
                    selected: _compound,
                    selectedColor: kGold.withValues(alpha: .3),
                    labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: _compound ? FontWeight.w700 : FontWeight.w500,
                        color: _compound ? kGoldDark : kInk),
                    onSelected: (_) => setState(() => _compound = true),
                  ),
                ),
              ]),
            ],
          ),
          const SizedBox(height: 12),
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
                  decoration: fieldDecoration('Rate  (%)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _basis,
                  decoration: fieldDecoration('Interest'),
                  items: const ['Monthly', 'Annually']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => _basis = v ?? 'Monthly'),
                ),
              ),
            ]),
          ]),
          const SizedBox(height: 12),
          SectionCard(
            title: 'From → To date',
            children: [
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(_fmt(_from)),
                    onPressed: () => _pickDate(true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward, size: 18, color: kGoldDark),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(_fmt(_to)),
                    onPressed: () => _pickDate(false),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${Num.diffYmd(_from, _to)}   |   $_days Days   |   '
                  '${_basis == 'Monthly' ? '$_months Months' : '${(_months / 12).toStringAsFixed(2)} Years'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: inkOf(context)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Real calendar count: $_days day(s) = $_months month(s). '
                'Rate is applied ${_basis == 'Monthly' ? 'every month' : 'every year'}.',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF8A6D14)),
              ),
            ],
          ),
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
                  _row('${_compound ? 'Compound' : 'Simple'} interest',
                      '₹${moneyWhole(_interest!)}', color: kGoldDark),
                  SizedBox(height: 6),
                  _row('Total to pay', '₹${moneyWhole(_total!)}',
                      color: inkOf(context), bold: true),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Enter amount & rate, pick From/To date, then tap CALCULATE.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8A6D14), fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}-${two(d.month)}-${d.year}';
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