import 'package:local_auth/local_auth.dart';

/// #066 — fingerprint / face unlock for the screen lock.
///
/// Android's BiometricPrompt does the matching and hands back only success or
/// failure; no biometric data is stored or sent by this app. Every call fails
/// closed: a device without an enrolled finger, a missing plugin or a
/// cancelled prompt simply returns `false`, and the PIN remains the way in.
class Biometrics {
  const Biometrics._();

  static final LocalAuthentication _auth = LocalAuthentication();

  /// True when this phone has biometric hardware **and** something enrolled.
  static Future<bool> available() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Shows the system prompt. `true` only when the phone verified the owner.
  static Future<bool> prompt({
    String reason = 'Unlock Jewellery Suite',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
