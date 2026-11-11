# Jewellery Suite — Known Issues & Unfinished Work

Status of `Apk_Develop_Branch_01_11` at **v1.4.26 / 2078**. Last updated **2026-11-08**.

This file is the "what is still wrong or missing" view. The authoritative,
one-row-per-item list is **`APK_Project_Progress/TRACKER.md`**; the dated phone
evidence is **`APK_Project_Progress/VERIFICATION.md`**. Every item here carries
its tracker number (`#0xx`) so the two files resolve each other.

An item leaves the open sections only when the fix is **written, tested, and
seen on the phone** — the same rule the tracker uses. 🟨 in the tracker means
code done, phone pass owed; it does not belong here as a bug.

## How to use this file

| Severity | Meaning |
|---|---|
| 🔴 **Critical** | Money is wrong, data is lost, or it blocks release |
| 🟠 **High** | Feature is broken or misleading to the shopkeeper |
| 🟡 **Medium** | Cosmetic or usability problem |
| ⚪ **Low** | Nice to have |
| 🔵 **Blocked** | Cannot start — needs a decision or an external dependency |

**Status values:** `OPEN` · `BLOCKED` · `WONTFIX` (deliberately not doing it) ·
`DONE` (moved to the fixed section with the tracker number).

Each item has a stable ID. Quote the ID in bug reports.

---

## A. Open bugs

### BUG-07 🟡 Dark mode is incomplete
- **Where:** Settings → **Dark mode (Beta)** (`lib/features/settings/screens/settings_screen.dart:44`);
  the debt is described in `lib/ui/palette.dart` — the shop screens were built
  from a light palette.
- **What:** the app itself labels the feature Beta because some screens still
  assume light ink and surfaces.
- **Progress:** #026 replaced the remaining fixed near-black inks with
  `inkOf` / `mutedOf` / `surfaceOf`, and #073 finished the leftover label debt.
  The label is still Beta because no full screen-by-screen sweep has been done.
- **Impact:** cosmetic. Light mode is unaffected.
- **Status:** OPEN

### SEC-05 🟡 The app-switcher snapshot shows ledger figures
- **What:** nothing sets `FLAG_SECURE` (or disables recents screenshots), so the
  Android task switcher keeps a readable image of the last screen — customer
  names, phone numbers and balances.
