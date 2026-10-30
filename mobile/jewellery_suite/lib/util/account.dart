import 'dart:math';

import '../data/local_db.dart';
import 'secret_hash.dart';

/// The shop's own account on this phone.
///
/// The app is offline-first: there is no cloud user directory, so the account
/// (identifier + salted password hash + session flag) lives in the existing
/// `settings` table. It exists so the shopkeeper can sign in with a Gmail
/// address or a mobile number, stay signed in until Logout, and reset a
/// forgotten password / PIN with a one-time code.
///
/// Security note, deliberately stated: this guards against a casual onlooker,
/// not a determined attacker with the unlocked phone and developer tools. The
/// ledger itself is still local SQLite, and clearing app data always resets
/// everything.
class LocalAccount {
  const LocalAccount._();

  static const identifierKey = 'account_identifier';
  static const nameKey = 'account_name';
  static const hashKey = 'account_password_hash';
  static const saltKey = 'account_password_salt';
  static const createdKey = 'account_created_at';

  /// Kept across restarts until Logout (#login persists).
  static const sessionKey = 'session_active';

  /// Individual password switches in Password Settings.
  static const passwordLoginEnabledKey = 'login_password_enabled';
  static const otpLoginEnabledKey = 'login_otp_enabled';

  // ------------------------------------------------------------ one-time code
  static const otpHashKey = 'otp_hash';
  static const otpSaltKey = 'otp_salt';
  static const otpExpiryKey = 'otp_expiry';
  static const otpPurposeKey = 'otp_purpose';
  static const otpAttemptsKey = 'otp_attempts';

  static const otpValidity = Duration(minutes: 10);
  static const otpMaxAttempts = 5;

  // ------------------------------------------------------------- identifiers
  static final _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  /// A mobile number: 10 digits, optionally with +91 / 0 in front.
  static bool isMobile(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length == 10 || (digits.length == 12 && digits.startsWith('91'));
  }

  /// Gmail address or mobile number — the two login identifiers the shop asked
  /// for. Any e-mail domain is accepted; Gmail is simply the common one.
  static bool isValidIdentifier(String value) {
    final v = value.trim();
    return _email.hasMatch(v) || isMobile(v);
  }

