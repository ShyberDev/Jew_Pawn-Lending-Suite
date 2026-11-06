# Jewellery Suite — project dashboard

**What this is:** an offline-first Flutter app that runs one jewellery + pawn +
khatabook + cashbook shop from a single Android phone. The ledger is SQLCipher on
the device; there is no server in the loop. This folder is the project’s memory:
what was built, what was seen on the phone, and what is still owed.

---

## Current state

| Thing | Value |
|---|---|
| Installed test build | **1.4.17 / versionCode 2069** on `10.52.61.103:32935` |
| Last published release | **v1.4.4 / versionCode 2056** — [GitHub release](https://github.com/ShyberDev/Jew_Pawn-Lending-Suite/releases/tag/v1.4.4) (arm64, armeabi-v7a, x86_64) |
| Branch | `Apk_Develop_Branch_01_11` |
| Database | `SQLCipher encrypted, schema v21` |
| Tests | **518 passing**; `flutter analyze` clean |
| Phone ledger | shyam / A01, Gold chain 10.0 g, ₹10,000 at 3 %/month, due 02-02-27, outstanding ₹10,900 |

> The installed 1.4.17 is a **development** build. The last build verified against
> the published release asset is v1.4.4.

---

## Start here

| File | Read it when you need… |
|---|---|
| **`TRACKER.md`** | The authoritative list of every numbered item and its status |
| **`VERIFICATION.md`** | The dated phone evidence behind every ✅ |
| **`CHANGELOG.md`** | The narrative history: what changed in each round and why |
| **`HANDOFF.md`** | Phone address, secrets pointer, environment traps, working rules |
| **`SPEC_JEWELLERY.md`** | The jewellery module’s agreed behaviour and screen map |
| **`CALCULATIONS.md`** | C01–C18 worked calculations and the test that covers each |
| **`docs/SETUP_GOOGLE_DRIVE_OAUTH.md`** | Creating the OAuth client for Drive backup (#072) |
| **`docs/SETUP_OTP_GATEWAY.md`** | A real SMS/Gmail gateway for one-time codes (#065) |
| **`docs/SETUP_FIREBASE.md`** | Crashlytics + App Distribution on the free tier (#081) |
| **`docs/GOOGLE_DRIVE_SYNC.md`** | The multi-device sync design and conflict rules |

---

## Next five actions

1. **No jewellery phone pass is owed** — #074, #075, #077, #078, #079, #082 and
   #080’s **Include database key** switch were all passed on v1.4.16 / v1.4.17.
   One question came out of the #079 pass and needs the shop's answer: a
   delivered worker order leaves the issued metal on the worker's reserve
   (`VERIFICATION.md`).
2. **#080 remaining** — rotate the PIN/admin password that were tracked in
   public git; try a restore on a phone with a different keystore.
3. **#065 real gateway** — once the shop supplies an SMS/e-mail gateway URL and
   shared secret, replace the mock; the contract is already verified.
4. **#072 Drive** — once the shop supplies the **Web client ID**, add
   `google_sign_in` + `googleapis` and upload/restore behind a settings switch.
5. **#081 Firebase** — once the shop supplies `google-services.json`, add
   Crashlytics with a guarded init; no Firestore/Storage for ledger data.

---

## Open blockers

| Item | Needs | Owner |
|---|---|---|
| **#065** real OTP | An SMS/e-mail gateway URL (+ shared secret) | shop |
| **#072** Drive | Google Cloud **Web client ID** (Android client + release SHA-1 already documented) | shop |
| **#081** Firebase | A Firebase project and `google-services.json` | shop |
| **#042** HTTPS | A server with TLS before certificate pinning | later |
| **#080** archive key | Rotate the PIN/admin password (deferred: the shop treats them as throwaway test values); cross-phone restore try-out | us |

Steps for each are in the linked setup guides. Do not paste secrets into a
tracked file.

---

## Where to change what

| Page / feature | Main file(s) |
|---|---|
| New / edit Pawn Loan | `lib/ui/pawn_screen.dart`, `lib/state/app_state.dart` (`savePawnLoan`) |
| Pawn dashboard, filters | `lib/ui/pawn_dashboard_screen.dart` |
| Customer Profile, ledger, refinance | `lib/ui/customer_profile_screen.dart`, `lib/ui/refinance_sheet.dart` |
| Khata list, filters, schedule | `lib/ui/khata_screen.dart`, `lib/ui/khatabook_screen.dart` |
| Cashbook UI + filters | `lib/ui/cashbook_screen.dart` |
| Cashbook queries / auto-hooks | `lib/data/local_db.dart`, `lib/state/app_state.dart` |
| Reports / overdue math | `lib/ui/reports_screen.dart` |
| Backup / restore | `lib/ui/backup_screen.dart`, `lib/data/backup_service.dart` |
| File picker save/restore | `lib/util/backup_files.dart`, `android/.../MainActivity.kt` |
| Offline login, admin gate | `lib/state/app_state.dart`, `lib/ui/login_screen.dart`, `lib/ui/admin_password_gate.dart` |
| App lock (PIN / Daily MPIN) | `lib/ui/app_lock_gate.dart`, `lib/util/app_lock.dart` |
| Account, sign-in, Forgot-password OTP | `lib/util/account.dart`, `lib/ui/otp_flow.dart`, `lib/util/otp_gateway.dart` |
| Password centre | `lib/ui/password_settings_screen.dart`, `lib/ui/secret_dialogs.dart` |
| Pawn categories | `lib/ui/pawn_categories_screen.dart`, `lib/data/migration_v16.dart` |
| Jewellery module | `lib/features/jewellery/**`, `lib/util/jewellery_math.dart` |
| Database schema + migrations | `lib/data/local_db.dart`, `lib/data/migration_v*.dart` |
| Release signing | `android/app/build.gradle.kts`, `android/key.properties` (gitignored) |

---

## How to update this folder

1. **One row per item** in `TRACKER.md`; do not create a second list.
2. **Phone evidence goes in `VERIFICATION.md`**, not in the tracker row. The row
   links to it by item number and date.
3. **History goes in `CHANGELOG.md`.** Add a dated `###` entry for each round.
4. **Never mark ✅ without a phone observation.** 🟨 CODE DONE is the honest state
   for written-and-tested work that has not been seen on the device.
5. **Run the checks before claiming them:**
   `flutter analyze` and `TMPDIR=$PWD/.dart_tool/tmp flutter test`.
6. **Do not use stream editors** (`sed -i`, `awk`) on these files; re-read the
   block and use the file tools.
7. **Secrets never go in git.** Use `APK_Project_Progress/.secrets.local.md`
   (gitignored) and keep only placeholders here.

---

## The short version

The app is feature-complete for the shop’s current workflow and runs offline. The
remaining work is **verification** (one jewellery phone pass and the OTP mock),
**security debt** (archive key, credentials), and **three external integrations**
(Drive, a real OTP gateway, Firebase) that are blocked on accounts only the shop
can create.
