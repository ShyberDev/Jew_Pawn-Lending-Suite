import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/local_db.dart';

/// Sends one-time codes to the shop's Gmail address or mobile number.
///
/// The app has no messaging account of its own, so delivery is a small HTTP
/// POST to a gateway the shop configures (an SMS provider, an Apps Script /
/// Worker that sends Gmail, or the shop's own server). Everything about the
/// code itself — hashing, expiry, attempt cap — already lives in
/// [LocalAccount]; this class only answers "did it actually leave the phone?".
///
/// Request body (JSON):
/// ```json
/// {"to":"9876543210","channel":"sms","purpose":"admin_reset",
///  "code":"123456","message":"Jewellery Suite code 123456 — valid 10 minutes",
///  "secret":"<shared secret, only when one is configured>"}
/// ```
/// When the shop sets a shared secret it travels both in the body as `secret`
/// (what the documented Apps Script / Worker gateways check) and in the
/// `X-Gateway-Secret` header (so a proxy can reject the request before the
/// script runs). Without a secret the URL alone is the only credential, which
/// is why the setup guide asks for one before a real gateway goes live.
///
/// Any 2xx response counts as delivered. Without a configured URL, or on a
/// network error, the caller shows the code on the phone instead.
class OtpGateway {
  const OtpGateway._();

  static const urlKey = 'otp_gateway_url';
  static const channelKey = 'otp_gateway_channel'; // 'sms' | 'email'
  static const secretKey = 'otp_gateway_secret';

  static Future<String> url(LocalDb db) async =>
      (await db.getSetting(urlKey) ?? '').trim();

  static Future<String> channel(LocalDb db) async {
    final saved = await db.getSetting(channelKey);
    return saved == 'email' ? 'email' : 'sms';
  }

  /// The shared secret the gateway expects, or an empty string.
  static Future<String> secret(LocalDb db) async =>
      (await db.getSetting(secretKey) ?? '').trim();

  /// Saves the endpoint. Pass `secret: ''` to remove a stored secret.
  static Future<void> configure(
    LocalDb db, {
    required String url,
    required String channel,
    String? secret,
  }) async {
    await db.setSetting(urlKey, url.trim());
    await db.setSetting(channelKey, channel == 'email' ? 'email' : 'sms');
    final value = (secret ?? '').trim();
    await db.setSetting(secretKey, value.isEmpty ? null : value);
  }

  static Future<void> clear(LocalDb db) async {
    await db.setSetting(urlKey, null);
    await db.setSetting(channelKey, null);
    await db.setSetting(secretKey, null);
  }

  /// True when [raw] is an absolute http / https URL with a host.
  ///
  /// Without this a typo such as `shop.local/otp` used to be stored happily and
  /// every send then failed silently, so the shop believed codes were going out
  /// by SMS while the app quietly fell back to the on-screen code.
  static bool validUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return false;
    return uri.scheme == 'https' || uri.scheme == 'http';
  }

  static Future<bool> isConfigured(LocalDb db) async =>
      (await url(db)).isNotEmpty;

  static String messageFor(String code) =>
      'Jewellery Suite code $code — valid 10 minutes. '
      'If you did not ask for it, ignore this message.';

  /// Returns true only when the gateway accepted the message.
  static Future<bool> send({
    required LocalDb db,
    required String to,
    required String code,
    required String purpose,
  }) async {
    final endpoint = await url(db);
    if (endpoint.isEmpty) return false;
    if (!validUrl(endpoint)) return false;
    final sharedSecret = await secret(db);
    try {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              if (sharedSecret.isNotEmpty)
                'X-Gateway-Secret': sharedSecret,
            },
            body: jsonEncode({
              'to': to,
              'channel': await channel(db),
              'purpose': purpose,
              'code': code,
              'message': messageFor(code),
              if (sharedSecret.isNotEmpty) 'secret': sharedSecret,
            }),
          )
          .timeout(const Duration(seconds: 12));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      // Offline, bad URL, gateway down — the caller falls back to showing the
      // code so a forgotten password never becomes a locked-out shop.
      return false;
    }
  }
}
