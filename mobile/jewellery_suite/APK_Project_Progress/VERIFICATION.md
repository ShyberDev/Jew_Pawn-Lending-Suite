# Phone verification log

**Purpose:** the dated, hands-on evidence behind every ✅ in `TRACKER.md`.
A test suite passing is not a phone pass; only what was seen on the device is
recorded here.

**Device:** Redmi Note 8 Pro (`infinity_begonia`), wireless debugging.
The address changes every session — discover it with `adb mdns services`, then
confirm with `adb shell echo alive` before installing.

**Current state (2026-11-06):** `10.52.61.148:42895`, build **1.4.15 /
versionCode 2067**, `SQLCipher encrypted, schema v21`. This is freebuff’s build;
the last **published** build is **v1.4.4 / 2056**.

**Template for a new entry**

```text
### YYYY-MM-DD — vX.Y.Z / versionCode NNN
- Items: #0xx, #0yy
- Setup: installed in place / fresh install; data kept / wiped
- Observed: what was tapped and what appeared
- Logcat: no FATAL EXCEPTION / relevant [db] line
- Not covered: anything still owed
```

---

## 2026-11-05 — v1.4.14 / v1.4.15 (2066 / 2067) — #080 manifest + crash sweep

- **#080:** the built APK’s manifest was inspected with `aapt2 dump xmltree`:
  `allowBackup=false`, `fullBackupContent=false`,
  `dataExtractionRules=@0x7f110000`. A crash sweep opened and scrolled Orders,
  Workers, Old Metal, Returns, Reports, Credit Book, Supplier Payables and
  Settings; logcat showed **0 exceptions / 0 RenderFlex**.
- The encrypted DB still opened as `SQLCipher encrypted, schema v21`.
- **Still owed:** the archive-key and tracked-credentials items in #080.

## 2026-11-05 — v1.4.5 (57) — #073 dark-mode ink

- With **Dark mode (Beta)** on, the Khata filter chips (All · Due · Upcoming ·
  No reminder), the summary card (Investment / Outstanding / To Collect /
  Members), the Reports tabs (KHATA / PAWN), the interest-calculator
  **Compound** chip, Khata Books, the General customer list and Settings all
  read as light text on the dark surface.
- The **Outstanding ₹0** figure was still near-black on the first v1.4.5 build;
  that is how the missed `_stat` call was found. Correct after the rebuild.
- The phone was returned to light mode afterwards.

## 2026-11-05 — v1.4.9 / v1.4.10 — #076 late fee and drafts

- Two drafts saved with `Raw gold 0.000 g` and rows reading **DRAFT · stock
  pending**. Confirming one raised raw gold to **10.000 g** and changed that row
  to `Bal ₹1,38,000`; the other stayed a draft.
- A real sale (₹1,50,000) took a **₹500 late fee** → Credit Book ₹1,50,500 and a
  ledger row **Late fee**; a **₹1,000 receipt** then left **₹1,49,500** with
  *Collected today ₹1,000*, so the fee survived the payment.
- The fee row printed **“-₹0”** until v1.4.10 keyed it on `debit > 0`; it now
  shows **₹500**.
- Test documents were deleted afterwards.

## 2026-11-04 — v1.4.4 (2056) — #047, #070, #071, #049 restore

- **#047:** with the shyam loan due **02-02-27**, a due-date range of
  **1–30 Nov 2026** hid the loan and the summary read **₹0 / ₹0 / ₹0** with
  *“No pawn loans here.”*; **Clear date filters** restored **₹10,000 /
  ₹900 / ₹10,900**; a **1–28 Feb 2027** range included it again.
- **#070:** `1234567890` was refused in Edit Customer with *“Use a 10-digit
  mobile number, or +91 and the 10 digits.”*; `+919121376318` saved and showed
  in the list. **Call** opened the dialler as **+91 91213 76318**; **WhatsApp**
  produced `api.whatsapp.com/send/?phone=919121376318&…` (no WhatsApp app on
  this phone, so it fell back to the browser — the `91` is present).
