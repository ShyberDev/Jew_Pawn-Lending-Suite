# Task tracker

**One row per permanent item.** `README.md` is the dashboard; this file is the
authoritative list. Phone evidence lives in `VERIFICATION.md`; dated release
history lives in `CHANGELOG.md`.

**Status legend**

| Mark | Meaning |
|---|---|
| ✅ DONE | Written, tested, **and observed on the phone** (the observation is in `VERIFICATION.md`) |
| 🟨 CODE DONE | Written and tested, but the phone pass is still owed |
| 🟧 PARTIAL | Some of the item works on the phone; the rest is listed in the row |
| ⬜ BLOCKED / PLANNED | Needs an external input, or not started |
| 🔵 DEFERRED | Deliberately postponed |

> **Rule:** never change a 🟨 to ✅ without a dated phone observation. A green
> test suite is not a phone pass.

---

## 1. Foundation and audit fixes (#001–#039)

| # | Status | Area | Item | Outcome |
|---|---|---|---|---|
| **#001** | ✅ | Pawn | New Pawn Loan → SAVE | Blank ID takes the next free book number; `id_photo_front/back` column names fixed; save wrapped in try/catch with a spinner. |
| **#002** | ✅ | Khatabook | Customer Profile → You Gave → Add | Schema v15 adds `khatabook_given.payment_mode`; the amount is validated and failures are shown. |
| **#003** | ✅ | Khatabook | Ledger → refinance transfer | The transfer tile says **₹33,000 refinanced** with **New loan ₹63,000 · Fresh cash ₹25,000**; same-day rows order by entry time. |
| **#004** | ✅ | UI | Ledger balance line | `bal ₹…` → **`Bal ₹…`**. |
| **#005** | ✅ | Cashbook | Filters | Source (All / Khatabook / Pawn / Jewellery / Manual) and payment mode filters; the tally follows both. |
| **#006** | ✅ | Docs | Project tracking | This folder. |
| **#020** | ✅ | Reports | Khata → Overdue accounts | Uses `dueNowForReports()` (due + arrears), not the whole outstanding; 4 tests. |
| **#021** | ✅ | UI | Profile header, khata member header, schedule | Flexible money columns + `FittedBox`/ellipsis; widget tests at 320 dp and 2× text. |
| **#022** | ✅ | UI | Customer Profile app bar | Call / SMS / WhatsApp / Move / Edit moved into one ⋮ menu. |
| **#023** | ✅ | UI | Khata “No Due Date” filter | Renamed **No reminder**; the predicate was already correct. |
| **#024** | ✅ | Money | Every money figure | True lakh/crore grouping (`₹83,33,500`, not `₹8,333,500`). |
| **#025** | ✅ | Tests | `flutter test` | Migration teardown hang fixed; tests run with `TMPDIR=$PWD/.dart_tool/tmp`. |
| **#026** | ✅ | UI | Settings → Dark mode (Beta) | Remaining fixed inks replaced with `surfaceOf` / `mutedOf` / `inkOf` helpers. |
| **#027** | ✅ | Release | Release build signing | Local upload keystore + `android/key.properties` (both gitignored). |
| **#028** | ✅ | Release | Gradle signing guard | Release tasks fail loudly if the keystore or any of the four properties is missing. |
| **#029** | ✅ | Android | Manifest permissions | Audited; only `INTERNET` at the time. |
| **#030** | ✅ | Cashbook | Auto-entries | Editing/deleting a Khatabook or Pawn source row updates/removes its cashbook row. |
| **#031** | ✅ | Khatabook | Refinance | Fresh cash writes a `KHATA_REFINANCE` **OUT**; the rolled balance is a transfer, not cash. |
| **#032** | ✅ | Backup | Remove sample data | Also deletes linked cashbook rows; real rows untouched. |
| **#033** | ✅ | Pawn | Dashboard metal filter | `_metal` filters both the list and the summary strip. |
| **#034** | ✅ | UI | Pawn dashboard figures | Whole-rupee money, three-decimal weights. |
| **#035** | ✅ | Backup | Snapshot completeness | All v15 tables tracked (including `migration_log`); photo paths deduped. |
| **#036** | ✅ | Backup | Restore | In-app restore validates the archive, writes a safety copy, replaces DB + photos, reloads state. |
| **#037** | ✅ | Security | App start lock | Optional 4–6 digit PIN, salted hash, startup + background gate. |
| **#038** | ✅ | Security | Admin password | Forced first-run setup, minimum 6 characters, `admin` refused, salted hash. |
| **#039** | ✅ | About | APK size | Reads the installed package size through the `AppSize` channel. |

