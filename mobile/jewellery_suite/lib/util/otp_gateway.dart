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
///  "code":"123456","message":"Jewellery Suite code 123456 — valid 10 minutes"}
/// ```
/// Any 2xx response counts as delivered. Without a configured URL, or on a
/// network error, the caller shows the code on the phone instead.
class OtpGateway {
  const OtpGateway._();

  static const urlKey = 'otp_gateway_url';
  static const channelKey = 'otp_gateway_channel'; // 'sms' | 'email'

  static Future<String> url(LocalDb db) async =>
      (await db.getSetting(urlKey) ?? '').trim();

  static Future<String> channel(LocalDb db) async {
    final saved = await db.getSetting(channelKey);
    return saved == 'email' ? 'email' : 'sms';
  }

  static Future<void> configure(
    LocalDb db, {
    required String url,
    required String channel,
  }) async {
    await db.setSetting(urlKey, url.trim());
    await db.setSetting(channelKey, channel == 'email' ? 'email' : 'sms');
  }

  static Future<void> clear(LocalDb db) async {
    await db.setSetting(urlKey, null);
    await db.setSetting(channelKey, null);
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
    try {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'to': to,
              'channel': await channel(db),
              'purpose': purpose,
              'code': code,
              'message': messageFor(code),
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