- **#071:** the Khata tab showed **PERIOD** (All / This month / This year),
  **LOANS** (All / Active / Overdue), the six cards (**Collected in view ·
  Active loans in view · Outstanding · Overdue accounts · Collectable now ·
  Interest earned**), **COLLECTIONS IN VIEW** (*No collections in this
  period.*) and the **ALL TIME** card. One **Share this report** opened
  **PDF / Excel (.xlsx) / CSV**; PDF produced
  `jewellery_suite_khata_2026-11-04_12-58.pdf`, CSV produced
  `jewellery_suite_khata_2026-11-04_12-59.csv`, both through the Android share
  sheet (Gmail / Quick Share / Bluetooth).
- **#049 restore:** restoring the fresh `jewellery_suite_2026-11-04_15-07-06.zip`
  asked for `Admin@123`, wrote a pre-restore safety copy
  `jewellery_suite_2026-11-04_15-08-34.zip`, and reopened as
  `[db] open: SQLCipher encrypted, schema v20`; Home and Pawn Loans still showed
  the shyam loan with **₹10,000 / ₹900 / ₹10,900**.
- **Release asset:** the arm64 APK was re-downloaded from the GitHub v1.4.4
  release, SHA-256 matched `3b7452bd…c614f5`, and `adb install -r` kept the data.

## 2026-11-04 — v1.3.5 (2051) — #066 fingerprint unlock

- Turning the lock to **Every time** enabled the fingerprint switch in the same
  session; it persisted (`checked=true`).
- A cold start showed *“Jewellery Suite is locked”* and auto-prompted *“Touch the
  fingerprint sensor”* (`owner=com.shyberdev.jewellery_suite`,
  `requestReason=BiometricPromptAuthentication`). **One touch opened Home**
  (`FingerprintAuthenticationClient … success: true`) with no second prompt.
- A cancelled prompt fell back to *“Fingerprint not recognised — enter your
  PIN.”* with **Use fingerprint** and the PIN field; PIN `1234` opened the app.
- Two defects were found and fixed on the device: the switch stayed disabled
  after turning the lock on, and the prompt looped about three times because the
  gate re-locked on the resume the prompt itself causes.

## 2026-11-04 — v1.4.2 (54) — #049 encrypted DB

- `[db] plaintext database migrated to SQLCipher` → `open: SQLCipher encrypted,
  schema v20`; Home opened with the ledger intact.
- **Create backup now** wrote a verified 409 KB archive.
- Two defects were found on the phone and fixed: `sqlcipher_export` drops
  `PRAGMA user_version`, which made the migrated file and restored snapshots
  reopen as schema 0; sqflite then deletes a database whose `onCreate` throws.
  The version is now carried across, a version-0 encrypted file is repaired on
  open, and the manifest records the schema version.
- **The phone’s ledger was a fresh, empty install** after the migration defect;
  the earlier test rows were lost and no automatic backups existed.

## 2026-11-03 — v1.3.0 / v1.3.1 / v1.3.2 — #043, #041, #047

- **v1.3.0:** the jewellery dashboard showed gold 16,000/g · 92 % = 14,720/g,
  raw 10.000 g, and the module screens opened with the ledger intact. The pawn
  **Filter ▾** menu listed **All categories · Forgot_Slip_List · Pawn_Removed ·
  Loan date range · Due date range · Amount range · Manage categories…**.
- **v1.3.1:** the Khata PDF share sheet read *Sharing 1 file* with
  `jewellery_suite_khata_2026-11-03_12-32.pdf`.
- **v1.3.2:** Excel export and Unicode PDF fonts were checked; the report
  share sheet still opened with the file.

## 2026-11-02 — v1.2.8 — #041 CSV export

- Reports → export opened the share sheet (*“Sharing 1 file”*,
  `jewellery_suite_khata_2026-11-02_09-07.csv`), no exception in logcat.
- The first v1.2.7 build crashed on the tap because the export read the tab
  through `DefaultTabController.of(context)` using the screen State’s own
  context; v1.2.8 tracks the index in state.

## 2026-11-02 — v1.2.6 — #048 automatic backup

- Switching it on read *“One verified backup a day, kept in Backup & data
  (newest 7)”*.