---

## 2. Accounts, cashbook, backup (#040–#049)

| # | Status | Area | Item | Outcome |
|---|---|---|---|---|
| **#040** | ✅ | Reminders | Due / overdue notifications | Settings switch; one 9:00 summary of who is collectable; Android 13+ permission; boot receiver re-arms. Phone-verified v1.2.0. |
| **#041** | ✅ | Reports | Export + charts | CSV → PDF → Excel, one Share sheet, six-month sales/purchases chart. Phone-verified v1.2.8 / v1.3.1 / v1.3.2. |
| **#042** | 🔵 | Security | HTTPS for server sync | Deferred until the server has TLS; certificate pinning later. |
| **#043** | ✅ | Jewellery | Full buy/sell/stock/valuation module | Schema v18–v20; sales/orders, purchases, credit book, payables, workers, returns, old metal, reports. Core phone-verified v1.3.0. |
| **#044** | ✅ | Cashbook | Manual row edit | Edit icon reopens the sheet pre-filled and saves over the same row; module rows are refused. Phone-verified v1.1.9. |
| **#045** | ✅ | Cashbook | Date-range view | Day / This month / All time / Range; the tally follows the filter. |
| **#046** | ✅ | Customer Profile | Payment mode on You Gave rows | The ledger note ends with the stored mode. Phone-verified v1.1.9. |
| **#047** | ✅ | Pawn | Metal / status / due-date filter | Due-date range uses the actual due date, falling back to the promised date; list and summary share the predicate. Phone-verified v1.4.4. |
| **#048** | ✅ | Backup | Automatic daily backup | One verified copy per day, newest 7 kept, manual copies never pruned. Phone-verified v1.2.6. |
| **#049** | ✅ | Security | Encrypted local DB | SQLCipher with a keystore-held key; plaintext migrated once; schema version carried across; backup/restore round-trip verified v1.4.4. |

---

## 3. Pawn UI, passwords, OTP (#050–#065)

| # | Status | Area | Item | Outcome |
|---|---|---|---|---|
| **#050** | ✅ | UI | Collection reminder | Removed the duplicate **Calendar…** chip; four quick choices + **Pick date**. |
| **#051** | ✅ | Pawn | Loan rows | Photo, name + village, ID / loan date / item / amount; falls back to the customer’s village. |
| **#052** | ✅ | Pawn | Customer Pawn Profile | Consolidated expandable details, six-field loan section, full-screen photo viewer, reordered actions. |
| **#053** | ✅ | Pawn | Villages filter | Filter row is Active · Released · Villages ▾; **All villages** lives inside the menu. |
| **#054** | ✅ | Login | Offline login | A fresh install with an existing local ledger no longer demands a server login. |
| **#055** | ✅ | Home | Customers Book | Drawer tile and screen title both say **Customers Book**. |
| **#056** | ✅ | Settings | Ask password for delete / release | Removed the duplicate switch from Settings; it lives only in Password Settings. |
| **#057** | ✅ | Login | One shop account | Gmail or mobile + salted password hash; password or one-time code; stays signed in until Logout. |
| **#058** | ✅ | Passwords | Forgot password for every secret | Admin, login and PIN/MPIN each have **Forgot …?** → 6-digit code → new secret. |
| **#059** | ✅ | Security | Password Settings | Biometric & screen lock moved into Password Settings; Daily MPIN; per-secret enable switches. |
| **#060** | ✅ | Pawn | Loan tiles | Two-row layout: photo + name + amount, then ID badge, village, date, item; sync cloud restored. |
| **#061** | ✅ | Pawn | Tile caller menu | ⋮ / long-press → Call · SMS · WhatsApp · Move · Edit. |
| **#062** | ✅ | Pawn | Custom categories | Categories ▾ seeded with Forgot_Slip_List and Pawn_Removed; add, rename, multi-move. |
| **#063** | ✅ | Pawn | Filters / search | Tap a selected chip to clear; search matches name, book ID, amount, phone or village; date range. Phone-verified v1.2.2. |
| **#064** | ✅ | Database | Schema v16 | `pawn_loans.category` + `pawn_categories`; backups track the table; restore keeps account + lock settings. Phone-verified v1.2.3. |
| **#065** | 🟧 | OTP | Real SMS / Gmail codes | Gateway URL + channel; POST `{to, channel, purpose, code, message}`; 2xx = sent; on-screen fallback. **Mock send phone-verified 2026-11-06** (payload received, fallback shown after Remove gateway). **Real gateway still blocked** on the shop URL + shared secret; setup guide in `docs/SETUP_OTP_GATEWAY.md`. |

