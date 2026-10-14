# Jewellery Suite — Known Issues & Unfinished Work

Status of `develop` at **v1.0.24**. Last updated **2026-10-14**.

This file is the single place to check "what is still wrong or missing".
It is updated as items are fixed — an item is only removed when the fix is
**built, tested and verified on a real device or emulator**.

## How to use this file

| Severity | Meaning |
|---|---|
| 🔴 **Critical** | Money is wrong, data is lost, or it blocks release |
| 🟠 **High** | Feature is broken or misleading to the shopkeeper |
| 🟡 **Medium** | Cosmetic or usability problem |
| ⚪ **Low** | Nice to have |
| 🔵 **Blocked** | Cannot start — needs a decision or an external dependency |

**Status values:** `OPEN` · `WONTFIX` (deliberately not doing it) ·
`DONE` (move to the Fixed section with the version).

Each item has a stable ID. Quote the ID in bug reports.

---

## A. Open bugs

### BUG-01 🔴 Reports "Overdue" shows the full balance, not what's due
- **Where:** `lib/ui/reports_screen.dart:150`
- **What:** `overdueAmt` adds the loan's entire outstanding balance.
- **Should be:** **To Collect** — only the installments due on or before today,
  plus arrears. This contradicts the locked rule *"To Collect = dues due today
  plus arrears, never the full balance"*, which the rest of the app obeys.
- **Impact:** a shopkeeper reads "Overdue accounts ₹X" in Reports and collects
  against the wrong figure. Directly affects money.
- **Repro:** give a member a 12-month loan, pay nothing. Reports → Khata →
  Overdue accounts shows the whole principal + interest instead of one month.
- **Status:** OPEN

### BUG-02 🟠 Three-column money headers overflow and collide
- **Where:** Customer Profile header, khata member-list header, Payment
  schedule sheet
- **What:** at long values the columns run together and numbers wrap mid-digit,
  e.g. **`₹100,002,0₹0`**. The principal and interest figures touch.
- **Cause:** the columns are not flexible, so a long rupee value overflows.
- **Impact:** the primary money display becomes unreadable exactly when the
  numbers are large. Triggers at roughly ₹50,00,000 and above, which real shops
  will reach.
- **Repro:** create a loan of ₹1,00,00,000 and open Customer Profile.
- **Status:** OPEN

### BUG-03 🟡 Screen title truncated to "Custo..."
- **Where:** Customer Profile app bar
- **What:** five action icons (Call, SMS, WhatsApp, Move, Edit) squeeze the
  title until it reads "Custo...".
- **Impact:** cosmetic; the screen is still identifiable.
- **Status:** OPEN

### BUG-04 🟡 "No Due Date" filter is mislabelled
- **Where:** `lib/ui/khata_screen.dart:1151`
- **What:** the filter chip reads "No Due Date" but it actually shows members
  with **no reminder set** (`!reminderSet`). It has nothing to do with whether a
  loan has a due date.
- **Impact:** a shopkeeper will reasonably read it as "loans without a
  schedule" and see unrelated members. Confusing rather than wrong.
- **Note:** to be checked manually — decide whether to rename the chip or change
  what it filters.
- **Status:** OPEN

### BUG-05 🟡 Rupee grouping is Western, not Indian
- **Where:** `lib/util/format.dart` — `moneyWhole`
- **What:** ₹8,333,500 is displayed where Indian convention is **₹83,33,500**.
  The function's own doc comment claims "Indian digit grouping" but the code
  groups in threes from the right.
- **Impact:** inconsistent with how the shopkeeper writes amounts. Cosmetic, but
  it is on every money figure in the app.
- **Note:** **decision needed.** Changing it alters every screen at once.
- **Status:** OPEN — awaiting decision

### BUG-06 🟡 `flutter test` occasionally hangs
- **Where:** `test/migration_v9_test.dart` `tearDownAll`
- **What:** a full `flutter test` run intermittently hangs at that teardown.
  Every test file passes when run on its own.
- **Impact:** developer friction only. No effect on the shipped app.
- **Status:** OPEN

### BUG-07 🟡 Dark mode is incomplete
- **Where:** Settings → Dark mode (labelled "Beta" in the app)
- **What:** the app itself warns some screens may not be fully dark.
- **Status:** OPEN

