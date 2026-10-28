import 'package:flutter/services.dart';

/// Size of the installed APK, read from Android rather than typed into the
/// About screen.
///
/// `package_info_plus` reports a version, not a byte count, and guessing the
/// APK size is how the old hard-coded "95 MB" drifted away from reality. The
/// platform channel below asks Android for `ApplicationInfo.sourceDir` and
/// stats that file, so the number is always the build actually installed.
///
/// Returns null when the platform cannot answer (tests, web, a non-Android
/// host). The UI then says "unavailable" instead of inventing a size.
class AppSize {
  const AppSize._();

  static const channel = MethodChannel('com.shyberdev.jewellery_suite/app_info');

  static Future<int?> apkBytes() async {
    try {
      return await channel.invokeMethod<int>('apkSizeBytes');
    } catch (_) {
      return null;
    }
  }
}
