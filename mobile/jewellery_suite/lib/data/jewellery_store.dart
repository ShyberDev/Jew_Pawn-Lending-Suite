import 'dart:math' as math;

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'local_db.dart';
import '../util/ids.dart';
import '../util/jewellery_math.dart';

/// One item line as the shop enters it. The store runs it through
/// [JewelleryMath] so every saved document uses the same formulas.
class JewelleryItemInput {
  const JewelleryItemInput({
    this.description = '',
    required this.metal,
    required this.grossWeight,
    required this.netWeight,
    required this.purity,
    required this.rate,
    this.makingMode = MakingMode.none,
    this.makingValue = 0,
    this.additionalCost = 0,
    this.discount = 0,
    this.estimatedCost = 0,
    this.actualCost = 0,
    this.billingBasis = BillingBasis.raw,
    this.wastagePct = 0,
    this.makingCharge = 0,
  });

  final String description;
  final String metal;
  final double grossWeight;
  final double netWeight;
  final double purity;
  final double rate;
  final MakingMode makingMode;
  final double makingValue;
  final double additionalCost;
  final double discount;
  final double estimatedCost;
  final double actualCost;
  final BillingBasis billingBasis;
  final double wastagePct;
  final double makingCharge;

  JewelleryLine get computed => JewelleryMath.line(
        weight: netWeight,
        purityPct: purity,
        pureRate: rate,
        makingMode: makingMode,
        makingValue: makingValue,
        additionalCost: additionalCost,
        discount: discount,
        billingBasis: billingBasis,
        wastagePct: wastagePct,
        makingCharge: makingCharge,
      );
}

/// Old metal handed in against one invoice. The accepted value may be edited by
/// the shop; when omitted the suggestion from [JewelleryMath.oldMetal] is used.
class OldMetalInput {
  const OldMetalInput({
    required this.metal,
    required this.grossWeight,
    required this.purity,
    required this.rate,
    this.acceptedValue,
  });

  final String metal;
  final double grossWeight;
  final double purity;
  final double rate;
  final double? acceptedValue;
}

/// One customer's jewellery credit position. Only **sales** create customer
/// credit; a purchase is a supplier payable and is deliberately excluded.
class JewelleryCreditCustomer {
  const JewelleryCreditCustomer({
    required this.name,
    required this.invoiceCount,
    required this.billed,
    required this.received,
    required this.returned,
    required this.outstanding,
    required this.lastDate,
  });

  final String name;
  final int invoiceCount;
  final double billed;
  final double received;
  final double returned;
  final double outstanding;
  final String lastDate;
}

/// One supplier's jewellery payable position, grouped by supplier name
/// (case-insensitive). Purchases create the payable; purchase payments reduce
/// it. Customer sales are deliberately excluded.
class JewellerySupplier {
  const JewellerySupplier({
    required this.name,
    required this.invoiceCount,
    required this.billed,
    required this.paid,
    required this.outstanding,
    required this.lastDate,
  });

  final String name;
  final int invoiceCount;
  final double billed;
  final double paid;
  final double outstanding;
  final String lastDate;
}

/// One row of a supplier's jewellery ledger. A purchase is a **credit** (the
/// shop owes the supplier); a purchase payment is a **debit** (the payable
/// falls). The running balance is always what the shop still owes.
class JewellerySupplierLedgerEntry {
  const JewellerySupplierLedgerEntry({
    required this.date,
    required this.type,
    required this.description,
    required this.reference,
    required this.mode,
    required this.debit,
    required this.credit,
    required this.invoiceUuid,
    required this.note,
    required this.balance,
  });

  final String date;
  final String type; // PURCHASE | PAYMENT
  final String description;
  final String reference;
  final String mode;
  final double debit;
  final double credit;
  final String invoiceUuid;
  final String note;
  final double balance;

  bool get isPurchase => type == 'PURCHASE';
  double get amount => isPurchase ? credit : debit;
}

/// One row of a customer's jewellery ledger. A sale debits the customer (the
/// invoice total, already net of old metal); every receipt credits them.
class JewelleryLedgerEntry {
  const JewelleryLedgerEntry({
    required this.date,
    required this.type,
    required this.description,
    required this.reference,
    required this.mode,
    required this.debit,
    required this.credit,
    required this.invoiceUuid,
    required this.oldMetalValue,
    required this.note,
    required this.balance,
  });

  final String date;
  final String type; // SALE | PAYMENT | RETURN
  final String description;
  final String reference;
  final String mode;
  final double debit;
  final double credit;
  final String invoiceUuid;
  final double oldMetalValue;
  final String note;
  final double balance;

  bool get isSale => type == 'SALE';
  bool get isReturn => type == 'RETURN';
  double get amount => isSale ? debit : credit;
}

/// A worker's cash and metal reserve. Positive cash is money the shop has paid
/// the worker; positive gold is metal the shop has issued. Both are assets held
/// by the worker, never a loss or a payable.
class JewelleryWorkerPosition {
  const JewelleryWorkerPosition({
    required this.name,
    required this.cashReserve,
    required this.goldReserve,
    required this.fineGoldReserve,
    required this.lastDate,
    required this.txnCount,
  });

  final String name;
  final double cashReserve;
  final double goldReserve;
  final double fineGoldReserve;
  final String lastDate;
  final int txnCount;
}

/// One stock line valued at the latest saved pure-metal rate. [grams] is the
/// net physical weight, [fineWeight] is the pure-metal equivalent and [value]
/// is `fineWeight × latest pure rate` for that metal.
class JewelleryStockLine {
  const JewelleryStockLine({
    required this.metal,
    required this.kind,
    required this.grams,
    required this.fineWeight,
    required this.value,
  });

  final String metal;
  final String kind;
  final double grams;
  final double fineWeight;
  final double value;
}

/// One month of jewellery sale/purchase totals for the on-screen chart.
class JewelleryMonthTotal {
  const JewelleryMonthTotal({
    required this.month,
    required this.label,
    required this.sales,
    required this.purchases,
  });

  /// `YYYY-MM`, useful for tests and ordering.
  final String month;
  final String label;
  final double sales;
  final double purchases;
}

/// The shop's stock valued from the single stock ledger. Old metal is included
/// as an asset; nothing here is fetched from a market feed.
class JewelleryStockValuation {
  const JewelleryStockValuation({
    required this.lines,
    required this.goldRate,
    required this.silverRate,
  });

  final List<JewelleryStockLine> lines;
  final double? goldRate;
  final double? silverRate;

  JewelleryStockLine? line(String metal, String kind) {
    for (final l in lines) {
      if (l.metal == metal && l.kind == kind) return l;
    }
    return null;
  }

  double grams(String metal, String kind) => line(metal, kind)?.grams ?? 0;
  double fineWeight(String metal, String kind) =>
      line(metal, kind)?.fineWeight ?? 0;
  double valueFor(String metal, String kind) => line(metal, kind)?.value ?? 0;

  double get totalFineGold => lines
      .where((l) => l.metal == JewelleryStore.gold)
      .fold(0, (sum, l) => sum + l.fineWeight);
  double get totalFineSilver => lines
      .where((l) => l.metal == JewelleryStore.silver)
      .fold(0, (sum, l) => sum + l.fineWeight);
  double get totalValue => lines.fold(0, (sum, l) => sum + l.value);
}

/// One line being returned against a sale. [value] is the accepted credit:
/// net weight × purity% × the sale's rate per gram.
class JewelleryReturnItemInput {
  const JewelleryReturnItemInput({
    required this.description,
    required this.metal,
    required this.grossWeight,
    required this.netWeight,
    required this.purity,
    required this.rate,
    this.restock = true,
  });

  final String description;
  final String metal;
  final double grossWeight;
  final double netWeight;
  final double purity;
  final double rate;
  final bool restock;

  double get value => netWeight * purity / 100.0 * rate;
}

/// The jewellery document store: rates, invoices, payments, old metal and the
/// single stock ledger. Screens talk to this class; they never write the
/// jewellery tables directly.
class JewelleryStore {
  JewelleryStore(this.db);

  final LocalDb db;

  static const gold = 'GOLD';
  static const silver = 'SILVER';

  static const saleDoc = 'SALE';
  static const purchaseDoc = 'PURCHASE';
  static const orderDoc = 'ORDER';

  /// A purchase saved as a draft. It stores the document and its lines but
  /// posts **nothing**: no payment, no old-metal stock and no stock movement
  /// until [confirmInvoice] runs. Confirm is idempotent, so stock can never be
  /// received twice.
  static const draftStatus = 'Draft';

  static const stockRaw = 'RAW';
  static const stockFinished = 'FINISHED';
  static const stockOld = 'OLD';

  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ------------------------------------------------------------------- rates
  /// The newest saved pure-metal rate for [metal], or null before the shop has
  /// saved one. Never fetched from a market feed.
  Future<double?> latestRate(String metal) async {
    final rows = await db.query('jewellery_rates',
        where: 'metal = ?',
        whereArgs: [metal],
        orderBy: 'rate_date DESC',
        limit: 1);
    if (rows.isEmpty) return null;
    return (rows.first['pure_rate'] as num?)?.toDouble();
  }

  /// The rate in force on [day] — the newest saved rate on or before that date.
  Future<double?> rateOn(String metal, DateTime day) async {
    final rows = await db.query('jewellery_rates',
        where: 'metal = ? AND rate_date <= ?',
        whereArgs: [metal, _day(day)],
        orderBy: 'rate_date DESC',
        limit: 1);
    if (rows.isEmpty) return null;
    return (rows.first['pure_rate'] as num?)?.toDouble();
  }