---

## B. Play Store blockers

### PLAY-01 🔴 Release APK is signed with the DEBUG keystore
- **Where:** `android/app/build.gradle.kts`
- **What:** `signingConfig = signingConfigs.getByName("debug")`.
- **Impact:** Play Store will not accept it, and it is not a real signature.
- **Progress:** keystore already generated at `~/jewellery_suite_keystore.jks`.
- **⚠️ Back that file up now.** Once an app is published under a keystore,
  losing it means the app can never be updated on Play.
- **Status:** OPEN

### PLAY-02 🔴 Signing config must fail loudly, not fall back
- **What:** the proposed Gradle checks `if (key.properties exists)` and
  otherwise **silently** uses debug signing — the build succeeds and produces an
  unusable APK.
- **Required:** missing `key.properties` should fail the build with a clear
  message.
- **Note:** the proposed document also puts `key.properties` in a path its own
  Gradle does not read. See `docs/PLAY_STORE_REVIEW.md`.
- **Status:** OPEN

### PLAY-03 🟠 No camera permission declared
- **Where:** `android/app/src/main/AndroidManifest.xml`
- **What:** no `CAMERA`, no `READ_MEDIA_IMAGES`. The app captures customer and
  pawn-item photos.
- **Status:** OPEN

### PLAY-04 🟡 `.gitignore` does not cover signing secrets
- **What:** neither `key.properties` nor `*.jks` is ignored. Adding signing
  without this would risk committing the keystore.
- **Status:** OPEN

### PLAY-05 🔵 Sync must move to HTTPS
- **What:** the app talks plain HTTP to a shop-LAN address
  (`login_screen.dart` prompts `http://192.168.1.10:8000`).
- **Chosen direction:** HTTPS. Recommended route is pinning a self-signed
  certificate, so no CA has to be installed on each phone.
- **Do not** use free DDNS + Let's Encrypt — it would expose the shop LAN.
- **Note:** a blanket `network-security-config` limited to `localhost` and
  `10.0.2.2` would **break** sync entirely, because the address is entered by the
  user and changes with DHCP.
- **See:** `docs/PLAY_STORE_REVIEW.md`
- **Status:** OPEN

### PLAY-06 ⚪ Store listing and declarations
- Screenshots, description, privacy policy URL, content rating, target age
  group, and the **Data Safety** form (customer names/phones, photos, financial
  records collected; not shared).
- **Status:** OPEN

### PLAY-07 ⚪ Code shrinking never enabled
- `isMinifyEnabled` / `isShrinkResources` are off. Enabling R8 shrinks the APK
  but ML Kit + Flutter can fail **at runtime**. Must be enabled, then the app
  fully exercised, before shipping.
- **Status:** OPEN

---

## C. Security & privacy

### SEC-01 🔴 No authentication gate — app opens straight to Home
- **Where:** `lib/main.dart:43` — `state.loggedIn = true`
- **What:** the Login screen exists (`app.dart:60`) but is unreachable. Anyone
  who opens the app lands directly on the dashboard with full access to all
  customer names, phone numbers and loan figures.
- **Impact:** anyone who picks up the phone sees every customer's financial
  record. Mitigated only by the device lock screen.
- **Status:** OPEN

### SEC-02 🔴 Android auto-backup is enabled
- **Where:** manifest has no `android:allowBackup`
- **What:** it defaults to **true**, so Android can copy the app's private
  data — the SQLite database holding every customer's financial records — into
  the user's Google backup.
- **Required:** `android:allowBackup="false"`.
- **Status:** OPEN

### SEC-03 🟠 The `admin` password ships inside the APK
- **Where:** `lib/ui/admin_guard.dart`
- **What:** the default password is a constant in the app binary, so anyone who
  has the APK can read it. It is an *accident guard*, not security, and the
  code says so.
- **Status:** OPEN (accepted limitation, documented)

### SEC-04 🟠 No PIN / biometric lock at launch
- **What:** nothing stops a second person opening the app. A "Biometric &
  screen lock" entry exists in the drawer.
- **Status:** OPEN

### SEC-05 🟡 Ledger rows expose financial detail on screen
- **Note:** worth considering whether the app should obscure figures when it
  goes to the background (app switcher snapshot).