- After a force-stop and relaunch the card read *“Last automatic backup
  02-11-26 08:53 · keeps the newest 7”* and **Backup & data** listed
  `auto_2026-11-02_08-53-00.zip` (10 KB).
- Covered by `test/auto_backup_test.dart` (4 cases).

## 2026-11-02 — v1.2.5 — #06A pawn-move password

- Password Settings → **Pawn-move password** → **Set a password** accepted
  `Admin@123` + the new secret; the pledge moved with it (*“Moved to
  Pawn_Removed.”*), moved back (*“Category removed.”*), and **Use admin
  password** restored the fallback.

## 2026-11-02 — v1.2.3 — #06A, #064, #065

- The pawn move asked for the move password, not the admin password.
- **Add Custom** created **QA_Cat** and the menu removed it again.
- The OTP card took `https://shop.local/otp` + **SMS** and **Save gateway**
  (*“Codes will be sent by SMS.”*); **Remove gateway** restored the offline
  fallback (*“Gateway removed — codes are shown on this phone.”*).

## 2026-11-01 — v1.2.2 — #06L, #063

- In dark mode the unselected **Released / Gold / Silver / Mixed** chips were
  readable after the `inkOf(context)` change.
- Pawn filters and search: chip tap-to-clear, name / ID / amount search and the
  loan-date range all behaved as specified; the summary strip followed the
  filters (₹0/₹0/₹0 when nothing matched).

## 2026-11-01 — v1.2.1 — #06K app shell

- Cold start went straight to **Home** — no PIN, no admin-password form, no
  login — with the dark theme and the ledger intact.
- `lib/app.dart` was restored from `0ae051f`; the launch gates were skipped by
  `kDevPasswordGateDisabled` (development only).

## 2026-11-01 — v1.2.0 — #040 due reminders

- Turning the switch on raised *“Allow Jewellery Suite to send you
  notifications?”*; **Allow** was accepted (`appops … POST_NOTIFICATION` →
  default allow) and the card read *“One 9:00 notification with who is due or
  overdue today”*.

## 2026-11-01 — v1.1.9 — #057, #044, #046

- **#057:** cold start → PIN → Home with no login screen; logout → login form.
- **#044:** the manual **Edit Test** row’s **Edit this entry** reopened **Edit
  Cash IN** pre-filled (Customer Payment, CASH, ₹750); switching to **UPI** and
  saving changed the same row to `Edit Test | UPI | 11:31:04 • CUSTOMER
  PAYMENT • manual row | +₹750` — no duplicate — then it was reverted to CASH.
- **#046:** the **Phone QA (A03)** row read `01 Nov 26 11:38 AM | ₹50 |
  Bal ₹1,150 | Late fee — test · UPI`.

## 2026-11-01 — v1.1.8 — #06J

- Gold `cloud_upload` badge on row 2 and ⋮ on row 1 of the Phone QB tile;
  tapping ⋮ opened Call / SMS / WhatsApp / Move / Edit.

## 2026-11-01 — v1.1.7 — #06G, #06H, #06I

- **#06G:** the amount-range dialog opened from **Filter** with From/To, worked
  open-ended, and **Clear** restored the list.
- **#06H:** returning from **+ KYC** filled the visible customer name and SAVE
  succeeded.
- **#06I:** the release confirmation button read **Release**.

---

## Passes still owed

| Item | What to drive on the phone |
|---|---|
| #065 | Mock gateway send: save `http://<laptop>:8765/otp`, E-mail, **Send code**, check the POST, then **Remove gateway** and confirm the on-screen fallback |
| #074 | One receipt split across two invoices; the saved-rate chart and WIP rows |
| #075 | A real sale with a **late fee**; the shared-expense split |
| #077 | An advance-only customer visible in the Credit Book |
| #078 | Create order → deliver → reopen/deliver refused; over-return refused |
| #079 | Deliver a worker order twice; second call refused |
| #080 | Create one backup with **Include database key** off and restore it on the same phone; toggle the switch on and confirm the warning, then restore again. Rotate the PIN and admin password |
| #081 | Install a Crashlytics build, force one test crash, see it in the console |
