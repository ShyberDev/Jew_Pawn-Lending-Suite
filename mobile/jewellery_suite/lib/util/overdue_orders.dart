/// Overdue-order rule shared by the jewellery dashboard banner (#088) and the
/// Orders list, so both agree on what "overdue" means.
///
/// An order is overdue when it is still open (Pending or Ready), carries a
/// promised date, and that date is before today (date-only comparison, the
/// same string comparison the Orders list uses).
int countOverdueOrders(List<Map<String, Object?>> orders, {DateTime? now}) {
  final today = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
  var count = 0;
  for (final o in orders) {
    final status = o['status']?.toString() ?? 'Pending';
    if (status != 'Pending' && status != 'Ready') continue;
    final raw = o['promised_date']?.toString() ?? '';
    if (raw.isEmpty) continue;
    final promised = raw.length >= 10 ? raw.substring(0, 10) : raw;
    if (promised.compareTo(today) >= 0) continue;
    count++;
  }
  return count;
}