  /// E-mail is lowercased; a mobile keeps only its last 10 digits so
  /// +91 98765 43210 and 9876543210 are the same account.
  static String normalizeIdentifier(String value) {
    final v = value.trim();
    if (v.contains('@')) return v.toLowerCase();
    final digits = v.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  static bool isEmail(String value) => value.contains('@');

  /// "+91 •••• 43210" / "sh•••@gmail.com" — safe to show on a lock screen.
  static String mask(String identifier) {
    final v = identifier.trim();
    if (v.isEmpty) return '';
    if (isEmail(v)) {
      final at = v.indexOf('@');
      final head = v.substring(0, at);
      final tail = v.substring(at);
      if (head.length <= 2) return '${head[0]}•••$tail';
      return '${head.substring(0, 2)}•••$tail';
    }
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return '••••';
    return '••••${digits.substring(digits.length - 4)}';
  }

  // ------------------------------------------------------------------ account
  static Future<bool> exists(LocalDb db) async {
    final id = await db.getSetting(identifierKey);
    final hash = await db.getSetting(hashKey);
    return (id ?? '').isNotEmpty && (hash ?? '').isNotEmpty;
  }

  static Future<String> identifierOf(LocalDb db) async =>
      await db.getSetting(identifierKey) ?? '';

  static Future<String> nameOf(LocalDb db) async =>
      await db.getSetting(nameKey) ?? '';

  static Future<void> create(
    LocalDb db, {
    required String name,
    required String identifier,
    required String password,
  }) async {
    final id = normalizeIdentifier(identifier);
    if (!isValidIdentifier(id)) {
      throw const FormatException('Enter a Gmail address or a 10-digit mobile number.');
    }
    if (password.trim().length < 6) {
      throw const FormatException('Use at least 6 characters.');
    }
    if (await exists(db)) {
      throw const FormatException('An account already exists on this phone.');
    }
    final salt = randomSalt();
    await db.setSetting(identifierKey, id);
    await db.setSetting(nameKey, name.trim());
    await db.setSetting(saltKey, salt);
    await db.setSetting(hashKey, hashSecret(password, salt));
    await db.setSetting(createdKey, DateTime.now().toIso8601String());
    await db.setSetting(passwordLoginEnabledKey, '1');
    await db.setSetting(otpLoginEnabledKey, '1');
  }

  static Future<bool> verifyPassword(
      LocalDb db, String identifier, String password) async {
    final saved = await identifierOf(db);
    final hash = await db.getSetting(hashKey) ?? '';
    final salt = await db.getSetting(saltKey) ?? '';
    if (saved.isEmpty || hash.isEmpty || salt.isEmpty) return false;
    if (normalizeIdentifier(identifier) != saved) return false;
    return constantTimeEquals(hashSecret(password, salt), hash);
  }

  /// Replaces the password after a verified OTP (or from Password Settings).
  static Future<void> setPassword(LocalDb db, String password) async {
    if (password.trim().length < 6) {
      throw const FormatException('Use at least 6 characters.');
    }
    final salt = randomSalt();
    await db.setSetting(saltKey, salt);
    await db.setSetting(hashKey, hashSecret(password, salt));
  }

  // ------------------------------------------------------------------ session
  static Future<bool> hasSession(LocalDb db) async =>
      await db.getSetting(sessionKey) == '1';

  static Future<void> setSession(LocalDb db, bool active) =>
      db.setSetting(sessionKey, active ? '1' : '0');

  static Future<bool> passwordLoginEnabled(LocalDb db) async =>
      await db.getSetting(passwordLoginEnabledKey) != '0';

  static Future<bool> otpLoginEnabled(LocalDb db) async =>
      await db.getSetting(otpLoginEnabledKey) != '0';

  // --------------------------------------------------------------- one time
  /// Creates a fresh 6-digit code for [purpose] and returns it.
  ///
  /// The app has no SMS/e-mail gateway of its own, so the caller shows the code
  /// on this phone (clearly labelled as an offline code). If a shop later adds
  /// a server/gateway, only this method needs to change: everything else
  /// already verifies a hashed code with an expiry and an attempt cap.
  static Future<String> issueOtp(LocalDb db, {required String purpose}) async {
    final code = List<int>.generate(6, (_) => Random.secure().nextInt(10)).join();
    final salt = randomSalt();
    await db.setSetting(otpSaltKey, salt);
    await db.setSetting(otpHashKey, hashSecret(code, salt));
    await db.setSetting(otpPurposeKey, purpose);
    await db.setSetting(
        otpExpiryKey,
        DateTime.now()
            .add(otpValidity)
            .toIso8601String());
    await db.setSetting(otpAttemptsKey, '0');
    return code;
  }

  static Future<bool> verifyOtp(
      LocalDb db, String purpose, String code) async {
    final savedPurpose = await db.getSetting(otpPurposeKey);
    final hash = await db.getSetting(otpHashKey) ?? '';
    final salt = await db.getSetting(otpSaltKey) ?? '';
    final expiry = DateTime.tryParse(await db.getSetting(otpExpiryKey) ?? '');
    final attempts = int.tryParse(await db.getSetting(otpAttemptsKey) ?? '') ?? 0;
    if (savedPurpose != purpose || hash.isEmpty || salt.isEmpty) return false;
    if (expiry == null || DateTime.now().isAfter(expiry)) return false;
    if (attempts >= otpMaxAttempts) return false;
    if (code.trim().length != 6) return false;
    final ok = constantTimeEquals(hashSecret(code.trim(), salt), hash);
    if (ok) {
      await clearOtp(db);
    } else {
      await db.setSetting(otpAttemptsKey, '${attempts + 1}');
    }
    return ok;
  }

  static Future<void> clearOtp(LocalDb db) async {
    await db.setSetting(otpHashKey, null);
    await db.setSetting(otpSaltKey, null);
    await db.setSetting(otpExpiryKey, null);
    await db.setSetting(otpPurposeKey, null);
    await db.setSetting(otpAttemptsKey, null);
  }
}
