/// Suggestion for the jewellery late-fee dialog (#089).
///
/// A sale has no promised date, so "overdue" cannot be computed — and the shop
/// has no per-day rate setting, so no fee is invented here. The suggestion is
/// the last fee already charged on this invoice (`late_fee_total`): the common
/// repeat-fee case becomes one tap instead of retyping. When there is no
/// history the fee is null (the field stays blank) but the sale's age in days
/// is still returned so the dialog can show it as a hint.
({double? fee, int daysSinceSale}) suggestLateFee({
  required DateTime invoiceDate,
  required double lateFeeTotal,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final day = DateTime(at.year, at.month, at.day);
  final sold = DateTime(invoiceDate.year, invoiceDate.month, invoiceDate.day);
  final days = day.difference(sold).inDays.clamp(0, 1 << 30);
  return (
    fee: lateFeeTotal > 0 ? lateFeeTotal : null,
    daysSinceSale: days,
  );
}
