# Phone verification log

**Purpose:** the dated, hands-on evidence behind every ✅ in `TRACKER.md`.
A test suite passing is not a phone pass; only what was seen on the device is
recorded here.

**Device:** Redmi Note 8 Pro (`infinity_begonia`), wireless debugging.
The address changes every session — discover it with `adb mdns services`, then
confirm with `adb shell echo alive` before installing.

**Current state (2026-11-06):** `10.52.61.103:32935`, build **1.4.16 /
versionCode 2068**, `SQLCipher encrypted, schema v21`. This is freebuff’s build;
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

## 2026-11-06 — v1.4.17 (2069) — #075 shared expense split

- Saved a purchase **PUR-20261106-0001** for a new supplier **Shared Test
  Supplier** with two gold lines at the saved ₹7,200/g and one **Shared expense
  ₹400**: 10.000 g @ 92% → 9.200 g × ₹7,200 = ₹66,240; 30.000 g @ 92% → 27.600 g
  × ₹7,200 = ₹1,98,720.
- The form preview read **Item 1 ₹66,240 · Item 2 ₹1,98,720 · Shared expense
  ₹400 · Payable ₹2,65,360** — the payable is the two lines plus the shared
  amount once.
- The saved document showed the share already allocated per line:
  **· Additional ₹100** on the 10 g line (₹66,340) and **· Additional ₹300** on
  the 30 g line (₹1,99,020), i.e. ₹400 divided by net weight 9.2 : 27.6 = 1 : 3
  and stored once on the document.
- **Not covered:** editing a line's weight after the shared expense is typed
  (the split recomputes on save; unit tests cover the maths).

## 2026-11-06 — v1.4.17 (2069) — #079 a worker order is delivered once

- Created the worker **Test Worker** with one **Shop gave · Gold 5** movement;
  Workers read **5.000 g metal reserve · 1 movement**.
- Saved a **Work order** for 5.000 g of gold (expected date left empty) — it
  appeared on the worker as **5.000 g · 06-11-26 · Pending**.
- Tapped it → **Deliver worker order** dialog, entered delivered weight
  **5.000** → **Deliver**. The order came back as **5.000 g · 06-11-26 ·
  delivered 5.000 g · Delivered**.
- Tapping the delivered row again does nothing, and the only “Deliver” left on
  screen is the word inside that row's own label — so a second delivery cannot
  be started from the UI at all. The store guard that backs this up
  (*“This order is already delivered.”*) is covered by unit tests.
- **Observation for the owner, not changed:** after delivery the worker still
  reads **5.000 g metal reserve**. `workerPositions()` sums worker movements
  only, and delivery posts finished stock without a matching “worker gave”
  movement, so a completed job leaves the issued metal sitting on the reserve.
  Decide whether delivery should close that reserve or whether the shop settles
  it by hand with a *Worker gave* movement.
- Harness note, so nobody chases it again: the earlier “cannot focus the name
  field” was a false alarm. The field did take focus; `dumpsys input_method`
  reports `mInputShown=false` while the numeric keypad is up, and drags that
  start inside that keypad never reach the list, which is why the form would not
  scroll to its Save button.

## 2026-11-06 — v1.4.17 (2069) — #082 offline sync message

- Built and installed over 2068 with data kept (`[db] open: SQLCipher
  encrypted, schema v21`).
- Tapping the home **Sync** action (the badge said *2 change(s) waiting*) showed
  **“Offline mode — sync needs a server login. Every change is already saved on
  this phone.”** instead of the old *“Sync failed: Not logged in”*.
- The drawer **Sync** tile now reads **Offline — changes stay on this phone**, and
  the Sync screen's Connection card adds **Mode: Offline — no server login**.
- Covered by `test/sync_offline_test.dart` (the state refuses a real sync with no
  client; the screen shows the offline notice and never says “Sync failed”).

## 2026-11-06 — v1.4.16 (2068) — #078 double delivery and over-return

- **Delivered once:** Orders → **ORD-20261106-0001** → **DELIVER ORDER** with
  the prefilled 8.000 g gross, 0 stone, no extra and no refund → the header
  turned **Delivered** and a **Delivery** card read *Delivered on 06-11-26 /
  gross weight 8.000 g / stone 0.000 g / net 8.000 g / difference 0.000 g*.