---

## 4. Security, dialler, reports, sync (#066–#072)

| # | Status | Area | Item | Outcome |
|---|---|---|---|---|
| **#066** | ✅ | Security | Fingerprint / face unlock | `local_auth` + `FlutterFragmentActivity`; fails closed; PIN always available. Phone-verified v1.3.5. |
| **#067** | ✅ | Pawn | Tile spacing | Removed the wide name/ID/menu gap; row 1 is photo + name + amount; row 2 is the gold ID badge, village, date, item. |
| **#068** | ✅ | Pawn | Tile actions | All five caller actions appear; KYC & details stay inside the pawn profile. Phone-verified. |
| **#069** | ✅ | Pawn | Loan details | Promised due date, actual due date, and outstanding tied to the actual date. |
| **#070** | ✅ | Customers | Indian mobile numbers | One rule: 10 digits or `+91` + 10 digits; `tel:`/`sms:`/`wa.me` always carry `+91`. Phone-verified v1.4.4. |
| **#071** | ✅ | Reports | Khata in the Pawn layout | Period / Loans filters, six metric cards, collections list, All-time card, one Share → PDF / Excel / CSV. Phone-verified v1.4.4. |
| **#072** | ⬜ | Sync | Google Drive backup + multi-device sync | Designed; blocked on the **Web client ID** from Google Cloud. Setup: `docs/SETUP_GOOGLE_DRIVE_OAUTH.md`; design: `docs/GOOGLE_DRIVE_SYNC.md`. |

---

## 5. Latest rounds (#073–#081)

