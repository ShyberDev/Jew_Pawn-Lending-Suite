import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../state/app_state.dart';
import '../../../data/migration_v11.dart';
import '../../../util/format.dart';
import '../../../util/report_csv.dart';
import '../../../util/report_pdf.dart';
import '../../../util/report_xlsx.dart';
import '../../../util/khata_loan_state.dart';
import '../../../util/pawn_math.dart';
import '../../../features/khata/screens/khata_screen.dart' show LoanBucket, loanBucket;
import '../../../util/khata_schedule.dart';
import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';

/// Reports hub — Khata reports (blueprint §17) and Pawn reports (§14).
/// Every rupee figure in Reports goes through here.
///
/// v1.0.20: Reports used to interpolate the raw double (`'₹${_r['x']}'`),
/// which printed `₹8333500.0` - no Indian digit grouping and a fake `.0`
/// of paise. Khata money is WHOLE rupees, so every figure is rendered by
/// [moneyWhole] exactly like the rest of the app.
String _m(Object? value) =>
    '₹${moneyWhole(value is num ? value : Num.toDouble(value))}';

/// What the shop can collect TODAY on one loan, used by Reports' overdue
/// figure and its overdue list.
///
/// #020: Reports used to sum the whole outstanding balance as "overdue",
/// which made a ₹1,00,000 loan two weeks late look ₹1,00,000 overdue when only
/// two installments had actually come due. This mirrors the To Collect engine:
/// only scheduled installments whose date has arrived, with the remaining
/// amount after collections. Interest-only loans use their billed periods.
///
/// Exposed for tests so the report figure cannot silently drift back to
/// "whole balance".
double dueNowForReports({
  required Map<String, Object?> loan,
  required List<Map<String, Object?>> interestPeriods,
  required DateTime today,
  required double outstanding,
}) {
  if (MigrationV11.isInterestOnly(loan)) {
    final day = DateTime(today.year, today.month, today.day);
    var due = 0.0;
    for (final p in interestPeriods) {
      final remaining = Num.toDouble(p['remaining_amount']);
      final dueDate = parseIso(p['due_date']);
      if (remaining <= 0 || dueDate == null) continue;
      if (!DateTime(dueDate.year, dueDate.month, dueDate.day).isAfter(day)) {
        due += remaining;
      }
    }
    return Num.rupees(due);
  }
  return Num.rupees(KhataSchedule.dueRemaining(
    expectedRepayment: Num.toDouble(loan['total_payable']),
    collected: Num.toDouble(loan['total_collected']),
    count: (loan['installment_count'] as num?)?.toInt() ?? 0,
    start: parseIso(loan['start_date'] ?? loan['loan_date']),
    frequency: loan['collection_frequency']?.toString() ?? '',
    today: today,
    fallbackOutstanding: outstanding,
  ));
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  /// The latest figures each tab computed, so the export writes exactly what
  /// the screen shows instead of re-deriving it (#041).
  Map<String, Object?> _khata = {};
  Map<String, Object?> _pawn = {};

  /// Which tab is showing. Kept here rather than read back from
  /// `DefaultTabController.of(context)`: this State's own context is ABOVE the
  /// controller it builds, so that lookup returned null and the export tap
  /// crashed on the phone (fixed in v1.2.8).
  int _tab = 0;

  Future<void> _exportCsv() async {
    final at = DateTime.now();
    final index = _tab;
    final csv = index == 0
        ? khataReportCsv(_khata, at: at)
        : pawnReportCsv(_pawn, at: at);
    final name = index == 0 ? khataReportFileName(at) : pawnReportFileName(at);
    try {
      final file = File('${Directory.systemTemp.path}/$name');
      await file.writeAsString(csv, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Jewellery Suite report',
        text: 'Generated ${DateFormat('d MMM yyyy, HH:mm').format(at)}.',
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('The report could not be shared.')));
    }
  }

  /// Same figures as the CSV, as a one-sheet workbook.
  Future<void> _exportXlsx() async {
    final at = DateTime.now();
    final index = _tab;
    final bytes = index == 0
        ? khataReportXlsx(_khata, at: at)
        : pawnReportXlsx(_pawn, at: at);
    final name =
        index == 0 ? khataReportXlsxFileName(at) : pawnReportXlsxFileName(at);
    try {
      final file = File('${Directory.systemTemp.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile(file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
        ],
        subject: 'Jewellery Suite report',
        text: 'Generated ${DateFormat('d MMM yyyy, HH:mm').format(at)}.',
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('The spreadsheet could not be shared.')));
    }
  }

  /// The single export entry point: pick PDF / Excel / CSV, then Android asks
  /// which app or device should receive it (Drive, WhatsApp, Gmail, Files …).
  Future<void> _chooseExport() async {
    final tab = _tab == 0 ? 'Khata' : 'Pawn';
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Share $tab report',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            ListTile(
              key: const ValueKey('export-pdf'),
              leading: const Icon(Icons.picture_as_pdf_outlined, color: kRed),
              title: const Text('PDF'),
              subtitle: const Text('Print or send on WhatsApp'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              key: const ValueKey('export-xlsx'),
              leading:
                  const Icon(Icons.grid_on_outlined, color: kGreen),
              title: const Text('Excel (.xlsx)'),
              subtitle: const Text('Open in Excel or Google Sheets'),
              onTap: () => Navigator.pop(ctx, 'xlsx'),
            ),
            ListTile(
              key: const ValueKey('export-csv'),
              leading:
                  const Icon(Icons.table_chart_outlined, color: kGoldDark),
              title: const Text('CSV'),
              subtitle: const Text('Plain data for any app or Drive'),
              onTap: () => Navigator.pop(ctx, 'csv'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    if (type == 'pdf') {
      await _exportPdf();
    } else if (type == 'xlsx') {
      await _exportXlsx();
    } else {
      await _exportCsv();
    }
  }

  /// Same figures as the CSV, laid out for printing.
  Future<void> _exportPdf() async {
    final at = DateTime.now();
    final index = _tab;
    final bytes = index == 0
        ? await khataReportPdf(_khata, at: at)
        : await pawnReportPdf(_pawn, at: at);
    final name =
        index == 0 ? khataReportPdfFileName(at) : pawnReportPdfFileName(at);
    try {
      final file = File('${Directory.systemTemp.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Jewellery Suite report',
        text: 'Generated ${DateFormat('d MMM yyyy, HH:mm').format(at)}.',
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('The PDF could not be shared.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      initialIndex: widget.initialTab,
      length: 2,
      child: Scaffold(
        backgroundColor: bgOf(context),
        appBar: AppBar(
          title: const Text('Reports'),
          actions: [
            // One button, then the file type, then Android's own share sheet —
            // the pattern Play Store apps use. Three separate icons made the
            // shopkeeper guess which one they wanted before they had even
            // decided where the file should go.
            IconButton(
              key: const ValueKey('reports-export'),
              tooltip: 'Share this report',
              icon: const Icon(Icons.ios_share),
              onPressed: _chooseExport,
            ),
          ],
          bottom: TabBar(
            onTap: (i) => setState(() => _tab = i),
            indicatorColor: kGold,
            labelColor: inkOf(context),
            unselectedLabelColor: Color(0xFF8A8A80),
            labelStyle: TextStyle(fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'KHATA'),
              Tab(text: 'PAWN'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            KhataReportsView(onData: (r) => _khata = r),
            PawnReportsView(onData: (r) => _pawn = r),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Khata reports
// ---------------------------------------------------------------------------

class KhataReportsView extends StatefulWidget {
  const KhataReportsView({super.key, this.onData});

  /// Hands the computed figures to the Reports shell for the CSV export.
  final void Function(Map<String, Object?> data)? onData;

  @override
  State<KhataReportsView> createState() => _KhataReportsViewState();
}

class _KhataReportsViewState extends State<KhataReportsView> {
  Map<String, Object?> _r = {};
  bool _loading = true;

  /// The same two filters the Pawn tab has, so the two reports read alike:
  /// a period, and which loans to count.
  String _period = 'All';
  String _status = 'All';

  bool _periodOk(String? date, DateTime today) {
    if (_period == 'All') return true;
    if (date == null || date.isEmpty) return false;
    if (_period == 'This year') return date.startsWith('${today.year}');
    return date.startsWith(today.toIso8601String().substring(0, 7));
  }

  Future<void> _load() async {
    final db = context.read<AppState>().db;
    final loans = await db.query('khatabook_loans');
    final collections = await db.query('khatabook_collections');
    final customers = await db.query('customers');
    final installments = await db.query('khatabook_installments');
    final periodsByLoan = <String, List<Map<String, Object?>>>{};
    for (final p in installments) {
      final ref = p['khatabook_loan']?.toString() ?? '';
      (periodsByLoan[ref] ??= <Map<String, Object?>>[]).add(p);
    }
    final today = DateTime.now();
    final todayStr = today.toIso8601String().substring(0, 10);
    final weekAgo = today.subtract(const Duration(days: 7));
    final monthAgo = today.subtract(const Duration(days: 30));
    String dstr(DateTime d) => d.toIso8601String().substring(0, 10);

    double todayCol = 0, weekCol = 0, monthCol = 0, totalReceived = 0;
    final todayRows = <Map<String, Object?>>[];
    final weekRows = <Map<String, Object?>>[];
    final monthRows = <Map<String, Object?>>[];
    final viewCollections = <Map<String, Object?>>[];
    for (final c in collections) {
      final date = c['collection_date']?.toString() ?? '';
      final amt = Num.toDouble(c['amount']);
      totalReceived += amt;
      if (date == todayStr) {
        todayCol += amt;
        todayRows.add(c);
      }
      if (date.compareTo(dstr(weekAgo)) >= 0) {
        weekCol += amt;
        weekRows.add(c);
      }
      if (date.compareTo(dstr(monthAgo)) >= 0) {
        monthCol += amt;
        monthRows.add(c);
      }
      if (_periodOk(date, today)) viewCollections.add(c);
    }
    // Newest collection first, like the Cashbook and the Pawn list.
    viewCollections.sort((a, b) => (b['collection_date']?.toString() ?? '')
        .compareTo(a['collection_date']?.toString() ?? ''));

    double totalGiven = 0, outstanding = 0, overdueAmt = 0;
    // Interest actually collected = every rupee of interest the loans ever
    // charged, minus the interest still owed. v1.0.20: this used to be
    // `received - given`, which was Capital Recovery wearing the wrong label —
    // it printed a NEGATIVE number whenever less had been collected than
    // lent out. It can no longer go below zero.
    double interestCharged = 0, interestOwed = 0;
    double interestView = 0, collectedView = 0;
    int overdueCount = 0, activeView = 0;
    final villageMap = <String, double>{};
    final villageCount = <String, int>{};
    final customerMap = <String, double>{};
    final overdueRows = <Map<String, Object?>>[];

    // "Overdue accounts" is a COLLECTION figure: what the shop can collect
    // today, not the whole balance. It uses the same To Collect engine as the
    // khata list (scheduled installments whose date has arrived), so a
    // ₹1,00,000 loan two weeks late reports the missed installments — never
    // the entire outstanding principal.
    double dueNowFor(Map<String, Object?> l, double outstanding) =>
        dueNowForReports(
          loan: l,
          interestPeriods: periodsByLoan[l['client_uuid']?.toString() ?? ''] ??
              const [],
          today: today,
          outstanding: outstanding,
        );

    for (final l in loans) {
      totalGiven += Num.toDouble(l['principal_amount']);
      // Read the balance through the one canonical reader, so Reports shows
      // exactly the same figure as the khata list and the profile screen.
      final st = KhataLoanState.fromRow(l);
      final out = st.netOutstanding;
      // A loan's interest for its whole term. Interest-only loans bill it per
      // period, so their single figure is `current_interest`.
      final charged = MigrationV11.isInterestOnly(l)
          ? Num.toDouble(l['current_interest'] ?? l['interest_amount'])
          : Num.toDouble(l['interest_amount']);
      interestCharged += charged;
      interestOwed += st.interestOutstanding;

      // The filters act on the loans; total given / total received stay
      // all-time so those two never move when a period is picked.
      final loanDate = (l['start_date'] ?? l['loan_date'])?.toString();
      if (!_periodOk(loanDate, today)) continue;
      final active = isActiveKhataStatus(l['status']);
      final overdue = active && loanBucket(l, today) == LoanBucket.overdue;
      if (_status == 'Active' && !active) continue;
      if (_status == 'Overdue' && !overdue) continue;

      interestView += charged - st.interestOutstanding;
      if (!active) continue;
      activeView++;
      outstanding += out;
      final village = l['village']?.toString() ?? 'General';
      villageMap[village] =
          Num.money((villageMap[village] ?? 0) + Num.toDouble(out));
      villageCount[village] = (villageCount[village] ?? 0) + 1;
      final customer = l['customer_name']?.toString() ?? '-';
      customerMap[customer] =
          Num.money((customerMap[customer] ?? 0) + Num.toDouble(out));
      if (overdue) {
        overdueCount++;
        final due = dueNowFor(l, out);
        overdueAmt += due;
        // Carry the due figure under `amount` so the shared list row shows
        // what is collectable now; the full balance stays available too.
        overdueRows.add({...l, 'amount': due, 'outstanding': out});
      }
    }
    if (_status != 'Overdue') {
      for (final c in viewCollections) {
        collectedView += Num.toDouble(c['amount']);
      }
    }

    final badCredit =
        customers.where((c) => (c['rating']?.toString() ?? '') == 'Bad').length;
    final blocked = customers
        .where((c) =>
            (c['status']?.toString() ?? '') == 'Blocked' ||
            (c['status']?.toString() ?? '') == 'Inactive')
        .length;

    if (mounted) {
      setState(() {
        _r = {
          'today_col': Num.money(todayCol),
          'week_col': Num.money(weekCol),
          'month_col': Num.money(monthCol),
          'total_given': Num.money(totalGiven),
          'total_received': Num.money(totalReceived),
          'interest_earned': Num.money(interestCharged - interestOwed),
          'interest_view': Num.money(interestView),
          'outstanding': Num.money(outstanding),
          'overdue_count': overdueCount,
          'overdue_amt': Num.money(overdueAmt),
          'collected_view': Num.money(collectedView),
          'active_view': activeView,
          'customers_view': customerMap.length,
          'collections_view': viewCollections,
          'today_rows': todayRows,
          'week_rows': weekRows,
          'month_rows': monthRows,
          'overdue_rows': overdueRows,
          'village_map': villageMap,
          'village_count': villageCount,
          'customer_map': customerMap,
          'bad_credit': badCredit,
          'blocked': blocked,
          'village_rows': [
            for (final e in villageMap.entries)
              {
                'name': e.key,
                'count': villageCount[e.key] ?? 0,
                'amount': e.value,
              }
          ]..sort((a, b) => (b['amount'] as num).compareTo(a['amount'] as num)),
          'customer_rows': [
            for (final e in customerMap.entries)
              {'name': e.key, 'amount': e.value}
          ]..sort((a, b) => (b['amount'] as num).compareTo(a['amount'] as num)),
        };
        _loading = false;
      });
      widget.onData?.call(_r);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Widget _filterChip(String label, String current, List<String> values) {
    Widget chip(String v) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(v),
            selected: current == v,
            selectedColor: kGold.withValues(alpha: .3),
            labelStyle: TextStyle(
                fontSize: 11.5,
                fontWeight: current == v ? FontWeight.w700 : FontWeight.w500),
            onSelected: (_) {
              if (label == 'Period') _period = v;
              if (label == 'Loans') _status = v;
              setState(() => _loading = true);
              _load();
            },
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: mutedOf(context))),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [for (final v in values) chip(v)],
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String value, String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: color ?? inkOf(context))),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
        ],
      ),
    );
  }

  Widget _metricGrid() {
    return Column(children: [
      Row(children: [
        Expanded(
            child: _metricCard(_m(_r['collected_view']), 'Collected in view',
                color: kGreen)),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard('${_r['active_view']}', 'Active loans in view')),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard(_m(_r['outstanding']), 'Outstanding',
                color: kGoldDark)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: _metricCard('${_r['overdue_count']}', 'Overdue accounts',
                color: _r['overdue_count'] == 0 ? null : kRed)),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard(_m(_r['overdue_amt']), 'Collectable now',
                color: kRed)),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard(_m(_r['interest_view']), 'Interest earned',
                color: kGreen)),
      ]),
    ]);
  }

  /// One collection, laid out like a Pawn report row: date and customer on the
  /// left, money on the right — not a table of lines.
  Widget _collectionRow(Map<String, Object?> c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.south_west, size: 20, color: kGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c['customer']?.toString() ??
                        c['customer_name']?.toString() ??
                        '-',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: inkOf(context))),
                Text(
                    '${fmtDate(c['collection_date'])}'
                    '${(c['village']?.toString() ?? '').isEmpty ? '' : '  ·  ${c['village']}'}',
                    style: TextStyle(fontSize: 11, color: mutedOf(context))),
              ],
            ),
          ),
          Text('₹${moneyWhole(c['amount'] as num?)}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: kGreen)),
        ],
      ),
    );
  }

  Widget _overdueRow(Map<String, Object?> l) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined, size: 20, color: kRed),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l['customer_name']?.toString() ?? '-',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: inkOf(context))),
                Text(
                    '${l['customer_id'] ?? ''}'
                    '${(l['village']?.toString() ?? '').isEmpty ? '' : '  ·  ${l['village']}'}',
                    style: TextStyle(fontSize: 11, color: mutedOf(context))),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${moneyWhole(l['amount'] as num?)}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: kRed)),
              Text('Bal ₹${moneyWhole(l['outstanding'] as num?)}',
                  style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    final entries =
        (_r[_status == 'Overdue' ? 'overdue_rows' : 'collections_view'] as List?) ??
            const [];
    final amount =
        _status == 'Overdue' ? _r['overdue_amt'] : _r['collected_view'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: lineOf(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
              '${entries.length} ${_status == 'Overdue' ? 'loan' : 'collection'}'
              '${entries.length == 1 ? '' : 's'}',
              style: TextStyle(
                  color: inkOf(context), fontWeight: FontWeight.w700)),
          Text('₹${moneyWhole(amount as num?)}',
              style: TextStyle(color: mutedOf(context), fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overdueMode = _status == 'Overdue';
    final entries =
        (_r[overdueMode ? 'overdue_rows' : 'collections_view'] as List?) ??
            const [];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _filterChip(
                    'Period', _period, ['All', 'This month', 'This year']),
              ),
              _filterChip('Loans', _status, ['All', 'Active', 'Overdue']),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kGold))
              : RefreshIndicator(
                  color: kGold,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _metricGrid(),
                      const SizedBox(height: 14),
                      Text(
                          (overdueMode
                                  ? 'Overdue loans'
                                  : 'Collections in view')
                              .toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: Color(0xFF8A6D14))),
                      const SizedBox(height: 6),
                      if (entries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                                overdueMode
                                    ? 'No overdue loans in this period. 🎉'
                                    : 'No collections in this period.',
                                textAlign: TextAlign.center),
                          ),
                        )
                      else ...[
                        for (final e in entries)
                          overdueMode
                              ? _overdueRow(e as Map<String, Object?>)
                              : _collectionRow(e as Map<String, Object?>),
                        const SizedBox(height: 6),
                        _footer(),
                      ],
                      const SizedBox(height: 14),
                      // The all-time figures the report has always shown stay
                      // available without cluttering the list.
                      Text('ALL TIME'.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: Color(0xFF8A6D14))),
                      const SizedBox(height: 6),
                      _allTimeCard(),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _allTimeCard() {
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: mutedOf(context))),
              Text(value,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        line('Total given (principal)', _m(_r['total_given'])),
        line('Total received', _m(_r['total_received'])),
        line('Interest earned', _m(_r['interest_earned'])),
        line("Today's collection", _m(_r['today_col'])),
        line('This week (7 days)', _m(_r['week_col'])),
        line('This month (30 days)', _m(_r['month_col'])),
        line('Bad credit / blocked',
            '${_r['bad_credit']} / ${_r['blocked']}'),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Pawn reports (blueprint §14: period / metal / status filters + totals)
// ---------------------------------------------------------------------------

class PawnReportsView extends StatefulWidget {
  const PawnReportsView({super.key, this.onData});

  /// Hands the computed figures to the Reports shell for the CSV export.
  final void Function(Map<String, Object?> data)? onData;

  @override
  State<PawnReportsView> createState() => _PawnReportsViewState();
}

class _PawnReportsViewState extends State<PawnReportsView> {
  String _period = 'All';
  String _metal = 'All';
  String _status = 'All';
  bool _loading = true;
  Map<String, Object?> _r = {};

  Future<void> _load() async {
    final db = context.read<AppState>().db;
    final loans = await db.query('pawn_loans');
    final items = await db.query('pawn_items');
    final releases = await db.query('pawn_releases');
    final today = DateTime.now();
    final year = today.year.toString();
    final month = today.toIso8601String().substring(0, 7);

    bool periodOk(String? date) {
      if (_period == 'All') return true;
      if (date == null) return false;
      if (_period == 'This year') return date.startsWith(year);
      return date.startsWith(month);
    }

    bool statusOk(String? status) {
      final s = status ?? 'Active';
      if (_status == 'All') return true;
      return s == _status;
    }

    // Loans in filter.
    final filtered = loans.where((l) =>
        periodOk(l['loan_date']?.toString()) &&
        statusOk(l['status']?.toString()));
    // "Outstanding" money is a LIVE figure, so it must only ever count active
    // loans — a released loan still holds its original principal, and adding it
    // here made this screen report ₹3,40,000 outstanding while the Pawn screen
    // (correctly) showed ₹1,00,000. Settled loans are still listed below, they
    // just do not inflate the totals.
    final liveForMoney =
        filtered.where((l) => isActiveKhataStatus(l['status'])).toList();
    // Pawn money always comes from PawnMath so reports match the Home KPI, the
    // Pawn screen and the Pawn dashboard.
    final pawnTotals = PawnMath.totals(liveForMoney);
    final principal = pawnTotals.investment;
    final interest = pawnTotals.interest;
    final receivable = pawnTotals.outstanding;
    final activeUuids = loans
        .where((l) => isActiveKhataStatus(l['status']))
        .map((l) => l['client_uuid']?.toString())
        .toSet();
    double goldReserve = 0, silverReserve = 0;
    for (final it in items) {
      final loanUuid = it['loan_uuid']?.toString();
      // Reserve only counts against active loans.
      if (loanUuid == null || !activeUuids.contains(loanUuid)) continue;
      final metal = it['metal_type']?.toString() ?? '';
      final w = Num.toDouble(it['net_weight']);
      if (_metal != 'All' && metal != _metal) continue;
      if (metal == 'Gold') {
        goldReserve += w;
      } else if (metal == 'Silver') {
        silverReserve += w;
      }
    }
    double realised = 0;
    int releasedCount = 0;
    for (final r in releases) {
      final date = r['release_date']?.toString();
      if (periodOk(date)) {
        realised += Num.toDouble(r['interest_paid']);
        releasedCount++;
      }
    }

    if (mounted) {
      setState(() {
        _r = {
          'active':
              filtered.where((l) => isActiveKhataStatus(l['status'])).length,
          'principal': Num.money(principal),
          'interest': Num.money(interest),
          'receivable': Num.money(receivable),
          'gold_reserve': Num.round3(goldReserve),
          'silver_reserve': Num.round3(silverReserve),
          'released_count': releasedCount,
          'realised': Num.money(realised),
          'rows': filtered.toList()
            ..sort((a, b) => (b['loan_date']?.toString() ?? '')
                .compareTo(a['loan_date']?.toString() ?? '')),
        };
        _loading = false;
      });
      widget.onData?.call(_r);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, key, values) in [
                ('Period', _period, ['All', 'This year', 'This month']),
                ('Metal', _metal, ['All', 'Gold', 'Silver']),
                ('Status', _status, ['All', 'Active', 'Released'])
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _filterChip(label, key, values),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kGold))
              : RefreshIndicator(
                  color: kGold,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _metricGrid(),
                      const SizedBox(height: 14),
                      Text('LOANS IN VIEW'.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: Color(0xFF8A6D14))),
                      const SizedBox(height: 6),
                      if ((_r['rows'] as List).isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child:
                                  Text('No pawn loans match these filters.')),
                        )
                      else ...[
                        for (final l in _r['rows'] as List)
                          _pawnRow(l as Map<String, Object?>),
                        const SizedBox(height: 6),
                        _rowFooter(),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String current, List<String> values) {
    Widget chip(String v) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(v),
            selected: current == v,
            selectedColor: kGold.withValues(alpha: .3),
            labelStyle: TextStyle(
                fontSize: 11.5,
                fontWeight: current == v ? FontWeight.w700 : FontWeight.w500),
            onSelected: (_) {
              if (label == 'Period') _period = v;
              if (label == 'Metal') _metal = v;
              if (label == 'Status') _status = v;
              setState(() => _loading = true);
              _load();
            },
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: mutedOf(context))),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [for (final v in values) chip(v)],
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String value, String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: color ?? inkOf(context))),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
        ],
      ),
    );
  }

  Widget _metricGrid() {
    return Column(children: [
      Row(children: [
        Expanded(child: _metricCard('${_r['active']}', 'Active loans in view')),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard(_m(_r['principal']), 'Principal outstanding',
                color: kGoldDark)),
        const SizedBox(width: 8),
        Expanded(
            child:
                _metricCard(_m(_r['interest']), 'Interest due', color: kRed)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: _metricCard(_m(_r['receivable']), 'Total receivable')),
        const SizedBox(width: 8),
        Expanded(child: _metricCard('${_r['gold_reserve']} g', 'Gold reserve')),
        const SizedBox(width: 8),
        Expanded(
            child: _metricCard('${_r['silver_reserve']} g', 'Silver reserve')),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: _metricCard('${_r['released_count']}', 'Released'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(_m(_r['realised']), 'Interest realised',
              color: kGreen),
        ),
        const SizedBox(width: 8),
        Expanded(
            child:
                _metricCard('${(_r['rows'] as List).length}', 'Loans listed')),
      ]),
    ]);
  }

  Widget _pawnRow(Map<String, Object?> l) {
    final released = (l['status']?.toString() ?? 'Active') == 'Released';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(released ? Icons.check_circle_outline : Icons.lock_clock,
              size: 20, color: released ? kGreen : kGoldDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l['customer_name']?.toString() ?? '-',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: inkOf(context))),
                Text(
                    '${l['loan_date']}  ·  ${released ? 'Released' : 'Active'}'
                    '${l['release_date'] != null ? ' · ${l['release_date']}' : ''}',
                    style: TextStyle(fontSize: 11, color: mutedOf(context))),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${moneyText(l['loan_amount'] as num?)}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              // Live outstanding (PawnMath), not the stale stored balance —
              // otherwise this row disagreed with the total on the same screen.
              Text(
                  released
                      ? 'Settled'
                      : 'Bal ₹${moneyText(PawnMath.outstanding(l))}',
                  style: TextStyle(
                      fontSize: 10.5,
                      color: released ? kGreen : mutedOf(context))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowFooter() {
    final rows = (_r['rows'] as List).cast<Map<String, Object?>>();
    // The footer must be the sum of exactly what the rows above show: live
    // outstanding for active loans, and no principal for settled ones.
    final live = rows.where((l) => isActiveKhataStatus(l['status'])).toList();
    final totals = PawnMath.totals(live);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: lineOf(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${rows.length} loans',
              style: TextStyle(
                  color: inkOf(context), fontWeight: FontWeight.w700)),
          Text(
              '₹${moneyText(totals.investment)} · ₹${moneyText(totals.outstanding)} bal',
              style: TextStyle(color: mutedOf(context), fontSize: 12)),
        ],
      ),
    );
  }
}
