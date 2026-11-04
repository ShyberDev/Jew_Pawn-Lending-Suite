/// Indian mobile numbers — one place that decides what a number is and how it
/// is dialled.
///
/// The shop only deals in Indian mobiles, so a number is either a plain
/// 10-digit mobile (`98765 43210`) or the same number with the `+91` country
/// code. Spaces, dashes, brackets and an Indian trunk `0` are accepted because
/// that is how people type and how older records were saved.
///
/// Two things used to go wrong without this:
///  * the dialer / SMS app was handed whatever text was saved, so a number with
///    a stray letter or a landline opened the dialer on a broken string;
///  * WhatsApp was opened as `wa.me/<10 digits>`, which WhatsApp rejects —
///    `wa.me` needs the country code, so an Indian number never matched a
///    contact and the shopkeeper only saw "Could not open WhatsApp".
class Phone {
  const Phone._();

  /// India's country calling code, without the `+`.
  static const countryCode = '91';

  /// TRAI mobile numbers: 10 digits starting 6–9 (landlines are not mobiles).
  static final _national = RegExp(r'^[6-9]\d{9}$');
  static final _nonDigits = RegExp(r'\D');

  /// Shown when a saved / typed number is not a usable Indian mobile.
  static const invalidMessage =
      'Use a 10-digit mobile number, or +91 and the 10 digits.';

  /// Every digit in [raw], nothing else.
  static String digits(String raw) => raw.replaceAll(_nonDigits, '');

  /// The 10-digit national number, or `''` when [raw] is not an Indian mobile.
  ///
  /// Accepts `+91 98765 43210`, `91 98765 43210`, `0091 98765 43210`,
  /// `098765 43210`, `9876543210`, and the same with spaces / dashes.
  static String national(String raw) {
    var d = digits(raw);
    if (d.length == 14 && d.startsWith('0091')) {
      d = d.substring(4);
    } else if (d.length == 12 && d.startsWith(countryCode)) {
      d = d.substring(2);
    } else if (d.length == 11 && d.startsWith('0')) {
      d = d.substring(1);
    }
    return _national.hasMatch(d) ? d : '';
  }

  static bool isValid(String raw) => national(raw).isNotEmpty;

  /// `+91XXXXXXXXXX`, or `''` when the number is not an Indian mobile.
  static String e164(String raw) {
    final n = national(raw);
    return n.isEmpty ? '' : '+$countryCode$n';
  }

  /// `91XXXXXXXXXX` — the form `wa.me` requires.
  static String waNumber(String raw) {
    final n = national(raw);
    return n.isEmpty ? '' : '$countryCode$n';
  }

  /// `+91 98765 43210` for display; the original text when it cannot be read.
  static String pretty(String raw) {
    final n = national(raw);
    if (n.isEmpty) return raw.trim();
    return '+$countryCode ${n.substring(0, 5)} ${n.substring(5)}';
  }

  static Uri? tel(String raw) {
    final v = e164(raw);
    return v.isEmpty ? null : Uri(scheme: 'tel', path: v);
  }

  static Uri? sms(String raw, {String? body}) {
    final v = e164(raw);
    if (v.isEmpty) return null;
    return Uri(
      scheme: 'sms',
      path: v,
      queryParameters: (body == null || body.isEmpty) ? null : {'body': body},
    );
  }

  static Uri? whatsapp(String raw, {required String text}) {
    final n = waNumber(raw);
    if (n.isEmpty) return null;
    return Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(text)}');
  }

  /// Error text for a phone field, or null when [raw] is acceptable.
  ///
  /// [required] is off because a phone number is optional on a customer.
  static String? validationError(String? raw, {bool required = false}) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return required ? 'Required' : null;
    return isValid(v) ? null : invalidMessage;
  }
}