| # | Status | Area | Item | Outcome |
|---|---|---|---|---|
| **#073** | ✅ | UI | Dark-mode ink debt | Every leftover fixed near-black label uses `inkOf(context)`; light mode unchanged. Phone-verified v1.4.5. |
| **#074** | ✅ DONE | Jewellery | Workflow checklist | **Phone 2026-11-06:** saved Gold ₹7,200/g + Silver ₹90/g; two credit sales to Ravi Kumar (₹79,260 + ₹38,960 = ₹1,18,220 due); **Receive payment** split ₹40,000 / ₹20,000 as one ₹60,000 receipt → outstanding ₹58,220; Reports saved-rate chart showed 7,200 (11/06) and WIP · gold 8.000 g after an open 8 g order. Evidence in `VERIFICATION.md`. |
| **#075** | ✅ | Jewellery | Drafts, shared expenses, late fees | Schema v21; draft purchase posts nothing until **Confirm purchase**; shared expense splits by net weight; late fee raises only the balance. **Phone v1.4.16–v1.4.17, 2026-11-06:** the fee dialog was used live (#076, ₹500 fee survived a payment), a draft posted stock only on confirm, and a two-line purchase with one **₹400** shared expense stored **Additional ₹100 / ₹300** on the lines (evidence in `VERIFICATION.md`). |
| **#076** | ✅ | Jewellery | Late fee / draft money defects | Payments use `total + late_fee_total − paid`; drafts excluded from every aggregate; fee row keys on `debit > 0`. Phone-verified v1.4.9 / v1.4.10. |
| **#077** | ✅ | Jewellery | Advance-only customers | Credit Book appends advance parties with no invoice; tile reads **Advance ₹X held · no invoice**. **Phone v1.4.16, 2026-11-06:** a ₹7,500 receipt against a ₹7,200 sale kept **₹300** as an advance row, and after the sale was deleted the Credit Book tile read **Advance ₹300 held · no invoice** with the strip counting the money once (evidence in `VERIFICATION.md`). |
| **#078** | ✅ | Jewellery | Double delivery / over-return | Delivered orders cannot be delivered or reopened; returns cannot exceed the remaining weight. **Phone v1.4.16, 2026-11-06:** an order delivered once (8.000 g, difference 0.000 g) lost its **Mark Ready / DELIVER ORDER** controls, and an **11.000 g** return against a 10.000 g sale was refused with *“Return is more than the weight still on this sale.”* (evidence in `VERIFICATION.md`). |
| **#079** | ✅ | Jewellery | Worker order delivered twice | A second delivery is refused before any stock or payment write. **Phone v1.4.17, 2026-11-06:** worker **Test Worker** got a 5 g issue, a 5.000 g order read **Pending**, delivery produced **delivered 5.000 g · Delivered**, and the delivered row is not tappable and offers no Deliver control, so a second delivery cannot start (evidence in `VERIFICATION.md`). The reserve that kept the issued metal after delivery was fixed in **#083**. |
| **#080** | 🟧 | Android | Platform backup / archive key / credentials | `allowBackup=false`, `fullBackupContent=false`, `dataExtractionRules` exclude everything; manifest test. Archive key is **opt-in** and **passphrase-wrapped** (PBKDF2-HMAC-SHA256 + HMAC-CTR; no clear-text `db_key`); restore prompts for the passphrase. Covered by `test/backup_manifest_test.dart` (6 cases); tracked credentials moved to a gitignored local file. **Phone v1.4.16, 2026-11-06:** passphrase backup created, restore asked for the passphrase, a wrong one was refused with *“That passphrase does not open this backup.”*, the right one restored behind a safety copy with the ledger intact (evidence in `VERIFICATION.md`). **Credentials:** live in `PASSWORDS.md` and were rotated once on 2026-11-07 (old PIN answered *“Wrong PIN. Try again.”*); **do not rotate them again** — the shop asked for one readable file instead. **Open:** cross-phone restore (different keystore) still untried; only one device is attached to adb. |
| **#081** | ⬜ | Tooling | Firebase crash reports + test distribution | Crashlytics + App Distribution only; no Firestore/Storage for ledger data. Blocked on a Firebase project. Setup: `docs/SETUP_FIREBASE.md`. |
| **#086** | ✅ | Security | Dialog controllers disposed mid-animation | Every shared prompt disposed its `TextEditingController` in a `finally` as soon as `showDialog` returned, while the route was still animating out and rebuilding its `TextField`; the new #085 test surfaced *“A TextEditingController was used after being disposed”*. `askPinDialog`, `askNewPinDialog`, `askNewPasswordDialog` and `askOtpCodeDialog` now each own their controller in a `State`, the pattern `_PasswordPrompt` already used; titles, labels, buttons and toast messages are unchanged. Covered by the 10 cases in `test/app_lock_gate_test.dart`, suite **529 passing**. **Phone v1.4.22 / 2074, 2026-11-07:** every prompt opened and closed cleanly — logcat held no *“used after being disposed”* and no Navigator error. |
| **#085** | ✅ | Security | Lock screen → **Send code** left the reset dead | On v1.4.20, **Forgot PIN?** → **Send code** closed the dialog and then showed nothing — no code box, no error — for 15 s or more, so a forgotten PIN could not be reset on the phone. v1.4.22 keeps a **“Sending the code…”** dialog up while the code is issued and the gateway is posted to, falls back to the on-screen code when the send fails, and drops the keypad so **Forgot PIN?** stays reachable. Covered by a new case in `test/app_lock_gate_test.dart` (10 in the file). **Phone v1.4.22 / 2074, 2026-11-07:** **Send code** raised **Enter the 6-digit code** with the offline code `996410`; a wrong `111111` was refused with *“The code is wrong or has expired. Try again.”*, the phone stayed locked and the keypad stayed down. |
| **#084** | ✅ | Security | Lock screen → Forgot PIN? did nothing | The gate rendered the lock screen in a bare `Overlay` above `MaterialApp`'s Navigator, so `showDialog` threw *“Navigator operation requested with a context that does not include a Navigator”* and the button was dead. The gate now gives the lock screen its own `Navigator`, the dialog title is **Forgot PIN** / **Forgot Daily MPIN** instead of *“Forgot always”*, and a phone with no Gmail / mobile account is asked for the **admin password** instead of being told to create an account it cannot reach. Both OTP dialogs are `scrollable` so the keypad cannot hide their buttons. Covered by 2 new cases in `test/app_lock_gate_test.dart` (7 in the file). **Phone v1.4.20 / 2072, 2026-11-07:** **Forgot PIN?** opened a dialog titled **Forgot PIN** — *“Reset the screen lock on this phone.”* — addressed to `benwolf449@gmail.com` with **Cancel · Send code**, and logcat held no Navigator exception. The reset itself was not completed, so the PIN was not rotated; the admin-password fallback was not exercised (evidence in `VERIFICATION.md`). |
| **#083** | ✅ | Jewellery | Worker reserve + order delete | Delivering a work order puts its finished weight into stock, so `workerPositions()` now subtracts the delivered net weight from the worker's metal/fine reserve; before this a completed job held the issued metal for ever. `deleteWorkerOrder` removes the order with its `WORKER_ORDER_IN` movement and a trash control sits on the order row. Covered by 3 tests in `test/jewellery_operations_test.dart`; **phone v1.4.18–v1.4.19, 2026-11-07:** the same delivered 5 g order read **0.000 g / settled** instead of 5.000 g, and deleting it returned 5.000 g, then deleting the issue left **0 workers · 0.000 g**. |
| **#090** | ✅ | Jewellery | Invoice PDF | **Share PDF** in the document sheet hands a one-page PDF bill to the share sheet via `SharePlus` files, with a timestamped name (`jewellery_suite_bill_<doc>_<stamp>.pdf`). Rows are shared with the CSV export (`jewelleryBillRows`) and the text bill (#087); Tamil names render with the bundled fonts. Covered by `test/jewellery_bill_pdf_test.dart` (4 cases); suite **542 passing**. **Phone v1.4.26 / 2078, 2026-11-08:** **Share PDF** on `SAL-20261106-0001` opened the share sheet with `jewellery_suite_bill_SAL-20261106-0001_2026-11-08_21-42.pdf` as the file; dismissing left Balance ₹39,760 unchanged (evidence in `VERIFICATION.md`). |
| **#088** | ✅ | Jewellery | WIP-overdue banner | The dashboard shows an amber **“N overdue orders · X g WIP”** banner when any Pending/Ready order’s promised date has passed; tap opens Orders. Same overdue rule as the Orders list (`lib/util/overdue_orders.dart`); WIP from `wipWeight()`. Covered by `test/overdue_orders_test.dart` (3 cases); suite **538 passing**. **Phone v1.4.25 / 2077, 2026-11-08:** new order `ORD-20261108-0001` promised 07-11-26 made the dashboard read **“1 overdue order · 12.520 g WIP / Promised date has passed”**, and tapping it opened Customer Orders showing the OVERDUE row (evidence in `VERIFICATION.md`). |
| **#089** | ✅ | Jewellery | Late-fee auto-suggest | The **Add late fee** dialog pre-fills with the last fee charged on that invoice (`late_fee_total`) and a hint shows the sale's age in days — no rate is invented, the shopkeeper edits the amount. Pure helper `lib/util/late_fee_suggest.dart`; covered by `test/late_fee_suggest_test.dart` (3 cases); suite **535 passing**. **Phone v1.4.24 / 2076, 2026-11-08:** **Add late fee** on `SAL-20261106-0001` (06-11-26, fee ₹500 already) opened with **500** filled and the hint *“Sale was 2 days ago (06-11-26).”*; dismissing left Late fee ₹500 / Balance ₹39,760 unchanged (evidence in `VERIFICATION.md`). |
| **#082** | ✅ | Sync | Offline sync message | The home Sync button and Sync → **Sync now** answered *“Sync failed: Not logged in”* although offline mode is the normal state. They now say **“Offline mode — sync needs a server login. Every change is already saved on this phone.”**, the drawer tile reads **Offline — changes stay on this phone** and the Sync card adds **Mode: Offline — no server login**. Covered by `test/sync_offline_test.dart` (2 cases); **phone v1.4.17, 2026-11-06** showed the new snackbar. |
| **#087** | ✅ | Jewellery | Share invoice | **Share invoice** in the document sheet hands a plain-text bill (party, doc, item lines, payable, received/paid, late fee, balance, payments) to Android's share sheet via `SharePlus`, matching the sheet's own `fmtDate`/`inr` figures. Drafts offer no share button. Covered by `test/jewellery_bill_text_test.dart` (3 cases); suite **532 passing**. **Phone v1.4.23 / 2075, 2026-11-07:** **Share invoice** on `SAL-20261106-0001` opened the share sheet with *“Ravi Kumar · SAL-20261106-0001 / 06-11-26 · Sale · GOLD / Gold chain · 10.000 g · 92.00% · ₹7,200/g / KDM · wastage 0.800 g · billing 10.800 g × ₹7,200 = ₹77,760 · making ₹1,500 / ₹79,260”*; dismissing left Balance ₹39,760 unchanged (evidence in `VERIFICATION.md`). |