- **No second delivery path on the screen:** with the order Delivered,
  **Mark Ready**, **DELIVER ORDER** and **Receive payment** were all gone — the
  controls cannot be tapped again, and the store refuses a repeat delivery and
  a reopen in code (`test/jewellery_order_guards_test.dart`). The order list
  moved it out of **Pending**.
- **Over-return refused:** Credit Book → Ravi Kumar → **SAL-20261106-0001**
  (10.000 g gold) → **Return against this sale** → the weight was typed as
  **11.000 g** (the form priced it live at ₹72,864) → **SAVE RETURN** produced
  the snackbar **“Return is more than the weight still on this sale.”** and
  nothing was saved; the form stayed open so the number can be corrected.
- **Logcat:** no FATAL EXCEPTION during the delivery or the refused return.
- **Not covered:** a legitimate partial return followed by an over-return of
  what is left, and a second delivery attempted from a stale screen (only the
  store guard, with its tests, stands there).

## 2026-11-06 — v1.4.16 (2068) — #077 advance-only customer

- **Setup:** Jewellery → **New Sale**, fresh customer **Advance Test**, 1.000 g
  gold KDM, wastage 0, making ₹0 at the saved ₹7,200/g → **SAL-20261106-0003**
  ₹7,200. The dashboard then read ₹1,25,420 sales · ₹65,920 outstanding ·
  **3 open**, and Credit Book **₹65,920 due from 2 customers**.
- **Overpayment:** Credit Book → Advance Test → **Receive payment** was
  prefilled ₹7,200; typing **₹7,500** made the dialog read *“Receipt ₹7,500.
  Each invoice takes at most its balance; anything above it stays as a customer
  advance.”* After Save the header read **Billed ₹7,200 / Received ₹7,500 /
  Outstanding ₹0**, with **Payment received · SAL-…-0003 −₹7,200** and a
  separate **Advance received −₹300 · Customer advance** row in the ledger.
- **Then the sale was deleted** (document sheet → **Delete document → OK**),
  leaving no invoice and only the advance: header **Billed ₹0 / Received ₹300 /
  Outstanding ₹0 · 0 open invoices · 0 sales**.
- **The #077 case:** Credit Book listed
  **Advance Test — “Advance ₹300 held · no invoice” · ₹300 · advance** (green),
  with the strip reading **1 customer with dues · 2 in the book** and
  **Received ₹60,300** — the advance is counted once, not as a due.
- **Not covered:** the same state reached a day later (same code path) and a
  real shop customer instead of a test one. The Advance Test customer is left
  on the phone so the row can be re-checked.

## 2026-11-06 — v1.4.16 (2068) — #080 passphrase-protected backup key

- **Why a new build:** the installed v1.4.15 (2067) predated commit `c1c6d5c`;
  its key switch still warned *“Anyone who has this file could then open it.”*
  v1.4.16 / 2068 is the first install carrying the wrapped key. Installed in
  place with data kept: `[db] open: SQLCipher encrypted, schema v21`.
- **Create:** Backup & data → **Include database key** on (the subtitle now
  reads *“The key is locked with a passphrase you choose, so the file alone
  cannot open the ledger.”*) → **Create backup now** → **Protect the database
  key** asked for the passphrase twice → saved. The card read **Latest:
  jewellery_suite_2026-11-06_22-04-55.zip · 425 KB** and *Saved backups*
  went 9 → 10.
- **The archive is protected:** ⋮ → **Restore this backup** → **Restore**
  opened **Backup passphrase** with **Unlock** before anything was replaced —
  the archive carries `db_key_wrapped`, not a clear `db_key`.
- **Wrong passphrase refused:** the red snackbar read **“Restore failed: That
  passphrase does not open this backup.”** and the screen returned unchanged.
- **Correct passphrase restored:** the safety copy
  `jewellery_suite_2026-11-06_22-08-01.zip` was written first, then the
  database was replaced (`22:08:04 [db] open: SQLCipher encrypted, schema
  v21`). Afterwards the Jewellery dashboard read **₹1,18,220 sales · ₹60,000
  collected · ₹58,720 outstanding · 2 open**, rates Gold 7,200/g · Silver
  90/g, Orders **1 pending**, and Credit Book **₹58,720 due from 1 customer**
  with the ₹500 late-fee row intact.