- **Status:** OPEN

---

## D. Not yet built

| ID | Feature | Notes |
|---|---|---|
| FEAT-01 | **Login / Auth screen** | Built but unreachable — see SEC-01 |
| FEAT-02 | Google Sign-In | Not started |
| FEAT-03 | OTP login | Not started |
| FEAT-04 | **Cashbook module** | Tile on Home is a `coming soon` stub |
| FEAT-05 | **Jewellery items module** | Tile on Home is a `coming soon` stub |
| FEAT-06 | Google Drive sync | Local zip backup only (Backup & data) |
| FEAT-07 | Help & Support | Drawer tile is a `coming soon` stub |
| FEAT-08 | Split into 4 separate apps | Original plan: Pawn / Khata / Cashbook / Jewellery launched independently |

---

## E. Recently fixed — do not re-report

| ID | Fixed in | Issue |
|---|---|---|
| FIX-01 | v1.0.24 | Ledger showed the **typing** time, not the payment date. Back-dated entries displayed and sorted as today, so the running balance was in the wrong order. |
| FIX-02 | v1.0.23 | Tapping **Refinance** left the "You Gave" dialog open with an amount box that was ignored; the refinance dialog only appeared after pressing Add. |
| FIX-03 | v1.0.23 | Sample late fee was both seeded on the loan and charged again — counted twice. |
| FIX-04 | v1.0.22 | `Sample_FullyPaid` was not fully paid (2 of 4 dues), so it still showed a red DUE chip. |
| FIX-05 | v1.0.22 | A sample named "No Due Date" had a **blank frequency**, which the app silently read as Weekly — and showed "DUE 3 DAYS AGO". An impossible state in the real loan form. |
| FIX-06 | v1.0.21 | Sample seeder wrote no v10 component columns, so every sample balance disagreed with the real engine. |
| FIX-07 | v1.0.21 | Collection insert used a non-existent `customer_name` column, so seeded payments silently vanished. |
| FIX-08 | v1.0.20 | Version was typed into three separate files; the app ran 1.0.19 while displaying 1.0.18. |
| FIX-09 | v1.0.20 | Reports printed raw doubles: `₹8333500.0`, and **"Interest earned ₹-91668500"**. |
| FIX-10 | v1.0.19 | 31 places could crash if Back was pressed while saving. |

---

## F. Manual verification checklist

Run through this after each release. Tick only what you have actually seen.

- [ ] Home KPI figures match Khata Books figures
- [ ] Each due chip shows the colour its name implies (red = today/late,
      blue = future, green = nothing due)
- [ ] To Collect is never the full balance
- [ ] Collect a part payment → Principal falls, Investment falls, ledger balance correct
- [ ] Interest-only loan → only interest is billed, principal untouched until interest is clear
- [ ] Refinance → old loan marked REFINANCED, new loan = previous + fresh + new interest
- [ ] Move to Loss → member and all loans move; Loss khata cannot be deleted
- [ ] Unpaid / Unavailable markers add no money and change no balance
- [ ] Ledger rows show the **payment** date, not today's date
- [ ] Reports figures match the screens they summarise
- [ ] A back-dated collection shows its own date and sorts correctly
- [ ] Deleting asks for the password; cancelling deletes nothing
- [ ] Sample data can be added and fully removed afterwards
- [ ] Drawer, About screen and Settings all show the same version number

---

## G. Manual test data

`Menu → Settings → Add sample data` adds one member per visible condition,
named after what it shows. Remove with `Backup & data → remove sample data`.

| Sample | Shows |
|---|---|
| `Sample_DueToday` | red DUE TODAY |
| `Sample_Overdue_4Days` | red, four days late |
| `Sample_Overdue_Arrears` | several missed installments |
| `Sample_Overdue_NoReminder` | overdue, no reminder set |
| `Sample_Upcoming` | blue chip, due in the future |
| `Sample_PartPaid` | one paid, next due ahead |
| `Sample_LateFee` | a dated late-fee charge |
| `Sample_FullyPaid` | settled, nothing due |
| `Sample_InterestOnly` | interest-only with billed periods |
| `Sample_Refinanced` | frozen old loan + new split loan |
| `Sample_InLoss` | a member in the Loss Khata |