---

## 6. Internal codes (#06A–#06J)

These were the shop’s short-lived codes for the pawn-UI round. They are kept so
old notes and commit messages still resolve.

| # | Status | Area | Item | Outcome |
|---|---|---|---|---|
| **#06A** | ✅ | Pawn | Move to another pawn profile | The move asks its own password (defaults to the admin secret, swappable in Password Settings), then moves one or many loans. Phone-verified v1.2.5. |
| **#06B** | ✅ | Pawn | Categories | Seeded defaults; **Add Custom**; rename keeps loans attached. Phone-verified v1.2.3. |
| **#06D** | ✅ | Pawn / Khata | Drag-to-delete bin | Root cause was the gesture arena: the inner long-press won, so the drag never started. The bin now deletes; covered by two tests. |
| **#06E** | ✅ | Security | Delete / Release prompt | Asks the MPIN first, falls back to the admin password when no MPIN is set. Phone-verified. |
| **#06F** | ✅ | Passwords | Password Settings copy | The card now describes the MPIN step, not the old admin-password step. Phone-verified. |
| **#06G** | ✅ | Pawn | Amount-range filter | From/To dialog, open-ended either side, Clear. Phone-verified v1.1.7. |
| **#06H** | ✅ | Pawn | KYC return to loan form | Returning from **+ KYC** fills the visible customer name, so SAVE succeeds. Phone-verified v1.1.7. |
| **#06I** | ✅ | Pawn | Release button label | The release confirmation says **Release**, not **Delete**. Phone-verified v1.1.7. |
| **#06J** | ✅ | Pawn | Sync cloud + ⋮ icon | Gold `cloud_upload` badge and a visible caller icon on every tile. Phone-verified v1.1.8. |
