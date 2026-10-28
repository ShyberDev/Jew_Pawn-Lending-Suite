import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted, stretched SHA-256 for the app's local PIN / admin password.
///
/// This is not a substitute for a server-side credential store, but it fixes
/// the v1.1.1 defect where the admin password was stored as readable text in
/// the SQLite `settings` table. A stolen device backup now yields a hash and a
/// random salt, not the password the shopkeeper typed.
///
/// The iteration count is deliberately modest: verification runs on a phone
/// while a shopkeeper waits at the counter, and the threat here is casual
/// inspection of the database file, not an offline GPU farm.
const kSecretHashIterations = 12000;

/// 16 random bytes, URL-safe base64 (no padding surprises in SQLite).
String randomSalt([int bytes = 16]) {
  final rnd = Random.secure();
  return base64UrlEncode(List<int>.generate(bytes, (_) => rnd.nextInt(256)));
}

/// Hash [secret] with [salt]. Case-insensitive by design, matching the old
/// password gate, so an existing shopkeeper's capitals still work.
String hashSecret(
  String secret,
  String salt, {
  int iterations = kSecretHashIterations,
}) {
  List<int> digest = utf8.encode('$salt:${secret.trim().toLowerCase()}');
  for (var i = 0; i < iterations; i++) {
    digest = sha256.convert(digest).bytes;
  }
  return base64UrlEncode(digest);
}

/// Length-independent comparison, so a wrong password cannot be discovered
/// faster by measuring how many leading bytes matched.
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
