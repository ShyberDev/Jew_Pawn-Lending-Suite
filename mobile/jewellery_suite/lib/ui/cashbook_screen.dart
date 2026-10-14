import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/format.dart';
import 'palette.dart';

/// Cashbook screen: daily Cash IN and Cash OUT ledger with payment mode filters
/// (Cash / UPI / Bank) and automatic synchronization with Khata and Pawn books.
class CashbookScreen extends StatefulWidget {
  const CashbookScreen({super.key});

  @override
  State<CashbookScreen> createState() => _CashbookScreenState();
}

class _CashbookScreenState extends State<CashbookScreen> {
  DateTime _selectedDate = DateTime.now();
  String _selectedMode = 'ALL';
  final String _selectedType = 'ALL';
  bool _loading = true;
  List<Map<String, Object?>> _entries = [];
  Map<String, double> _summary = {'total_in': 0.0, 'total_out': 0.0, 'net': 0.0};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _dateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final state = context.read<AppState>();
    final dateStr = _dateString(_selectedDate);
    final entries = await state.getCashbookEntries(
      date: dateStr,
      mode: _selectedMode,
      type: _selectedType,
    );
    final summary = await state.getCashbookDailySummary(dateStr);
    if (mounted) {
      setState(() {
        _entries = entries;
        _summary = summary;
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: kGold,
                onPrimary: Colors.white,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _loading = true;
      });
      await _load();
    }
  }

  void _showAddEntryModal(String entryType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddEntrySheet(
        entryType: entryType,
        selectedDate: _selectedDate,
        onAdded: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  Future<void> _deleteEntry(String uuid) async {
    final state = context.read<AppState>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry?'),
        content: const Text(
            'Are you sure you want to delete this cashbook transaction?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await state.deleteCashbookEntry(uuid);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _dateString(_selectedDate) == _dateString(DateTime.now());
    final dateDisplay = isToday
        ? 'Today (${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year})'
        : '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}';

    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(
        title: const Text(
          'Cashbook',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: surfaceOf(context),
        foregroundColor: inkOf(context),
        elevation: 0.5,
        actions: [
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month, size: 18, color: kGoldDark),
            label: Text(
              dateDisplay,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kGoldDark,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTallyCard(),
          _buildFilters(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kGold))
                : _entries.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: kGold,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          itemCount: _entries.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: lineOf(context)),
                          itemBuilder: (ctx, i) => _buildEntryRow(_entries[i]),
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildTallyCard() {
    final totalIn = _summary['total_in'] ?? 0.0;
    final totalOut = _summary['total_out'] ?? 0.0;
    final net = _summary['net'] ?? 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.arrow_downward, size: 14, color: kGreen),
                        SizedBox(width: 4),
                        Text(
                          'TOTAL IN',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: kGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${moneyWhole(totalIn)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: kGreen,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 38,
                width: 1,
                color: lineOf(context),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.arrow_upward, size: 14, color: kRed),
                        SizedBox(width: 4),
                        Text(
                          'TOTAL OUT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: kRed,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${moneyWhole(totalOut)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: kRed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: lineOf(context)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DAILY NET BALANCE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: mutedOf(context),
                ),
              ),
              Text(
                '${net >= 0 ? '+' : ''}₹${moneyWhole(net)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: net >= 0 ? kGreen : kRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final modes = ['ALL', 'CASH', 'UPI', 'BANK'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          for (final m in modes) ...[
            ChoiceChip(
              label: Text(m),
              labelStyle: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _selectedMode == m ? Colors.white : inkOf(context),
              ),
              selected: _selectedMode == m,
              selectedColor: kGoldDark,
              backgroundColor: surfaceOf(context),
              onSelected: (val) {
                if (val) {
                  setState(() => _selectedMode = m);
                  _load();
                }
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 54, color: mutedOf(context)),
          const SizedBox(height: 12),
          Text(
            'No transactions recorded',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: inkOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Use the buttons below to record Cash IN or OUT',
            style: TextStyle(fontSize: 12, color: mutedOf(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryRow(Map<String, Object?> entry) {
    final isIn = entry['entry_type'] == 'IN';
    final amount = (entry['amount'] as num?)?.toDouble() ?? 0.0;
    final category = entry['category']?.toString() ?? 'OTHER';
    final party = entry['party_name']?.toString() ?? '';
    final time = entry['entry_time']?.toString() ?? '';
    final mode = entry['payment_mode']?.toString() ?? 'CASH';
    final notes = entry['notes']?.toString() ?? '';
    final uuid = entry['client_uuid']?.toString() ?? '';

    String categoryLabel = category.replaceAll('_', ' ');
    IconData catIcon = Icons.payments_outlined;
    if (category.contains('KHATA')) {
      catIcon = Icons.menu_book_outlined;
    } else if (category.contains('PAWN')) {
      catIcon = Icons.account_balance_outlined;
    } else if (category.contains('EXPENSE')) {
      catIcon = Icons.shopping_bag_outlined;
    }

    return Dismissible(
      key: Key(uuid),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: kRed,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        await _deleteEntry(uuid);
        return false;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (isIn ? kGreen : kRed).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(catIcon, size: 18, color: isIn ? kGreen : kRed),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          party.isNotEmpty ? party : categoryLabel,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: inkOf(context),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          mode,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: kGoldDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (time.isNotEmpty) time,
                      if (party.isNotEmpty) categoryLabel,
                      if (notes.isNotEmpty) notes,
                    ].join(' • '),
                    style: TextStyle(fontSize: 11, color: mutedOf(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${isIn ? '+' : '-'}₹${moneyWhole(amount)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isIn ? kGreen : kRed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: surfaceOf(context),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _showAddEntryModal('IN'),
                icon: const Icon(Icons.arrow_downward, size: 18),
                label: const Text(
                  '+ CASH IN',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _showAddEntryModal('OUT'),
                icon: const Icon(Icons.arrow_upward, size: 18),
                label: const Text(
                  '- CASH OUT',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddEntrySheet extends StatefulWidget {
  final String entryType;
  final DateTime selectedDate;
  final VoidCallback onAdded;

  const _AddEntrySheet({
    required this.entryType,
    required this.selectedDate,
    required this.onAdded,
  });

  @override
  State<_AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends State<_AddEntrySheet> {
  final _amountCtrl = TextEditingController();
  final _partyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late String _category;
  String _paymentMode = 'CASH';

  @override
  void initState() {
    super.initState();
    _category = widget.entryType == 'IN' ? 'CUSTOMER_PAYMENT' : 'SHOP_EXPENSE';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _partyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    final state = context.read<AppState>();
    await state.addCashbookEntry(
      type: widget.entryType,
      amount: amount,
      category: _category,
      mode: _paymentMode,
      date: widget.selectedDate,
      partyName: _partyCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
    );

    widget.onAdded();
  }

  @override
  Widget build(BuildContext context) {
    final isIn = widget.entryType == 'IN';
    final categories = isIn
        ? [
            ('CUSTOMER_PAYMENT', 'Customer Payment'),
            ('KHATA_COLLECTION', 'Khata Collection'),
            ('PAWN_REPAYMENT', 'Pawn Repayment'),
            ('OTHER_INCOME', 'Other Income'),
          ]
        : [
            ('SHOP_EXPENSE', 'Shop Expense'),
            ('VENDOR_PURCHASE', 'Vendor Purchase'),
            ('SALARY', 'Salary / Wages'),
            ('TEA_FOOD', 'Tea & Food'),
            ('RENT', 'Shop Rent'),
            ('PERSONAL_DRAW', 'Personal Draw'),
            ('OTHER_EXPENSE', 'Other Expense'),
          ];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isIn ? Icons.arrow_downward : Icons.arrow_upward,
                  color: isIn ? kGreen : kRed,
                ),
                const SizedBox(width: 8),
                Text(
                  isIn ? 'Record Cash IN' : 'Record Cash OUT',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isIn ? kGreen : kRed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                prefixText: '₹ ',
                labelText: 'Amount',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: [
                for (final (k, label) in categories)
                  DropdownMenuItem(value: k, child: Text(label)),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _category = val);
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final mode in ['CASH', 'UPI', 'BANK']) ...[
                  Expanded(
                    child: ChoiceChip(
                      label: Center(child: Text(mode)),
                      selected: _paymentMode == mode,
                      selectedColor: kGoldDark,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _paymentMode == mode ? Colors.white : null,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _paymentMode = mode);
                      },
                    ),
                  ),
                  if (mode != 'BANK') const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _partyCtrl,
              decoration: InputDecoration(
                labelText: 'Party / Person Name (Optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: 'Notes / Remarks (Optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isIn ? kGreen : kRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _submit,
                child: Text(
                  isIn ? 'SAVE CASH IN' : 'SAVE CASH OUT',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
