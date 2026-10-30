import '../data/local_db.dart';
import 'secret_hash.dart';

/// Optional offline screen lock: a 4–6 digit PIN / MPIN.
///
/// Three modes, chosen in Home → Password Settings:
///
/// * **off**   — no lock.
/// * **always** — ask every time the app opens or comes back from the
///   background (the v1.1.3 behaviour).
/// * **daily**  — the "Daily MPIN": ask once per calendar day, so the shop
///   opens quickly in the morning and stays open for the rest of the day.
///
/// The PIN is stored only as a salted hash in the `settings` table. There is
/// no server and no biometric dependency.
class AppLock {
  const AppLock._();

  static const modeKey = 'app_lock_mode'; // 'off' | 'always' | 'daily'
  static const legacyEnabledKey = 'app_lock_enabled';
  static const saltKey = 'app_lock_salt';
  static const hashKey = 'app_lock_hash';
  static const unlockedOnKey = 'app_lock_unlocked_on';

  static const off = 'off';
  static const always = 'always';
  static const daily = 'daily';

  static bool validPin(String pin) =>
      RegExp(r'^\d{4,6}$').hasMatch(pin.trim());

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  /// Reads the mode, also understanding the single on/off switch written by
  /// v1.1.3 (`app_lock_enabled = 1` → every time).
  static Future<String> mode(LocalDb db) async {
    final saved = await db.getSetting(modeKey);
    if (saved == off || saved == always || saved == daily) return saved!;
    if (await db.getSetting(legacyEnabledKey) == '1') return always;
    return off;
  }

  static Future<void> setMode(LocalDb db, String mode) async {
    await db.setSetting(modeKey, mode);
    await db.setSetting(legacyEnabledKey, mode == off ? '0' : '1');
    if (mode != daily) await db.setSetting(unlockedOnKey, null);
  }

  static Future<bool> isEnabled(LocalDb db) async {
    if (await mode(db) == off) return false;
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
    if (await mode(db) == off) await setMode(db, always);
  }

  static Future<bool> verify(LocalDb db, String pin) async {
    final salt = await db.getSetting(saltKey) ?? '';
    final hash = await db.getSetting(hashKey) ?? '';
    if (salt.isEmpty || hash.isEmpty) return false;
    return constantTimeEquals(hashSecret(pin.trim(), salt), hash);
  }

  /// True when the app must show the lock screen right now.
  static Future<bool> shouldLock(LocalDb db) async {
    if (!await isEnabled(db)) return false;
    if (await mode(db) == daily) {
      return await db.getSetting(unlockedOnKey) != _today();
    }
    return true;
  }

  /// Records today's unlock for the daily MPIN, so the same day stays open.
  static Future<void> markUnlocked(LocalDb db) async {
    if (await mode(db) == daily) {
      await db.setSetting(unlockedOnKey, _today());
    }
  }

  static Future<void> disable(LocalDb db) async {
    await db.setSetting(modeKey, off);
    await db.setSetting(legacyEnabledKey, '0');
    await db.setSetting(saltKey, null);
    await db.setSetting(hashKey, null);
    await db.setSetting(unlockedOnKey, null);
  }
}