  /// Saves (or replaces) one day's rate. Earlier days are untouched, so saved
  /// invoices keep the rate they used.
  Future<void> saveRate(String metal, double pureRate, {DateTime? date}) async {
    if (pureRate < 0) throw const FormatException('Rate cannot be negative.');
    final day = _day(date ?? DateTime.now());
    // The primary key is composite (metal, rate_date); LocalDb.upsert matches
    // on a single pk column, so write this one explicitly.
    await db.db.insert(
      'jewellery_rates',
      {
        'metal': metal.toUpperCase(),
        'rate_date': day,
        'pure_rate': pureRate,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> rateHistory(String metal,
          {int limit = 30}) =>
      db.query('jewellery_rates',
          where: 'metal = ?',
          whereArgs: [metal.toUpperCase()],
          orderBy: 'rate_date DESC',
          limit: limit);

  // ------------------------------------------------------------ doc numbers
  /// `SAL-20261102-0001` (the spec's proposed consistent format). Sequences are
  /// per type and per day, and an issued number is never reused.
  Future<String> nextDocNo(String docType, DateTime date) async {
    final prefix = switch (docType) {
      saleDoc => 'SAL',
      purchaseDoc => 'PUR',
      orderDoc => 'ORD',
      _ => 'DOC',
    };
    final day = _day(date).replaceAll('-', '');
    final like = '$prefix-$day-%';
    final rows = await db.db.rawQuery(
      'SELECT doc_no FROM jewellery_invoices WHERE doc_no LIKE ?',
      [like],
    );
    var max = 0;
    for (final r in rows) {
      final no = r['doc_no']?.toString() ?? '';
      final seq = int.tryParse(no.split('-').last) ?? 0;
      max = math.max(max, seq);
    }
    return '$prefix-$day-${(max + 1).toString().padLeft(4, '0')}';
  }

  // ---------------------------------------------------------------- reading
  Future<List<Map<String, Object?>>> invoices({
    String? docType,
    String search = '',
    String? metal,
    String paymentStatus = '',
    int limit = 100,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (docType != null && docType.isNotEmpty) {
      where.add('doc_type = ?');
      args.add(docType);
    }
    if (metal != null && metal.isNotEmpty) {
      where.add('metal = ?');
      args.add(metal.toUpperCase());
    }
    final needle = search.trim().toLowerCase();
    if (needle.isNotEmpty) {
      where.add('(LOWER(doc_no) LIKE ? OR LOWER(party_name) LIKE ? '
          'OR LOWER(notes) LIKE ?)');
      args.addAll(['%$needle%', '%$needle%', '%$needle%']);
    }
    switch (paymentStatus) {
      case 'open':
        where.add('outstanding > 0.005');
        break;
      case 'settled':
        where.add('outstanding <= 0.005');
        break;
      case 'partial':
        where.add('amount_paid > 0.005 AND outstanding > 0.005');
        break;
      case 'unpaid':
        where.add('amount_paid <= 0.005 AND outstanding > 0.005');
        break;
    }
    return db.query('jewellery_invoices',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'invoice_date DESC, updated_at DESC',
        limit: limit);
  }

  Future<Map<String, Object?>?> invoice(String uuid) =>
      db.byUuid('jewellery_invoices', uuid);

  Future<List<Map<String, Object?>>> itemsFor(String invoiceUuid) =>
      db.query('jewellery_invoice_items',
          where: 'invoice_uuid = ?',
          whereArgs: [invoiceUuid],
          orderBy: 'sort_order');

  Future<List<Map<String, Object?>>> paymentsFor(String invoiceUuid) =>
      db.query('jewellery_payments',
          where: 'invoice_uuid = ?',
          whereArgs: [invoiceUuid],
          orderBy: 'pay_date ASC, updated_at ASC');

  Future<Map<String, Object?>?> oldMetalFor(String invoiceUuid) async {
    final rows = await db.query('jewellery_old_metal',
        where: 'invoice_uuid = ?', whereArgs: [invoiceUuid], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  // ----------------------------------------------------------- old metal book
  /// Every old-metal voucher with its source invoice, newest first.
  Future<List<Map<String, Object?>>> oldMetalVouchers({
    String search = '',
    String? metal,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (metal != null && metal.isNotEmpty) {
      where.add('o.metal = ?');
      args.add(metal.toUpperCase());
    }
    final needle = search.trim().toLowerCase();
    if (needle.isNotEmpty) {
      where.add('(LOWER(o.voucher_no) LIKE ? OR LOWER(o.customer) LIKE ? '
          'OR LOWER(i.doc_no) LIKE ?)');
      args.addAll(['%$needle%', '%$needle%', '%$needle%']);
    }
    final rows = await db.db.rawQuery('''
      SELECT o.*, i.doc_no AS invoice_doc_no, i.party_name AS invoice_party
      FROM jewellery_old_metal o
      LEFT JOIN jewellery_invoices i ON i.client_uuid = o.invoice_uuid
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY o.received_date DESC, o.updated_at DESC
    ''', args);
    return rows;
  }

  /// Accepted value and equivalent grams received, split by metal.
  Future<
      ({
        double goldGrams,
        double silverGrams,
        double acceptedValue,
        int vouchers,
      })> oldMetalTotals() async {
    final rows = await db.db.rawQuery('''
      SELECT metal,
             COALESCE(SUM(equivalent_weight), 0) AS grams,
             COALESCE(SUM(accepted_value), 0) AS value,
             COUNT(*) AS vouchers
      FROM jewellery_old_metal
      GROUP BY metal
    ''');
    var goldGrams = 0.0;
    var silverGrams = 0.0;
    var value = 0.0;
    var vouchers = 0;
    for (final r in rows) {
      final metal = (r['metal']?.toString() ?? '').toUpperCase();
      final grams = (r['grams'] as num?)?.toDouble() ?? 0;
      if (metal == gold) {
        goldGrams += grams;
      } else if (metal == silver) {
        silverGrams += grams;
      }
      value += (r['value'] as num?)?.toDouble() ?? 0;
      vouchers += (r['vouchers'] as num?)?.toInt() ?? 0;
    }
    return (
      goldGrams: goldGrams,
      silverGrams: silverGrams,
      acceptedValue: value,
      vouchers: vouchers,
    );
  }

  // ------------------------------------------------------- customer credit
  /// Customer credit positions for jewellery **sales**, grouped by name
  /// (case-insensitive). Purchases are supplier payables and are excluded.
  Future<List<JewelleryCreditCustomer>> creditCustomers(
      {String search = ''}) async {
    final rows = await db.db.rawQuery('''
      SELECT MIN(TRIM(party_name)) AS name,
             COUNT(*) AS invoice_count,
             COALESCE(SUM(total), 0) AS billed,
             COALESCE(SUM(amount_paid), 0) AS received,
             COALESCE(SUM(outstanding), 0) AS outstanding,
             MAX(invoice_date) AS last_date
      FROM jewellery_invoices
      WHERE doc_type = ? AND party_name IS NOT NULL AND TRIM(party_name) <> ''
      GROUP BY LOWER(TRIM(party_name))
      ORDER BY outstanding DESC, last_date DESC, name COLLATE NOCASE
    ''', [saleDoc]);
    final returnRows = await db.db.rawQuery('''
      SELECT MIN(TRIM(party_name)) AS name,
             COALESCE(SUM(total - refund_amount), 0) AS credit
      FROM jewellery_returns
      WHERE party_name IS NOT NULL AND TRIM(party_name) <> ''
      GROUP BY LOWER(TRIM(party_name))
    ''');
    final returned = <String, double>{};
    for (final r in returnRows) {
      final key = (r['name']?.toString() ?? '').trim().toLowerCase();
      if (key.isNotEmpty) {
        returned[key] = (r['credit'] as num?)?.toDouble() ?? 0;
      }
    }
    // Receipts that were more than the open invoices become customer credit.
    // They belong to the customer, not to an invoice, so they are summed by
    // party name and shown as `received` (and taken off the outstanding).
    final advanceRows = await db.db.rawQuery('''
      SELECT MIN(TRIM(party)) AS name,
             COALESCE(SUM(amount), 0) AS credit
      FROM jewellery_payments
      WHERE invoice_uuid IS NULL OR TRIM(invoice_uuid) = ''
      GROUP BY LOWER(TRIM(party))
    ''');
    final advances = <String, double>{};
    final advanceNames = <String, String>{};
    for (final r in advanceRows) {
      final name = (r['name']?.toString() ?? '').trim();
      final key = name.toLowerCase();
      if (key.isNotEmpty) {
        advances[key] = (r['credit'] as num?)?.toDouble() ?? 0;
        advanceNames[key] = name;
      }
    }
    final needle = search.trim().toLowerCase();
    final out = <JewelleryCreditCustomer>[];
    for (final r in rows) {
      final name = r['name']?.toString() ?? '';
      if (needle.isNotEmpty && !name.toLowerCase().contains(needle)) {
        continue;
      }
      final key = name.trim().toLowerCase();
      final advance = advances[key] ?? 0;
      out.add(JewelleryCreditCustomer(
        name: name,
        invoiceCount: (r['invoice_count'] as num?)?.toInt() ?? 0,
        billed: (r['billed'] as num?)?.toDouble() ?? 0,
        received: ((r['received'] as num?)?.toDouble() ?? 0) + advance,
        returned: returned[key] ?? 0,
        outstanding: math.max(
            0,
            ((r['outstanding'] as num?)?.toDouble() ?? 0) -
                (returned[key] ?? 0) -
                advance),
        lastDate: r['last_date']?.toString() ?? '',
      ));
    }
    // A customer who paid in advance and has no live invoice (never bought, or
    // every invoice was deleted) has no row in the query above, so their money
    // would sit in the advances table with nobody to open the ledger from.
    final seen = {for (final c in out) c.name.trim().toLowerCase()};
    for (final entry in advances.entries) {
      if (entry.value <= 0.005 || seen.contains(entry.key)) continue;
      final name = advanceNames[entry.key] ?? entry.key;
      if (needle.isNotEmpty && !name.toLowerCase().contains(needle)) continue;
      out.add(JewelleryCreditCustomer(
        name: name,
        invoiceCount: 0,
        billed: 0,
        received: entry.value,
        returned: 0,
        outstanding: 0,
        lastDate: '',
      ));
    }
    return out;
  }

  /// Totals for the dashboard's Credit Book entry, net of returns.
  Future<({double outstanding, int customers})> creditBookTotals() async {
    final customers = await creditCustomers();
    return (
      outstanding: customers.fold<double>(0, (sum, c) => sum + c.outstanding),
      customers: customers.where((c) => c.outstanding > 0).length,
    );
  }

  // ------------------------------------------------------- supplier payables
  /// Supplier payable positions for jewellery **purchases**, grouped by name
  /// (case-insensitive). Customer sales are excluded.
  Future<List<JewellerySupplier>> supplierPayables({String search = ''}) async {
    final rows = await db.db.rawQuery('''
      SELECT MIN(TRIM(party_name)) AS name,
             COUNT(*) AS invoice_count,
             COALESCE(SUM(total), 0) AS billed,
             COALESCE(SUM(amount_paid), 0) AS paid,
             COALESCE(SUM(outstanding), 0) AS outstanding,
             MAX(invoice_date) AS last_date
      FROM jewellery_invoices
      WHERE doc_type = ?
        AND COALESCE(status, 'Active') NOT IN ('Cancelled', 'Draft')
        AND party_name IS NOT NULL AND TRIM(party_name) <> ''
      GROUP BY LOWER(TRIM(party_name))
      ORDER BY outstanding DESC, last_date DESC, name COLLATE NOCASE
    ''', [purchaseDoc]);
    final needle = search.trim().toLowerCase();
    return [
      for (final r in rows)
        if (needle.isEmpty ||
            (r['name']?.toString().toLowerCase().contains(needle) ?? false))
          JewellerySupplier(
            name: r['name']?.toString() ?? '',
            invoiceCount: (r['invoice_count'] as num?)?.toInt() ?? 0,
            billed: (r['billed'] as num?)?.toDouble() ?? 0,
            paid: (r['paid'] as num?)?.toDouble() ?? 0,
            outstanding:
                math.max(0, (r['outstanding'] as num?)?.toDouble() ?? 0),
            lastDate: r['last_date']?.toString() ?? '',
          ),
    ];
  }

  /// Totals for the dashboard's Supplier Payables entry.
  Future<({double outstanding, int suppliers})> supplierBookTotals() async {
    final suppliers = await supplierPayables();
    return (
      outstanding: suppliers.fold<double>(0, (sum, s) => sum + s.outstanding),
      suppliers: suppliers.where((s) => s.outstanding > 0).length,
    );
  }

  /// Open purchase invoices for one supplier, oldest first. The supplier
  /// ledger uses this to choose which purchase a payment belongs to.
  Future<List<Map<String, Object?>>> openPurchaseInvoicesForSupplier(
      String partyName) async {
    return db.query(
      'jewellery_invoices',
      where: "doc_type = ? AND outstanding > 0 "
          "AND COALESCE(status, 'Active') NOT IN ('Cancelled', 'Draft') "
          "AND LOWER(TRIM(party_name)) = LOWER(TRIM(?))",
      whereArgs: [purchaseDoc, partyName.trim()],
      orderBy: 'invoice_date ASC, updated_at ASC',
    );
  }

  /// The supplier's jewellery ledger, newest first, with a running payable.
  /// A purchase is a credit; every payment (the initial one and later ones)
  /// is a debit.
  Future<List<JewellerySupplierLedgerEntry>> ledgerForSupplier(
      String partyName) async {
    final name = partyName.trim();
    if (name.isEmpty) return const [];
    final invoices = await db.query(
      'jewellery_invoices',
      // A draft or cancelled purchase is not a debt of the shop, so it must not
      // appear in the supplier ledger that the payables total is built from.
      where: "doc_type = ? "
          "AND COALESCE(status, 'Active') NOT IN ('Cancelled', 'Draft') "
          "AND LOWER(TRIM(party_name)) = LOWER(TRIM(?))",
      whereArgs: [purchaseDoc, name],
      orderBy: 'invoice_date ASC, updated_at ASC',
    );
    final payments = await db.db.rawQuery('''
      SELECT p.*, i.doc_no AS invoice_doc_no
      FROM jewellery_payments p
      JOIN jewellery_invoices i ON i.client_uuid = p.invoice_uuid
      WHERE i.doc_type = ? AND LOWER(TRIM(i.party_name)) = LOWER(TRIM(?))
      ORDER BY p.pay_date ASC, p.updated_at ASC
    ''', [purchaseDoc, name]);

    final staged = <({
      String date,
      int order,
      String stamp,
      JewellerySupplierLedgerEntry entry,
    })>[];
    for (final inv in invoices) {
      final date = inv['invoice_date']?.toString() ?? '';
      staged.add((
        date: date,
        order: 0,
        stamp: inv['updated_at']?.toString() ?? '',
        entry: JewellerySupplierLedgerEntry(
          date: date,
          type: 'PURCHASE',
          description: 'Purchase · ${inv['metal'] ?? ''}',
          reference: inv['doc_no']?.toString() ?? '',
          mode: '',
          debit: 0,
          credit: (inv['total'] as num?)?.toDouble() ?? 0,
          invoiceUuid: inv['client_uuid']?.toString() ?? '',
          note: inv['notes']?.toString() ?? '',
          balance: 0,
        ),
      ));
    }
    for (final p in payments) {
      final date = p['pay_date']?.toString() ?? '';
      staged.add((
        date: date,
        order: 1,
        stamp: p['updated_at']?.toString() ?? '',
        entry: JewellerySupplierLedgerEntry(
          date: date,
          type: 'PAYMENT',
          description: 'Payment made',
          reference: p['invoice_doc_no']?.toString() ?? '',
          mode: p['payment_mode']?.toString() ?? '',
          debit: (p['amount'] as num?)?.toDouble() ?? 0,
          credit: 0,
          invoiceUuid: p['invoice_uuid']?.toString() ?? '',
          note: p['notes']?.toString() ?? '',
          balance: 0,
        ),
      ));
    }
    staged.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      final byOrder = a.order.compareTo(b.order);
      if (byOrder != 0) return byOrder;
      return a.stamp.compareTo(b.stamp);
    });

    var balance = 0.0;
    final chronological = <JewellerySupplierLedgerEntry>[];
    for (final s in staged) {
      balance += s.entry.credit - s.entry.debit;
      if (balance < 0) balance = 0;
      chronological.add(JewellerySupplierLedgerEntry(
        date: s.entry.date,
        type: s.entry.type,
        description: s.entry.description,
        reference: s.entry.reference,
        mode: s.entry.mode,
        debit: s.entry.debit,
        credit: s.entry.credit,
        invoiceUuid: s.entry.invoiceUuid,
        note: s.entry.note,
        balance: balance,
      ));
    }
    return chronological.reversed.toList();
  }

  /// Open sale invoices for one customer, oldest first, with returns netted
  /// off. The Credit Book uses this to choose which invoice a receipt belongs
  /// to.
  Future<List<Map<String, Object?>>> openInvoicesForCustomer(
      String partyName) async {
    final rows = await db.query(
      'jewellery_invoices',
      where: "doc_type = ? AND outstanding > 0 "
          "AND LOWER(TRIM(party_name)) = LOWER(TRIM(?))",
      whereArgs: [saleDoc, partyName.trim()],
      orderBy: 'invoice_date ASC, updated_at ASC',
    );
    final out = <Map<String, Object?>>[];
    for (final row in rows) {
      final credit =
          await returnsForInvoice(row['client_uuid']?.toString() ?? '');
      final effective =
          math.max(0, ((row['outstanding'] as num?)?.toDouble() ?? 0) - credit);
      if (effective > 0.005) {
        out.add({...row, 'outstanding': effective});
      }
    }
    return out;
  }

  /// The customer's jewellery ledger, newest first, with a running balance.
  /// A sale is the debit; every receipt (the initial one and later ones) is a
  /// credit. Old metal is already inside the invoice total, so it is shown as
  /// a note and never posted twice.
  Future<List<JewelleryLedgerEntry>> ledgerForCustomer(String partyName) async {
    final name = partyName.trim();
    if (name.isEmpty) return const [];
    final invoices = await db.query(
      'jewellery_invoices',
      where: "doc_type = ? AND LOWER(TRIM(party_name)) = LOWER(TRIM(?))",
      whereArgs: [saleDoc, name],
      orderBy: 'invoice_date ASC, updated_at ASC',
    );
    final payments = await db.db.rawQuery('''
      SELECT p.*, i.doc_no AS invoice_doc_no
      FROM jewellery_payments p
      JOIN jewellery_invoices i ON i.client_uuid = p.invoice_uuid
      WHERE i.doc_type = ? AND LOWER(TRIM(i.party_name)) = LOWER(TRIM(?))
      ORDER BY p.pay_date ASC, p.updated_at ASC
    ''', [saleDoc, name]);
    final returns = await db.query(
      'jewellery_returns',
      where: 'LOWER(TRIM(party_name)) = LOWER(TRIM(?))',
      whereArgs: [name],
      orderBy: 'return_date ASC, updated_at ASC',
    );
    // A receipt larger than the open invoices is kept as customer credit; the
    // JOIN above cannot see it (it has no invoice), so it is read separately.
    final advances = await db.query(
      'jewellery_payments',
      where: "(invoice_uuid IS NULL OR TRIM(invoice_uuid) = '') "
          'AND LOWER(TRIM(party)) = LOWER(TRIM(?))',
      whereArgs: [name],
      orderBy: 'pay_date ASC, updated_at ASC',
    );
    // Manual late fees are charges, not part of the sale value: the invoice
    // total keeps the item prices, so the fee is staged as its own debit.
    final charges = await db.query(
      'jewellery_charges',
      where: 'LOWER(TRIM(party)) = LOWER(TRIM(?))',
      whereArgs: [name],
      orderBy: 'charge_date ASC, updated_at ASC',
    );

    final staged = <({
      String date,
      int order,
      String stamp,
      JewelleryLedgerEntry entry,
    })>[];
    for (final inv in invoices) {
      final date = inv['invoice_date']?.toString() ?? '';
      staged.add((
        date: date,
        order: 0,
        stamp: inv['updated_at']?.toString() ?? '',
        entry: JewelleryLedgerEntry(
          date: date,
          type: 'SALE',
          description: 'Sale · ${inv['metal'] ?? ''}',
          reference: inv['doc_no']?.toString() ?? '',
          mode: '',
          debit: (inv['total'] as num?)?.toDouble() ?? 0,
          credit: 0,
          invoiceUuid: inv['client_uuid']?.toString() ?? '',
          oldMetalValue: (inv['old_metal_value'] as num?)?.toDouble() ?? 0,
          note: inv['notes']?.toString() ?? '',
          balance: 0,
        ),
      ));
    }
    for (final p in payments) {
      final date = p['pay_date']?.toString() ?? '';
      staged.add((
        date: date,
        order: 1,
        stamp: p['updated_at']?.toString() ?? '',
        entry: JewelleryLedgerEntry(
          date: date,
          type: 'PAYMENT',
          description: 'Payment received',
          reference: p['invoice_doc_no']?.toString() ?? '',
          mode: p['payment_mode']?.toString() ?? '',
          debit: 0,
          credit: (p['amount'] as num?)?.toDouble() ?? 0,
          invoiceUuid: p['invoice_uuid']?.toString() ?? '',
          oldMetalValue: 0,
          note: p['notes']?.toString() ?? '',
          balance: 0,
        ),
      ));
    }
    for (final p in advances) {
      final date = p['pay_date']?.toString() ?? '';
      staged.add((
        date: date,
        order: 1,
        stamp: p['updated_at']?.toString() ?? '',
        entry: JewelleryLedgerEntry(
          date: date,
          type: 'ADVANCE',
          description: 'Advance received',
          reference: '',
          mode: p['payment_mode']?.toString() ?? '',
          debit: 0,
          credit: (p['amount'] as num?)?.toDouble() ?? 0,
          invoiceUuid: '',
          oldMetalValue: 0,
          note: p['notes']?.toString() ?? '',
          balance: 0,
        ),
      ));
    }
    for (final c in charges) {
      final date = c['charge_date']?.toString() ?? '';
      final amount = (c['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0.005) continue;
      staged.add((
        date: date,
        order: 2,
        stamp: c['updated_at']?.toString() ?? '',
        entry: JewelleryLedgerEntry(
          date: date,
          type: 'LATE_FEE',
          description: 'Late fee',
          reference: '',
          mode: '',
          debit: amount,
          credit: 0,
          invoiceUuid: c['invoice_uuid']?.toString() ?? '',
          oldMetalValue: 0,
          note: c['note']?.toString() ?? '',
          balance: 0,
        ),
      ));
    }
    for (final r in returns) {
      final date = r['return_date']?.toString() ?? '';
      final net = ((r['total'] as num?)?.toDouble() ?? 0) -
          ((r['refund_amount'] as num?)?.toDouble() ?? 0);
      if (net <= 0.005) continue;
      staged.add((
        date: date,
        order: 2,
        stamp: r['updated_at']?.toString() ?? '',
        entry: JewelleryLedgerEntry(
          date: date,
          type: 'RETURN',
          description: 'Return credit',
          reference: r['return_no']?.toString() ?? '',
          mode: '',
          debit: 0,
          credit: net,
          invoiceUuid: r['source_invoice_uuid']?.toString() ?? '',
          oldMetalValue: 0,
          note: r['notes']?.toString() ?? '',
          balance: 0,
        ),
      ));
    }
    staged.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      final byOrder = a.order.compareTo(b.order);
      if (byOrder != 0) return byOrder;
      return a.stamp.compareTo(b.stamp);
    });

    var balance = 0.0;
    final chronological = <JewelleryLedgerEntry>[];
    for (final s in staged) {
      balance += s.entry.debit - s.entry.credit;
      if (balance < 0) {
        balance = 0;
      }
      chronological.add(JewelleryLedgerEntry(
        date: s.entry.date,
        type: s.entry.type,
        description: s.entry.description,
        reference: s.entry.reference,
        mode: s.entry.mode,
        debit: s.entry.debit,
        credit: s.entry.credit,
        invoiceUuid: s.entry.invoiceUuid,
        oldMetalValue: s.entry.oldMetalValue,
        note: s.entry.note,
        balance: balance,
      ));
    }
    return chronological.reversed.toList();
  }

  // ---------------------------------------------------------------- writing
  /// Saves a sale or purchase document.
  ///
  /// The totals are computed here from the entered lines, the old-metal credit
  /// is deducted exactly once, and the final payable rounds to whole rupees
  /// (the round-off is stored). Stock moves only for a **sale** (finished,
  /// out) and a **purchase** (raw, in).
  Future<String> saveInvoice({
    required String docType,
    required String partyName,
    required DateTime date,
    required String metal,
    required List<JewelleryItemInput> items,
    double discount = 0,
    double amountPaid = 0,
    String paymentMode = 'CASH',
    OldMetalInput? oldMetal,
    String notes = '',
    double costTotal = 0,
    DateTime? promisedDate,
    String mobile = '',
    String address = '',
    String photoPath = '',
    String slipPhotoPath = '',
    String status = 'Active',
    double sharedExpense = 0,
  }) async {
    final name = partyName.trim();
    if (name.isEmpty) throw const FormatException('Enter a name.');
    if (items.isEmpty) throw const FormatException('Add at least one item.');
    for (final item in items) {
      if (item.netWeight <= 0) {
        throw const FormatException('Item weight must be greater than zero.');
      }
      if (item.purity <= 0 || item.purity > 100) {
        throw const FormatException('Purity must be between 0 and 100.');
      }
      if (item.rate < 0) {
        throw const FormatException('Rate cannot be negative.');
      }
    }

    final uuid = newUuid();
    final now = DateTime.now();
    final stamp = now.toIso8601String();
    final docNo = await nextDocNo(docType, date);
    // A shared expense (freight, hallmarking, stones for the lot) is split by
    // net weight, so each line carries its own share and the total is still
    // the sum of the lines. C08 in the calculations document.
    final safeShared = math.max(0.0, sharedExpense);
    final shares = JewelleryMath.allocateSharedExpense(
        safeShared, [for (final item in items) item.netWeight]);
    final computed = [
      for (var i = 0; i < items.length; i++)
        JewelleryMath.line(
          weight: items[i].netWeight,
          purityPct: items[i].purity,
          pureRate: items[i].rate,
          makingMode: items[i].makingMode,
          makingValue: items[i].makingValue,
          additionalCost: items[i].additionalCost + shares[i],
          discount: items[i].discount,
          billingBasis: items[i].billingBasis,
          wastagePct: items[i].wastagePct,
          makingCharge: items[i].makingCharge,
        ),
    ];

    var lineTotal = 0.0;
    var additional = 0.0;
    var cost = 0.0;
    for (var i = 0; i < items.length; i++) {
      lineTotal += computed[i].total;
      additional += computed[i].additionalCost;
      cost += items[i].estimatedCost > 0
          ? items[i].estimatedCost
          : items[i].actualCost;
    }

    var oldValue = 0.0;
    double oldEquivalent = 0;
    if (oldMetal != null && oldMetal.grossWeight > 0) {
      final suggestion = JewelleryMath.oldMetal(
        netWeight: oldMetal.grossWeight,
        purityPct: oldMetal.purity,
        ratePerGram: oldMetal.rate,
      );
      oldEquivalent = suggestion.equivalentWeight;
      oldValue = oldMetal.acceptedValue ?? suggestion.suggestedValue;
      if (oldValue < 0) oldValue = 0;
    }

    final safeDiscount = discount < 0 ? 0.0 : discount;
    final rawPayable = math.max(0.0, lineTotal - safeDiscount - oldValue);
    final rounded = JewelleryMath.roundRupee(rawPayable).toDouble();
    final roundOff = rounded - rawPayable;
    final paid = amountPaid < 0 ? 0.0 : amountPaid;
    // Overpayment is not modelled as customer credit yet, so it is refused
    // instead of being hidden inside a zero balance.
    if (paid > rounded + 0.005) {
      throw const FormatException('Payment is more than the payable amount.');
    }
    final outstanding = math.max(0.0, rounded - paid);
    // A draft records the document and its lines but posts nothing at all.
    final isDraft = status == draftStatus;
    final paidNow = isDraft ? 0.0 : paid;
    final dueNow = isDraft ? rounded : outstanding;

    await db.upsert('jewellery_invoices', {
      'client_uuid': uuid,
      'doc_no': docNo,
      'doc_type': docType,
      'metal': metal.toUpperCase(),
      'party': partyName,
      'party_name': name,
      'invoice_date': _day(date),
      'subtotal': lineTotal,
      'additional_total': additional,
      'discount': safeDiscount,
      'old_metal_value': oldValue,
      'round_off': roundOff,
      'total': rounded,
      'amount_paid': paidNow,
      'outstanding': dueNow,
      'cost_total': costTotal > 0 ? costTotal : cost,
      'shared_expense': safeShared,
      'status': status,
      'notes': notes,
      'promised_date': promisedDate == null ? null : _day(promisedDate),
      'mobile': mobile.trim(),
      'address': address.trim(),
      'photo_path': photoPath,
      'slip_photo_path': slipPhotoPath,
      'dirty': 1,
      'updated_at': stamp,
    });

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final line = computed[i];
      await db.upsert('jewellery_invoice_items', {
        'client_uuid': newUuid(),
        'invoice_uuid': uuid,
        'description': item.description,
        'metal': item.metal.toUpperCase(),
        'purity': item.purity,
        'gross_weight': item.grossWeight,
        'net_weight': item.netWeight,
        'rate_per_gram': item.rate,
        'making_mode': line.makingMode.name,
        'making_value': line.makingValue,
        'billing_basis': item.billingBasis.name,
        'wastage_pct': item.wastagePct,
        'making_charge': item.makingCharge,
        'fine_weight': line.fineWeight,
        'effective_pct': line.effectivePct,
        'equivalent_weight': line.equivalentWeight,
        'metal_value': line.metalValue,
        'making_amount': line.makingAmount,
        'additional_cost': line.additionalCost,
        'discount': line.discount,
        'line_total': line.total,
        'estimated_cost': item.estimatedCost,
        'actual_cost': item.actualCost,
        'sort_order': i,
      });
    }

    if (paidNow > 0) {
      await db.upsert('jewellery_payments', {
        'client_uuid': newUuid(),
        'invoice_uuid': uuid,
        'party': partyName,
        'pay_date': _day(date),
        'amount': paidNow,
        'payment_mode': paymentMode.toUpperCase(),
        'reference_no': '',
        'notes': docType == saleDoc ? 'Sale receipt' : 'Purchase payment',
        'dirty': 1,
        'updated_at': stamp,
      });
    }

    if (!isDraft && oldMetal != null && oldMetal.grossWeight > 0) {
      await db.upsert('jewellery_old_metal', {
        'client_uuid': newUuid(),
        'invoice_uuid': uuid,
        'customer': partyName,
        'voucher_no': docNo.replaceFirst('SAL', 'OLD'),
        'metal': oldMetal.metal.toUpperCase(),
        'gross_weight': oldMetal.grossWeight,
        'purity': oldMetal.purity,
        'equivalent_weight': oldEquivalent,
        'rate_per_gram': oldMetal.rate,
        'accepted_value': oldValue,
        'received_date': _day(date),
        'notes': 'Linked to $docNo',
        'dirty': 1,
        'updated_at': stamp,
      });
      await _moveStock(
        metal: oldMetal.metal,
        date: date,
        type: 'OLD_METAL_IN',
        kind: stockOld,
        // Old-metal stock is stored in pure-equivalent grams, so its purity is
        // 100 here; the customer's original purity stays on the voucher.
        weight: oldEquivalent,
        purity: 100,
        sourceUuid: uuid,
        sourceType: docType,
        notes: 'Old metal voucher ${docNo.replaceFirst('SAL', 'OLD')}',
      );
    }

    if (!isDraft) {
      for (final item in items) {
        if (docType == saleDoc) {
          await _moveStock(
            metal: item.metal,
            date: date,
            type: 'SALE_OUT',
            kind: stockFinished,
            weight: -item.netWeight,
            purity: item.purity,
            sourceUuid: uuid,
            sourceType: docType,
            notes: 'Sold on $docNo',
          );
        } else if (docType == purchaseDoc) {
          await _moveStock(
            metal: item.metal,
            date: date,
            type: 'PURCHASE_IN',
            kind: stockRaw,
            weight: item.netWeight,
            purity: item.purity,
            sourceUuid: uuid,
            sourceType: docType,
            notes: 'Purchased on $docNo',
          );
        }
      }
    }

    return uuid;
  }

  /// Posts a draft document: stock is received/sold **once** and the document
  /// becomes Active. Re-confirming is refused, and any leftover movement from a
  /// half-finished confirm is removed first so stock cannot double-post.
  Future<void> confirmInvoice(String uuid) async {
    final invoice = await db.byUuid('jewellery_invoices', uuid);
    if (invoice == null) throw const FormatException('Document not found.');
    final status = invoice['status']?.toString() ?? 'Active';
    if (status != draftStatus) {
      throw const FormatException('This document is not a draft.');
    }
    final docType = invoice['doc_type']?.toString() ?? '';
    final date = DateTime.parse(invoice['invoice_date']?.toString() ?? '');
    final docNo = invoice['doc_no']?.toString() ?? '';
    final metal = invoice['metal']?.toString() ?? gold;
    final items = await itemsFor(uuid);
    await db
        .deleteWhere('jewellery_stock_movements', 'source_uuid = ?', [uuid]);
    for (final item in items) {
      final weight = (item['net_weight'] as num?)?.toDouble() ?? 0;
      final purity = (item['purity'] as num?)?.toDouble() ?? 0;
      if (weight <= 0) continue;
      await _moveStock(
        metal: item['metal']?.toString() ?? metal,
        date: date,
        type: docType == saleDoc ? 'SALE_OUT' : 'PURCHASE_IN',
        kind: docType == saleDoc ? stockFinished : stockRaw,
        weight: docType == saleDoc ? -weight : weight,
        purity: purity,
        sourceUuid: uuid,
        sourceType: docType,
        notes: docType == saleDoc ? 'Sold on $docNo' : 'Purchased on $docNo',
      );
    }
    await db.upsert('jewellery_invoices', {
      ...invoice,
      'status': 'Active',
      'dirty': 1,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// One manual late fee against a sale (spec §7).
  ///
  /// It is a separate charge row: the invoice's item total and its recorded
  /// cost are never rewritten, the customer's outstanding rises by the fee and
  /// the ledger shows it as its own debit. Nothing is generated automatically.
  Future<String> addLateFee({
    required String invoiceUuid,
    required double amount,
    required DateTime date,
    String note = '',
  }) async {
    if (amount <= 0) {
      throw const FormatException('Late fee must be above zero.');
    }
    final invoice = await db.byUuid('jewellery_invoices', invoiceUuid);
    if (invoice == null) throw const FormatException('Document not found.');
    final uuid = newUuid();
    final stamp = DateTime.now().toIso8601String();
    await db.upsert('jewellery_charges', {
      'client_uuid': uuid,
      'invoice_uuid': invoiceUuid,
      'party': invoice['party_name'] ?? invoice['party'] ?? '',
      'charge_date': _day(date),
      'amount': amount,
      'note': note.trim(),
      'dirty': 1,
      'updated_at': stamp,
    });
    final fees = (invoice['late_fee_total'] as num?)?.toDouble() ?? 0;
    final outstanding = (invoice['outstanding'] as num?)?.toDouble() ?? 0;
    await db.upsert('jewellery_invoices', {
      ...invoice,
      'late_fee_total': fees + amount,
      'outstanding': outstanding + amount,
      'dirty': 1,
      'updated_at': stamp,
    });
    return uuid;
  }

  // ---------------------------------------------------------------- orders
  /// Customer jewellery orders, newest first. Orders never move stock until
  /// they are delivered.
  Future<List<Map<String, Object?>>> orders({
    String status = '',
    String search = '',
  }) async {
    final where = <String>['doc_type = ?'];
    final args = <Object?>[orderDoc];
    if (status.isNotEmpty) {
      where.add('status = ?');
      args.add(status);
    }
    final needle = search.trim().toLowerCase();
    if (needle.isNotEmpty) {
      where.add('(LOWER(party_name) LIKE ? OR LOWER(doc_no) LIKE ? '
          'OR LOWER(mobile) LIKE ?)');
      args.addAll(['%$needle%', '%$needle%', '%$needle%']);
    }
    return db.query('jewellery_invoices',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'COALESCE(promised_date, invoice_date) ASC, updated_at DESC');
  }

  Future<Map<String, int>> orderStatusSummary() async {
    final rows = await db.db.rawQuery('''
      SELECT status, COUNT(*) AS c
      FROM jewellery_invoices
      WHERE doc_type = ?
      GROUP BY status
    ''', [orderDoc]);
    final out = <String, int>{};
    for (final r in rows) {
      out[r['status']?.toString() ?? 'Pending'] =
          (r['c'] as num?)?.toInt() ?? 0;
    }
    return out;
  }

  Future<void> updateOrderStatus(String uuid, String status) async {
    final invoice = await db.byUuid('jewellery_invoices', uuid);
    if (invoice == null ||
        (invoice['doc_type']?.toString() ?? '') != orderDoc) {
      throw const FormatException('Order not found.');
    }
    if (status == 'Delivered') {
      throw const FormatException('Use delivery to complete an order.');
    }
    // Reopening a delivered order would let it be delivered again, which
    // would move the stock and the money a second time.
    if ((invoice['status']?.toString() ?? '') == 'Delivered') {
      throw const FormatException(
          'This order is delivered and cannot be reopened.');
    }
    await db.upsert('jewellery_invoices', {
      ...invoice,
      'status': status,
      'dirty': 1,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Completes an order. The order-date rate snapshot is already on its items;
  /// delivery only records actual weights, money and the single stock movement.
  Future<({String paymentUuid, double extra, double refund})> deliverOrder({
    required String uuid,
    required DateTime date,
    required double deliveredGrossWeight,
    double stoneWeight = 0,
    double extraAmount = 0,
    double refundAmount = 0,
    String paymentMode = 'CASH',
    String notes = '',
  }) async {
    final invoice = await db.byUuid('jewellery_invoices', uuid);
    if (invoice == null ||
        (invoice['doc_type']?.toString() ?? '') != orderDoc) {
      throw const FormatException('Order not found.');
    }
    if ((invoice['status']?.toString() ?? '') == 'Delivered') {
      throw const FormatException('This order is already delivered.');
    }
    if (deliveredGrossWeight <= 0) {
      throw const FormatException('Enter the delivered gross weight.');
    }
    if (stoneWeight < 0 || stoneWeight >= deliveredGrossWeight) {
      throw const FormatException('Stone weight must be below gross weight.');
    }
    final deliveredNet = deliveredGrossWeight - stoneWeight;
    final items = await itemsFor(uuid);
    var orderedNet = 0.0;
    for (final item in items) {
      orderedNet += (item['net_weight'] as num?)?.toDouble() ?? 0;
    }
    // Delivery posts an OUT movement and possibly a payment, so a second call
    // must be refused here rather than duplicating both.
    if ((invoice['status']?.toString() ?? '') == 'Delivered') {
      throw const FormatException('This order is already delivered.');
    }
    final extra = extraAmount < 0 ? 0.0 : extraAmount;
    final refund = refundAmount < 0 ? 0.0 : refundAmount;
    if (refund > 0 && refund > extra + 0.005) {
      // A refund can be paid from the order's own collected advance, so this
      // is allowed; the only hard guard is that it cannot exceed what was
      // actually received plus the extra collected now.
      final paid = (invoice['amount_paid'] as num?)?.toDouble() ?? 0;
      if (refund > paid + extra + 0.005) {
        throw const FormatException(
            'Refund is more than the amount received for this order.');
      }
    }
    final stamp = DateTime.now().toIso8601String();
    final total = (invoice['total'] as num?)?.toDouble() ?? 0;
    final fees = (invoice['late_fee_total'] as num?)?.toDouble() ?? 0;
    final finalTotal = math.max(0.0, total + extra - refund);
    final currentPaid = (invoice['amount_paid'] as num?)?.toDouble() ?? 0;
    var paid = currentPaid;
    var paymentUuid = '';
    if (extra > 0) {
      paymentUuid = newUuid();
      await db.upsert('jewellery_payments', {
        'client_uuid': paymentUuid,
        'invoice_uuid': uuid,
        'party': invoice['party'],
        'pay_date': _day(date),
        'amount': extra,
        'payment_mode': paymentMode.toUpperCase(),
        'reference_no': '',
        'notes': 'Order delivery extra',
        'dirty': 1,
        'updated_at': stamp,
      });
      paid += extra;
    }
    await db.upsert('jewellery_invoices', {
      ...invoice,
      'status': 'Delivered',
      'delivery_date': _day(date),
      'delivered_gross_weight': deliveredGrossWeight,
      'stone_weight': stoneWeight,
      'delivered_net_weight': deliveredNet,
      'difference_weight': deliveredNet - orderedNet,
      'extra_amount': extra,
      'refund_amount': refund,
      'total': finalTotal,
      'amount_paid': paid,
      'outstanding': math.max(0.0, finalTotal + fees - paid),
      'notes': notes.trim().isEmpty
          ? invoice['notes']
          : '${invoice['notes'] ?? ''}\n$notes'.trim(),
      'dirty': 1,
      'updated_at': stamp,
    });
    await _moveStock(
      metal: invoice['metal']?.toString() ?? gold,
      date: date,
      type: 'ORDER_DELIVERY_OUT',
      kind: stockFinished,
      weight: -deliveredNet,
      purity: 100,
      sourceUuid: uuid,
      sourceType: orderDoc,
      notes: 'Order delivered ${invoice['doc_no'] ?? ''}',
    );
    return (paymentUuid: paymentUuid, extra: extra, refund: refund);
  }

  // --------------------------------------------------------------- workers
  /// Worker names that have either an order or a cash/metal movement.
  Future<List<String>> workerNames() async {
    final rows = await db.db.rawQuery('''
      SELECT worker_name FROM jewellery_worker_orders
      WHERE worker_name IS NOT NULL AND TRIM(worker_name) <> ''
      UNION
      SELECT worker_name FROM jewellery_worker_txns
      WHERE worker_name IS NOT NULL AND TRIM(worker_name) <> ''
      ORDER BY worker_name COLLATE NOCASE
    ''');
    return [
      for (final r in rows)
        if ((r['worker_name']?.toString() ?? '').trim().isNotEmpty)
          r['worker_name'].toString().trim(),
    ];
  }

  /// Cash and metal held by each worker. Positive cash = shop paid the worker;
  /// positive gold = shop issued metal. A delivered order gives its metal back,
  /// so the delivered net weight is subtracted — otherwise a finished job would
  /// sit on the reserve for ever.
  Future<List<JewelleryWorkerPosition>> workerPositions() async {
    final names = await workerNames();
    final out = <JewelleryWorkerPosition>[];
    for (final name in names) {
      final rows = await db.db.rawQuery('''
        SELECT COALESCE(SUM(cash_amount), 0) AS cash,
               COALESCE(SUM(gold_weight), 0) AS gold,
               COALESCE(SUM(gold_weight * purity / 100.0), 0) AS fine,
               COUNT(*) AS c,
               MAX(txn_date) AS last_date
        FROM jewellery_worker_txns
        WHERE LOWER(TRIM(worker_name)) = LOWER(TRIM(?))
      ''', [name]);
      final r = rows.isEmpty ? null : rows.first;
      // Delivery puts the finished weight into shop stock, so the same grams
      // have to leave the reserve. The weight lives on the order, so no extra
      // movement is written and deleting the order reverses this for free.
      final back = await db.db.rawQuery('''
        SELECT COALESCE(SUM(delivered_net_weight), 0) AS g
        FROM jewellery_worker_orders
        WHERE LOWER(TRIM(worker_name)) = LOWER(TRIM(?))
          AND status = 'Delivered'
      ''', [name]);
      final returned =
          (back.isEmpty ? null : back.first['g'] as num?)?.toDouble() ?? 0;
      // Delivered metal is booked into stock at 100%, so its fine weight is the
      // net weight and both figures fall by the same grams.
      out.add(JewelleryWorkerPosition(
        name: name,
        cashReserve: (r?['cash'] as num?)?.toDouble() ?? 0,
        goldReserve: ((r?['gold'] as num?)?.toDouble() ?? 0) - returned,
        fineGoldReserve: ((r?['fine'] as num?)?.toDouble() ?? 0) - returned,
        lastDate: r?['last_date']?.toString() ?? '',
        txnCount: (r?['c'] as num?)?.toInt() ?? 0,
      ));
    }
    return out;
  }

  Future<List<Map<String, Object?>>> workerTransactions(String workerName) =>
      db.query('jewellery_worker_txns',
          where: 'LOWER(TRIM(worker_name)) = LOWER(TRIM(?))',
          whereArgs: [workerName.trim()],
          orderBy: 'txn_date DESC, updated_at DESC');

  /// Records one signed worker movement.
  ///
  /// [cashAmount] positive = the shop paid the worker; negative = the worker
  /// paid the shop. [goldWeight] positive = the shop issued metal; negative =
  /// the worker returned it. Gold issue/return posts the matching stock
  /// movement in the same transaction, so shop and worker can never disagree.
  Future<String> saveWorkerTransaction({
    required String workerName,
    required DateTime date,
    required String type,
    double cashAmount = 0,
    double goldWeight = 0,
    String metal = gold,
    double ratePerGram = 0,
    double purity = 100,
    String orderUuid = '',
    String notes = '',
  }) async {
    final name = workerName.trim();
    if (name.isEmpty) throw const FormatException('Enter the worker name.');
    if (cashAmount.abs() < 0.005 && goldWeight.abs() < 0.005) {
      throw const FormatException('Enter a cash or gold amount.');
    }
    if (goldWeight.abs() > 0.0005 && (purity <= 0 || purity > 100)) {
      throw const FormatException('Purity must be between 0 and 100.');
    }
    final uuid = newUuid();
    final stamp = DateTime.now().toIso8601String();
    await db.upsert('jewellery_worker_txns', {
      'client_uuid': uuid,
      'worker_name': name,
      'order_uuid': orderUuid,
      'txn_date': _day(date),
      'txn_type': type,
      'cash_amount': cashAmount,
      'gold_weight': goldWeight,
      'rate_per_gram': ratePerGram > 0 ? ratePerGram : null,
      'purity': purity,
      'notes': notes.trim(),
      'dirty': 1,
      'updated_at': stamp,
    });
    if (goldWeight.abs() > 0.0005) {
      await _moveStock(
        metal: metal,
        date: date,
        type: goldWeight > 0 ? 'WORKER_ISSUE' : 'WORKER_RETURN',
        kind: stockRaw,
        weight: -goldWeight,
        purity: purity,
        sourceUuid: uuid,
        sourceType: 'WORKER',
        notes: '${goldWeight > 0 ? 'Issued to' : 'Returned by'} $name',
      );
    }
    return uuid;
  }

  /// Removes a worker order and the stock movement its delivery posted, so a
  /// deleted order cannot leave finished metal behind. The reserve reads the
  /// delivered weights from the order itself, so the metal goes back on the
  /// reserve without touching any other row.
  Future<void> deleteWorkerOrder(String uuid) async {
    await db.deleteWhere('jewellery_stock_movements', 'source_uuid = ?', [uuid]);
    await db.deleteWhere('jewellery_worker_orders', 'client_uuid = ?', [uuid]);
  }

  Future<List<Map<String, Object?>>> workerOrders({String workerName = ''}) =>
      db.query('jewellery_worker_orders',
          where: workerName.trim().isEmpty
              ? null
              : 'LOWER(TRIM(worker_name)) = LOWER(TRIM(?))',
          whereArgs: workerName.trim().isEmpty ? null : [workerName.trim()],
          orderBy: 'order_date DESC, updated_at DESC');

  Future<String> saveWorkerOrder({
    required String workerName,
    required DateTime date,
    DateTime? expectedDate,
    String orderUuid = '',
    String metal = gold,
    String description = '',
    required double orderedWeight,
    MakingMode makingMode = MakingMode.none,
    double makingValue = 0,
    double additionalCost = 0,
    String notes = '',
  }) async {
    final name = workerName.trim();
    if (name.isEmpty) throw const FormatException('Enter the worker name.');
    if (orderedWeight <= 0) {
      throw const FormatException('Ordered weight must be above zero.');
    }
    final uuid = newUuid();
    await db.upsert('jewellery_worker_orders', {
      'client_uuid': uuid,
      'worker_name': name,
      'order_uuid': orderUuid,
      'order_date': _day(date),
      'expected_date': expectedDate == null ? null : _day(expectedDate),
      'metal': metal.toUpperCase(),
      'item_description': description.trim(),
      'ordered_weight': orderedWeight,
      'making_mode': makingMode.name,
      'making_value': makingValue,
      'additional_cost': additionalCost,
      'status': 'Pending',
      'notes': notes.trim(),
      'dirty': 1,
      'updated_at': DateTime.now().toIso8601String(),
    });
    return uuid;
  }

  Future<void> deliverWorkerOrder({
    required String uuid,
    required DateTime date,
    required double deliveredGrossWeight,
    double stoneWeight = 0,
    double cashPaid = 0,
    double metalPaid = 0,
    String notes = '',
  }) async {
    final row = await db.byUuid('jewellery_worker_orders', uuid);
    if (row == null) throw const FormatException('Worker order not found.');
    // Delivery puts the finished metal into shop stock, so delivering the same
    // worker order twice would add the grams twice.
    if ((row['status']?.toString() ?? '') == 'Delivered') {
      throw const FormatException('This worker order is already delivered.');
    }
    if (deliveredGrossWeight <= 0) {
      throw const FormatException('Enter the delivered gross weight.');
    }
    if (stoneWeight < 0 || stoneWeight >= deliveredGrossWeight) {
      throw const FormatException('Stone weight must be below gross weight.');
    }
    final deliveredNet = deliveredGrossWeight - stoneWeight;
    await db.upsert('jewellery_worker_orders', {
      ...row,
      'status': 'Delivered',
      'delivered_date': _day(date),
      'delivered_gross_weight': deliveredGrossWeight,
      'stone_weight': stoneWeight,
      'delivered_net_weight': deliveredNet,
      'cash_paid': cashPaid < 0 ? 0 : cashPaid,
      'metal_paid': metalPaid < 0 ? 0 : metalPaid,
      'notes': notes.trim().isEmpty
          ? row['notes']
          : '${row['notes'] ?? ''}\n$notes'.trim(),
      'dirty': 1,
      'updated_at': DateTime.now().toIso8601String(),
    });
    // Finished metal received from the worker enters shop stock. Metal issued
    // to the worker left RAW stock through saveWorkerTransaction, so the two
    // movements reconcile without double counting.
    await _moveStock(
      metal: row['metal']?.toString() ?? gold,
      date: date,
      type: 'WORKER_ORDER_IN',
      kind: stockFinished,
      weight: deliveredNet,
      purity: 100,
      sourceUuid: uuid,
      sourceType: 'WORKER_ORDER',
      notes: 'Worker order delivered',
    );
  }

  /// Removes a worker movement and the stock movement it created. Returns the
  /// cashbook references the caller must remove.
  Future<List<String>> deleteWorkerTransaction(String uuid) async {
    await db
        .deleteWhere('jewellery_stock_movements', 'source_uuid = ?', [uuid]);
    await db.deleteWhere('jewellery_worker_txns', 'client_uuid = ?', [uuid]);
    return [uuid];
  }

  // --------------------------------------------------------------- returns
  Future<String> _nextReturnNo(DateTime date) async {
    final day = _day(date).replaceAll('-', '');
    final rows = await db.db.rawQuery(
      'SELECT return_no FROM jewellery_returns WHERE return_no LIKE ?',
      ['RET-$day-%'],
    );
    var max = 0;
    for (final r in rows) {
      final no = r['return_no']?.toString() ?? '';
      final seq = int.tryParse(no.split('-').last) ?? 0;
      max = math.max(max, seq);
    }
    return 'RET-$day-${(max + 1).toString().padLeft(4, '0')}';
  }

  /// Creates a linked credit note against a sale. The original invoice is never
  /// edited; the return reduces the customer's balance through the ledger and
  /// adds stock back only when [JewelleryReturnItemInput.restock] is true.
  Future<String> saveReturn({
    required String sourceInvoiceUuid,
    required DateTime date,
    required List<JewelleryReturnItemInput> items,
    double refundAmount = 0,
    String notes = '',
  }) async {
    final source = await db.byUuid('jewellery_invoices', sourceInvoiceUuid);
    if (source == null || (source['doc_type']?.toString() ?? '') != saleDoc) {
      throw const FormatException('Choose a sale invoice to return against.');
    }
    if (items.isEmpty) throw const FormatException('Add at least one item.');
    for (final item in items) {
      if (item.netWeight <= 0) {
        throw const FormatException('Return weight must be above zero.');
      }
      if (item.purity <= 0 || item.purity > 100) {
        throw const FormatException('Purity must be between 0 and 100.');
      }
    }
    var total = 0.0;
    for (final item in items) {
      total += item.value;
    }
    total = math.max(0.0, total);
    final refund = refundAmount < 0 ? 0.0 : refundAmount;
    if (refund > total + 0.005) {
      throw const FormatException('Refund is more than the return value.');
    }
    // The return form checks this too, but the store is the last line of
    // defence: a credit note must never take back more metal than the sale.
    final soldItems = await itemsFor(sourceInvoiceUuid);
    var soldNet = 0.0;
    for (final item in soldItems) {
      soldNet += (item['net_weight'] as num?)?.toDouble() ?? 0;
    }
    var requestedNet = 0.0;
    for (final item in items) {
      requestedNet += item.netWeight;
    }
    final alreadyReturned = await returnedWeightForInvoice(sourceInvoiceUuid);
    if (soldNet > 0 && alreadyReturned + requestedNet > soldNet + 0.005) {
      final left = math.max(0.0, soldNet - alreadyReturned);
      throw FormatException(
          'Only ${left.toStringAsFixed(3)} g of this sale is left to return.');
    }
    final uuid = newUuid();
    final stamp = DateTime.now().toIso8601String();
    final returnNo = await _nextReturnNo(date);
    await db.upsert('jewellery_returns', {
      'client_uuid': uuid,
      'return_no': returnNo,
      'source_invoice_uuid': sourceInvoiceUuid,
      'party_name': source['party_name'],
      'return_date': _day(date),
      'metal': source['metal'],
      'total': total,
      'refund_amount': refund,
      'restock': items.any((i) => i.restock) ? 1 : 0,
      'notes': notes.trim(),
      'dirty': 1,
      'updated_at': stamp,
    });
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      await db.upsert('jewellery_return_items', {
        'client_uuid': newUuid(),
        'return_uuid': uuid,
        'description': item.description,
        'metal': item.metal.toUpperCase(),
        'gross_weight': item.grossWeight,
        'net_weight': item.netWeight,
        'purity': item.purity,
        'rate_per_gram': item.rate,
        'value': item.value,
        'restock': item.restock ? 1 : 0,
        'sort_order': i,
      });
      if (item.restock) {
        await _moveStock(
          metal: item.metal,
          date: date,
          type: 'RETURN_IN',
          kind: stockFinished,
          weight: item.netWeight,
          purity: item.purity,
          sourceUuid: uuid,
          sourceType: 'RETURN',
          notes: 'Returned on $returnNo',
        );
      }
    }
    return uuid;
  }

  Future<List<Map<String, Object?>>> returns({String search = ''}) async {
    final needle = search.trim().toLowerCase();
    final rows = await db.db.rawQuery('''
      SELECT r.*, i.doc_no AS source_doc_no
      FROM jewellery_returns r
      LEFT JOIN jewellery_invoices i ON i.client_uuid = r.source_invoice_uuid
      ${needle.isEmpty ? '' : 'WHERE LOWER(r.return_no) LIKE ? OR LOWER(r.party_name) LIKE ? OR LOWER(i.doc_no) LIKE ?'}
      ORDER BY r.return_date DESC, r.updated_at DESC
    ''', needle.isEmpty ? [] : ['%$needle%', '%$needle%', '%$needle%']);
    return rows;
  }

  Future<List<Map<String, Object?>>> returnItems(String returnUuid) =>
      db.query('jewellery_return_items',
          where: 'return_uuid = ?',
          whereArgs: [returnUuid],
          orderBy: 'sort_order');

  /// Net credit from returns against one sale (return value minus cash refund).
  Future<double> returnsForInvoice(String invoiceUuid) async {
    final rows = await db.db.rawQuery('''
      SELECT COALESCE(SUM(total - refund_amount), 0) AS credit
      FROM jewellery_returns
      WHERE source_invoice_uuid = ?
    ''', [invoiceUuid]);
    if (rows.isEmpty) return 0;
    return (rows.first['credit'] as num?)?.toDouble() ?? 0;
  }

  Future<double> returnsForCustomer(String partyName) async {
    final rows = await db.db.rawQuery('''
      SELECT COALESCE(SUM(total - refund_amount), 0) AS credit
      FROM jewellery_returns
      WHERE LOWER(TRIM(party_name)) = LOWER(TRIM(?))
    ''', [partyName.trim()]);
    if (rows.isEmpty) return 0;
    return (rows.first['credit'] as num?)?.toDouble() ?? 0;
  }

  /// Net grams already returned against one sale, so the form can refuse to
  /// return more metal than the customer bought.
  Future<double> returnedWeightForInvoice(String invoiceUuid) async {
    final rows = await db.db.rawQuery('''
      SELECT COALESCE(SUM(ri.net_weight), 0) AS grams
      FROM jewellery_return_items ri
      JOIN jewellery_returns r ON r.client_uuid = ri.return_uuid
      WHERE r.source_invoice_uuid = ?
    ''', [invoiceUuid]);
    if (rows.isEmpty) return 0;
    return (rows.first['grams'] as num?)?.toDouble() ?? 0;
  }

  Future<List<String>> deleteReturn(String uuid) async {
    await db
        .deleteWhere('jewellery_stock_movements', 'source_uuid = ?', [uuid]);
    await db.deleteWhere('jewellery_return_items', 'return_uuid = ?', [uuid]);
    await db.deleteWhere('jewellery_returns', 'client_uuid = ?', [uuid]);
    return [uuid];
  }

  Future<void> _moveStock({
    required String metal,
    required DateTime date,
    required String type,
    required String kind,
    required double weight,
    required double purity,
    required String sourceUuid,
    required String sourceType,
    String notes = '',
  }) async {
    await db.upsert('jewellery_stock_movements', {
      'client_uuid': newUuid(),
      'metal': metal.toUpperCase(),
      'movement_date': _day(date),
      'movement_type': type,
      'stock_kind': kind,
      'weight': weight,
      'purity': purity,
      'fine_weight': weight * purity / 100.0,
      'source_uuid': sourceUuid,
      'source_type': sourceType,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Adds one receipt/payment and re-derives the invoice balance.
  ///
  /// The invoice total already had accepted old metal deducted once, so this
  /// only compares money actually received with that final payable figure.
  Future<String> addPayment({
    required String invoiceUuid,
    required double amount,
    required DateTime date,
    String mode = 'CASH',
    String reference = '',
    String notes = '',
  }) async {
    if (amount <= 0) throw const FormatException('Amount must be above zero.');
    final invoice = await db.byUuid('jewellery_invoices', invoiceUuid);
    if (invoice == null) throw const FormatException('Invoice not found.');
    final returnCredit = await returnsForInvoice(invoiceUuid);
    final currentOutstanding = math.max(
        0, ((invoice['outstanding'] as num?)?.toDouble() ?? 0) - returnCredit);
    if (amount > currentOutstanding + 0.005) {
      throw const FormatException(
          'Payment is more than the outstanding balance.');
    }
    final stamp = DateTime.now().toIso8601String();
    final uuid = newUuid();
    await db.upsert('jewellery_payments', {
      'client_uuid': uuid,
      'invoice_uuid': invoiceUuid,
      'party': invoice['party'],
      'pay_date': _day(date),
      'amount': amount,
      'payment_mode': mode.toUpperCase(),
      'reference_no': reference,
      'notes': notes,
      'dirty': 1,
      'updated_at': stamp,
    });
    final paid = await db.sum('jewellery_payments', 'amount',
        where: 'invoice_uuid = ?', whereArgs: [invoiceUuid]);
    // Late fees are part of what the customer owes, so a payment must not
    // recompute the balance from the item total alone and wipe the fees out.
    final total = (invoice['total'] as num?)?.toDouble() ?? 0;
    final fees = (invoice['late_fee_total'] as num?)?.toDouble() ?? 0;
    await db.upsert('jewellery_invoices', {
      ...invoice,
      'amount_paid': paid,
      'outstanding': math.max(0.0, total + fees - paid),
      'dirty': 1,
      'updated_at': stamp,
    });
    return uuid;
  }

  /// Records one customer receipt and spreads it over that customer's open
  /// sale invoices (C13).
  ///
  /// [allocations] is a manual split (invoice uuid → amount); when it is empty
  /// the receipt is spread oldest-first. Each invoice takes at most what it
  /// still owes, and anything left over is stored as an **unallocated advance**
  /// on the customer — the spec asks for overpayment to be visible credit, not
  /// a refusal and not a hidden zero balance.
  Future<
      ({
        Map<String, double> allocated,
        double unallocated,
        List<({String uuid, double amount, String invoiceUuid})> payments,
      })> receiveCustomerPayment({
    required String partyName,
    required double amount,
    required DateTime date,
    String mode = 'CASH',
    String reference = '',
    String notes = '',
    Map<String, double> allocations = const {},
  }) async {
    final name = partyName.trim();
    if (name.isEmpty) throw const FormatException('Enter a customer name.');
    if (amount <= 0) throw const FormatException('Amount must be above zero.');

    final open = await openInvoicesForCustomer(name);
    final owes = <String, double>{};
    for (final inv in open) {
      final uuid = inv['client_uuid']?.toString() ?? '';
      if (uuid.isEmpty) continue;
      owes[uuid] = math.max(0, (inv['outstanding'] as num?)?.toDouble() ?? 0);
    }

    final plan = <String, double>{};
    var remaining = amount;
    if (allocations.isNotEmpty) {
      for (final entry in allocations.entries) {
        if (remaining <= 0.005) break;
        final take = math.min(
            math.min(entry.value < 0 ? 0.0 : entry.value, owes[entry.key] ?? 0),
            remaining);
        if (take <= 0.005) continue;
        plan[entry.key] = take;
        remaining -= take;
      }
    } else {
      final uuids = [
        for (final inv in open)
          if (owes.containsKey(inv['client_uuid']?.toString() ?? ''))
            inv['client_uuid']!.toString(),
      ];
      final spread = JewelleryMath.allocatePayment(
          amount, [for (final u in uuids) owes[u] ?? 0]);
      for (var i = 0; i < uuids.length; i++) {
        final take = spread.allocations[i];
        if (take <= 0.005) continue;
        plan[uuids[i]] = take;
        remaining -= take;
      }
    }
    final unallocated = math.max(0.0, remaining);

    final stamp = DateTime.now().toIso8601String();
    final payments = <({String uuid, double amount, String invoiceUuid})>[];
    for (final entry in plan.entries) {
      final uuid = newUuid();
      await db.upsert('jewellery_payments', {
        'client_uuid': uuid,
        'invoice_uuid': entry.key,
        'party': name,
        'pay_date': _day(date),
        'amount': entry.value,
        'payment_mode': mode.toUpperCase(),
        'reference_no': reference,
        'notes': notes,
        'dirty': 1,
        'updated_at': stamp,
      });
      payments.add((uuid: uuid, amount: entry.value, invoiceUuid: entry.key));
      final invoice = await db.byUuid('jewellery_invoices', entry.key);
      if (invoice == null) continue;
      final total = (invoice['total'] as num?)?.toDouble() ?? 0;
      final paid = await db.sum('jewellery_payments', 'amount',
          where: 'invoice_uuid = ?', whereArgs: [entry.key]);
      // The balance includes manual late fees; deriving it from the item total
      // would silently drop them as soon as a receipt is recorded.
      final fees = (invoice['late_fee_total'] as num?)?.toDouble() ?? 0;
      await db.upsert('jewellery_invoices', {
        ...invoice,
        'amount_paid': paid,
        'outstanding': math.max(0.0, total + fees - paid),
        'dirty': 1,
        'updated_at': stamp,
      });
    }
    if (unallocated > 0.005) {
      final uuid = newUuid();
      await db.upsert('jewellery_payments', {
        'client_uuid': uuid,
        'invoice_uuid': '',
        'party': name,
        'pay_date': _day(date),
        'amount': unallocated,
        'payment_mode': mode.toUpperCase(),
        'reference_no': reference,
        'notes': notes.trim().isEmpty
            ? 'Customer advance'
            : 'Customer advance — ${notes.trim()}',
        'dirty': 1,
        'updated_at': stamp,
      });
      payments.add((uuid: uuid, amount: unallocated, invoiceUuid: ''));
    }
    return (allocated: plan, unallocated: unallocated, payments: payments);
  }

  /// Deletes a document and everything it created. Returns the references the
  /// caller must remove from the cashbook before/after calling this.
  Future<List<String>> deleteInvoice(String uuid) async {
    final payments = await paymentsFor(uuid);
    final oldMetal = await oldMetalFor(uuid);
    final linkedReturns = await db.query('jewellery_returns',
        where: 'source_invoice_uuid = ?', whereArgs: [uuid]);
    final refs = <String>[uuid, '${uuid}_refund'];
    for (final p in payments) {
      refs.add(p['client_uuid']?.toString() ?? '');
    }
    if (oldMetal != null) refs.add(oldMetal['client_uuid']?.toString() ?? '');
    for (final r in linkedReturns) {
      final returnUuid = r['client_uuid']?.toString() ?? '';
      if (returnUuid.isEmpty) continue;
      refs.add(returnUuid);
      await db.deleteWhere(
          'jewellery_return_items', 'return_uuid = ?', [returnUuid]);
      await db.deleteWhere(
          'jewellery_stock_movements', 'source_uuid = ?', [returnUuid]);
    }
    await db
        .deleteWhere('jewellery_returns', 'source_invoice_uuid = ?', [uuid]);
    await db.deleteWhere('jewellery_invoice_items', 'invoice_uuid = ?', [uuid]);
    await db.deleteWhere('jewellery_payments', 'invoice_uuid = ?', [uuid]);
    await db.deleteWhere('jewellery_old_metal', 'invoice_uuid = ?', [uuid]);
    await db.deleteWhere('jewellery_charges', 'invoice_uuid = ?', [uuid]);
    await db
        .deleteWhere('jewellery_stock_movements', 'source_uuid = ?', [uuid]);
    await db.deleteWhere('jewellery_invoices', 'client_uuid = ?', [uuid]);
    return refs.where((r) => r.isNotEmpty).toList();
  }

  // ------------------------------------------------------------------ stock
  /// Net grams per metal and stock kind. Stock changes only through
  /// `jewellery_stock_movements`, so this can never disagree with a document.
  Future<Map<String, double>> stockTotals() async {
    final rows = await db.db.rawQuery('''
      SELECT stock_kind, metal, COALESCE(SUM(weight), 0) AS w
      FROM jewellery_stock_movements
      GROUP BY stock_kind, metal
    ''');
    final out = <String, double>{};
    for (final r in rows) {
      final kind = r['stock_kind']?.toString() ?? '';
      final metal = (r['metal']?.toString() ?? '').toUpperCase();
      if (kind.isEmpty || metal.isEmpty) continue;
      out['${metal}_$kind'] = (r['w'] as num?)?.toDouble() ?? 0;
    }
    return out;
  }

  /// Ordered net grams still in production — orders that are Pending or Ready.
  ///
  /// This is **work in progress**, not shop stock: the metal is neither in the
  /// shop's finished shelf nor received from the worker yet, so reports show it
  /// separately instead of double-counting it.
  Future<Map<String, double>> wipWeight() async {
    final rows = await db.db.rawQuery('''
      SELECT i.metal AS metal, COALESCE(SUM(it.net_weight), 0) AS grams
      FROM jewellery_invoices i
      JOIN jewellery_invoice_items it ON it.invoice_uuid = i.client_uuid
      WHERE i.doc_type = ?
        AND COALESCE(i.status, 'Pending') IN ('Pending', 'Ready')
      GROUP BY i.metal
    ''', [orderDoc]);
    final out = <String, double>{};
    for (final r in rows) {
      final metal = (r['metal']?.toString() ?? '').toUpperCase();
      if (metal.isEmpty) continue;
      out[metal] = (r['grams'] as num?)?.toDouble() ?? 0;
    }
    return out;
  }

  Future<List<Map<String, Object?>>> stockMovements({
    String? metal,
    int limit = 100,
  }) =>
      db.query('jewellery_stock_movements',
          where: metal == null ? null : 'metal = ?',
          whereArgs: metal == null ? null : [metal.toUpperCase()],
          orderBy: 'movement_date DESC, created_at DESC',
          limit: limit);

  /// Stock valued at the newest saved pure-metal rate for each metal.
  ///
  /// Fine grams come from the stock ledger itself, so a sale, purchase, return
  /// or worker movement is reflected without a separate valuation table. A
  /// metal with no saved rate is still listed, with a null rate and zero value.
  Future<JewelleryStockValuation> stockValuation() async {
    final rows = await db.db.rawQuery('''
      SELECT stock_kind, metal,
             COALESCE(SUM(weight), 0) AS grams,
             COALESCE(
               SUM(CASE WHEN stock_kind = 'OLD' THEN weight ELSE fine_weight END),
               SUM(CASE WHEN stock_kind = 'OLD' THEN weight
                        ELSE weight * purity / 100.0 END),
               0
             ) AS fine
      FROM jewellery_stock_movements
      GROUP BY stock_kind, metal
      ORDER BY metal, stock_kind
    ''');
    final goldRate = await latestRate(gold);
    final silverRate = await latestRate(silver);
    final lines = <JewelleryStockLine>[];
    for (final r in rows) {
      final kind = r['stock_kind']?.toString() ?? '';
      final metal = (r['metal']?.toString() ?? '').toUpperCase();
      if (kind.isEmpty || metal.isEmpty) continue;
      final rate = metal == gold
          ? goldRate
          : metal == silver
              ? silverRate
              : null;
      final fine = (r['fine'] as num?)?.toDouble() ?? 0;
      lines.add(JewelleryStockLine(
        metal: metal,
        kind: kind,
        grams: (r['grams'] as num?)?.toDouble() ?? 0,
        fineWeight: fine,
        value: fine * (rate ?? 0),
      ));
    }
    return JewelleryStockValuation(
      lines: lines,
      goldRate: goldRate,
      silverRate: silverRate,
    );
  }

  // ---------------------------------------------------------------- reports
  /// Sale/purchase totals for the last [months] calendar months, oldest first.
  /// The on-screen chart uses this so the bars and the money cards read from
  /// the same documents. Orders and cancelled documents are excluded.
  Future<List<JewelleryMonthTotal>> monthlyTotals({
    int months = 6,
    DateTime? asOf,
  }) async {
    if (months <= 0) return const [];
    final now = asOf ?? DateTime.now();
    final start = DateTime(now.year, now.month - (months - 1), 1);
    final rows = await db.db.rawQuery('''
      SELECT substr(invoice_date, 1, 7) AS ym,
             COALESCE(SUM(CASE WHEN doc_type = ? THEN total ELSE 0 END), 0)
               AS sales,
             COALESCE(SUM(CASE WHEN doc_type = ? THEN total ELSE 0 END), 0)
               AS purchases
      FROM jewellery_invoices
      WHERE doc_type IN (?, ?)
        AND COALESCE(status, 'Active') NOT IN ('Cancelled', 'Draft')
        AND invoice_date >= ?
      GROUP BY ym
      ORDER BY ym
    ''', [saleDoc, purchaseDoc, saleDoc, purchaseDoc, _day(start)]);
    final byMonth = <String, Map<String, Object?>>{
      for (final r in rows) r['ym']?.toString() ?? '': r,
    };
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return [
      for (var i = 0; i < months; i++)
        () {
          final m = DateTime(start.year, start.month + i, 1);
          final ym = '${m.year.toString().padLeft(4, '0')}-'
              '${m.month.toString().padLeft(2, '0')}';
          final row = byMonth[ym];
          return JewelleryMonthTotal(
            month: ym,
            label: names[m.month - 1],
            sales: (row?['sales'] as num?)?.toDouble() ?? 0,
            purchases: (row?['purchases'] as num?)?.toDouble() ?? 0,
          );
        }(),
    ];
  }

  Future<
      ({
        double sales,
        double purchases,
        double collections,
        double returns,
        double refunds,
        double oldMetalValue,
        double oldGold,
        double oldSilver,
        double outstandingSales,
        double outstandingPurchases,
        int saleCount,
        int purchaseCount,
      })> reportTotals({DateTime? from, DateTime? to}) async {
    String between(String column) {
      final parts = <String>[];
      if (from != null) parts.add('$column >= ?');
      if (to != null) parts.add('$column <= ?');
      return parts.isEmpty ? '' : ' AND ${parts.join(' AND ')}';
    }

    List<Object?> args() => [
          if (from != null) _day(from),
          if (to != null) _day(to),
        ];

    final salesRows = await db.db.rawQuery('''
      SELECT COALESCE(SUM(total), 0) AS total, COUNT(*) AS c
      FROM jewellery_invoices
      WHERE doc_type = ?
        AND COALESCE(status, 'Active') NOT IN ('Cancelled', 'Draft')
        ${between('invoice_date')}
    ''', [saleDoc, ...args()]);
    final purchaseRows = await db.db.rawQuery('''
      SELECT COALESCE(SUM(total), 0) AS total, COUNT(*) AS c
      FROM jewellery_invoices
      WHERE doc_type = ?
        AND COALESCE(status, 'Active') NOT IN ('Cancelled', 'Draft')
        ${between('invoice_date')}
    ''', [purchaseDoc, ...args()]);
    final collectionRows = await db.db.rawQuery('''
      SELECT COALESCE(SUM(p.amount), 0) AS total
      FROM jewellery_payments p
      JOIN jewellery_invoices i ON i.client_uuid = p.invoice_uuid
      WHERE i.doc_type IN (?, ?)${between('p.pay_date')}
    ''', [saleDoc, orderDoc, ...args()]);
    final returnRows = await db.db.rawQuery('''
      SELECT COALESCE(SUM(total), 0) AS total,
             COALESCE(SUM(refund_amount), 0) AS refunds
      FROM jewellery_returns
      WHERE 1 = 1${between('return_date')}
    ''', args());
    final oldRows = await db.db.rawQuery('''
      SELECT metal,
             COALESCE(SUM(equivalent_weight), 0) AS grams,
             COALESCE(SUM(accepted_value), 0) AS value
      FROM jewellery_old_metal
      WHERE 1 = 1${between('received_date')}
      GROUP BY metal
    ''', args());
    final outstandingSalesRows = await db.db.rawQuery('''
      SELECT COALESCE(SUM(outstanding), 0) AS total
      FROM jewellery_invoices
      WHERE doc_type = ?
        AND COALESCE(status, 'Active') NOT IN ('Cancelled', 'Draft')
    ''', [saleDoc]);
    final outstandingPurchaseRows = await db.db.rawQuery('''
      SELECT COALESCE(SUM(outstanding), 0) AS total
      FROM jewellery_invoices
      WHERE doc_type = ?
        AND COALESCE(status, 'Active') NOT IN ('Cancelled', 'Draft')
    ''', [purchaseDoc]);

    var oldGold = 0.0;
    var oldSilver = 0.0;
    var oldValue = 0.0;
    for (final r in oldRows) {
      final metal = (r['metal']?.toString() ?? '').toUpperCase();
      final grams = (r['grams'] as num?)?.toDouble() ?? 0;
      if (metal == gold) oldGold += grams;
      if (metal == silver) oldSilver += grams;
      oldValue += (r['value'] as num?)?.toDouble() ?? 0;
    }
    final returnCredit =
        ((returnRows.first['total'] as num?)?.toDouble() ?? 0) -
            ((returnRows.first['refunds'] as num?)?.toDouble() ?? 0);
    return (
      sales: (salesRows.first['total'] as num?)?.toDouble() ?? 0,
      purchases: (purchaseRows.first['total'] as num?)?.toDouble() ?? 0,
      collections: (collectionRows.first['total'] as num?)?.toDouble() ?? 0,
      returns: (returnRows.first['total'] as num?)?.toDouble() ?? 0,
      refunds: (returnRows.first['refunds'] as num?)?.toDouble() ?? 0,
      oldMetalValue: oldValue,
      oldGold: oldGold,
      oldSilver: oldSilver,
      outstandingSales: math
          .max(
              0,
              ((outstandingSalesRows.first['total'] as num?)?.toDouble() ?? 0) -
                  returnCredit)
          .toDouble(),
      outstandingPurchases:
          (outstandingPurchaseRows.first['total'] as num?)?.toDouble() ?? 0,
      saleCount: (salesRows.first['c'] as num?)?.toInt() ?? 0,
      purchaseCount: (purchaseRows.first['c'] as num?)?.toInt() ?? 0,
    );
  }

  Future<
      ({
        double estimated,
        double finalProfit,
        double cost,
        double actualCost
      })> profitSummary({DateTime? from, DateTime? to}) async {
    final where = <String>["doc_type = ?", "status <> 'Cancelled'"];
    final args = <Object?>[saleDoc];
    if (from != null) {
      where.add('invoice_date >= ?');
      args.add(_day(from));
    }
    if (to != null) {
      where.add('invoice_date <= ?');
      args.add(_day(to));
    }
    final invoices = await db.query('jewellery_invoices',
        where: where.join(' AND '), whereArgs: args);
    var sales = 0.0;
    var cost = 0.0;
    var actual = 0.0;
    for (final inv in invoices) {
      // Old metal is an asset received, not a discount. Using the invoice
      // `total` here would subtract its value from revenue and understate the
      // sale's profit, so profit starts from subtotal − invoice discount.
      final subtotal = (inv['subtotal'] as num?)?.toDouble() ?? 0;
      final discount = (inv['discount'] as num?)?.toDouble() ?? 0;
      final invoiceCost = (inv['cost_total'] as num?)?.toDouble() ?? 0;
      final items = await itemsFor(inv['client_uuid']?.toString() ?? '');
      var itemActual = 0.0;
      for (final item in items) {
        itemActual += (item['actual_cost'] as num?)?.toDouble() ?? 0;
      }
      sales += math.max(0.0, subtotal - discount);
      // If the document-level cost was left blank, the item actual cost is the
      // best figure the shop has; never report a fake zero-cost profit.
      cost += invoiceCost > 0 ? invoiceCost : itemActual;
      actual += itemActual > 0 ? itemActual : invoiceCost;
    }
    var returns = 0.0;
    final returnRows = await db.db.rawQuery('''
      SELECT COALESCE(SUM(total - refund_amount), 0) AS credit
      FROM jewellery_returns
      ${from == null && to == null ? '' : 'WHERE 1 = 1'}
      ${from == null ? '' : 'AND return_date >= ?'}
      ${to == null ? '' : 'AND return_date <= ?'}
    ''', [
      if (from != null) _day(from),
      if (to != null) _day(to),
    ]);
    returns = (returnRows.first['credit'] as num?)?.toDouble() ?? 0;
    return (
      estimated: sales - cost - returns,
      finalProfit: sales - actual - returns,
      cost: cost,
      actualCost: actual,
    );
  }

  // ---------------------------------------------------------------- summary
  Future<
      ({
        double salesToday,
        double purchasesToday,
        double collectedToday,
        double outstanding,
        int openInvoices,
      })> summary({DateTime? today}) async {
    final day = _day(today ?? DateTime.now());
    // A draft is not a purchase and a cancelled document is not a sale, so
    // neither may appear in today's totals or the shop's open balance.
    const live = "COALESCE(status, 'Active') NOT IN ('Cancelled', 'Draft')";
    final sales = await db.sum('jewellery_invoices', 'total',
        where: 'doc_type = ? AND invoice_date = ? AND $live',
        whereArgs: [saleDoc, day]);
    final purchases = await db.sum('jewellery_invoices', 'total',
        where: 'doc_type = ? AND invoice_date = ? AND $live',
        whereArgs: [purchaseDoc, day]);
    final collectedRows = await db.db.rawQuery('''
      SELECT COALESCE(SUM(p.amount), 0) AS total
      FROM jewellery_payments p
      JOIN jewellery_invoices i ON i.client_uuid = p.invoice_uuid
      WHERE p.pay_date = ? AND i.doc_type <> ?
    ''', [day, purchaseDoc]);
    final collected = (collectedRows.first['total'] as num?)?.toDouble() ?? 0;
    final returnRows = await db.db.rawQuery('''
      SELECT COALESCE(SUM(total - refund_amount), 0) AS credit
      FROM jewellery_returns
    ''');
    final returnCredit = (returnRows.first['credit'] as num?)?.toDouble() ?? 0;
    final outstandingRaw = await db.sum('jewellery_invoices', 'outstanding',
        where: 'doc_type IN (?, ?) AND $live',
        whereArgs: [saleDoc, purchaseDoc]);
    final outstanding = math.max(0.0, outstandingRaw - returnCredit);
    final open = await db.count('jewellery_invoices',
        where: 'doc_type IN (?, ?) AND outstanding > 0 AND $live',
        whereArgs: [saleDoc, purchaseDoc]);
    return (
      salesToday: sales,
      purchasesToday: purchases,
      collectedToday: collected,
      outstanding: outstanding,
      openInvoices: open,
    );
  }

  /// Recovery colour for a stored invoice. Collections are the money received;
  /// old metal is a deduction, not a collection. A document without a recorded
  /// cost stays grey rather than claiming a green profit.
  static RecoveryStatus recoveryFor(Map<String, Object?> invoice) {
    if ((invoice['status']?.toString() ?? 'Active') != 'Active') {
      return RecoveryStatus.grey;
    }
    final cost = (invoice['cost_total'] as num?)?.toDouble() ?? 0;
    if (cost <= 0) return RecoveryStatus.grey;
    return JewelleryMath.recovery(
      collections: (invoice['amount_paid'] as num?)?.toDouble() ?? 0,
      actualCost: cost,
    );
  }
}
