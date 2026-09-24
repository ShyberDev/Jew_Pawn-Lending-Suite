#!/usr/bin/env bash
# =============================================================================
#  build-apk.sh  —  build the Android APK for the Jewellery Suite mobile app
# -----------------------------------------------------------------------------
#  Requires Flutter + Android SDK. If they are not installed, see README.md.
#
#  Usage:
#     ./build-apk.sh              # release APK
#     ./build-apk.sh --debug      # debug APK (faster)
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$HERE/jewellery_suite"

# --- toolchain locations (edit if yours differ) ------------------------------
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/development/flutter}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/development/android-sdk}"
JAVA_HOME="${JAVA_HOME:-$HOME/development/jdk-17}"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  echo "[x] Flutter not found at $FLUTTER_HOME" >&2
  echo "    Install it, or set FLUTTER_HOME to your Flutter folder." >&2
  exit 1
fi
[ -d "$ANDROID_HOME" ] || { echo "[x] Android SDK not found at $ANDROID_HOME" >&2; exit 1; }

export JAVA_HOME ANDROID_HOME
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$FLUTTER_HOME/bin:$PATH"

MODE="release"
[ "${1:-}" = "--debug" ] && MODE="debug"

cd "$APP_DIR"
echo "==> flutter pub get"
flutter pub get
echo "==> flutter build apk --$MODE"
flutter build apk --$MODE

SRC="$APP_DIR/build/app/outputs/flutter-apk/app-$MODE.apk"
if [ "$MODE" = "release" ]; then
  DST="$HERE/jewellery_suite-release.apk"
else
  DST="$HERE/jewellery_suite-debug.apk"
fi
cp "$SRC" "$DST"
echo "==> APK ready: $DST"
