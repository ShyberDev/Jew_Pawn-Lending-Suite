/// Data read off a pawn slip by the scanner.
class SlipFields {
  const SlipFields({
    this.idNumber = '',
    this.customerName = '',
    this.item = '',
    this.itemDetails = '',
    this.amount = '',
    this.date,
    this.address = '',
    this.rawText = '',
  });

  factory SlipFields.empty(String? imagePath) =>
      SlipFields(rawText: imagePath == null ? '' : '');

  final String idNumber;
  final String customerName;
  final String item;
  final String itemDetails;
  final String amount;

  /// Parsed From the slip (dd-mm-yyyy), null when the slip had no date.
  final DateTime? date;
  final String address;
  final String rawText;

  /// The fields that were actually found on the slip.
  List<String> get found {
    final list = <String>[];
    if (customerName.isNotEmpty) list.add('Customer Name');
    if (idNumber.isNotEmpty) list.add('ID Number');
    if (item.isNotEmpty) list.add('Item');
    if (itemDetails.isNotEmpty) list.add('Item details');
    if (amount.isNotEmpty) list.add('Loan amount');
    if (date != null) list.add('Date');
    if (address.isNotEmpty) list.add('Address');
    return list;
  }

  bool get isEmpty => found.isEmpty;
}
