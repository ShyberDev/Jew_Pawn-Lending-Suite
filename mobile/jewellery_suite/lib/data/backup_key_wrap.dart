import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Passphrase protection for the database key that travels inside a backup.
///
/// The archive never contains the raw SQLCipher key. When the shop asks to move
/// a backup to another phone, the key is wrapped with a passphrase:
///
/// * PBKDF2-HMAC-SHA256 derives 64 bytes (32 for encryption, 32 for the MAC);
/// * an HMAC-SHA256 counter stream encrypts the key;
/// * an HMAC-SHA256 tag over the nonce and ciphertext detects a wrong
///   passphrase or a damaged block.
///
/// Only `crypto` is used, so no platform cipher plugin is involved. The
/// construction is encrypt-then-MAC and the tag is compared in constant time.
class BackupKeyWrap {
  const BackupKeyWrap._();

  /// Manifest marker. A future format can be detected without guessing.
  static const String format = 'pbkdf2-hmac-sha256+hmac-sha256-ctr';

  /// Deliberately slow enough to make guessing expensive, still usable on a
  /// phone for a one-off backup or restore. Tests pass a smaller value.
  static const int defaultIterations = 120000;

  static const int _saltBytes = 16;
  static const int _nonceBytes = 16;
  static const int _tagBytes = 16;

  /// Wraps [key] with [passphrase]. The returned map is merged into the backup
  /// manifest. Throws [ArgumentError] when the passphrase is too short.
  static Map<String, Object?> wrap({
    required String key,
    required String passphrase,
    int iterations = defaultIterations,
  }) {
    final secret = passphrase.trim();
    if (secret.length < 6) {
      throw ArgumentError.value(
          secret.length, 'passphrase', 'Use at least 6 characters');
    }
    if (iterations < 1) {
      throw ArgumentError.value(iterations, 'iterations', 'Must be positive');
    }
    final salt = _randomBytes(_saltBytes);
    final nonce = _randomBytes(_nonceBytes);
    final derived = _pbkdf2(utf8.encode(secret), salt, iterations, 64);
    final cipher = _xor(utf8.encode(key), _keystream(derived.sublist(0, 32),
        nonce, utf8.encode(key).length));
    final tag = _hmac(derived.sublist(32, 64), [...nonce, ...cipher])
        .sublist(0, _tagBytes);
    return <String, Object?>{
      'db_key_wrapped': base64Encode([...nonce, ...cipher, ...tag]),
      'key_wrap': format,
      'key_salt': base64Encode(salt),
      'key_iterations': iterations,
    };
  }

  /// Recovers the key from a manifest produced by [wrap].
  ///
  /// Throws [FormatException] with a shop-readable message when the block is
  /// malformed, the format is unknown, or the passphrase is wrong.
  static String unwrap(Map<String, Object?> manifest, String passphrase) {
    if (manifest['key_wrap'] != format) {
      throw const FormatException(
          'This backup uses an unsupported key protection.');
    }
    try {
      final blob = base64Decode('${manifest['db_key_wrapped']}');
      final salt = base64Decode('${manifest['key_salt']}');
      final iterations = (manifest['key_iterations'] as num?)?.toInt() ?? 0;
      if (blob.length <= _nonceBytes + _tagBytes ||
          salt.length < 8 ||
          iterations < 1) {
        throw const FormatException('This backup key block is damaged.');
      }
      final nonce = blob.sublist(0, _nonceBytes);
      final cipher = blob.sublist(_nonceBytes, blob.length - _tagBytes);
      final tag = blob.sublist(blob.length - _tagBytes);
      final derived = _pbkdf2(utf8.encode(passphrase.trim()), salt, iterations,
          64);
      final expected = _hmac(derived.sublist(32, 64), [...nonce, ...cipher])
          .sublist(0, _tagBytes);
      if (!_sameBytes(tag, expected)) {
        throw const FormatException(
            'That passphrase does not open this backup.');
      }
      final plain = _xor(
          cipher, _keystream(derived.sublist(0, 32), nonce, cipher.length));
      return utf8.decode(plain);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('This backup key block is damaged.');
    }
  }

  static List<int> _pbkdf2(
      List<int> password, List<int> salt, int iterations, int length) {
    final hmac = Hmac(sha256, password);
    final out = <int>[];
    var block = 1;
    while (out.length < length) {
      var u = hmac.convert([...salt, ..._be32(block)]).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.addAll(t);
      block++;
    }
    return out.sublist(0, length);
  }

  static List<int> _keystream(List<int> key, List<int> nonce, int length) {
    final hmac = Hmac(sha256, key);
    final out = <int>[];
    var counter = 0;
    while (out.length < length) {
      out.addAll(hmac.convert([...nonce, ..._be32(counter)]).bytes);
      counter++;
    }
    return out.sublist(0, length);
  }

  static List<int> _hmac(List<int> key, List<int> data) =>
      Hmac(sha256, key).convert(data).bytes;

  static List<int> _xor(List<int> a, List<int> b) =>
      [for (var i = 0; i < a.length; i++) a[i] ^ b[i]];

  static List<int> _be32(int value) => [
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ];

  static List<int> _randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
