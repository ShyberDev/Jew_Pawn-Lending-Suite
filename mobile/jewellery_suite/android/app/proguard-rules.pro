# R8 / ProGuard rules for the release build.

# Flutter / Dart wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ML Kit text recognition: the app only bundles the LATIN script model, so the
# script-specific recognizer classes below are legitimately absent at runtime.
# Without these -dontwarn rules R8 treats them as missing-class errors.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Google Play services / ML Kit internals
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.android.gms.**

# Play Core (split install / deferred components) is referenced by Flutter's
# embedding but this app ships as a single APK, so it is never used.
-dontwarn com.google.android.play.core.**
