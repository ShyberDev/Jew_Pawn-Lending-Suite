# Jewellery Suite — Android app

Offline-first Android app for the **Jewellery + Pawn + Khatabook** suite. It
stores everything on the phone and syncs to your Frappe server whenever the
phone and laptop are on the same Wi-Fi (or the server is reachable).

This is a **native Flutter app**, not a web/PWA wrapper, so it keeps working
with no network at all.

---

## What it does (v1)

| Screen | Purpose |
|---|---|
| Login | Server URL + Frappe username/password. Session is remembered. |
| Home | Today's collections, active pawn loans, outstanding, sync button. |
| Customers | Add/edit customers with **photo**, phone, village, ID, ratings and per-customer interest overrides. |
| Pawn Loans | New loan with items (metal, weight, hallmark, rate, **item photo**), and one-tap **Release** (principal + interest). |
| Khatabook | New loan (principal + interest, N installments, weekly/biweekly/monthly), **Collect** payments (with irregular flag) and **Refinance** the balance. |
| Sync | Pending-change count, manual sync, and any records that need attention. |

Photos are stored on the phone and uploaded to the server (attached to the
document) as soon as that document has synced.

### Rounding rules (same as the server)

* Money — **ceiling** to 2 decimals (never under-charges).
* Weights — **round half-up** to 3 decimals.
* Interest — simple `principal × rate%/month × (days ÷ 30)`, money ceiling.

---

## Offline & sync model

* Every record gets a `client_uuid`. The server keys on it, so retries never
  create duplicates.
* **Push** sends your pending changes; **pull** downloads anything changed on
  the server since the last sync.
* Transactions (pawn loans, releases, khatabook collections, refinances) are
  append-only — they are never edited once they reach the server.
* Masters (customers, villages) are last-write-wins.
* Photos are queued and uploaded after their parent document exists.

Sync endpoints live in the `pawn_shop` app:
`pawn_shop.api.sync.{register_device,pull,push,status}`.

---

## Build the APK

### Option A — the helper script

```bash
cd mobile
./build-apk.sh            # release APK -> mobile/jewellery_suite-release.apk
./build-apk.sh --debug    # faster debug build
```

### Option B — plain Flutter

```bash
cd mobile/jewellery_suite
flutter pub get
flutter build apk --release
# APK: build/app/outputs/flutter-apk/app-release.apk
```

### Installing the toolchain (once)

The app needs Flutter + the Android SDK. On Linux, without root:

```bash
# 1. Flutter
mkdir -p ~/development && cd ~/development
curl -LO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.5-stable.tar.xz
tar xf flutter_linux_3.47.5-stable.tar.xz
export PATH="$HOME/development/flutter/bin:$PATH"

# 2. Android command-line tools
curl -LO https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip
mkdir -p ~/development/android-sdk/cmdline-tools
unzip commandlinetools-linux-15859902_latest.zip -d ~/development/android-sdk/cmdline-tools
mv ~/development/android-sdk/cmdline-tools/cmdline-tools ~/development/android-sdk/cmdline-tools/latest
export ANDROID_HOME=~/development/android-sdk

# 3. A JDK 17 (Android's Gradle plugin does not support Java 25)
curl -L -o /tmp/jdk17.tar.gz "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse"
mkdir -p ~/development/jdk-17 && tar xf /tmp/jdk17.tar.gz -C ~/development/jdk-17 --strip-components=1
export JAVA_HOME=~/development/jdk-17

# 4. SDK packages + point Flutter at them
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
    "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter config --android-sdk "$ANDROID_HOME"
flutter config --jdk-dir "$JAVA_HOME"
flutter doctor
```

---

## Install the APK on a phone

1. Copy `jewellery_suite-release.apk` to the phone (USB, Bluetooth, or
   `adb install jewellery_suite-release.apk`).
2. On the phone, allow **Install unknown apps** for the file manager.
3. Open the app and log in with the server URL, e.g.
   `http://192.168.1.10:8000` (the laptop's LAN IP — **not** `localhost`).

> The app allows plain-HTTP (`usesCleartextTraffic`) so it can reach the local
> server. If you later put the server behind HTTPS, you can turn that off.

---

## Project layout

```
mobile/jewellery_suite/
├── lib/
│   ├── main.dart                 app entry
│   ├── app.dart                  MaterialApp + theme
│   ├── data/
│   │   ├── local_db.dart         SQLite schema + helpers
│   │   ├── api_client.dart       Frappe login + sync/upload calls
│   │   └── sync_service.dart     push / pull / photo upload
│   ├── state/app_state.dart      session + save helpers + dashboard
│   ├── util/
│   │   ├── format.dart           money/weight rounding (mirrors server)
│   │   └── ids.dart              client_uuid generator
│   └── ui/                       screens
└── android/                      Android project (manifest, Gradle)
```

---

## Adding a new syncable DocType later

1. Add the DocType to `SYNC_DOCTYPES` in
   `apps/pawn_shop/pawn_shop/api/sync.py` (server).
2. Add a local table in `lib/data/local_db.dart`.
3. Add a `server doctype -> table` entry in `SyncService.tableFor`
   (`lib/data/sync_service.dart`).
4. Build a screen in `lib/ui/`.

Nothing else is needed — push/pull handle the rest.
