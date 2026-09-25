import 'local_db.dart';

/// Seeds the local database with realistic sample data so the app is fully
/// explorable offline — no server and no login required.
///
/// Every row is keyed by a fixed `client_uuid` and inserted with REPLACE
/// semantics, so running this is safe on an empty database (guard inside
/// [main.dart] only seeds when the villager list is empty).
Future<void> seedDemo(LocalDb db) async {
  final today = DateTime.now();
  String dstr(DateTime dt) => dt.toIso8601String().substring(0, 10);
  String dtstr(DateTime dt) =>
      dt.toIso8601String().substring(0, 16); // date + time, seconds omitted

  Future<void> put(String table, Map<String, Object?> row) => db.upsert(table, row);

  // ---------------------------------------------------------------- villages
  for (final (uuid, name, district, pincode, lat, lng) in [
    ('v-demo-1', 'Pallipatti', 'Kadapa', '516101', 14.4681, 78.0167),
    ('v-demo-2', 'Uppalapadu', 'Kadapa', '516104', 14.4872, 78.0450),
  ]) {
    await put('villages', {
      'client_uuid': uuid,
      'village_name': name,
      'district': district,
      'pincode': pincode,
      'latitude': lat,
      'longitude': lng,
    });
  }

  // --------------------------------------------------------------- customers
  for (final (uuid, name, phone, village, rating) in [
    ('c-demo-1', 'Lakshmi Bai', '9848012311', 'Pallipatti', 'Good'),
    ('c-demo-2', 'Ramulu Naidu', '9848023456', 'Uppalapadu', 'Good'),
    ('c-demo-3', 'Sunitha Rani', '9848034567', 'Pallipatti', 'Average'),
  ]) {
    await put('customers', {
      'client_uuid': uuid,
      'customer_name': name,
      'phone': phone,
      'village': village,
      'status': 'Active',
      'rating': rating,
      'gold_interest_rate': 3.0,
      'silver_interest_rate': 3.0,
      'khatabook_interest_rate': 10.0,
    });
  }

  // --------------------------------------------------------------- pawn loans
  await put('pawn_loans', {
    'client_uuid': 'p-demo-1',
    'customer': 'c-demo-1',
    'customer_name': 'Lakshmi Bai',
    'village': 'Pallipatti',
    'business': 'Own',
    'status': 'Active',
    'loan_date': dstr(today.subtract(const Duration(days: 45))),
    'interest_basis': 'Monthly',
    'loan_amount': 100000,
    'interest_rate': 3.0,
    'due_date': dstr(today.add(const Duration(days: 320))),
    'total_gross_weight': 22.7,
    'total_net_weight': 21.3,
    'hallmarked_weight': 12.2,
    'non_hallmarked_weight': 9.1,
    'total_market_value': 145000,
    'ltv': 68.97,
    'interest_accrued': 4500,
    'total_payable': 104500,
    'amount_paid': 0,
    'balance': 104500,
    'last_interest_date': dstr(today.subtract(const Duration(days: 15))),
  });
  await put('pawn_items', {
    'loan_uuid': 'p-demo-1',
    'item_description': 'Bangle B21',
    'metal_type': 'Gold',
    'purity': '22K',
    'quantity': 1,
    'gross_weight': 10.5,
    'net_weight': 9.8,
    'hallmarked': 1,
    'valuation_rate': 7800,
    'market_value': 76440,
    'approved_amount': 55000,
  });
  await put('pawn_items', {
    'loan_uuid': 'p-demo-1',
    'item_description': 'Chain C14',
    'metal_type': 'Gold',
    'purity': '18K',
    'quantity': 1,
    'gross_weight': 12.2,
    'net_weight': 11.5,
    'hallmarked': 0,
    'valuation_rate': 6200,
    'market_value': 71300,
    'approved_amount': 45000,
  });

  await put('pawn_loans', {
    'client_uuid': 'p-demo-2',
    'customer': 'c-demo-2',
    'customer_name': 'Ramulu Naidu',
    'village': 'Uppalapadu',
    'business': 'Own',
    'status': 'Active',
    'loan_date': dstr(today.subtract(const Duration(days: 90))),
    'interest_basis': 'Monthly',
    'loan_amount': 40000,
    'interest_rate': 3.0,
    'due_date': dstr(today.add(const Duration(days: 270))),
    'total_gross_weight': 88.0,
    'total_net_weight': 85.4,
    'hallmarked_weight': 85.4,
    'non_hallmarked_weight': 0,
    'total_market_value': 30000,
    'ltv': 85.0,
    'interest_accrued': 3600,
    'total_payable': 43600,
    'amount_paid': 0,
    'balance': 43600,
    'last_interest_date': dstr(today.subtract(const Duration(days: 30))),
  });
  await put('pawn_items', {
    'loan_uuid': 'p-demo-2',
    'item_description': 'Silver Anklet Set',
    'metal_type': 'Silver',
    'purity': '92.5',
    'quantity': 2,
    'gross_weight': 88.0,
    'net_weight': 85.4,
    'hallmarked': 1,
    'valuation_rate': 320,
    'market_value': 27330,
    'approved_amount': 40000,
  });

  // ---------------------------------------------------------- khatabook loans
  await put('khatabook_loans', {
    'client_uuid': 'k-demo-1',
    'customer': 'c-demo-1',
    'customer_name': 'Lakshmi Bai',
    'village': 'Pallipatti',
    'business': 'Own',
    'status': 'Active',
    'loan_date': dstr(today.subtract(const Duration(days: 42))),
    'principal_amount': 10000,
    'interest_amount': 2000,
    'total_payable': 12000,
    'installment_count': 12,
    'installment_amount': 1000,
    'collection_frequency': 'Weekly',
    'start_date': dstr(today.subtract(const Duration(days: 42))),
    'end_date': dstr(today.add(const Duration(days: 42))),
    'customer_rating': 'Good',
    'total_collected': 6000,
    'paid_installments': 6,
    'outstanding': 6000,
    'updated_at': dtstr(today.subtract(const Duration(days: 42))) + ':00',
  });
  for (var i = 5; i >= 0; i--) {
    await put('khatabook_collections', {
      'client_uuid': 'kc-demo-$i',
      'khatabook_loan': 'k-demo-1',
      'customer': 'c-demo-1',
      'village': 'Pallipatti',
      'collection_date': dstr(today.subtract(Duration(days: i * 7))),
      'amount': 1000,
      'payment_mode': 'Cash',
      'updated_at':
          dtstr(today.subtract(Duration(days: i * 7))) + ':0${6 - (i % 5)}',
    });
  }

  await put('khatabook_loans', {
    'client_uuid': 'k-demo-2',
    'customer': 'c-demo-3',
    'customer_name': 'Sunitha Rani',
    'village': 'Pallipatti',
    'business': 'Tailor',
    'status': 'Active',
    'loan_date': dstr(today.subtract(const Duration(days: 40))),
    'principal_amount': 8000,
    'interest_amount': 800,
    // Includes the late-fee "You Gave" ₹500: 8,800 total + 500 fee.
    'total_payable': 9300,
    'installment_count': 8,
    'installment_amount': 1100,
    'collection_frequency': 'Monthly',
    'start_date': dstr(today.subtract(const Duration(days: 40))),
    'end_date': dstr(today.add(const Duration(days: 200))),
    'customer_rating': 'Average',
    'total_collected': 1100,
    'paid_installments': 1,
    'outstanding': 8200,
    'updated_at': dtstr(today.subtract(const Duration(days: 40))) + ':00',
  });
  // Keep the ledger consistent: Sunitha's ₹1,100 collected has one matching
  // collection row, and a late-fee "You Gave" ₹500 that added to her balance.
  await put('khatabook_collections', {
    'client_uuid': 'kc-demo-sunitha',
    'khatabook_loan': 'k-demo-2',
    'customer': 'c-demo-3',
    'village': 'Pallipatti',
    'collection_date': dstr(today.subtract(const Duration(days: 5))),
    'amount': 1100,
    'payment_mode': 'Cash',
    'updated_at': dtstr(today.subtract(const Duration(days: 5))) + ':00',
  });
  await put('khatabook_given', {
    'client_uuid': 'kg-demo-sunitha',
    'customer': 'c-demo-3',
    'customer_name': 'Sunitha Rani',
    'village': 'Pallipatti',
    'khatabook_loan': 'k-demo-2',
    'given_date': dstr(today.subtract(const Duration(days: 2))),
    'amount': 500,
    'note': 'Late fee (month 2)',
    'updated_at': dtstr(today.subtract(const Duration(days: 2))) + ':00',
  });
}