- **Logcat:** no FATAL EXCEPTION and no Flutter exception during either
  restore.
- **Cleanup:** the passphrase archive was deleted (*Saved backups* back to
  10; the keyless safety copy kept), display rotation restored, phone left on
  Jewellery → Credit Book. The test passphrase is deliberately not recorded.
- **Noticed, not this item:** tapping the home **Sync** action while offline
  showed *“Sync failed: Not logged in”* even though the badge says
  “2 change(s) waiting”. Worth a numbered row next round.
- **Not covered:** restoring on a phone with a different keystore (the
  cross-phone case the passphrase exists for), and the PIN/admin-password
  rotation #080 still owes.

## 2026-11-06 — v1.4.15 (2067) — #074 receipt split, saved-rate chart, WIP

- **Rates:** saved **Gold 7,200/g** (92% → 6,624/g) and **Silver 90/g** on the
  jewellery dashboard; both cards showed the saved values after reopening the
  rate dialogs.
- **Two credit sales to one customer:** `SAL-20261106-0001` ₹79,260 (10 g gold,
  KDM, 8% wastage, ₹1,500 making) and `SAL-20261106-0002` ₹38,960 (5 g gold,
  KDM, 6% wastage, ₹800 making). The dashboard then read *“₹1,18,220 due from
  1 customer”*.
- **Split receipt:** Credit Book → Ravi Kumar → **Receive payment** listed both
  invoices prefilled with their balances (₹79,260 / ₹38,960). Entering
  **₹40,000** and **₹20,000** made the dialog read *“Receipt ₹60,000. Each
  invoice takes at most its balance; anything above it stays as a customer
  advance.”* Saving changed the header to **Billed ₹1,18,220 / Received ₹60,000
  / Outstanding ₹58,220**, and the ledger showed `-₹20,000` against
  `SAL-…-0002` and `-₹40,000` against `SAL-…-0001`.
- **WIP:** created `ORD-20261106-0001` for the same customer (8 g gold, KDM, 5%
  wastage, ₹2,000 making, ₹62,480 pending) because WIP was zero with no open
  orders.
- **Reports:** the **Saved gold rates** chart drew one bar (**7,200, 11/06**);
  Money card showed 2 invoices / ₹1,18,220 sales / ₹60,000 collections /
  ₹58,220 dues; Stock position showed **WIP · gold 8.000 g** and WIP · silver
  0.000 g; Order pipeline showed **Pending 1**.
- **Not covered:** nothing outstanding for #074. (Test data remains on the
  phone for the later passes.)

## 2026-11-06 — v1.4.15 (2067) — #065 mock gateway send + offline fallback

- Saved `http://10.52.61.21:8765/otp` as the **E-mail** gateway; the card
  confirmed *“Codes will be sent by e-mail.”*
- **Forgot admin password → Send code:** the phone showed **Code sent** (*“A
  6-digit code was sent to benwolf449@gmail.com. It is valid for 10 minutes.”*)
  and the mock received
  `{"to":"benwolf449@gmail.com","channel":"email","purpose":"admin_reset","code":"413578","message":"Jewellery Suite code 413578 — valid 10 minutes. …"}`.
  The dialog was cancelled, so the admin password was not changed.
- **Remove gateway:** the toast read *“Gateway removed — codes are shown on this
  phone.”* A second send showed **Offline code (valid 10 minutes) 390506** with
  the explanation that no gateway is configured.
- The mock was stopped afterwards and the phone’s gateway left unconfigured.
  **Still owed:** a real SMS/e-mail gateway URL and shared secret from the shop.

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
| #075 | A real sale with a **late fee**; the shared-expense split |
| #077 | An advance-only customer visible in the Credit Book |
| #078 | Create order → deliver → reopen/deliver refused; over-return refused |
| #079 | Deliver a worker order twice; second call refused |
| #080 | Create a backup with **Include database key** on, enter a passphrase, restore it and confirm the passphrase prompt; try a wrong passphrase and confirm it is refused. Rotate the PIN and admin password |
| #081 | Install a Crashlytics build, force one test crash, see it in the console |
