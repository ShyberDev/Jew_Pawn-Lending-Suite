# Jewellery Suite — Android app

Offline-first Android app for the **Jewellery + Pawn + Khatabook** suite. It
stores everything on the phone (SQLite) and runs **fully offline with sample
demo data and no login** — a live server is *not* involved in the current
workflow. (The server link exists as a data interface only and is deferred.)

This is a **native Flutter app**, not a web/PWA wrapper.

---

## What it does (v1.0.2)

| Screen | Purpose |
|---|---|
| Home | Jewellers-gold module launcher — greeting, KPI strip (collected today, pawn outstanding), compact Core Modules grid (Khatabook / Pawn Loans / Jewellery / Cashbook), Reports entry, sync count. |
| Khata Books | **Khata/Village groups** (Village Location / Personal / Business) with members + outstanding + overdue badges, **Create New Khata**, and a **collection-first customer list** (🔴 overdue → due today → this week → upcoming) with filters + search. |
| Customer profile | Outstanding hero card, **You Gave** (loans), **You Got** (collections), **Collect**, **Refinance**, **Add Loan**, full history + payment schedule sheets. |
| Customers | Add/edit customers with **photo**, phone, village, ID, ratings and per-customer interest overrides. |
| Pawn Loans | Summary strip (principal out · interest due · active count), status chips, new loan with items (metal, weight, hallmark, rate, **item photo**), and **Release** — now enforces the blueprint rule: interest clears first and **partial release is not supported**. |
| Pawn Dashboard | Principal outstanding hero, gold/silver reserve, **age groups (0–3M / 3–6M / 6–12M / 12M+)**, quick views (interest due, old pawns 12M+, recently added, released). |
| Reports | **Khata reports** (Today's/This week/This month collection, total given/received, interest earned, outstanding, overdue, village-wise, customer-wise, bad credit/blocked) and **Pawn reports** (period/metal/status filters, principal, interest due, receivable, reserves, released, interest realised). |
| Sync | Pending-change count and manual sync (currently nothing to sync — offline mode). |

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
#    (platforms 34/35 and cmake are pulled in transitively by the plugins, so
#     install them up front to keep the first build offline-friendly)
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
    "platform-tools" \
    "platforms;android-34" "platforms;android-35" "platforms;android-36" \
    "build-tools;36.0.0" "cmake;3.22.1"
flutter config --android-sdk "$ANDROID_HOME"
flutter config --jdk-dir "$JAVA_HOME"
flutter doctor
```

> **Low-RAM machines:** Flutter's template sets
> `org.gradle.jvmargs=-Xmx8G`, which can be OOM-killed on an 8 GB laptop.
> It is already lowered to `-Xmx2G` in
> `mobile/jewellery_suite/android/gradle.properties`; raise it if you have
> more RAM. Gradle 9.3.1 is fetched on first build — if the wrapper downloader
> times out, download
> `gradle-9.3.1-all.zip` with `curl` into
> `~/.gradle/wrapper/dists/gradle-9.3.1-all/<hash>/` and create the `.ok`
> marker next to it.

---

## Install the APK on a phone

1. Copy `app-release.apk` to the phone (USB, Bluetooth, or adb), or install
   over USB:
   `adb install -r build/app/outputs/flutter-apk/app-release.apk`.
2. **No login, no server** — on first launch the app seeds demo khatas,
   customers, pawn loans and khatabook loans, and opens straight to the Home
   screen (the old login screen is gone in v1.0.2).

> **Xiaomi/Redmi (MIUI/HyperOS) — "Install canceled by user":** after you
> uninstall the app, fresh USB installs are blocked until you enable
> **Settings → Additional settings → Developer options → "Install via USB"**
> (may ask for Mi-account/SIM verification once). Then re-plug the cable and
> tap **Allow** on the USB-debugging prompt. "Update" installs over an
> existing app usually don't need this.

> The app allows plain-HTTP (`usesCleartextTraffic`) so it can later reach a
> local server without extra setup.

---

## Preview in Chromium (web demo mode — no server needed)

For fast design review without a phone, the app also runs in a browser with
**seeded sample data** and **no login** (server login + sync stay phone-only):

```bash
cd mobile/jewellery_suite
flutter run -d web-server --web-port 8090
# then open http://localhost:8090 in Chromium
```

Demo data: 2 villages · 3 customers · 2 pawn loans · 2 khatabook loans
(one collection today + one overdue). Photos render as placeholders on web (no
persistent file system in a browser). The web platform is demo-only — the
Android app is unchanged and remains the real product.

---

## Live preview on your phone (hot reload)

The fastest way to review design changes on a real screen — no APK install,
changes appear in ~1s while the app is running:

1. **Plug your Android phone in with USB** and enable **USB debugging**
   (Settings → About phone → tap *Build number* 7× → Developer options →
   *USB debugging*).
2. Trust the computer when the phone prompts.
3. In VS Code: File → Open Folder → `mobile/jewellery_suite` → Run →
   **Start Debugging**. Or from a terminal:

   ```bash
   cd mobile/jewellery_suite
   export PATH="$HOME/development/flutter/bin:$PATH"   # if not on PATH
   flutter run
   ```

4. Edit any screen in `lib/ui/` and press **`r`** in the terminal — the app
   updates instantly on the phone.

> No emulator is bundled; if you prefer one, `flutter emulators --create
> --name pixel` needs a system image (`sdkmanager "system-images;android-34;
> google_apis;x86_64"`) first.

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
│   └── ui/                       screens (home, khata, customer profile,
│                                pawn, pawn dashboard, reports, customers…)
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
