import 'package:package_info_plus/package_info_plus.dart';

/// The one place the app's version is read from.
///
/// v1.0.20 lesson: the version used to be typed in by hand in three separate
/// files (`about_app_screen.dart`, and twice in `home_screen.dart`). Bumping
/// `pubspec.yaml` to 1.0.19 shipped an app that still *said* 1.0.18 on the
/// drawer and the About screen — so a shopkeeper reporting a fault quoted the
/// wrong build, and so did we.
///
/// Now the string comes from the installed APK itself, which is generated from
/// `pubspec.yaml` at build time. `pubspec.yaml` is therefore the only place a
/// version is ever written, and the app cannot disagree with it.
class AppVersion {
  const AppVersion._();

  /// Shown until the platform reports the real value (and in tests, where no
  /// plugin is available). Never a number a shopkeeper could be misled by.
  static const fallback = 'unknown';

  static String _value = fallback;

  /// The version string, e.g. `1.0.19`.
  static String get value => _value;

  /// The build number, e.g. `19`.
  static String get build => _build;
  static String _build = '';

  /// Reads the version from the installed package. Call once at startup,
  /// before the first frame that can display it. Safe to call more than once.
  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _value = info.version.isEmpty ? fallback : info.version;
      _build = info.buildNumber;
    } catch (_) {
      // Never let a version lookup stop the app from starting.
      _value = fallback;
      _build = '';
    }
  }

  /// One-line form for headers and subtitles, e.g. `1.0.19 (19)`.
  static String get label => _build.isEmpty ? value : '$value ($_build)';
}
