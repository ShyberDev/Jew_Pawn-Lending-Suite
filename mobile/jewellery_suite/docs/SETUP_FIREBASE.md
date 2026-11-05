# Firebase — what to use, what to avoid, and how to link it

**Item:** #081 (agenda) · **Status:** planned, blocked on a Firebase project
**Decision:** use Firebase for **crash reports + test distribution only**. Do not
put the ledger, backups or money data in Firebase. That keeps the free tier from
ever throttling the shop.

---

## Why this split

The app is offline-first: SQLCipher on the phone is the source of truth, and
`BackupService` already writes encrypted zips. Firebase is a convenience layer
around that, not a replacement.

| Firebase product | Use it? | Why |
|---|---|---|
| **Crashlytics** | **Yes** | Free, unlimited crashes; tells us what broke on the shop's phone without asking them to read logcat |
| **App Distribution** | **Yes** | Free; send a build to testers by e-mail, no Play Store review |
| **Analytics** | Optional | Free, but the shop gains little; skip unless we want screen-usage data |
| **Remote Config** | Optional | Free; useful for feature flags later |
| **Cloud Messaging** | Later | Free; only if we add push reminders |
| **Firestore** | **No** | 1 GiB / 50k reads / 20k writes per day on Spark — a busy shop could hit the write cap and stall |
| **Cloud Storage** | **No** | 5 GB / 1 GB-per-day download on Spark; photos would eat it |
| **Cloud Functions** | **No** | Requires the paid Blaze plan |

**Rule of thumb:** if losing the free tier would stop the shop from billing a
customer, it does not belong in Firebase. Crashlytics and App Distribution can
fail without touching a single ledger row.

---

## Free-tier budget (Spark)

These are Google's published Spark limits; confirm them in the console before
relying on them, because Google changes them.

| Product | Spark allowance | Our expected use |
|---|---|---|
| Crashlytics | Free, no cap on crash reports | A handful of reports per release |
| App Distribution | Free | 3–5 testers, a few builds a month |
| Analytics | Free (event volume limits apply) | None if disabled |
| Remote Config | Free | None initially |
| Firestore | 1 GiB storage, 50k reads/day, 20k writes/day, 20k deletes/day | **0** |
| Cloud Storage | 5 GB storage, 1 GB/day download, 20k uploads/day | **0** |
| Hosting | 10 GB storage, 360 MB/day transfer | **0** |
| Cloud Functions | Not on Spark — Blaze required | **0** |

At our usage, the only realistic ceiling is **App Distribution tester count**
(Google caps testers per project) and **Analytics event volume**, neither of
which affects the shop's bookkeeping.

---

## Link the project — step by step

### 1. Create the Firebase project

1. <https://console.firebase.google.com> → **Add project**.
2. Name: `jewellery-suite` (the project ID becomes something like
   `jewellery-suite-1a2b3`; note it).
3. Google Analytics: **off** is fine for Crashlytics. Turning it on adds the
   Analytics SDK and data collection; the shop does not need it.
4. **Create project**.

### 2. Register the Android app

1. Project overview → **Add app → Android**.
2. Package name: `com.shyberdev.jewellery_suite` — must match exactly.
3. App nickname: `Jewellery Suite`.
4. **Debug signing certificate SHA-1:**
   `CE:85:4B:43:DD:C1:2F:88:CD:04:AB:92:92:E2:D1:1B:FB:A9:3E:49`
5. **Register app** → download `google-services.json`.
6. Put it at `android/app/google-services.json`.
7. Add the **release** SHA-1 too (Project settings → Your apps → Add fingerprint):
   `C9:27:26:27:AB:0F:66:40:9B:FC:12:C0:50:0E:B5:3A:05:88:13:B6`

> Crashlytics only needs the package name. The SHA-1s matter for Google Sign-In,
> App Check and Dynamic Links. Register both now so we do not have to come back.

### 3. Add the Flutter side

**Recommended — FlutterFire CLI** (does the Gradle edits for you):

```bash
dart pub global activate flutterfire_cli
firebase login
flutterfire configure --project=<PROJECT_ID>
# select android; it writes lib/firebase_options.dart and android/app/google-services.json
```

**Manual alternative** if the CLI is unavailable:

`android/settings.gradle.kts` — inside the existing `plugins { }` block:

```kotlin
id("com.google.gms.google-services") version "4.4.4" apply false
```

`android/app/build.gradle.kts` — add to its `plugins { }` block:

```kotlin
id("com.google.gms.google-services")
```

Dependencies:

```bash
flutter pub add firebase_core firebase_crashlytics
# optional: flutter pub add firebase_analytics firebase_app_distribution
```

Do **not** pin versions by hand; let `pub` resolve the current compatible set.

### 4. Initialize safely

Firebase must never be able to stop the app from opening. Wrap it:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (_) {
    // No google-services.json, no Play Services, or offline first run:
    // run exactly as before, just without crash reporting.
  }

  runApp(const JewellerySuiteApp());
}
```

If `DefaultFirebaseOptions` is not generated (manual setup), use
`Firebase.initializeApp()` with the values from `google-services.json`, or skip
Firebase entirely until the CLI has run.

### 5. Verify Crashlytics

1. Build a debug APK and install it.
2. Add a temporary button or use `FirebaseCrashlytics.instance.crash();` in a
   debug-only path.
3. Crash the app once, reopen it, wait ~5 minutes.
4. Firebase console → **Crashlytics** → the crash appears with the device model
   and stack trace.
5. Remove the test crash before committing.

Crashlytics needs one launch after install to upload symbols; a debug build is
enough for the first check. Release builds need the mapping file for readable
stack traces — the Flutter Gradle plugin uploads it when the Crashlytics Gradle
plugin is applied (the FlutterFire CLI adds it).

### 6. App Distribution for testers

```bash
# arm64 phone (Redmi Note 8 Pro) — matches the split APK we ship
flutter build apk --release --target-platform android-arm64

firebase appdistribution:distribute \
  build/app/outputs/flutter-apk/app-release.apk \
  --app <FIREBASE_APP_ID> \
  --testers "tester1@example.com,tester2@example.com" \
  --release-notes "v1.4.15 test build — #0xx"
```

`FIREBASE_APP_ID` looks like `1:1234567890:android:abcdef` and is in
`google-services.json` (`mobilesdk_app_id`) or Project settings.

Testers get an e-mail, open the link on the phone, allow install from unknown
sources, and install. No Play Store, no cable. This is the fastest way to get a
build to the shop while we keep using `adb` for our own passes.

> Split APKs: `--split-per-abi` produces three files. For testers, either send the
> arm64 one or build a universal APK (`flutter build apk --release`) so a wrong
> ABI cannot fail silently.

---

## Repo and secret handling

The repository is **public**. `google-services.json` is not a secret in Google's
model — it contains the project ID, app ID and an Android API key that is
restricted by package name + SHA-1. Two workable choices:

- **Commit it** (simplest): builds work for anyone who clones; the API key is
  package/SHA-1-restricted. Add the SHA-1s in the console and restrict the key to
  the Android app.
- **Keep it out** (tighter): add `android/app/google-services.json` and
  `lib/firebase_options.dart` to `.gitignore`, store them in the private handover
  folder, and give them to whoever builds. Clones will not build until they add
  the file.

Do **not** commit service-account JSON, the Twilio/MSG91 keys, or the OTP gateway
secret. Those are real secrets, unlike the Firebase Android config.

---

## What Firebase does *not* solve

- **Drive backup / multi-device sync** — that is #072 and needs Google OAuth
  (`docs/SETUP_GOOGLE_DRIVE_OAUTH.md`). Firebase Auth gives an identity, not Drive
  file access; you still need the `drive.appdata` scope and a Google access token.
- **OTP delivery** — that is #065 and needs an SMS/e-mail gateway
  (`docs/SETUP_OTP_GATEWAY.md`). Firebase Auth phone sign-in is a different
  product and would replace the app's local account model, which we are not doing.
- **Backups** — the encrypted zip stays on the phone / goes to Drive. Firestore is
  not a backup target.

---

## Acceptance checklist

- [ ] Firebase project created; Analytics off (or a deliberate decision to enable)
- [ ] Android app registered with package `com.shyberdev.jewellery_suite`
- [ ] Debug + release SHA-1 registered
- [ ] `google-services.json` in `android/app/`
- [ ] Gradle plugin applied (CLI or manual)
- [ ] `firebase_core` + `firebase_crashlytics` resolve and the app still builds
- [ ] App opens with Firebase deliberately broken/missing (guarded init)
- [ ] A test crash appears in Crashlytics
- [ ] One tester installs a build through App Distribution
- [ ] No Firestore/Storage/Functions usage added for ledger data
- [ ] APK size delta recorded before/after the SDKs
