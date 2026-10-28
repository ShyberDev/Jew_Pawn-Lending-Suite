import '../data/local_db.dart';
import 'secret_hash.dart';

/// Optional offline PIN lock.
///
/// The app used to open straight into the shop. A phone left on the counter
/// therefore showed every customer and every balance. This lock is local and
/// offline-first: a salted hash in the existing `settings` table, no network,
/// no biometric dependency, no new plugin.
///
/// It is off by default. The shopkeeper enables it in Settings → App lock and
/// chooses a 4–6 digit PIN. The PIN is never stored, and there is no recovery
/// besides clearing app data — the screen warns about that before enabling.
class AppLock {
  const AppLock._();

  static const enabledKey = 'app_lock_enabled';
  static const saltKey = 'app_lock_salt';
  static const hashKey = 'app_lock_hash';

  static bool validPin(String pin) =>
      RegExp(r'^\d{4,6}$').hasMatch(pin.trim());

  static Future<bool> isEnabled(LocalDb db) async {
    if (await db.getSetting(enabledKey) != '1') return false;
    final hash = await db.getSetting(hashKey);
    return hash != null && hash.isNotEmpty;
  }

  static Future<void> setPin(LocalDb db, String pin) async {
    final clean = pin.trim();
    if (!validPin(clean)) {
      throw const FormatException('The PIN must be 4 to 6 digits.');
    }
    final salt = randomSalt();
    await db.setSetting(saltKey, salt);
    await db.setSetting(hashKey, hashSecret(clean, salt));
    await db.setSetting(enabledKey, '1');
  }

  static Future<bool> verify(LocalDb db, String pin) async {
    final salt = await db.getSetting(saltKey) ?? '';
    final hash = await db.getSetting(hashKey) ?? '';
    if (salt.isEmpty || hash.isEmpty) return false;
    return constantTimeEquals(hashSecret(pin.trim(), salt), hash);
  }

  static Future<void> disable(LocalDb db) async {
    await db.setSetting(enabledKey, '0');
    await db.setSetting(saltKey, null);
    await db.setSetting(hashKey, null);
  }
}