- **Where:** no occurrence in `lib/` or `android/app/src/main`.
- **Mitigation today:** the launch PIN / biometric gate (#037, #066) covers the
  app itself, not the OS snapshot.
- **Decision needed:** obscuring the figure on `paused` is cosmetic; `FLAG_SECURE`
  is stronger but also blocks the shop from taking their own screenshots.
- **Status:** OPEN — awaiting decision

---

## B. Play Store blockers

### PLAY-05 🔵 Sync must move to HTTPS
- **What:** the server-sync path still talks plain HTTP to a shop-LAN address
  typed by the shopkeeper.
- **Chosen direction:** HTTPS with a pinned self-signed certificate, so no CA has
  to be installed on each phone.
- **Do not** use free DDNS + Let's Encrypt — it would expose the shop LAN.
- **Do not** ship a blanket `network-security-config` limited to `localhost` and
  `10.0.2.2`: the sync address is user-entered and DHCP-assigned, so that would
  silently break sync while every local feature kept working.
- **Tracker:** #042 (deferred until a TLS server exists). See
  `docs/PLAY_STORE_REVIEW.md`.
- **Status:** BLOCKED

### PLAY-06 ⚪ Store listing and declarations
- Screenshots, description, privacy policy URL, content rating, target age
  group, and the **Data Safety** form (customer names/phones, photos, financial
  records collected; not shared).
- **Status:** OPEN

### PLAY-07 ⚪ Code shrinking never enabled
- `isMinifyEnabled` / `isShrinkResources` are absent from
  `android/app/build.gradle.kts`. Enabling R8 shrinks the 45.7 MB arm64 APK but
  ML Kit + Flutter can fail **at runtime**, so it has to be enabled and the app
  fully exercised on the phone before shipping.
- **Status:** OPEN

---

## C. Blocked on an external account

| Item | Tracker | Needs | Guide |
|---|---|---|---|
| Real OTP delivery | **#065** | An SMS / e-mail gateway URL + shared secret. The mock transport and the payload contract are already phone-verified (2026-11-06); the app now stores and sends the shared secret (`X-Gateway-Secret` + `secret` in the body), so only the shop's URL and secret are missing. | `docs/SETUP_OTP_GATEWAY.md` |
| Google Drive backup + sync | **#072** | A Google Cloud **Web client ID** (the Android client and release SHA-1 are documented). Design and conflict rules are written. | `docs/SETUP_GOOGLE_DRIVE_OAUTH.md`, `docs/GOOGLE_DRIVE_SYNC.md` |
| Firebase Crashlytics + App Distribution | **#081** | A Firebase project and its `google-services.json`. No Firestore / Storage for ledger data. | `docs/SETUP_FIREBASE.md` |

`google_sign_in`, `googleapis` and the Firebase packages are deliberately **not**
in `pubspec.yaml` yet — they land with the credentials, not before.

---

## D. Not built

| ID | Feature | Notes |
|---|---|---|
| FEAT-06 | Google Drive sync | Local zip backup works; Drive upload is #072 above |
| FEAT-07 | Help & Support | Drawer tile still opens the "coming soon" sheet (`lib/features/home/screens/home_screen.dart:231`) |
| FEAT-08 | Split into 4 separate apps | **WONTFIX** — one app for pawn + khata + cashbook + jewellery was the decision; this row is kept so old notes resolve |

---

## E. Fixed — do not re-report

Every row below is code done, tested **and** seen on the phone; the dated
evidence is in `APK_Project_Progress/VERIFICATION.md`.

| ID | Fixed by | What it was |
|---|---|---|
| BUG-01 🔴 | #020 | Reports **Overdue** added the whole outstanding instead of what is due. Khata → Overdue now uses `dueNowForReports()` (due + arrears); 4 regression tests. |
| BUG-02 🟠 | #021 | Three-column money headers collided (`₹100,002,0₹0`). Columns are flexible with `FittedBox` / ellipsis; widget tests at 320 dp and 2× text. |
| BUG-03 🟡 | #022 | Customer Profile title truncated to "Custo...". Call / SMS / WhatsApp / Move / Edit moved into one ⋮ menu. |
| BUG-04 🟡 | #023 | The "No Due Date" chip actually filtered on *no reminder set*. Renamed **No reminder**; the predicate was already correct. |
| BUG-05 🟡 | #024 | Rupee grouping was Western (`₹8,333,500`). `moneyWhole` now emits true lakh/crore groups (`₹83,33,500`, `₹10,00,02,000`) and a test locks it. |
| BUG-06 🟡 | #025 | `flutter test` hung in the migration teardown. Fixed, and `./tool/test.sh` points `TMPDIR` at `.dart_tool/tmp` so a full `/tmp` cannot hang a run. |
| PLAY-01 🔴 | #027 | Release APK was signed with the **debug** keystore. A real upload keystore + `android/key.properties` are in place; `apksigner` on v1.4.20 reports `CN=Jewellery Suite, O=ShyberDev`. |
| PLAY-02 🔴 | #028 | Missing signing config fell back to debug signing silently. `android/app/build.gradle.kts` now fails the build with "Release signing is not configured…" naming the missing properties. |
| PLAY-03 🟠 | — | **Not a gap.** Photos come from `image_picker`, which launches the system camera; it needs neither `CAMERA` nor `READ_MEDIA_IMAGES`. The manifest declares only INTERNET, USE_BIOMETRIC, POST_NOTIFICATIONS and RECEIVE_BOOT_COMPLETED. |
| PLAY-04 🟡 | #027 | `key.properties` and `**/*.jks` were unignored. `android/.gitignore` now covers both; `git check-ignore` confirms. |
| SEC-01 🔴 | #037, #054, #057 | The app opened straight to Home. It now requires the shop account (Gmail or mobile + salted hash), stays signed in until Logout, and an existing local ledger works offline. |
| SEC-02 🔴 | #080 | Android auto-backup was on, so the SQLCipher database could be copied to Google. `allowBackup="false"`, `fullBackupContent="false"` and `dataExtractionRules` exclude everything; covered by `test/backup_manifest_test.dart`. |
| SEC-03 🟠 | #038 | The `admin` password shipped inside the APK as a constant. A forced first-run admin password (min 6 chars, `admin` refused, salted hash) replaced it. |
| SEC-04 🟠 | #037, #066 | Nothing stopped a second person opening the app. Optional 4–6 digit PIN with a salted hash, startup + background gate, fingerprint/face via `local_auth` that fails closed. |
| FEAT-01 | #037, #057 | Login / auth screen — built and reachable |
| FEAT-03 | #057, #065 | OTP login — built; mock delivery phone-verified, real gateway is #065 above |
| FEAT-04 | #005, #030, #031, #044, #045 | Cashbook — built, with source/mode filters, auto-entries and manual-row edit |
| FEAT-05 | #043, #074–#079, #083 | Jewellery items module — built end to end |

### Older fixes (pre-v1.0.25), IDs kept for old bug reports

| ID | Fixed in | Issue |
|---|---|---|
| FIX-01 | v1.0.24 | Ledger showed the **typing** time, not the payment date. |
| FIX-02 | v1.0.23 | **Refinance** left the "You Gave" dialog open with an ignored amount box. |
| FIX-03 | v1.0.23 | Sample late fee was seeded and charged twice. |
| FIX-04 | v1.0.22 | `Sample_FullyPaid` still showed a red DUE chip. |
| FIX-05 | v1.0.22 | A sample with a blank frequency silently read as Weekly. |
| FIX-06 | v1.0.21 | Sample seeder wrote no v10 component columns. |
| FIX-07 | v1.0.21 | Collection insert used a non-existent `customer_name` column. |
| FIX-08 | v1.0.20 | Version typed into three files; the app ran a different build than it displayed. |
| FIX-09 | v1.0.20 | Reports printed raw doubles (`₹8333500.0`) and a negative interest total. |
| FIX-10 | v1.0.19 | 31 places could crash if Back was pressed while saving. |

---

## F. Phone-pass status

**#085** — on v1.4.20 the lock screen's **Forgot PIN?** → **Send code** closed the
dialog and then showed nothing (no code box, no error) while the code was issued
and the gateway POST ran; a failure in that step dropped the reset silently.
v1.4.22 covers the exchange with a **“Sending the code…”** dialog and always ends
on the six-digit code box, falling back to the on-screen code when the gateway
fails. **Seen on the phone 2026-11-07** on v1.4.22 / 2074: the code box
appeared with the offline code, a wrong code was refused, and the keypad stayed
down. Nothing owed.

**#086** — every shared PIN / password / one-time-code prompt disposed its
`TextEditingController` in a `finally` while the dialog route was still animating
out, throwing *“A TextEditingController was used after being disposed”* on close
(a debug assertion; a red error frame in debug builds). The four remaining
prompts now own their controller in a `State`, like `_PasswordPrompt` already
did. Behaviour is unchanged. **Seen on the phone 2026-11-07** on v1.4.22 / 2074:
every prompt opened and closed cleanly, with no *“used after being disposed”* in
logcat. Nothing owed.

**#084** — the lock screen's **Forgot PIN?** was a dead button (the gate rendered
the lock screen in a bare `Overlay`, so `showDialog` had no `Navigator`). Fixed
in **v1.4.20 / 2072**, plus an admin-password fallback when no account exists and
a **Forgot PIN** / **Forgot Daily MPIN** title. **Seen on the phone 2026-11-07:**
the dialog opened with *“Reset the screen lock on this phone.”* and the code
delivery line, no Navigator exception. The reset itself was not completed, so no
credential was rotated.

---

## G. How to verify after a fix

The checklist lives in one place to stop it drifting: **`APK_Project_Progress/Manual-Handle-by-Person-Possible.md`**
§A3 (run a phone pass) and §A4 (module spot-checks). Record the exact on-screen
words in `VERIFICATION.md`; a green suite is not a phone pass.
