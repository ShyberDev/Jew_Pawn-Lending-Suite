# Change log

Dated history, newest first. Each entry records what changed, the build number,
the phone pass, and anything deliberately left open. The task list itself lives
in `TRACKER.md`; this file is the narrative.

---

### 2026-11-08 — #088 WIP-overdue banner (code done, phone pass owed)

- The jewellery dashboard now shows an amber **“N overdue orders · X g WIP”** banner above the Orders/Workers row when any Pending/Ready order’s promised date has passed; tap opens Orders. Hidden when zero overdue — the dashboard is otherwise unchanged.
- Overdue uses the same rule as the Orders list (new pure helper `lib/util/overdue_orders.dart`); WIP comes from the existing `wipWeight()` store query Reports uses.
- **Checks:** `test/overdue_orders_test.dart` 3 cases (pending yesterday overdue, today/future not, delivered/cancelled/date-less never); `flutter analyze` clean; full suite **538 passing**.
- **Phone v1.4.25 / 2077:** dashboard showed **“1 overdue order · 12.520 g WIP / Promised date has passed”** after creating `ORD-20261108-0001` promised 07-11-26; tapping it opened Customer Orders. Evidence in `VERIFICATION.md`.

### 2026-11-08 — #089 late-fee dialog pre-fills from the invoice's history (code done, phone pass owed)

- **Add late fee** now opens with the fee field already filled when the invoice has a previous fee (`late_fee_total` — the repeat-fee case), plus a hint line with the sale's age: *“Sale was N days ago (DD-MM-YY).”* or *“Sale made today.”* With no history the field stays blank but the age hint still shows. No per-day rate is invented — the shopkeeper edits the amount.
- **Checks:** `test/late_fee_suggest_test.dart` 3 cases (previous fee suggested, blank when no history, same-day = 0 days); `flutter analyze` clean; full suite **535 passing**.
- **Phone v1.4.24 / 2076:** **Add late fee** on `SAL-20261106-0001` opened with **500** filled and *“Sale was 2 days ago (06-11-26).”*; dismissing left Late fee ₹500 / Balance ₹39,760 unchanged. Evidence in `VERIFICATION.md`.

### 2026-11-07 — #087 invoice share (code done, phone pass owed)

- Added **Share invoice** to the jewellery document sheet. It builds a plain-text bill in a new pure helper (`lib/util/jewellery_bill_text.dart`) using the sheet's own `fmtDate`/`inr` figures — party, doc number, each item line with KDM/non-KDM/weight detail, Payable, Received/Paid, Late fee when present, Balance and the payments list — and hands it to Android's share sheet via `SharePlus`. Drafts offer no share button; dismissing the sheet writes nothing.
- **Checks:** `test/jewellery_bill_text_test.dart` 3 cases (sale figures, Paid vs Received, late fee + payments); `flutter analyze` clean; full suite **532 passing**.
- **Phone v1.4.23 / 2075:** **Share invoice** on `SAL-20261106-0001` opened the share sheet with the correct bill text; dismissing left Balance ₹39,760 unchanged. Evidence in `VERIFICATION.md`.

### 2026-11-07 — #086 dialogs used their text controller after disposing it (v1.4.22)

- **Found by the new #085 test:** every shared prompt disposed its
  `TextEditingController` in a `finally` as soon as `showDialog` returned. The
  dialog route is still animating out and rebuilds its `TextField` at least once
  more, so closing threw *“A TextEditingController was used after being
  disposed”*.
- **The fix:** `askPinDialog`, `askNewPinDialog`, `askNewPasswordDialog` and
  `askOtpCodeDialog` now own their controllers in a `State` — the pattern
  `_PasswordPrompt` in the same file already used. Public behaviour is unchanged:
  same titles, labels, buttons and toast messages.
- Tests: `test/app_lock_gate_test.dart` **10 passed**, full suite **529 passing**,
  `flutter analyze` clean.
- **Not yet seen on the phone** — same install as #085 (**1.4.22 / 2074**).

### 2026-11-07 — #085 “Send code” closed the reset (v1.4.21)

- **Found on the phone** while passing #084 on v1.4.20: the lock screen's
  **Forgot PIN?** → **Send code** closed the dialog and left nothing on screen —
  no code box, no error — for 15 s or more, so a shop that forgot its PIN could
  not reset it.
- **The bug:** the send step awaits the code issue and the gateway POST (12 s
  timeout) with nothing on screen, and the dialog has already closed by then; an
  error in that step ended the reset silently.
- **The fix:** a **“Sending the code…”** progress dialog covers the exchange, and
  a failed send issues a fresh code and shows the offline code instead of dropping
  the reset. The lock screen also drops the keypad while the reset dialogs are
  open, so **Forgot PIN?** stays reachable.
- Tests: new case *“Forgot PIN with an account asks for the code and shows it
  offline”* in `test/app_lock_gate_test.dart` (**8 in the file**), suite **527
  passing**; `flutter analyze` clean.
- **Not yet seen on the phone** — the phone left the network before v1.4.21 could
  be installed, so the item is 🟨.

### 2026-11-07 — #084 “Forgot PIN?” was a dead button (v1.4.20)

- **Reported by the shop:** the lock screen's **Forgot PIN?** did nothing.
- **The bug:** `AppLockGate` builds the lock screen *above* `MaterialApp`'s
  Navigator (that is how it covers pushed routes). It rendered it inside a bare
  `Overlay`, which gives text fields their handles but has **no Navigator**, so
  `showDialog` threw *“Navigator operation requested with a context that does not
  include a Navigator”* and the tap vanished. Nothing was logged on screen.
- **The fix:** the gate now hands the lock screen its own `Navigator`; a Navigator
  contains an Overlay, so the PIN field keeps working and dialogs have somewhere
  to open.
- **Second defect, same button:** with no Gmail / mobile account the flow only
  said *“No account registered → create it in Password Settings”*, which the lock
  screen cannot reach — a lockout. It now asks the **admin password** in that
  case, the same secret the delete / release prompts use.
- **Copy:** the dialog title was `'Forgot $mode'`, so it read *“Forgot always”* or
  *“Forgot daily”*. It now reads **Forgot PIN** / **Forgot Daily MPIN**.
- **Layout:** both OTP dialogs are `scrollable`, so a 6-digit keypad can no longer
  push **Send code** / **Verify** off a phone screen.
- Tests: 2 new cases in `test/app_lock_gate_test.dart`, suite **526 passing**.
- **Phone v1.4.20 / 2072, 2026-11-07:** **Forgot PIN?** opened a dialog titled
  **Forgot PIN** — *“Reset the screen lock on this phone.”* — addressed to
  `benwolf449@gmail.com` with **Cancel · Send code**; logcat held no Navigator
  exception. The reset was not completed, so the PIN was not rotated, and the
  admin-password fallback was not exercised. Evidence in `VERIFICATION.md`.

### 2026-11-07 — #083 worker reserve follows delivery; delivered orders can be deleted (v1.4.18–1.4.19)

- **The bug:** `workerPositions()` summed worker movements only. Delivery posts
  the finished weight into stock but writes no worker movement, so a completed job
  left the issued metal on the reserve for ever — the #079 pass showed 5.000 g
  still held after a 5.000 g delivery.
- **The fix:** the reserve subtracts the delivered net weight of delivered orders.
  The weight already lives on the order, so no extra movement is written and
  deleting the order reverses it. Delivered metal is booked into stock at 100%, so
  the fine reserve falls by the same grams.
- **A short delivery keeps the shortfall** on the reserve (5 g issued, 4 g net
  delivered → 1 g still held), which is what the shop is owed or lost.
- **New:** `deleteWorkerOrder` removes the order with its `WORKER_ORDER_IN` stock
  movement, and the order row gained a trash control with a confirm dialog.
- Tests: 3 new cases in `test/jewellery_operations_test.dart` (reserve on
  delivery, short delivery, delete undoes stock). Suite **524 passing**.
- **Clean-up:** the test purchase and the Test Worker were removed from the phone;
  a ₹300 advance cannot be deleted because receipts have no delete path outside
  their invoice.
- **Credentials:** PIN and admin password rotated once, then documented in
  `PASSWORDS.md` with a standing rule that agents must not rotate them.

### 2026-11-06 — #075 shared-expense split phone-verified (v1.4.17)

- One purchase, two gold lines (10.000 g and 30.000 g) and one **Shared expense
  ₹400**. The preview read **Payable ₹2,65,360**, and the saved document carried
  **Additional ₹100** on the 10 g line and **₹300** on the 30 g line — the net
  weight ratio 9.2 : 27.6, with the amount stored once on the document.
- With the fee dialog already exercised live in #076 (a ₹500 fee survived a
  ₹1,000 receipt) and drafts confirmed onto stock in the same pass, #075's
  three behaviours have now all been seen on the device.
- No code changed; evidence is in `VERIFICATION.md`.
- **#079 (worker double delivery) passed in the same session** on the same
  build: worker **Test Worker** was issued 5 g, a 5.000 g work order went
  **Pending** → **delivered 5.000 g · Delivered**, and the delivered row is no
  longer tappable, so a second delivery cannot start. Still open for the owner:
  the worker's metal reserve keeps the issued 5.000 g after delivery (see
  `VERIFICATION.md`).

### 2026-11-06 — #082 offline Sync message (v1.4.17 / 2069)

- **The bug:** this shop runs offline, where `AppState.api` is null. The home
  Sync button and Sync → **Sync now** both surfaced the raw exception, so an
  offline shop was told *“Sync failed: Not logged in”* while the badge said two
  changes were waiting — a failure where there was only a normal state.
- **The fix:** `AppState.canSync` reports whether a server session exists, and a
  shared `offlineSyncNotice` explains the situation. Both entry points check it
  before calling `sync()`, the drawer tile reads **Offline — changes stay on
  this phone**, and the Sync card shows **Mode: Offline — no server login**. The
  guard changes no data path: a sync with no client still throws, so nothing
  pretends to have synced.
- **Checks:** `flutter analyze` → **No issues found**; full suite **520 passing,
  exit 0** (new `test/sync_offline_test.dart`, 2 cases); APK
  `mobile/jewellery_suite_v1.4.17-arm64-v8a.apk`, **45,727,292** bytes, SHA-256
  `11104475e279eb1a5e0fc3f4ae48ca692cc66cd0f6e5917e97925bcf9dc0af1e`,
  installed in place over 2068 with data kept; the new snackbar was read on the
  phone.

### 2026-11-06 — #078 double delivery and over-return phone-verified (v1.4.16)

- Delivered **ORD-20261106-0001** once (8.000 g gross, no stone, difference
  0.000 g). Afterwards the order screen offered no **Mark Ready** and no
  **DELIVER ORDER**, so the second delivery that used to double the stock and
  the payment has no way to be started.
- Typed an **11.000 g** return against a **10.000 g** sale: the form priced it
  live, but **SAVE RETURN** refused with *“Return is more than the weight still
  on this sale.”* and nothing was written.
- No code changed; evidence is in `VERIFICATION.md`.

### 2026-11-06 — #077 advance-only customer phone-verified (v1.4.16)

- Made a ₹7,200 sale to a test customer, received **₹7,500**, and watched the
  extra **₹300** land as an *Advance received* ledger row instead of being
  refused or inflating the payment. Deleting the sale afterwards left the
  customer with no invoice — and the Credit Book tile then read **“Advance ₹300
  held · no invoice” · ₹300 · advance**, which is exactly the hole #077 closed.
- The strip counted the money once (**Received ₹60,300**, **1 customer with
  dues · 2 in the book**), so the advance is neither hidden nor double-counted.
- No code changed; the write-up is in `VERIFICATION.md`.

### 2026-11-06 — #080 passphrase backup key phone-verified (v1.4.16 / 2068)

- **A new build was needed:** the installed v1.4.15 (2067) predated commit
  `c1c6d5c`, so its key switch still warned *“Anyone who has this file could
  then open it.”* v1.4.16 / versionCode 2068 is the first install that carries
  the wrapped key; `pubspec.yaml` is now `1.4.16+68`.
- **Phone pass:** with **Include database key** on, **Create backup now** asked
  for the passphrase twice and produced a verified 425 KB archive (9 → 10).
  Restoring it asked for **Backup passphrase** before replacing anything — proof
  the archive carries `db_key_wrapped` rather than a clear `db_key`. A wrong
  passphrase failed with *“Restore failed: That passphrase does not open this
  backup.”*; the right one wrote the safety copy
  `jewellery_suite_2026-11-06_22-08-01.zip` and restored, leaving **₹1,18,220 /
  ₹60,000 / ₹58,720** with the late-fee row, saved rates and the pending order
  intact. Logcat showed no FATAL EXCEPTION.
- **Checks:** `flutter analyze` → **No issues found**; full suite **518 passing,
  exit 0**; APK `mobile/jewellery_suite_v1.4.16-arm64-v8a.apk`,
  **45,727,292** bytes, SHA-256
  `347ed3bbff45aa7af3ac8e4f4b73c391f82088a768a3fd1542a1d44ca93742d2`,
  installed in place over 2067 with data kept. The passphrase archive was
  deleted after the test.
- **Still owed:** rotate the PIN/admin password tracked in public git, and try
  a restore on a phone with a different keystore.
- **Noticed:** the home **Sync** action answers *“Sync failed: Not logged in”*
  while offline although the badge shows “2 change(s) waiting”.

### 2026-11-06 — #074 receipt split, saved-rate chart and WIP verified on the phone

- Saved **Gold ₹7,200/g** and **Silver ₹90/g**, then made two credit sales to
  Ravi Kumar (`SAL-…-0001` ₹79,260; `SAL-…-0002` ₹38,960). The dashboard read
  **₹1,18,220 due from 1 customer**.
- **Receive payment** listed both invoices; entering ₹40,000 and ₹20,000 produced
  one **₹60,000** receipt. After saving, the header read **Billed ₹1,18,220 /
  Received ₹60,000 / Outstanding ₹58,220**, and each payment was attached to its
  own invoice in the ledger.
- Created `ORD-20261106-0001` (8 g gold, ₹62,480 pending) so the report’s WIP
  rows had data: **WIP · gold 8.000 g**, and the **Saved gold rates** chart
  drew **7,200 (11/06)**. Order pipeline showed **Pending 1**.
- Evidence is in `VERIFICATION.md`.

### 2026-11-06 — #080 archive key is passphrase-wrapped

- The **Include database key** switch no longer writes `db_key` in clear text. When it is on, the shop is asked for a passphrase (6+ characters, typed twice); the SQLCipher key is wrapped with **PBKDF2-HMAC-SHA256** (120,000 iterations) + an **HMAC-SHA256 counter stream** and an HMAC tag, and stored as `db_key_wrapped`. Restoring an archive that carries one asks for the passphrase and refuses a wrong one with *“That passphrase does not open this backup.”*
- Same-phone restores still need no passphrase: the live key never leaves the Android keystore. Legacy archives with a clear-text `db_key` still restore.
- **Checks:** `test/backup_manifest_test.dart` now has 6 cases (no key by default, passphrase required, wrapped round-trip, wrong passphrase, damaged block, 64-character key); `flutter analyze` clean; full suite **518 passing, exit 0**.
- **Still owed:** the phone pass for the passphrase backup/restore, and rotating the PIN/admin password that were tracked in public git.

### 2026-11-06 — #065 mock gateway send verified on the phone

- Saved a local mock (`http://10.52.61.21:8765/otp`) as the E-mail gateway, then used **Forgot admin password → Send code**. The phone showed **Code sent**, and the mock received the full contract payload (`to`, `channel`, `purpose`, `code`, `message`) with a 6-digit code. The reset dialog was cancelled, so no secret changed.
- **Remove gateway** restored the offline path: the toast read *“Gateway removed — codes are shown on this phone”*, and the next send displayed **Offline code (valid 10 minutes)** with the code on-screen.
- **Still owed:** the shop’s real SMS/e-mail gateway URL and shared secret. The mock is not part of the app.

### 2026-11-06 — #080 archive key is opt-in; tracker folder rebuilt

- **The archive key no longer travels by default.** `BackupService.buildManifest` only writes `db_key` when the caller passes one, and `createBackup` defaults `includeKey` to `false`. The Backup & data screen gained an **Include database key** switch (off by default) with the warning that anyone holding the file could open it. A restore without a key now says plainly that the archive was made without the database key instead of failing obscurely. Same-phone restores keep working because the SQLCipher key stays in the Android keystore.
- **Checks:** new `test/backup_manifest_test.dart` (2 cases — key absent by default, present only when opted in); `flutter analyze` clean; full suite **514 passing, exit 0**.
- **Open:** the shop passphrase/rotation decision is still needed before a backup is moved between shops; the new switch needs a phone pass.
- **Tracker folder rebuilt.** The 926-line README was split into `TRACKER.md` (one row per item), `VERIFICATION.md` (dated phone evidence), `CHANGELOG.md` (this narrative), `HANDOFF.md` (phone, secrets pointer, traps, rules) and a short `README.md` dashboard. The two reference documents became `SPEC_JEWELLERY.md` and `CALCULATIONS.md`; `agent_readme.md`, `COORDINATION.md` and `Temp_Passwords_readme.md` were retired after their unique content was merged here or moved to the gitignored `.secrets.local.md`. The obsolete 95 MB APK in `.tmp_apk/` was deleted.

### 2026-11-05 — #080 security pass: platform backup closed, two risks recorded (v1.4.14)
- **Fixed — Android platform backup was on by default.** With no `allowBackup` in the manifest, the OS could copy the app's data (including the encrypted ledger) to cloud backup and device transfer. That is a privacy leak for a pawn shop, and the restored copy is useless anyway because the SQLCipher key lives in the Android keystore and is never backed up. The manifest now sets `allowBackup="false"`, `fullBackupContent="false"` and `dataExtractionRules` from a new `res/xml/data_extraction_rules.xml` that excludes root, database, sharedpref, file and external for **both** cloud backup and device transfer.
- **Verified in the artifact, not the source:** `aapt2 dump xmltree … AndroidManifest.xml` on the built APK reports `allowBackup=false`, `fullBackupContent=false`, `dataExtractionRules=@0x7f110000`. `test/manifest_security_test.dart` (2 cases) fails if any of that is removed.
- **OPEN — the backup ZIP carries its own key.** `backup_service.dart` writes `db_key` into the archive manifest (`#049`), so a stolen backup is decryptable. Fixing it needs a user secret (PIN-derived key wrap) plus prompts in the backup and restore flows; breaking a working restore path without a device test would be worse, so it is recorded here for the next round.
- **OPEN — credentials are tracked in the repo.** `APK_Project_Progress/Temp_Passwords_readme.md` (19.8 KB) is in git and holds the shop's dev credentials. It must be deleted before handover; it was left untouched because it may be the shop's only reference.
- **Crash sweep (v1.4.14):** Orders, Workers, Old Metal, Returns, Reports, Credit Book, Supplier Payables and Settings were opened and scrolled on the phone — logcat showed **0 Flutter exceptions, 0 render overflows**, and the encrypted DB still opens at schema v21 after the manifest change.
- **APK:** v1.4.14 / versionCode 66, `mobile/jewellery_suite_v1.4.14-arm64-v8a.apk` (`45,727,304` bytes), SHA-256 `836280c6dce653575bf8b8c6225b5aa48149555261d80c40a74bbb576af04ea8`, installed in place at `10.52.61.148:42895`.

### 2026-11-05 — #079 worker order could be delivered twice (v1.4.13)
- **The bug:** `deliverWorkerOrder` had no status guard. A second call rewrote the delivered weights, cash and metal paid, and posted a second `WORKER_ORDER_IN`, so the finished metal entered stock twice. `saveWorkerTransaction` already reconciles raw out / finished in, so this broke that reconciliation.
- **The fix:** delivery throws if the worker order is already `Delivered`, before touching the row or stock.
- **Checks:** `test/jewellery_order_guards_test.dart` now 5 cases; `flutter analyze` clean; full suite **510 passing, exit 0**.
- **APK:** v1.4.13 / versionCode 65, `mobile/jewellery_suite_v1.4.13-arm64-v8a.apk` (`45,726,744` bytes), SHA-256 `4bf3713c821f133dba794a90d1e9f2e41bb3fb440d4069edcd767c92bcfb1077`, installed in place at `10.52.61.148:42895`.

### 2026-11-05 — #078 double delivery and over-return refused in the store (v1.4.12)
- **The bug:** `deliverOrder` had no “already delivered” guard, and `updateOrderStatus` only forbade setting `Delivered` directly — it happily moved a delivered order back to `Ready`. Reopening and delivering again posted the finished-stock OUT movement and any delivery payment **a second time**. `saveReturn` validated weights but never compared them with what the sale still held, leaving the form as the only defence.
- **The fix:** delivery throws before any write if the order is already `Delivered`, reopening a delivered order throws, and `saveReturn` sums the invoice's item weights, subtracts what was already returned and refuses anything above the remainder.
- **Checks:** new `test/jewellery_order_guards_test.dart` (4 cases); `flutter analyze` clean; full suite **509 passing, exit 0**.
- **APK:** v1.4.12 / versionCode 64, `mobile/jewellery_suite_v1.4.12-arm64-v8a.apk` (`45,726,744` bytes), SHA-256 `a271fd0e604336faa084ea70cb300da9d49df7e60b0c2a131e31314b1d9dae1d`, installed in place at `10.52.61.148:42895`.

### 2026-11-05 — #077 advance-only customers made visible (v1.4.11)
- **The bug:** overpayment is kept as an advance (`jewellery_payments` with `invoice_uuid = ''`). The Credit Book built its list from invoice rows, so once a customer had no live invoice their advance had no row — the overdraft strip and the Credit Book both said nothing while the shop still held the cash. The same hole made an advance-taking customer vanish after their sale was deleted.
- **The fix:** `creditCustomers` adds a synthetic row per advance party that has no invoice row, and the tile shows **Advance ₹X held · no invoice** with the amount and an *advance* label instead of “0 invoices · last —”. The advance is still netted off any dues when invoices do exist, so nothing is counted twice.
- **Checks:** new test in `test/jewellery_draft_contract_test.dart` (10 cases); `flutter analyze` clean; full suite **505 passing, exit 0**.
- **APK:** v1.4.11 / versionCode 63, `mobile/jewellery_suite_v1.4.11-arm64-v8a.apk` (`45,726,744` bytes), SHA-256 `94cb515e918e0560207ce3e358b9a228fa259862e60df673d085c7de9f7dafdc`, installed in place at `10.52.61.148:42895`. Phone not checked for this item: the state needs an advance with no invoice.

### 2026-11-05 — #076 four money defects found by review and fixed (v1.4.9)
- **The late-fee wipe (serious).** `addPayment` and `receiveCustomerPayment` recomputed the balance as `total − paid`. A late fee lives in `late_fee_total`, so the first payment after a fee **erased it** — the customer owed less than the app showed a moment earlier. The order-delivery path recomputed the same way. All three now use `total + late_fee_total − paid`, and a new test asserts the fee survives both a single payment and a spread receipt.
- **Drafts treated as money.** `summary()` counted drafts in today's purchases and in the outstanding strip, the report period totals summed them into purchases, the outstanding sales/purchases sums included them, and the supplier ledger listed a draft as a payable — while the store had just been taught to keep drafts out of supplier payables. Every one of those queries now excludes `Draft` as well as `Cancelled`.
- **Draft looked like a real purchase.** The dashboard row now says **DRAFT · stock pending** instead of showing a balance the shop may think it owes.
- **A typed “Paid now” vanished on save-as-draft.** The form now warns first, and `AppState` no longer creates a cashbook row for a draft even if an amount is passed.
- **Checks:** `flutter analyze` → **No issues found**; full suite **504 passing, exit 0**; `test/jewellery_draft_contract_test.dart` now 9 cases.
- **APK:** v1.4.9 / versionCode 61, `mobile/jewellery_suite_v1.4.9-arm64-v8a.apk` (`45,726,744` bytes), SHA-256 `16b7162cbff4e89bc3e4616d2dc5b45691bb6320ce725a5ac09edd7711857d64`, **installed in place** at `10.52.61.148:42895`, data kept.
- **Phone check with real documents (first time this flow had data):** a purchase saved as a draft appeared with `Raw gold 0.000 g` and the row **DRAFT · stock pending**; **Confirm purchase → OK** posted the stock once (`Raw gold 10.000 g`) and the same row became `Bal ₹1,38,000`; a second untouched draft stayed a draft with no extra stock.
- **A fifth defect, found only on the phone.** A real sale then took a ₹500 late fee (Credit Book ₹1,50,500) and a ₹1,000 receipt (₹1,49,500 — the fee survived, which is the #076 fix working on the device). But the fee row in the ledger read **“-₹0”**: the row keyed its amount on `entry.isSale`, so any debit that is not a sale was formatted as a credit. It now keys on `entry.debit > 0` and prints **₹500** in red. No test could have caught this — the store was right and only the label was wrong — which is why the phone pass still matters after a green suite.
- **APK (v1.4.10):** versionCode 62, `mobile/jewellery_suite_v1.4.10-arm64-v8a.apk` (`45,726,744` bytes), SHA-256 `29c3502e747613cb0cd52bc63e9ba479fd4795943f6360bbad8cd4b61062c8ff`, installed in place. Full suite **504 passing**, analyzer clean.

### 2026-11-05 — #075 draft purchases, shared expenses and late fees close the checklist (v1.4.7)
- **Why this round happened:** #074 ended with three `CALCULATIONS.md` boxes deliberately left unticked. Ticking them without code would have been the exact dishonesty §5 item 8 of `agent_readme.md` warns about, so they were built.
- **Draft purchases (schema v21).** A purchase can now be saved as a **Draft**: the document and its lines are stored, but no stock movement, no payment and no old-metal stock are posted. The document sheet shows *Draft · stock is not received until you confirm* with **Confirm purchase · receive stock**, which posts the `PURCHASE_IN` movement once. `confirmInvoice` removes any leftover movement for that document before posting and refuses anything that is no longer a draft, so a double tap or a retry cannot receive stock twice. Drafts are excluded from supplier payables and the reports' period totals, so a document that is not a real purchase never becomes a debt.
- **Shared expenses.** The form takes one **shared expense** for the whole document (freight, hallmarking, stones for the lot). `saveInvoice` splits it across the lines by net weight with `allocateSharedExpense` — the function that had tests but no caller — adds each line's share to that line's additional cost and stores the total once on the invoice. The preview adds it to the payable and subtracts it from estimated profit, and the invoice total remains exactly the sum of its lines.
- **Manual late fees.** A sale's sheet has **Add late fee**. The fee is a `jewellery_charges` row; the invoice's item total and recorded cost are never rewritten, `late_fee_total` and `outstanding` grow instead, and the customer ledger shows **Late fee** as a separate debit. Deleting the document deletes its fees. Nothing generates a fee automatically, which is what the specification asks for.
- **Checks:** `flutter analyze` → **No issues found**; full suite **502 passing, exit 0** (`./tool/test.sh`), including new `test/jewellery_draft_contract_test.dart` (7 cases: draft posts nothing, confirm posts once and refuses a second, draft stays out of supplier payables, weight split, zero shared expense, fee raises only the balance, fee removed with its sale).
- **APK:** v1.4.8 / versionCode 60, `mobile/jewellery_suite_v1.4.8-arm64-v8a.apk` (`45,726,744` bytes), SHA-256 `77dbc62f7f4ac63bd3f8abef9bb62868aa6f5d3ca01eabd7b27086ece5fa5139`, **installed in place at `10.52.61.148:42895`, data kept** (`[db] open: SQLCipher encrypted, schema v21`). v1.4.7 was superseded inside the same round: on the phone its shared-expense label was cut mid-word (*“…freight, hallmarking — split by wei…”*), so the label was shortened to **Shared expense ₹ (split by weight)** and the build remade. The v1.4.7 APK never carried a data check.
- **Phone check:** the v21 migration ran on the existing ledger without loss; the purchase form shows **SAVE AS DRAFT** beside **SAVE PURCHASE**, the **Shared expense ₹ (split by weight)** field, and the documented *“Rate saved with this document”* note. The phone still holds no jewellery documents, so the draft confirm, the shared-expense split and the late-fee dialog have no data to run against — those are covered by the tests and marked 🟨, not ✅.

### 2026-11-05 — #074 workflow checklist audited; receipts allocated, rate graph and WIP added (v1.4.6)
- **The audit:** every box in `CALCULATIONS.md` §2 was checked against the code and the suite, not just ticked. **34 boxes are proven by automated tests**, 10 by code or an earlier phone pass, **2 are genuinely open** (draft purchases, shared expenses) and the late-fee box is partial (nothing auto-generates a fee, but the jewellery module has no manual fee entry yet). The document now records which check proves each box.
- **Gap 1 — allocation engine with no caller.** `JewelleryMath.allocatePayment` was written for C13 and unit-tested, but nothing in the app used it: a receipt went to exactly one invoice, an overpayment was refused, and a customer advance could not be recorded — the exact “wrote the rule, never wired it” mistake this tracker warns about twice. Now `JewelleryStore.receiveCustomerPayment` spreads a receipt over the customer's open invoices (manual per-invoice amounts or oldest-first), trims each part to what is owed, and stores the remainder as an advance (`invoice_uuid = ''`). `AppState.receiveJewelleryReceipt` posts one cashbook **IN** row per part.
- **Gap 2 — no rate graph.** Reports now draws **Saved gold rates** from `jewellery_rates` (last seven saved days), so the chart is the shop's own history, never a market feed.
- **Gap 3 — reconciliation.** The stock card lists **WIP · gold/silver (open orders)** from `wipWeight()` and states plainly that WIP is neither shelf stock nor the worker reserve, which the separate worker card already shows.
- **Open, deliberately not half-built:** **Draft does not change stock** needs a real draft→confirm lifecycle (stock must post once, never twice), and **item-specific and shared expenses** needs an invoice-level shared amount persisted and split by weight (`allocateSharedExpense` is already tested; nothing feeds it). Both are recorded in the checklist with what they need.
- **Checks:** `flutter analyze` → **No issues found**; full suite **495 passing, exit 0** (`./tool/test.sh`), including new `test/jewellery_receipt_test.dart` (6 cases).
- **APK:** v1.4.6 / versionCode 58, `mobile/jewellery_suite_v1.4.6-arm64-v8a.apk` (`45,660,940` bytes), SHA-256 `1e02e6606c608526da67fe3c6e57f5ae157032ef431dd4311ed51cdf6320dbfa`, **installed in place at `10.52.61.148:42895`, data kept** (`versionName=1.4.6`, SQLCipher schema v20).
- **Phone check:** the Jewellery dashboard, Credit Book and Reports were opened on the device. The phone holds **no jewellery documents and no saved rates**, so the receipt dialog and the rate chart could not be exercised there this round; the new Reports cards render. The dialog and allocation are covered by the tests, and a phone pass is still owed once a sale exists on the device.

### 2026-11-05 — #073 dark-mode ink debt closed (v1.4.5)
- **Why this round:** every remaining tracker item is blocked on the shop (**#072** needs the Android OAuth client ID, **#065** a real SMS/e-mail gateway, **#042** HTTPS on the server), so the round took the one code-level defect the tracker had left open: the 2026-11-02 change log recorded the hard-coded dim ink on the Khata and customer-profile screens as *deliberately not changed*.
- **What was wrong:** `kInk` is a fixed near-black. On dark mode's `surfaceOf` cards the unselected Khata filter chips, the customer-profile ledger stamps, the Reports tab labels, the interest-calculator chips, the Settings pager dots, the **NO LOAN** tag and the Khata **Outstanding** figure were all black-on-black — the same defect #026 and #06L fixed elsewhere.
- **Fix:** every site now calls `inkOf(context)`; no palette value changed, so light mode renders exactly as before. Found one extra site during the phone pass that the first grep missed — `_stat('Outstanding', …, kInk)` in `khata_screen.dart` — and fixed it in a second build.
- **Checks:** `flutter analyze` → **No issues found**; full suite **489 passing, exit 0** (`./tool/test.sh`), including new `test/dark_mode_ink_test.dart`.
- **APK:** v1.4.5 / versionCode 57, `mobile/jewellery_suite_v1.4.5-arm64-v8a.apk` (`45,660,940` bytes), SHA-256 `bff3c554c1ab3a662f3b6d703efde810db8f55d2b33dcbc5e3a667236b7bcb96`, **installed in place at `10.52.61.148:42895`, data kept** (`versionName=1.4.5`, `[db] open: SQLCipher encrypted, schema v20`). Intermediate build `06b7da4c…8d8a7a` carried every fix except the summary card and was replaced in place.
- **Phone verification:** dark mode on → the Khata customer list's four filter chips, its summary card, the Reports tabs, the interest-calculator chips, Settings, Home, Khata Books and General were all read on the screen; the summary **Outstanding ₹0** was still dark on the intermediate build and correct after the rebuild. The phone was put back to light mode and the app returned to Home.
- **Still blocked (unchanged):** **#072** Drive backup + sync (needs the Android OAuth client ID), **#065** real one-time-code delivery (needs the shop's gateway URL), **#042** HTTPS + pinning (needs the server's TLS).

### 2026-11-04 — #047 and #070 phone-verified on v1.4.4; backup menu re-checked; interrupted rewrite reverted
- **#047 due-date filter ✅ phone-verified.** The shyam loan is due **02-02-27**. A **1 Nov – 30 Nov 2026** range hid it and the strip read **₹0 / ₹0 / ₹0** with *“No pawn loans here.”*; **Clear date filters** restored **₹10,000 / ₹900 / ₹10,900** and the loan; a **1 Feb – 28 Feb 2027** range included it again. The list and summary move together, so the actual due date (promised `due_date` fallback) is the only predicate in play.
- **#070 Indian mobile numbers ✅ phone-verified.** **Customers Book → Edit Customer** refused `1234567890` with *“Use a 10-digit mobile number, or +91 and the 10 digits.”* and kept the form open; `+919121376318` saved. The pawn tile menu's **Call** opened the dialler as **+91 91213 76318**, and **WhatsApp** opened `api.whatsapp.com/send/?phone=919121376318&…` (no WhatsApp app on this phone, so the browser handled it — the `91` prefix is present). The saved customer record now holds `+919121376318` for future checks.
- **Backup & data re-checked, including a full restore.** Four backups were listed, latest `auto_2026-11-04_12-57-04.zip` (409 KB). The row menu showed **Restore this backup · Save or share · Save a copy to Downloads… · Delete backup**; **Save or share** reached Android's share sheet with Gmail / Quick Share / Bluetooth. A fresh `jewellery_suite_2026-11-04_15-07-06.zip` was then created and restored: the confirmation named the file, `Admin@123` was accepted, a pre-restore safety copy `jewellery_suite_2026-11-04_15-08-34.zip` was written, the DB reopened as `SQLCipher encrypted, schema v20`, and the shyam loan with **₹10,000 / ₹900 / ₹10,900** was intact.
- **Interrupted freebuff session recovered.** The only uncommitted files were a partial rewrite of `lib/data/backup_service.dart` and `lib/features/backup/screens/backup_screen.dart` — 49 analyzer errors, unfinished methods, and no tracker entry. Both were reverted to the committed v1.4.4 versions, which then passed the backup menu/share check above. Nothing from that rewrite remains in the tree.
- **Checks:** `flutter analyze` → **No issues found**; full suite **485 passing, exit 0** (`./tool/test.sh`). Working tree clean; all 12 earlier commits (`515cc1a..ddb7a8b`) pushed to `origin/Apk_Develop_Branch_01_11`.
- **Published:** GitHub release **v1.4.4** with all three split APKs (arm64 / armeabi-v7a / x86_64), tag `v1.4.4` at `6315c2c`; the release notes carry the exact sizes and SHA-256 for each asset. First published build since v1.1.6.
- **Release asset verified end-to-end:** downloaded `jewellery_suite_v1.4.4-arm64-v8a.apk` from the v1.4.4 release, confirmed SHA-256 `3b7452bd…c614f5`, installed it with `adb install -r` (versionCode 2056 / versionName 1.4.4), and reopened the app with `[db] open: SQLCipher encrypted, schema v20` and the ₹10,000 pawn investment intact.

### 2026-11-04 — #071 Reports: Khata in the Pawn layout, one share button (v1.4.4); #072 Drive design
- **Why:** the Pawn report was easy to read (filters, metric cards, a short list), while Khata was eleven tappable rows with the detail hidden behind each one, and exporting meant choosing between three icons before knowing where the file would go.
- **Khata tab rebuilt** in `lib/features/reports/screens/reports_screen.dart`: **Period** (All / This month / This year) and **Loans** (All / Active / Overdue) filters, six metric cards, the collections in view listed like Pawn rows with a count/total footer, and an **All time** card for the figures the old screen always showed (total given, total received, interest earned, today/week/month, bad credit / blocked). **Overdue** swaps the list for the overdue loans with *Collectable now* and *Bal* — the same numbers the metric card totals. The CSV/PDF/Excel exports keep reading the same `_r` map, so the file and the screen cannot disagree.
- **One share button:** the app bar now has a single **Share** action (`reports-export`) that opens a chooser — **PDF** (print / WhatsApp), **Excel (.xlsx)** (Excel or Google Sheets), **CSV** (any app or Drive) — and only then hands the file to Android's share sheet, which is the pattern the Play Store khata apps use.
- **Checks:** `flutter analyze` → **No issues found**; full suite **485 passing, exit 0** (`./tool/test.sh`), including new `test/reports_ui_test.dart` (filters + cards, Overdue switch, single button → three file types → dismiss keeps the report).
- **APK:** v1.4.4 / versionCode 56, `mobile/jewellery_suite_v1.4.4-arm64-v8a.apk`, **45,660,940** bytes, SHA-256 `3b7452bdaf55a9dca9df100db96d7f7cb46cd1a7e6510140de61f38bc6c614f5` — **installed in place at `10.235.54.202:40933`, data kept**.
- **Phone-verified (v1.4.4):** Khata tab drew the two filter rails, the six metric cards, *COLLECTIONS IN VIEW* and the *ALL TIME* card; **Share this report** opened the PDF / Excel / CSV chooser; **PDF** → share sheet with `jewellery_suite_khata_2026-11-04_12-58.pdf` and **CSV** → `…_12-59.csv`, with Gmail / Quick Share / Bluetooth listed; logcat held no crash.
- **#072 (Drive backup + multi-device sync) is designed, not coded:** `docs/GOOGLE_DRIVE_SYNC.md` covers the OAuth requirement, the hidden app folder, the shop-passphrase encryption, the main-device / pairing-code model, the device registry with remove, the conflict rule, and the four-step build order. It cannot start until the shop creates the Android OAuth client ID (Google Drive API, `drive.appdata` + `email`, package + release SHA-1).

### 2026-11-04 — #070 Indian mobile numbers (v1.4.3); WhatsApp country code and loose validation fixed
- **One rule for Indian numbers.** `lib/util/phone.dart` now owns it: `national()` returns the 10-digit number for a plain mobile, `+91 …`, `91 …`, `0091 …` or `0…`, and refuses everything else (short numbers, landlines, numbers starting 0–5, foreign numbers). `e164()` gives `+91XXXXXXXXXX`, `waNumber()` gives `91XXXXXXXXXX`, and `tel()` / `sms()` / `whatsapp()` build the links — so the dialer, the SMS app and WhatsApp can no longer disagree.
- **Hidden defect 1 — WhatsApp never opened the right chat.** Both the customer profile and the pawn tile menu used `https://wa.me/<digits>` with the bare 10-digit number. `wa.me` requires the country code, so an Indian number was not recognised; Call and SMS appeared to work while WhatsApp silently failed. Both now use `wa.me/91XXXXXXXXXX?text=…`.
- **Hidden defect 2 — raw text went into the URI.** Call/SMS built `tel:$phone` / `sms:path` from whatever was saved (`98765 43210`, `+91-…`, `(0)…`), which some dialers refuse. Numbers are normalised first; an unreadable number now says *“Use a 10-digit mobile number, or +91 and the 10 digits.”* instead of opening a broken screen.
- **Hidden defect 3 — the login rule was too loose.** `LocalAccount.isMobile` accepted any 10 digits (including landlines) and any 12 digits starting `91`; `create()` normalised first and then validated, so a 13+ digit number ending in 10 digits became a valid account. It now uses `Phone.isValid`. `normalizeIdentifier` keeps the last-10 fallback only so an account made under the old rule can still sign in.
- **Where it is enforced:** Add/Edit customer phone, the new-pawn-loan *Mobile no* form field, the jewellery order *Mobile* field (checked before saving), User Details phone, and the account identifier on Login / Create account. A phone number stays optional on a customer; when one is typed it must be usable.
- **Checks:** `flutter analyze` → **No issues found**; full suite **482 passing, exit 0** (`./tool/test.sh`), including new `test/phone_test.dart` (9 cases: +91 / 91 / 0091 / trunk 0 / dashes, landline and foreign rejection, tel & SMS & wa.me links, one account per number typed either way).
- **APK:** v1.4.3 / versionCode 55, `mobile/jewellery_suite_v1.4.3-arm64-v8a.apk`, **45,661,104** bytes, SHA-256 `0c1d6d6802de92640aa180f469ac2328bdf1538ad2984909f8e47eefa7361b87`. **Built, not installed** — wireless debugging had dropped (`10.235.54.202:41273` refused connections), so the phone still runs v1.4.2. Install this build before the next phone pass.

### 2026-11-04 — #049 encrypted local database (v1.4.2); migration defects fixed on the phone
- **Encryption at rest.** The ledger now opens through **SQLCipher** (`sqflite_sqlcipher 3.4.1`) with a 256-bit key generated on the phone and stored in the Android keystore (`flutter_secure_storage 11.2.0`). Nothing derives that key from the PIN, so forgetting or changing the PIN can never make the books unreadable. `lib/data/db_crypto.dart` is the platform-neutral face (`supported`, `key`, `looksPlaintext`, `encryptFile`, `verify`, `snapshot`, `rekeyFile`, `open`, `openExternal`) behind a conditional import — `db_crypto_io.dart` on Android/iOS, `db_crypto_stub.dart` elsewhere — so the web build and the Linux test VM keep the plain driver. About → **Storage** reports *Encrypted (SQLCipher)* or *Not encrypted on this build* instead of guessing.
- **One-time migration.** `LocalDb.init()` spots a plaintext header, writes an encrypted copy through `sqlcipher_export`, verifies it (integrity check plus a schema read), and only then swaps it in; the plaintext file is kept until the encrypted copy has actually opened, and a failed migration falls back to the plain file rather than losing the ledger.
- **Defect 1 — the migrated file reopened as schema 0.** `sqlcipher_export` copies the schema and rows but **not `PRAGMA user_version`**, so sqflite saw an empty-version database, ran `onCreate`, threw, and sqflite deleted the file — on the phone that emptied the disposable test ledger. Migration now carries `PRAGMA encrypted.user_version` across, and `open()` refuses to open a ciphertext file as plain SQLite.
- **Defect 2 — the same gap in backup snapshots.** Restoring a backup produced a schema-0 copy. Snapshots now stamp `PRAGMA _snapshot.user_version`, the manifest records the schema version, a restored/snapshot file whose version is 0 is repaired in place before it is opened (`_repairSchemaVersion`, logged as *repaired the missing schema version on the encrypted file*), and `BackupService` re-encrypts a backup made on another phone to this phone's key before restoring it.
- **Phone-verified (v1.4.2 / versionCode 54, installed in place over v1.4.1, data kept):** logcat reads `[db] plaintext database migrated to SQLCipher` then `[db] open: SQLCipher encrypted, schema v20`; after the restore experiment left a schema-0 copy, the next start logged `[db] repaired the missing schema version on the encrypted file` and opened `SQLCipher encrypted, schema v20` straight to Home with the ledger intact; **Backup & data → Create backup now** produced a verified 409 KB encrypted archive listed under *Saved backups*.
- **Not re-run on the phone:** the restore confirmation → admin password → replace round-trip on the final build. The wireless-debugging mDNS record went stale at the end of the session (`10.235.54.202:41273`, connection refused); the path is covered by the unit tests and the device runs above, and should get one hands-on re-check next session.
- **Checks:** `flutter analyze` → **No issues found**; full suite **473 passing, exit 0** (`./tool/test.sh`), including new `test/db_crypto_test.dart` (encryption reported unavailable on the VM, plaintext header detection, 256-bit hex key, a plaintext snapshot still opens read-only, and the live DB stays plain where SQLCipher is absent).
- **APK:** v1.4.2 / versionCode 54, `mobile/jewellery_suite_v1.4.2-arm64-v8a.apk`, **45,661,104** bytes, SHA-256 `6f65f123c0ce7dfcf4ea520982d21627690745353b18618526080d3a10dacdee`.
- **Note for the next session:** this is the first build whose database is not a readable `.db` file on disk. `adb pull` of the database no longer yields a usable ledger without the keystore key — use **Backup & data** for anything that must be read elsewhere.

### 2026-11-04 — #066 phone-verified (v1.3.5); prompt loop and stale switch fixed
- **Pass on the Redmi Note 8 Pro.** The gates were armed for this pass (`kDevPasswordGateDisabled = false`) — with the dev switch on, `AppLockGate` and `AdminPasswordGate` are skipped, so neither the lock screen nor the biometric prompt exists. The forced **Set your admin password** gate appeared after arming and was completed with `Admin@123`.
- **Defect 1 — the fingerprint switch stayed disabled after turning the lock on.** `_biometricAvailable` was read only when Password Settings loaded, which happened while the lock mode was still **Off**; the row therefore read *“No fingerprint or face is enrolled on this phone”* and ignored taps, even though the phone has two enrolled prints (reopening the screen showed it correctly, which is how the stale read was found). Turning a lock mode on now re-reads availability in `_setLockMode` (`lib/ui/password_settings_screen.dart`).
- **Defect 2 — the prompt looped ~3 times after a correct touch.** `AppLockGate._refresh()` re-locked on **every** resume. A BiometricPrompt backgrounds the app, so the resume after a successful match locked it again, rebuilt the `Overlay` (remounting `_LockScreen`) and fired the auto-prompt again; `_lockIfAlways()` also called `setState` while already locked, with the same remount effect. Locking is now only the `paused`/`hidden` handler's job, a rebuild happens only on a real state change, and the gate ignores the pause/resume pair caused by its own system prompt through the new `onBioPrompt` callback (`lib/ui/app_lock_gate.dart`). Regression test: *a resume right after unlocking does not re-lock the gate* (`test/app_lock_gate_test.dart`).
- **Phone-verified (v1.3.5 / versionCode 2051, installed in place over v1.3.4, data kept):** lock **Off → Every time** with PIN `1234`, and the fingerprint switch became usable in the same session (defect 1 fixed); switch **on** persisted with the toast *“Fingerprint unlock on — the PIN stays as the fallback.”*; cold start showed **Jewellery Suite is locked** and the system prompt *“Touch the fingerprint sensor”* owned by the app; **one touch unlocked straight to Home** (`FingerprintAuthenticationClient … success: true`, `topResumedActivity=…MainActivity`) with **no second prompt** (defect 2 fixed); the cancel path showed *“Fingerprint not recognised — enter your PIN.”*, kept **Use fingerprint** and the PIN field, and `1234` opened the app.
- **Checks:** `flutter analyze` → **No issues found**; full suite **469 passing, exit 0** (`./tool/test.sh`), including the new gate regression.
- **APK:** v1.3.5 / versionCode 2051, `mobile/jewellery_suite_v1.3.5-arm64-v8a.apk`, **40,417,300** bytes, SHA-256 `fa5a3c0f11025a3de1c45461a9edfa5c9cfdd7910e41ffe70e913bb13301aa99`. An intermediate v1.3.4 (2050) carried only the switch fix — it proved the prompt but still looped; superseded by v1.3.5.
- **Left on the phone:** screen lock **Every time**, fingerprint unlock **on**, admin password `Admin@123`. Set the lock to **Off** in Password Settings to skip the prompt while developing; keep the gate armed so the phone runs release behaviour.

### 2026-11-03 — #066 fingerprint unlock (v1.3.3)
- **Fingerprint / face unlock for the screen lock.** `local_auth 3.0.2` (flat `biometricOnly` / `persistAcrossBackgrounding` flags in v3), `MainActivity` switched to `FlutterFragmentActivity`, `USE_BIOMETRIC` declared. `lib/util/biometrics.dart` never throws: no hardware, nothing enrolled, a cancelled prompt or a missing plugin all return `false`.
- **Where it lives:** Password Settings → **Biometric & screen lock** gains **Unlock with fingerprint**, shown only while a lock mode is on and enabled only when the phone reports an enrolled finger/face; the lock screen adds **Use fingerprint** and auto-prompts once, with the PIN untouched as the fallback.
- **Checks:** `flutter analyze` clean; full suite **468 passing, exit 0** (`./tool/test.sh`), including `test/biometric_lock_test.dart`.
- **APK:** v1.3.3 / versionCode 2049, `mobile/jewellery_suite_v1.3.3-arm64-v8a.apk`, **40,351,492** bytes, SHA-256 `8445c9ff…`, **installed in place** on the phone, data kept.
- **Not phone-verified yet:** the settings switch, the auto-prompt and an actual finger match. The automated pass could not reach Password Settings inside the 30-minute box; this is the one remaining gate for ✅.

### 2026-11-03 — #041 closed: Excel export + Unicode PDF fonts (v1.3.2)
- **Excel export added.** Reports → **Export this tab as Excel** (`lib/util/report_xlsx.dart`) writes a single-sheet OOXML workbook from the same `khataReportRows` / `pawnReportRows` the CSV and PDF use. Written by hand because `excel` needs `archive ^3.6.1` (the app's backups run on `archive 4.x`) and `excel` also caps `xml <7` while `pdf 3.13` needs `xml ^7` — no added dependency, no downgrade of the backup engine.
- **Unicode PDFs.** `assets/fonts/` now carries Noto Sans, Noto Sans Tamil and Noto Sans Devanagari (939 KB, APK 38.5 → 39.9 MB). `report_pdf.dart` registers them as the base font plus fallbacks, so customer names in Tamil or Devanagari print as typed; if an asset cannot load the export still runs on the built-in font. Verified by inspecting the generated bytes: the PDF embeds `NotoSansTamil`.
- **Phone check (v1.3.2 / 2048, installed in place over v1.3.1, data kept):** Excel → share sheet `jewellery_suite_khata_2026-11-03_12-52.xlsx`; PDF → `jewellery_suite_khata_2026-11-03_12-53.pdf`; no `FATAL EXCEPTION` / `E/flutter` in logcat.
- **Checks:** `flutter analyze` → **No issues found**; full suite **466 passing, exit 0** (`./tool/test.sh`), including new `test/report_xlsx_test.dart` (zip parts, numeric cells, Tamil text, nine columns) and the Tamil PDF case.
- **APK:** `mobile/jewellery_suite_v1.3.2-arm64-v8a.apk`, **39,920,526** bytes, SHA-256 `27640c45…0f50ab13`.
- **#041 is now complete** — CSV, PDF, Excel and the six-month chart all ship.

### 2026-11-03 — #041 PDF export shipped (v1.3.1)
- **PDF export added** beside the CSV action: the Reports app bar now has an **Export this tab as PDF** action. `lib/util/report_pdf.dart` renders the same rows as the CSV — `report_csv.dart` exposes `khataReportRows` / `pawnReportRows`, and both exports read them — so the screen, the CSV and the PDF cannot disagree.
- **Why it was blocked before, and the fix:** pub.dev answers again, so `pdf: ^3.13.1` was added. Its `image` dependency resolved to 4.11.0, which calls `ZLibDecoder.decodeLazy` — removed in the `archive 4.x` this app pins — and every test file failed to compile. Pinning `image: ^4.12.0` (needs archive ^4.5.0) fixed it. **PDF is no longer blocked; Excel (.xlsx) is the remaining slice of #041.**
- **Rendering:** A4, one line per row (the pawn report has nine columns, so a table would not fit), bold section headings, page footer; non-Latin-1 characters (e.g. Tamil names) print as `?` because the built-in Helvetica font cannot draw them — the CSV keeps the full text.
- **Version:** `pubspec.yaml` is now **1.3.1+47**.
- **Checks:** `flutter analyze` → **No issues found**; full suite **461 passing, exit 0** via `./tool/test.sh`, including `test/report_pdf_test.dart` (real `%PDF-` header, nine-column pawn report, timestamped file names, CSV/PDF row parity, Latin-1 fallback).
- **Built, installed and phone-checked:** the v1.3.1 arm64 split APK (`mobile/jewellery_suite_v1.3.1-arm64-v8a.apk`, **38,483,916** bytes, SHA-256 `60ae17f2…3eb7a47`) installed in place over v1.3.0 — `dumpsys package` reports **versionName 1.3.1 / versionCode 2047**, data kept. Reports showed both new actions, and the share sheet produced `jewellery_suite_khata_2026-11-03_12-32.pdf` from the Khata tab and `jewellery_suite_pawn_2026-11-03_12-35.pdf` from the Pawn tab, with **no exceptions in logcat**.
- **Still open:** Excel (.xlsx) export only.


### 2026-11-03 — v1.3.0 installed on the phone; retail pricing and #047 due-date filter checked on-device
- **Installed in place** at `10.235.54.170:33013` with `adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` → **Success**; `dumpsys package` reports **versionName 1.3.0 / versionCode 2046**, data kept, and the v20 schema opened without a migration error.
- **Launch smoke test:** force-stop → launcher → `topResumedActivity=com.shyberdev.jewellery_suite/.MainActivity`, with **no FATAL EXCEPTION / E/flutter** lines in logcat.
- **Jewellery dashboard renders the built module:** saved gold rate **16,000/g · 92 % (14,720/g)**, raw gold **10.000 g**, old gold **1.260 g**, outstanding **₹2,65,750 across 2 open documents**, **Customer Credit Book ₹1,12,750 due from 1 customer**, **Supplier Payables ₹1,53,000 payable to 1 supplier**, **Orders 0 pending · 0 ready**, **Workers 0 workers · 0.000 g**, **Returns 0 credit notes**.
- **Retail pricing verified by hand** (owner's acceptance figures at the phone's saved ₹16,000/g instead of ₹15,000): a **KDM** line of 10 g + 10 % read **Billing weight 11.000 g × ₹16,000/g = ₹1,76,000 · Making ₹1,000 · Line total ₹1,77,000 · Fine metal 9.200 g @ 92.00 %**; switching the same line to **Non-KDM** dropped the wastage (**Wastage: None**) and read **10.000 g × ₹16,000/g = ₹1,60,000 · Line total ₹1,61,000** with the same 9.200 g fine metal. At the spec's ₹15,000/g these are the **₹1,66,000 / ₹1,51,000** cases that `test/jewellery_math_test.dart` pins.
- **Unsaved form discarded cleanly:** Back from New Sale returned to the dashboard with **Today's sales ₹0** — no document was written.
- **#047 is live on the device:** Pawn Loans → **Filter ▾** lists **All categories · Forgot_Slip_List · Pawn_Removed · Loan date range · Due date range · Amount range · Manage categories…**. The range was not exercised because the phone currently holds no pawn loans.
- **Checks:** `flutter analyze` → **No issues found**; `flutter test` → **456 passing, exit 0**. **Test temp dir fixed:** `/tmp` here is a **437 MB partition** and a full run needs ~300 MB there, so a killed run made the next one die at compile time (`writeFrom failed … No space left on device`). The 309 MB of `dart_test.kernel.*` / `flutter_tools.*` leftovers were cleared, and **`tool/test.sh`** (new, `chmod +x`) now runs the suite with `TMPDIR=$PWD/build/tmp` on the project disk; `./tool/test.sh` passes with `/tmp` left at 25 %.
- **Transient dashboard frame, re-checked — no defect:** one dump taken immediately after the receipt paired “₹1,000” with **Today's sales**. After a relaunch the card reads **Today's sales ₹0 · Collected today ₹1,000**, which agrees with Reports → Day (**Sales 0 · Collections ₹1,000**), so the earlier frame was stale, not a wrong query.
- **Document list filters verified:** search `PUR` narrowed the list to **1 of 2 documents** (only the purchase); **Sales** → 1 of 2, **Dues** → 1 of 2, clearing both → 2 of 2 with `SAL-20261102-0001 ₹1,38,750 · Bal ₹1,12,750` and `PUR-20261102-0001 ₹1,53,000 · Bal ₹1,53,000`.
- **Customer Credit Book receipt verified:** **Receive payment** on `SAL-20261102-0001` pre-filled ₹1,12,750; ₱1,000 (edited) + **Save** → ledger read **Received ₹27,000 · Outstanding ₹1,11,750**, a new `Payment received · -₹1,000 · 03-11-26 · CASH · Bal ₹1,11,750` row, and the dashboard tile moved to **₹1,11,750 due from 1 customer**.
- **Supplier payment verified:** **Pay supplier** on `PUR-20261102-0001` pre-filled ₹1,53,000; ₹1,000 + **Save** → **Paid ₹1,000 · Payable ₹1,52,000** with a `Payment made · -₹1,000 · 03-11-26 · CASH · Bal ₹1,52,000` row and the dashboard tile at **₹1,52,000 payable**.
- **Cashbook direction verified:** today's cashbook shows exactly two rows — `Shyam · CASH · 11:55 • JEWELLERY COLLECT · +₹1,000` and `Phone Supplier · CASH · 11:54 • JEWELLERY PURCHASE · -₹1,000` — so **TOTAL IN ₹1,000 / TOTAL OUT ₹1,000 / net +₹0**.
- **Old Metal, Returns, Orders, Workers screens verified:** Old Metal lists the **1.260 g · 63.00% · SAL-20261102-0001** voucher with **Gold equivalent 1.260 g · Silver 0.000 g · Accepted ₹15,750 · 1 voucher**; Returns reads **0 returns · sale invoices stay unchanged**; Orders shows the **Pending 0 · Ready 0 · Delivered 0** pipeline plus **All / Pending / Ready / Delivered / Cancelled** chips and a **New Order** form (customer, promised delivery date, KDM/Non-KDM, live billing weight); Workers shows **Held by workers ₹0 · Cash reserve ₹0 · Metal reserve 0.000 g** with **New movement**.
- **Reports verified:** **Money · Today** reads Sales 0 invoices ₹0, Purchases 0 ₹0, **Collections ₹1,000**, Returns ₹0, **Customer dues ₹1,11,750**, **Supplier payable ₹1,52,000**; the **six-month Sales vs purchases** chart renders with a ₹1,53,000 peak and Jun–Nov bars; **Stock valuation** reads raw gold **9.200 g fine · ₹1,47,200**, old gold **1.260 g fine · ₹20,160**, **Total stock value ₹20,160** (finished gold −9.201 g because the sale predates any purchase).
- **Order → delivery, return and worker movement driven on the device:** the form entry ran with a `boundsOf`/`fillField` helper that scrolls a field out from behind the IME and closes the keyboard only when `dumpsys input_method` reports it open (a bare back key dismisses the IME *and* pops the route — that is what broke the first attempt). **Order:** `ORD-20261103-0001` 2 g + 10 % → **₹35,700**, Pending → Ready → **Delivered** (gross/net 2.000 g, difference 0.000 g), pipeline 1/0/0 → 0/0/1, finished stock **−10.001 → −12.001 g**. **Return:** 1 g against the sale → **RET-20261103-0001 · ₹13,800**, sale unchanged at ₹1,38,750, dues **₹1,11,750 → ₹97,950**, stock **+1.000 g**, Reports **Returns ₹13,800**. **Worker:** ₹500 cash to *QA Worker* → **Held by workers ₹500 · Cash reserve ₹500** and cashbook `QA · JEWELLERY WORKER · -₹500`.

### 2026-11-03 — jewellery completion round: supplier payables, valuation, filters, chart; pawn due-date filter
- **Supplier Payables built.** Purchases are grouped by supplier name (case-insensitive), with billed/paid/outstanding, an open-purchase chooser, and a ledger where a purchase is a credit and every purchase payment is a debit. **Pay supplier** posts **OUT/red** (`JEWELLERY_PURCHASE`); customer sales never appear in the supplier book. New `test/jewellery_supplier_test.dart` — **6 cases**.
- **Stock valuation built.** `JewelleryStore.stockValuation()` reads fine grams from the stock ledger and multiplies by the newest saved pure-metal rate for each metal. Old metal is included as an asset. Reports shows raw/finished/old fine grams and values per metal plus a total. Old-metal movements now store their purity as 100 because their weight is already pure-equivalent; the valuation query also treats historical OLD rows that way. `test/jewellery_store_test.dart` gained two valuation cases.
- **Jewellery document search/filter built.** The dashboard list now has a search box (doc no / party / notes) and chips for **All types · Sales · Purchases**, **All metals · Gold · Silver**, **All status · Dues · Settled**. The store's `invoices()` supports the same `search`, `metal`, `paymentStatus`, and `partial` / `unpaid` predicates. Three store cases cover search, type+metal, and payment status.
- **Package-free chart built.** Jewellery → Reports adds **Sales vs purchases · last 6 months**, fed by `JewelleryStore.monthlyTotals()` and drawn with ordinary widgets. Orders and cancelled documents are excluded. Two store cases cover the six-month fill and a shorter window. #041 remains 🟧 PARTIAL because **PDF/Excel** still need unavailable packages.
- **Pawn #047 due-date filter built.** **Filter ▾ → Due date range** uses the actual due date when present, else the promised date, and narrows both the list and the summary strip. **Clear date filters** clears loan-date and due-date ranges. `PawnMath.dueDateIso` / `dueBetween` have two new cases; the filter menu has a widget test.
- **Checks:** `flutter analyze` → **No issues found**; full suite **456 tests passing**. **Release build:** v1.3.0 / versionCode 2046, arm64 split APK `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (`37,172,836` bytes, SHA-256 `bf6ef15f318fecaa8163921f4b9b8b6280a1d6f4c87df8c71313bfb80127d36b`), copied to `mobile/jewellery_suite_v1.3.0-arm64-v8a.apk`; release certificate SHA-256 `54f9833223d1a85278a749b89ffa613cecc88e147dca25fa1cf6bad52ab61c09`. **Built but NOT installed** — the consolidated phone pass is still the gate for ✅.

### 2026-11-03 — jewellery feature batch code-complete (schema v20), phone pass pending
- **Retail sale pricing corrected.** A sale/order no longer applies purity to the selling price. **KDM** bills `(net + wastage%) × rate + flat making`; **non-KDM** bills `net × rate + flat making`. The owner's examples are now acceptance tests: 10 g + 10% at ₹15,000 + ₹1,000 making = **₹1,66,000**; 10 g non-KDM at ₹15,000 + ₹1,000 making = **₹1,51,000** at 60%, 80% or 85% actual purity. Purity is cost-only and drives `fine_weight`; optional cost-to-shop gives the profit/loss preview.
- **Sale/order vs purchase forms split.** The sale/order form now shows KDM/Non-KDM chips, wastage %, flat making ₹, actual purity % and cost-to-shop ₹, with a retail billing-weight preview. The purchase form keeps purity-based raw metal and supplier making modes (% / grams / ₹). They no longer look or calculate like the same document.
- **Schema v20:** `jewellery_invoice_items.billing_basis`, `wastage_pct`, `making_charge`, `fine_weight`; old rows default to `raw` so historical totals are unchanged. Wired into `LocalDb` (version 20), fresh installs and `BackupService`.
- **Feature screens built:** Customer Credit Book (list + customer ledger + receive payment), old-metal register, customer orders (list/detail/status/delivery), worker list/ledger/transaction/order, returns (list/form), and on-screen reports. Dashboard tiles added; orders are excluded from the sale/purchase list. Shared invoice sheet shows retail vs raw line breakdowns, wastage/billing weight, order labels and return credit.
- **Cash direction:** purchase payments post **OUT/red** (`JEWELLERY_PURCHASE`); customer receipts post **IN/green** (`JEWELLERY_SALE` / `JEWELLERY_COLLECT`); order advances are IN. `AppState` derives direction from the document type.
- **Profit fix:** reports now start from `subtotal − invoice discount`, not the invoice total, so old-metal credit is treated as an asset exchange and no longer understates profit. If only item actual cost is recorded, profit uses it instead of reporting a fake zero-cost profit.
- **Tests:** `test/jewellery_math_test.dart` **42** (C01–C15), `test/jewellery_store_test.dart` **15**, `test/jewellery_credit_book_test.dart` **8**, `test/jewellery_operations_test.dart` **15**; full suite **440 passing**, `flutter analyze` clean.
- **Not done at the time of this entry:** release APK build/install, consolidated phone pass, supplier ledgers, PDF/Excel/charts, encrypted DB, biometric and real OTP gateway. **Superseded by the completion-round entry above** for supplier ledgers, stock valuation, filters and charts. No status below is upgraded to ✅ without a phone observation.

### 2026-11-02 — jewellery core (schema v18), code complete, build pending
- **Calculation engine:** `lib/util/jewellery_math.dart` is now the one formula home for the jewellery module. It implements the owner's purity-rate rule, percentage / fixed-weight / flat-rupee making (one mode per line), sale discount reducing sale value, supplier costing, worker return suggestions (never posted), old-metal equivalent and suggested credit, weight-proportional shared expenses, half-up whole-rupee rounding + stored adjustment, recovery colours, outstanding with one old-metal credit, worker cash↔metal conversion with a kept remainder, payment allocation and estimated/final profit.
- **Acceptance tests:** `test/jewellery_math_test.dart` — **37 cases, C01–C14 all passing** (`flutter test test/jewellery_math_test.dart`).
- **Schema v18:** `jewellery_rates`, `jewellery_invoices`, `jewellery_invoice_items`, `jewellery_payments`, `jewellery_old_metal`, `jewellery_stock_movements`; added to `BackupService.trackedTables`. `LocalDb` now opens at version 18, which also applies the v17 pawn-date migration that upgrades had skipped.
- **Store + screens:** `lib/data/jewellery_store.dart` computes and persists a document atomically (totals, old metal once, round-off, stock, payment), and `lib/features/jewellery/screens/` provides the dashboard and the sale/purchase form. **Home → Jewellery** no longer says “coming soon”. Cashbook receives the money side under `JEWELLERY_*` categories, and deleting a document removes its cash rows and stock movement too.
- **Store tests:** `test/jewellery_store_test.dart` — **12 cases passing** (rate history, sale/purchase totals, old metal counted once, stock, sequences, part payment, overpayment refusal, cascade delete, grey-without-cost recovery).
- **Not done:** APK build/install/phone pass, customer + worker orders, returns, ledgers, worker settlement UI, reports, multi-line entry and actual-cost entry.

### 2026-10-30 — v1.1.5 built, installed and published
- **Signed release APK:** v1.1.5 / versionCode 31, 98.6 MB (`98,554,731` bytes), `mobile/jewellery_suite-release.apk`, SHA-256 `91b4f83801ac6c4e82c222dd353924104efde99dc40b814d9280ae7ae8f2dbb2`.
- **Installed in place** over v1.1.4 at `10.235.54.6:36647`; `dumpsys package` reports **versionName 1.1.5 / versionCode 31**, data kept. Launched to `MainActivity` with **no crash lines** in logcat.
- **Published:** GitHub release **v1.1.5** with asset `jewellery_suite_v1.1.5.apk` (release assets are how the APK ships; `mobile/.gitignore` excludes `*.apk`).
- **Play Store:** deliberately parked until **v2** — no listing, signing-for-Play or policy work is being done before the app is finished.

### 2026-10-30 — v1.1.5 — cashbook edit/ranges, payment mode, OTP gateway
- **Cashbook editing (#044):** manual rows get an edit action that reopens the sheet pre-filled. Automated rows (Khata / Pawn / Jewellery, or any row with a `reference_id`) are refused so the module and the cash can never disagree.
- **Cashbook ranges (#045):** `getCashbookEntries` / `getCashbookDailySummary` accept an inclusive `from`/`to`; the screen adds **Day · This month · All time · Range** and the tally follows it.
- **Payment mode (#046):** You Gave rows now show `· CASH / UPI / BANK` from the stored `payment_mode`.
- **OTP delivery (#065):** new `lib/util/otp_gateway.dart` and a Password Settings card. When a gateway URL is configured the code is POSTed as JSON and **not** shown on the phone; otherwise the offline code appears as before.
- **Tests:** new `test/cashbook_edit_range_test.dart` (4 cases: manual edit, module-owned refusal, range totals, gateway config). `flutter analyze` clean; **330 tests pass**, exit 0.
- Deferred: **#066 biometric unlock** (needs `local_auth`, not available in the offline pub cache, and device enrolment to verify).

### 2026-10-30 — v1.1.4 built, installed and published
- **Signed release APK:** v1.1.4 / versionCode 30, 98.5 MB, `mobile/jewellery_suite-release.apk`, SHA-256 `0a67da8b2c647d7926ac574326192b0eb088cebc1625f7330d17843bf1f4cd29`, signed with the upload keystore (certificate SHA-256 `54f98332…ab61c09`).
- **Installed over wireless debugging** at `10.235.54.6:36647` with `adb install -r`; `dumpsys package` reports **versionName 1.1.4 / versionCode 30**, and the existing data was preserved. The app launched to `MainActivity` with no crash in logcat, and the v16 schema migrated in place.
- **Published:** GitHub release **v1.1.4** with asset `jewellery_suite_v1.1.4.apk`. The repo's `mobile/.gitignore` excludes `*.apk`, so the APK is a release asset (the v1.1.0 convention), not a tracked file.
- Checks before the build: `flutter analyze` → **No issues found**; `flutter test` → **326 pass**, exit 0.

### 2026-10-30 — v1.1.4 code complete (account, password centre, pawn list)
- **Customers Book (#055):** Home drawer tile and screen title renamed.
- **One password home (#056/#059):** Settings no longer carries the delete/release switch; Home → System no longer carries the biometric stub. **Password Settings** now holds account & login, screen lock (Off / Every time / **Daily MPIN**), the delete/release master + per-action switches, and the admin password — each with Change and **Forgot…?**. `lib/ui/app_lock_settings_screen.dart` removed.
- **Account & login (#057):** local account with Gmail or 10-digit mobile, salted hash, password **or** one-time-code sign-in, and a session that survives restarts until Logout. The optional shop-server login is still there for sync. Phones that already hold data auto-continue, so existing users are not locked out.
- **Forgot password (#058):** shared OTP flow for the admin password, login password and PIN/MPIN — hashed code, 10-minute expiry, 5-attempt cap. Codes are shown on the phone because no SMS/e-mail gateway is configured (tracked as #065).
- **Pawn tiles (#060):** two rows — name + amount on top, ID badge + village/date/item + sync cloud below. The Active word is gone; released loans are muted with a small tag.
- **Pawn actions (#061):** Call / SMS / WhatsApp / Move to another pawn profile / Edit in every tile menu, plus long-press.
- **Pawn categories (#062):** `Forgot_Slip_List` and `Pawn_Removed` seeded, custom categories added/renamed/removed, filter chip, and multi-select bulk move.
- **Pawn filters (#063):** Active/Released/metal chips deselect on a second tap; search covers name, ID and amount; new custom date range.
- **Schema v16 (#064):** `pawn_loans.category`, `pawn_categories`, backup tracking and restore carry-over for the new account/lock settings.
- **Checks:** `flutter analyze` → **No issues found**; `flutter test` → **326 tests pass**, exit 0. New/updated tests: `test/pawn_profile_ui_test.dart` (two-row tile, ID/amount search, Active-chip deselect).
- Version bumped to **v1.1.4+30** in `pubspec.yaml`. **No APK has been built or installed for this round yet.**

### 2026-10-30 — v1.1.3 verified on phone, release-signed
- **Release migration:** exported the v1.1.1 debug database/photos, uninstalled the old app, installed the release-signed v1.1.3 build, then restored the data through the in-app flow. Live result: 13 customers, 16 pending sync changes, Home shows ₹15,000 pawn investment / ₹1,57,500 khata investment (₹1,57,700 after the live refinance check).
- **#020–#039 all ✅ DONE** — see the phone-verification list in section 1b. Highlights: reports due-now ₹17,810 across 5 accounts; 2× font layout; ⋮ profile actions; “No reminder”; Indian grouping; dark-mode audit; cashbook linkage; backup/restore with safety copy; optional PIN lock; forced admin password; real APK size.
- **#031 live proof:** a ₹100 fresh-cash refinance created exactly one `KHATA REFINANCE` OUT row in the 30/10/2026 Cashbook; the ₹64,100 rolled balance stayed a transfer. This leaves one extra demo refinance in the sample set.
- **#037 follow-up:** `AppLockGate` moved from `MaterialApp.home` to `MaterialApp.builder`, above the Navigator, so the lock covers pushed routes (Settings, profiles, Cashbook); lock screen wrapped in its own `Overlay`. 4 regression tests.
- **#054 offline use:** Login → **Use without a server** sets `offline_mode=1`; real login clears it. Fixes the lockout after installing/restoring a server-less backup.
- **Backup files:** SAF **Save a copy to Downloads…** / **Restore from a file…**; no new permission (manifest still only `INTERNET`). Restore validates the archive, takes a verified safety backup, and carries the phone’s admin password / PIN / toggles across the DB replacement.
- **Tests:** 325 pass, exit 0, ~30 s; `flutter analyze` clean.
- **Final APK:** v1.1.3 / versionCode 29, `mobile/jewellery_suite-release.apk` (97.8 MB), SHA-256 `d6f0946cc278c3be9720c973e85589ae913317a2946c09cbc3f28de75d53b111`, release-signed with certificate SHA-256 `54f98332…ab61c09`. About App reads the installed size, **93.3 MB**.
- Keystore: `android/app/upload-keystore.jks` + `android/key.properties` (both gitignored). Back them up together; credentials are not recorded here.

### 2026-10-29 — v1.1.2 bug-fix round (#020–#039), release-signed
- **Reports (#020):** `dueNowForReports()` uses the To Collect schedule (installments / interest periods that have arrived) instead of the whole outstanding; 4 regression tests.
- **Layout (#021/#022):** profile hero, schedule stats, khata row and member header scale/ellipsis at large values; secondary profile actions moved into one ⋮ menu; 320 dp / 2× text tests.
- **Formatting (#023/#024/#034):** “No reminder” label; true Indian lakh/crore grouping; pawn money/weights formatted; old Western-grouping test replaced.
- **Cashbook (#030–#032):** create/edit/zero/delete hooks for pawn, khata, member and sample data; collection entries keyed by collection UUID with legacy loan-keyed migration; refinance writes fresh cash only.
- **Backup (#035/#036):** all 20 v15 tables tracked (including `migration_log` on fresh installs); photo dedupe; in-app restore with validation, verified safety backup, `AppState.load()` after restore, and 3 new restore tests.
- **Security (#037/#038):** optional 4–6 digit PIN app lock with salted hash and startup/background gate; forced first-run admin password, minimum 6 characters, `admin` refused, salted hash replaces plain text.
- **Signing/Play (#027–#029):** release keystore + `android/key.properties`; Gradle fails loudly on a missing/incomplete key; signed v1.1.2 APK verified with `apksigner`; manifest audited (only `INTERNET`, no camera/storage/media permission needed).
- **APK size (#039):** read from Android via `AppSize` MethodChannel.
- **Test runner (#025):** reproduced the post-suite hang at default concurrency; `dart_test.yaml` caps it at 2. Plain `flutter test`: **314 pass, exit 0**. `flutter analyze`: clean.
- Final APK **v1.1.2 / versionCode 28**, `mobile/jewellery_suite-release.apk`, SHA-256 `1beb0a1a8f52421ade4c2f40495a66d7ed1c12716ea7609f810fb4d2959d1a3c`; **release-signed** (certificate SHA-256 `54f98332…ab61c09`).
- Keystore: `android/app/upload-keystore.jks` + `android/key.properties` (both gitignored). Back them up together; credentials are not recorded here.

### 2026-10-28 — v1.1.1 development round 2 — verified on phone
- Added **#050–#053** (UI/UX round 2), implemented in `lib/ui/customer_profile_screen.dart` and `lib/ui/pawn_screen.dart`.
- **#050:** removed the duplicate **Calendar…** chip; the four quick choices and **Pick date** now share one date value, and the preview follows the picked date.
- **#051:** pawn rows show the customer photo/initial, name, village and book ID above loan date, metal and amount. Village falls back to the customer’s saved village.
- **#052:** the profile header avatar opens a full-screen viewer; **Customer KYC & Details** expands to ID, name, village, address, mobile, KYC photos and **Edit customer**; the loan card shows the six agreed fields; actions are **Interest Paying → Amount Paying → Amount Requesting → Release**, with **Delete Loan** separate below.
- **#053:** the filter row is **Active · Released · Villages ▾** (no **All**); the chosen village filters both the list and the summary. Active is the default view.
- Added 3 widget tests in `test/pawn_profile_ui_test.dart` (row + village filter, profile layout/action order, reminder preview).
- `flutter analyze`: clean. **287 tests pass**.
- Final APK **v1.1.1 / versionCode 27**, `mobile/jewellery_suite-release.apk`, SHA-256 `f52b6f22bb155b146b5f07bc8a8e98dfd82cc8e251cdde8373e7efe075f757c1`; still **debug-signed** — release signing remains #027/#028.
- Committed on `develop` (not pushed).

### 2026-10-28 — v1.1.1 development round 1 — verified on phone
- Added **#001–#006** (this round).
- Added schema **v15** (`khatabook_given.payment_mode`).
- Added regression suite `test/v1_1_1_regression_test.dart` (8 tests).
- `flutter analyze`: clean. **284 tests pass** (276 old + 8 new).
- Same-day ledger ordering fixed (`ledgerWhen`) so a refinance transfer sits below the new loan.
- **#003 refined after the first on-device look:** the ₹63,000 new-loan row stays on top; the transfer tile below headlines ₹33,000 “refinanced” instead of repeating ₹63,000.
- **#001 / #002 verified on an isolated QA install** (fresh application ID, sample-free). New pawn customer + loan saved with auto ID `A01`; You Gave ₹50 late fee saved and wrote its Cashbook OUT. QA app was uninstalled afterwards.
- **#003–#005 verified on the live v1.1.1 install** with existing data intact.
- Final APK **v1.1.1 / versionCode 26**, `mobile/jewellery_suite-release.apk`, SHA-256 `1af92f28…9d3685af`; still **debug-signed** — release signing remains #027/#028.
- Committed on `develop` (not pushed).

### 2026-10-28 — v1.1.0 installed for testing
- Commit `488b4c8`: personalised greeting, editable Khata type, Lolugu map default.
- Installed v1.1.0 / versionCode 25; user reported **#001–#005**.

### 2026-10-30 — Apk Develop Branch snapshot — refactor repo reorganization staged
- Branch `Apk_Develop_Branch_01_11` created on this worktree for APK + GitHub traceability.
- Snapshot staged: screens moved into `lib/features/<feature>/screens/`, helpers remain in `lib/ui/`, tests and state changes aligned.
- Current worktree analyzer state: clean (`flutter analyze` — no issues found).
- Debug APK present in this worktree: `build/app/outputs/flutter-apk/app-debug.apk`.
- This entry is a branch snapshot, not an installed APK verification.
- **Signed release APK:** v1.1.5 / versionCode 31, 98.6 MB (`98,554,731` bytes), `mobile/jewellery_suite-release.apk`, SHA-256 `91b4f83801ac6c4e82c222dd353924104efde99dc40b814d9280ae7ae8f2dbb2`.
- **Checks before the build:** `flutter analyze` → **No issues found**; `flutter test` → **330 pass**, exit 0.
- **Published:** GitHub release **v1.1.5** with asset `jewellery_suite_v1.1.5.apk`.

### 2026-11-01 — Apk Develop Branch work loop established on `Apk_Develop_Branch_01_11`
- Branch `Apk_Develop_Branch_01_11` is now the active APK develop + GitHub work branch for this project (created 01/11/2026).
- Purpose of this branch: release-sign the build, install it on the phone over wireless debugging, run the hands-on phone pass, record each result here, then commit and push on this branch.
- Current snapshot on this branch is the refactor repo reorganization plus the v1.1.5 round note. `flutter analyze` is clean; the working tree is clean except for committed/pushed progress-note updates.
- Phone state: the app was uninstalled on the device so the manual check could proceed; after reinstall the on-device database is a clean first-run state (1 village, 2 pawn categories, admin password salt/hash and customer-id scheme marker only) — no stale sample/demo rows in the business tables.
- CODE DONE backlog waiting on the phone: **#055–#065** and **#067–#06B** are written and unit-tested but not yet verified by hand on the phone on this branch; **#040–#043** and **#066** remain deferred/TODO.
- Release signing is configured locally (`android/key.properties`, `android/app/upload-keystore.jks`, both gitignored). The debug build can be installed after wipe; the release build installs in place.
- Next action on this branch: build/install a fresh APK and run the phone pass over #055–#065 and #067–#06B.

### 2026-11-01 — new report logged: drag-to-delete bin and the MPIN gate (#06D–#06F)
- Two things were reported from the phone and are now tracked in **section 1g**; no code has changed for them yet.
- **#06D** — the **“Hold and drag here to delete”** bin lifts a tile but dropping on it never deletes the row.
- **#06E** — Delete / Release should ask for the **general MPIN**, not the admin password.
- **#06F** — the Password Settings card must describe the MPIN gate and its admin-password fallback.
- Nothing built, installed or published for this report; the branch state is unchanged from the #06C note above.

### 2026-11-01 — Pawn UI rework (#06C), interrupted mid-session, carried forward
- This round is **CODE DONE in the repo but not yet installed/verified on the phone**; the session that started it was interrupted, so the note is written now so the next session can resume without re-reading the code.
- Changed file: `lib/features/pawn/screens/pawn_screen.dart` (only file touched this round).
- Checks on this round: `flutter analyze` → **No issues found**; `dart format` applied; `git diff --stat` → 1 file, 228 insertions, 191 deletions.
- Changes queued for the phone pass:
  - **Customer pawn profile:** loan card now labels the promised date as **Due Date (Promised)** instead of **Due Date**.
  - **Customer pawn profile:** the **Active / Released** status pill now sits beside a new three-dot menu (⋮) that opens **Call**, **SMS**, **WhatsApp**, **Move to another pawn profile**, **Edit loan**.
  - **Pawn list tile:** the left-side **Move** dot and the cloud sync badge are removed from the tile.
  - **Pawn loans page filter bar:** the old **Categories** + **Date range** pills are collapsed into one **Filter ▾** menu beside **Active / Released / Villages**, with **All categories**, each category, **Date range**, and **Amount range** inside it.
  - **Amount range** is a placeholder for this round: tapping it shows “Amount range picker — coming next.” Date range still opens the existing date picker.
- What to verify on the phone next (after install):
  - Open a pawn loan profile and confirm the menu items and Due Date (Promised) label.
  - Open the pawn loans page and confirm the Filter menu replaces the old Categories/Date pills and that Date range still works.
  - Confirm long-press on a pawn tile still opens the customer name / amount / date sheet with Call / SMS / WhatsApp / Move / Edit.
- Deferred follow-ups from this round, to be done after the phone pass:
  - Wire a real **Amount range** picker into the pawn Filter menu.
  - Decide whether the pawn list tile long-press sheet and the profile three-dot menu should stay in sync or diverge.
  - Clean up any leftover pawn-move password gating behavior once the on-device flow is confirmed.

### 2026-11-01 — #06D–#06F implemented, plus a real layout crash found by the suite
- **#06D — drag-to-delete actually deletes now.** Root cause was not the bin: `InkWell.onLongPress` sat *inside* `LongPressDraggable` on every pawn tile, and the inner long-press recogniser wins the gesture arena, so the tile was never lifted and the bin never appeared. `DragToDeleteTile` is now stateful, takes its own `onLongPress`, and tells a real drag (more than 12 px of travel) from a hold-in-place: hold-and-move drags to the bin, hold-and-release opens the caller menu. The drop zone is the full bottom band (104 px) instead of only the pill.
- **#06E — Delete / Release ask the MPIN.** `askPasswordIfEnabled` verifies the screen-lock MPIN (`AppLock.verify`) and falls back to the admin password only when no MPIN is set, so no shop can be locked out of its own delete button. The dialog says **Type MPIN**, numeric keypad, and keeps the same call sites.
- **#06F — Password Settings** card is now **Ask MPIN for Delete / Release** and states which secret will be asked, depending on whether the screen lock is on.
- **Layout crash fixed (found by `flutter test`, not reported):** the new ⋮ menu in the customer pawn profile header put an `Expanded` inside a `Row` that is itself a child of a `Row`, so the constraint was unbounded and every profile open threw *“RenderFlex children have non-zero flex but incoming width constraints are unbounded”*. The pill now shrink-wraps and the ⋮ sits beside it.
- **Stale test corrected:** `test/pawn_profile_ui_test.dart` still expected the old bare **Due Date** label; it now expects **Due Date (Promised)** and **Actual Due Date**.
- Files changed: `lib/ui/widgets.dart`, `lib/ui/admin_guard.dart`, `lib/ui/password_settings_screen.dart`, `lib/features/pawn/screens/pawn_screen.dart`, `test/pawn_profile_ui_test.dart`.
- **New regression test:** `test/drag_to_delete_test.dart` (2 cases) locks the gesture contract — hold + move + drop on the bin deletes, hold + release in place opens the tile menu, and neither fires the other. This is the test that was missing when the conflict shipped.
- **Checks:** `flutter analyze` → **No issues found**; `flutter test` → **332 pass**, exit 0 (was 330 + the 2 new cases).
- **Environment note:** `/tmp` on this machine is a small 437 MB tmpfs and filled up, which made `flutter test` hang and then fail to copy its listener. Runs now use `TMPDIR=$PWD/.dart_tool/tmp`. If a test run hangs with no output, check `df -h /tmp` first.
- **New file:** `APK_Project_Progress/agent_readme.md` — the intent, the real progress, the root causes, what the agent did wrong and the communication log. Read it with this file.
- Still not installed or phone-checked for this round.

### 2026-11-01 — #06G amount range, stray tree removed, v1.1.6 prepared
- **#06G:** the pawn Filter menu's **Amount range** is a real filter now. From/To dialog with either side blank for an open end, **Clear** and **Cancel**; the pill shows `≥ ₹50,000`, `≤ ₹5,000` or the band, and the list plus the summary follow it. Implemented as a `StatefulWidget` dialog because disposing the text controllers right after `showDialog` returned threw *“A TextEditingController was used after being disposed”* while the dialog was still animating out.
- **Popup-menu overflow avoided:** labelling the entry “Amount range (set)” overflowed the menu row by 26 px at 430 dp, so the label stays **Amount range** and the pill carries the active state.
- **Tests:** `test/pawn_profile_ui_test.dart` gains an amount-range case (menu → dialog → Apply narrows the list to Ravi's ₹63,000, pill reads `≥ ₹50,000`, Clear restores both). `flutter analyze` clean; **333 tests pass**, exit 0.
- **Stray tree removed:** `mobile/jewellery_suite/mobile/jewellery_suite/` (an accidental nested copy with `lib/core/refactor_audit.py` and a `refactor_checkpoint` file) is deleted. The real app lives in `mobile/jewellery_suite/lib`.
- **Version:** bumped to **v1.1.6+32** for the release build of this round.

### 2026-10-31 — v1.1.6 release-signed and published
- **Signed release APK:** v1.1.6 / versionCode 32, **98.6 MB** (`98,623,551` bytes), built with `flutter build apk --release` in 142.5 s.
  - Local copy: `mobile/jewellery_suite_v1.1.6.apk` (gitignored — `*.apk`).
  - SHA-256 `a2da42f41ca625270c7cba4257419cbe70310f67fbe4b7983957bdc39adcf583`.
- **Published:** GitHub release **v1.1.6**, asset `jewellery_suite_v1.1.6.apk` (`98,623,551` bytes) — https://github.com/ShyberDev/Jew_Pawn-Lending-Suite/releases/tag/v1.1.6
- **Not installed on the phone yet.** The device still runs v1.1.5; the hands-on pass over #06D–#06G is the next session's job.
- Checks before the build: `flutter analyze` → **No issues found**; `flutter test` → **333 pass**, exit 0.

### 2026-11-01 — v1.1.7 release-signed and installed in place
- **Signed release APK:** v1.1.7 / versionCode 33, **98.6 MB** (`98,623,551` bytes), `mobile/jewellery_suite_v1.1.7.apk` (gitignored).
- SHA-256 `be3bc8ebf5fdcf708ed98e7bef5fa54a5e546d2c043077b58a3fa3dde5e08c82`.
- **Installed in place** over v1.1.6 with `adb install -r` (both builds carry the same upload keystore), so the shop data was kept; `dumpsys package` reports **versionName 1.1.7 / versionCode 33**.
- **Not published yet:** GitHub still points at **v1.1.6**; the release asset for v1.1.7 is created only after this phone pass.
- Checks before the build: `flutter analyze` → **No issues found**; `flutter test` → **334 pass**, exit 0.
- Version bumped to **v1.1.7+33** in `pubspec.yaml`.

### 2026-11-01 — v1.1.7 phone pass — #06G/#06H/#06I verified, #06J logged
- **#06G ✅** — with a ₹60,000 and a ₹20,000 loan, `≥ ₹50,000` left only the ₹60,000 row and the summary became **₹60,000 / ₹5,400 / ₹65,400** with the `≥ ₹50,000` caption. The previous build left the summary at the unfiltered ₹80,000, so this is a real fix, not a display coincidence.
- **#06H ✅** — two runs of **New Pawn Loan → + (Full KYC) → SAVE** returned with **Phone QA / A03** and **Phone QB / A04** visible in both the name and ID boxes; the loan saved without retyping the customer.
- **#06I ✅** — the release prompt read **Are you sure to release this pawn loan?** with a **Release** button (previously **Delete**); `1234` completed the release.
- **#06J 🟧** — the released tile is muted with a **Released** tag and no **Active** word, but neither the sync-state cloud nor a visible ⋮ caller icon is rendered. The long-press menu still offers Call / SMS / WhatsApp / Move / Edit, so nothing is unreachable; the visual state indicator is the open defect. Logged in section 1g and flagged in section 2.
- **Phone test data created for this pass:** **Phone QA** (A03, ₹60,000 loan, released) and **Phone QB** (A04, ₹20,000 loan, active), alongside the earlier **Ravi** (A02) and **Test Drag**. These are disposable test rows; delete them before any real hand-over.
- Checks after the fixes: `flutter analyze` → **No issues found**; `flutter test` → **334 pass**, exit 0 (new + KYC name regression case).

### 2026-11-01 — #06J fixed in code: pawn tile sync cloud + visible caller icon (v1.1.8)
- **#06J** was the only open defect from the v1.1.7 phone pass: the tile promised a sync-state cloud and a caller-menu icon and rendered neither. The long-press menu (#068) was the only way in, so nothing was unreachable — the state indicator was simply missing.
- **Root cause:** the tile rebuild in #06C/#067 removed the old cloud badge (and the walking *Move* dot) and never re-added either, and the `_loanRow` comment kept describing them. No test ever asserted the badge existed, so a green suite hid it. Same failure pattern as the #06D gesture: behaviour deleted during a visual cleanup without a covering test.
- **Fix:** `_syncState()` in `lib/features/pawn/screens/pawn_screen.dart` renders the state from the loan row itself — `cloud_upload` in gold while `server_name` is empty or `dirty ≠ 0` (queued for the server), `cloud_done` in green once the server has named it and no local edit is pending. A 28×28 **⋮** `IconButton` on row 1 opens the same sheet as the long-press (Call / SMS / WhatsApp / Move / Edit) and is hidden while the multi-select checklist is on, where it would collide with the checkbox.
- **Tests:** `test/pawn_profile_ui_test.dart` gains *“pawn tile shows the sync state and a visible caller menu”* — one seeded pledge is marked `server_name = srv-ravi, dirty = 0` and must show `cloud_done`, the other must show `cloud_upload`, both tiles must expose a ⋮ key, and the opened sheet must list all five caller actions.
- **Checks:** `flutter analyze` → **No issues found**; `flutter test` → **335 pass**, exit 0 (334 + the new case).
- **Version:** bumped to **v1.1.8+34**. **No APK built, installed or published for this round** — the next session builds v1.1.8, installs it in place over v1.1.7 and runs the #06J phone check together with the still-pending CODE DONE items (#057–#060, #063–#065, #06A, #044/#046).
- **Phone test rows carried over:** Phone QA (A03), Phone QB (A04), Ravi (A02) and Test Drag are still disposable and must be deleted before any real hand-over.

### 2026-11-01 — v1.1.8 release-signed, built and installed (#06J verified)
- **Signed release APK:** v1.1.8 / versionCode 34, **98.6 MB** (`98,623,595` bytes), `mobile/jewellery_suite_v1.1.8.apk` (gitignored — `*.apk`), built 2026-11-01 in 169.1 s with `flutter build apk --release`.
- **SHA-256** `8554642c4e05d1cdeafabf6760329fa21c252674bbcf2f997d267e10ecbcd836`.
- **Signer re-verified this round with `apksigner`** (build-tools 36.0.0): `CN=Jewellery Suite, OU=Mobile, O=ShyberDev, L=India, ST=India, C=IN`, certificate SHA-256 `54f9833223d1a85278a749b89ffa613cecc88e147dca25fa1cf6bad52ab61c09` — the same upload keystore as v1.1.3–v1.1.7, so it upgrades in place over the installed v1.1.7 and keeps the shop data.
- **Installed in place** over v1.1.7 once the shop's phone was reachable at `10.235.54.186:35879` (Redmi Note 8 Pro, `infinity_begonia`): `adb install -r` → **Success**, and `dumpsys package` reports **versionName 1.1.8 / versionCode 34**, `lastUpdateTime 2026-11-01 13:10:19`, so the shop data was kept. Launched to `MainActivity` with no `AndroidRuntime` / Flutter exception in logcat.
- **Not published:** GitHub still points at **v1.1.6**; the v1.1.8 release asset is created only after the phone pass.
- **Checks before the build:** `flutter analyze` → **No issues found**; `flutter test` → **335 pass**, exit 0.
- **Phone check (#06J) — PASSED on v1.1.8.** The phone was reachable again at `10.235.54.186:35879` (Redmi Note 8 Pro). The PIN gate accepted `1234`; the build then showed the account login, so **Use without a server** (#054) was used to open Home with the shop data kept (₹20,000 pawn investment, 11 changes waiting). **Pawn Loans → Active** showed the **Phone QB / ID A04 / 01-11-26 · Gold / ₹20,000** tile with the gold `cloud_upload` badge on row 2 and a **⋮** on row 1. Tapping ⋮ opened the sheet headed **Phone QB / ₹20,000 · 01-11-26** with **Call · SMS · WhatsApp · Move to another pawn profile · Edit**. The cloud is gold, not green, because this offline phone has never pushed to a server — that is the correct state, and `cloud_done` is covered by the new widget test.
- **Still open from the install:** the app opened on the **account login** (not Home) after the PIN, so #057's “stay signed in until Logout” needs its own look; the sheet was dismissed without choosing an action, and no loan was created, edited or deleted during this pass.
- **Next action:** run the remaining phone pass — **#058–#060** (password centre, pawn tile), **#063–#065** (pawn filters, schema, OTP gateway) and **#06A** (pawn-move gate) — then delete the disposable test rows (Phone QA A03, Phone QB A04, Ravi A02, Test Drag) and publish the v1.1.9 release asset.

### 2026-11-01 — v1.1.9 — #057 session fix; #044 and #046 phone-verified
- **#057 root cause (found on the v1.1.8 install, not reported by the shop):** after the PIN the app showed the **account login** instead of Home although the shop's ledger was on the phone. `AppState.load()` only applied the “a phone that already holds the ledger must never be locked out” fallback inside `else if (!hasAccount)`. This phone **has** an account (identifier `9876543210` prefilled on that screen) but no active session flag, so it fell through to Login. Nothing was wrong with the account or the password — the session flag had simply been lost along an in-place install/restore, and the code could not tell “session lost” from “nothing here yet”.
- **#057 fix:** the ledger fallback now runs regardless of whether an account exists, and a new `account_signed_out` marker (`lib/util/account.dart`) records a deliberate **Logout** so the fallback can never undo it — Logout remains the only way back to the login form. `createAccount`, `signInWithPassword/OTP`, `continueOffline` clear the marker; Logout sets it; backup/restore carries it. Files: `lib/state/app_state.dart`, `lib/util/account.dart`, `lib/data/backup_service.dart`.
- **#057 tests:** new `test/account_session_test.dart` (6 cases) — a lost session flag on a phone with data reopens the shop; an account with no ledger still shows Login; a fresh phone shows Login; a deliberate Logout is honoured even with the ledger present; signing in again clears the marker and sticks; creating the account signs in immediately.
- **#044 phone check (PASSED):** Cashbook → the manual **Edit Test** row → **Edit this entry** opened **Edit Cash IN** pre-filled (Customer Payment · CASH · ₹750). Switching the mode to **UPI** and **SAVE CASH IN** rewrote that same row (`Edit Test | UPI | 11:31:04 • CUSTOMER PAYMENT • manual row | +₹750`): amount preserved, no duplicate row. The row was then reopened and reverted to **CASH**, so the shop's test data is as it was found.
- **#046 phone check (PASSED):** Customer → **Phone QA (A03)** → ledger row `01 Nov 26 11:38 AM | ₹50 | Bal ₹1,150 | Late fee — test · UPI`. The stored mode is appended to the note exactly as specified; no data was created for this check.
- **Checks:** `flutter analyze` → **No issues found**; `flutter test` → **341 pass**, exit 0 (335 + 6 new session cases).
- **Build:** v1.1.9 / versionCode 35, **98.6 MB** (`98,623,595` bytes), `mobile/jewellery_suite_v1.1.9.apk` (gitignored), SHA-256 `10e1449009e1e683f113c3575d77b663b25344c5db12db2f127cb63e27a74af1`, release-signed with the same upload keystore as v1.1.3–v1.1.8.
- **Installed in place** on `10.235.54.186:35879` (Redmi Note 8 Pro): `adb install -r` → **Success**; `dumpsys package` reports **1.1.9 / versionCode 35**, data kept. Cold start showed the PIN gate, `1234` opened **Home** directly — the reported symptom is gone.
- **Deliberately not done:** the account **password was not known to the agent**, so Logout → sign in could not be exercised on the phone (logging out would have locked the shop's data behind a login the agent could not pass). That path is covered by `test/account_session_test.dart` instead. **No** loan, collection, You Gave row or cashbook row was created for these checks.
- **Not published:** GitHub still points at **v1.1.6**; nothing was pushed.

### 2026-11-01 — v1.2.0 — due reminders (#040) and the test-credential sheet
- **#040 implemented.** Settings → **Due reminders** is now a real switch (it replaced the two “coming in a later release” rows). When on, the app schedules **one 9:00 summary** naming the khatabook accounts collectable today, e.g. `3 accounts due today` / `1 account overdue` with the first three names and the total. One summary, not one ping per member: a shop with 30 accounts should not be buzzed 30 times.
- **The arithmetic is shared, not reinvented.** `lib/util/due_reminders.dart` plans from the loan rows using the same `KhataSchedule` rule as the profile and Reports, so the notification can never quote the outstanding when ₹1,000 is due. Active loans only — a settled, cancelled or refinanced loan stays silent. Fully collected and no-schedule loans are skipped rather than guessed.
- **Android side:** `lib/data/due_notifications.dart` wraps `flutter_local_notifications` 22.3.3 and `timezone`; `zonedSchedule` fires at the next 9:00 as a real instant (UTC `TZDateTime` built from local wall-clock time), `inexactAllowWhileIdle` so it never asks for the exact-alarm permission. Every entry point catches its own failure, so a phone that refuses notifications still opens the ledger.
- **Permissions / manifest:** `POST_NOTIFICATIONS` (requested at runtime on Android 13+ when the switch is turned on) and `RECEIVE_BOOT_COMPLETED`, plus the plugin's `ScheduledNotificationReceiver` and `ScheduledNotificationBootReceiver` so the reminder survives a reboot. That is the first permission added since the #029 audit; INTERNET is no longer alone and section 2's note must be read with that in mind.
- **Gradle:** `isCoreLibraryDesugaringEnabled = true` + `desugar_jdk_libs:2.1.5`, required by the plugin on minSdk 24. Release build still **98→99.0 MB** (`99,015,812` bytes) and still release-signed with the same upload keystore.
- **State:** `AppState.dueRemindersEnabled` (`due_reminders_enabled`), `setDueReminders()` (asks permission, then schedules), `refreshDueReminders()` (re-plans on every start; cancels when nobody is due so the shop is never trained to ignore a “0 accounts” ping), and `dueReminderPlan()` for the card. `main()` initialises the plugin and rolls the summary forward.
- **Tests:** new `test/due_reminders_test.dart` (7 cases) — arrears plus the arrived installment, oldest-first collections, closed loans silent, fully collected, no-schedule skipped, biggest-first ordering and the shaded body wording. `flutter analyze` clean; **348 tests pass**, exit 0.
- **Build:** v1.2.0 / versionCode 36, `mobile/jewellery_suite_v1.2.0.apk`, SHA-256 `36b9a2a7bf8b1936fac956dea0561c452792d9e24c7e9f758eba481d6b1b7171`.
- **Installed in place** over v1.1.9 (`adb install -r` → Success, `dumpsys` 1.2.0 / versionCode 36, data kept). **Phone check (#040):** the Settings card read **“Off — turn on to be told each morning who to collect from”**; turning it on raised *“Allow Jewellery Suite to send you notifications?”*; **Allow** was accepted (`cmd appops get … POST_NOTIFICATION` → `Default mode: allow`) and the card then read **“One 9:00 notification with who is due or overdue today”**.
- **Known limitation:** the summary is a single inexact 9:00 slot re-armed on each app start, so a phone that never opens the app for days keeps the last summary; per-member scheduling and a “choose the hour” control are deliberately not in this round.
- **New file:** `APK_Project_Progress/Temp_Passwords_readme.md` — the shop's own account password was unknown to everyone, so it was reset through the **Forgot password?** OTP flow and every test secret is now written down for the next agent. Delete that file (and this folder) before the final release.

### 2026-11-01 — #058 / #059 phone pass and the dev-credential sheet
- **#058 ✅** — **Password Settings → Account & login → Forgot password?** was run end-to-end on the phone: **Send code** raised *“Enter the 6-digit code”* with **Offline code (valid 10 minutes) `298947`**, **Verify** opened **New login password**, the two fields were filled and **Save** returned to the card. No SMS/e-mail gateway is configured, which is exactly the documented fallback. **Forgot PIN?** and the admin **Forgot …?** open the same shared `confirmWithOtp` + `askNewPasswordDialog` flow; those two were opened but not completed.
- **#059 ✅** — the drawer has no separate lock entry any more; **Password Settings** carries Account & login (identifier, password/OTP switches, Change + Forgot), the lock row **Off · Every time · Daily MPIN** with Change PIN / Forgot PIN?, the **Ask MPIN for Delete / Release** card with per-action switches (Khata Delete, Customer Delete, Ledger Row Delete, Move to Loss, Pawn Delete, Pawn Release) and the admin password card. All three lock chips were tappable. **Daily MPIN's once-a-day behaviour was not observed** (needs a calendar-day boundary).
- **Login round-trip — partly blocked.** `Logout` correctly returned to the login form instead of reopening the shop (the new `account_signed_out` marker working), and **Use without a server** opened Home with the data intact. Signing back in with the freshly set password could **not** be confirmed: automated taps kept landing on the one-time-code toggle, and `Change login password → Current password` closed without opening the new-password dialog. The account password is therefore recorded as *set once, unconfirmed* with the OTP route documented as the reliable way in.
- **No app code changed in this pass** — the round is documentation plus the credential sheet; `flutter analyze` and the 348-test suite were already green on the v1.2.0 commit.

### 2026-11-01 — #06K ✅ — the real app shell is back, password gates off (dev pass only)
- **What was wrong.** The previous session could not clear three VSCode problems in `lib/app.dart`,
  `lib/ui/app_lock_gate.dart` and `lib/util/secret_dev.dart`, and patched `lib/app.dart` until it
  compiled as a **placeholder shell** — `_AuthShell`, `_SignedInShell`, `_ScreenRouter`, literal
  strings like *“Auth shell placeholder”*. It had **no `MaterialApp`**: no theme, no dark mode, no
  Smart-fit zoom, no `AdminPasswordGate`, and `_ScreenRouter` rebuilt `_SignedInShell` around itself,
  so the signed-in branch would have recursed forever. The analyzer was green because the file was
  self-consistent — it just was not the app. This is the same failure as §5 item 6 ("added a
  placeholder and called the item done") and item 8 ("tracker written in past tense for unverified
  work").
- **#06K fix.** `lib/app.dart` is restored to the real shell from `HEAD` (`0ae051f`): the gold theme,
  dark mode, the Smart-fit + in-app Zoom `MediaQuery` in `builder`, `AdminPasswordGate` on `home`.
  The two launch gates are skipped **behind one dev flag** instead of being deleted:
  `kDevPasswordGateDisabled` in `lib/util/secret_dev.dart`.
- **Deleted:** `lib/ui/app_lock_gate_disabled_placeholder.dart` (invented this round, never part of
  the app, and its text was the only thing on screen).
- **Reverted:** the `AppLock.isActive(db)` helper that had been added to `lib/util/app_lock.dart` —
  it returned `db.path != null`, i.e. *always true*, so it could never have been a lock decision.
  `lib/util/app_lock.dart` is byte-identical to `HEAD` again; `AppLockGate` and its 4 gate tests are
  untouched.
- **Password position for this dev pass (as the shop asked):** no PIN screen on launch, no forced
  admin-password form, no password re-testing each session. **Nothing was weakened:** the PIN hashes,
  `AppLock`, `AdminPasswordGate`, Password Settings, `askPasswordIfEnabled` (#06E) and every
  password unit test still exist and still run. Flip `kDevPasswordGateDisabled` to `false` before the
  release build and check the lock on the phone. Secrets are only in `Temp_Passwords_readme.md`.
- **Checks run in this session:** `flutter analyze lib` → **No issues found** (1.6 s); `flutter test` →
  **348 tests pass**, exit 0, 38 s (run with `TMPDIR=$PWD/.dart_tool/tmp` because `/tmp` is 89 % full —
  see agent_readme §4).
- **Build:** v1.2.1 / versionCode 37, `mobile/jewellery_suite_v1.2.1.apk` (`98,982,780` bytes), SHA-256
  `cbb22833d27657f2e845849205b7e4003c8f5de0c0b168f89fbeb9beaf727ee1`, release-signed with the same
  upload keystore. Gradle `assembleRelease` took 219 s; stitching warning about an SDK XML v4 file is
  the same harmless one as previous builds.
- **Installed in place** over v1.2.0 (`adb install -r` → **Success**; `dumpsys package` reports
  **1.2.1 / versionCode 37**), data kept.
- **✅ Phone check (2026-11-01), #06K verified:** force-stop → cold start landed **directly on Home** —
  **no PIN screen**, no **Set your admin password** form, no login form. The screen read
  *“Good Evening / Sun, 1 Nov”* with **₹0 collected today**, **₹20,000 pawn investment**,
  **₹1,000 khata investment**, the four **CORE MODULES** tiles (Khatabook, Pawn Loans, Cashbook,
  Jewellery), the **MORE** list (Reports, History, Interest Calculator, **Sync · 11 change(s) waiting**)
  and the shop's dark theme — which is the proof the real `MaterialApp` theme is back, since the
  placeholder shell had no theme at all. Ledger intact across the install. Nothing was tapped beyond
  the cold start and no row was created or deleted.
- **Device address note:** the phone answered on its **mDNS** name and at `10.235.54.83:38271` this
  session; the `10.234.54.83:45969` address recorded in `Temp_Passwords_readme.md` is stale, and the
  connection dropped once mid-pass and was restored with `adb connect`.
- **Still open for this item:** nothing. The password gates stay off until the release build, where
  `kDevPasswordGateDisabled` must be set back to `false` and the lock checked manually.

### 2026-11-01 — #06L ✅ — dark-mode pawn chips were unreadable (v1.2.2), and #063 verified

**Reported from the phone:** “In DarkMode the spelling in Pawn loans Gold / Released / Silver / Mixed
is text colour very dim which is not visible.”

- **Cause.** The pawn filter chips painted their *unselected* label with `kInk` — a fixed near-black
  (`0xFF2B2B2B`) at 70 % alpha — instead of the theme-aware ink. On the cream light background that is
  fine; on the dark surface it is black text on black, so **Released · Gold · Silver · Mixed** (and the
  unselected **Active** chip and the **Villages / Filter** pills) were effectively invisible. Same class
  of bug as §4's earlier note that `kInk` must never be hard-coded where dark mode can reach it.
- **Fix (#06L).** Every unselected chip / pill label and icon in `lib/features/pawn/screens/pawn_screen.dart`
  now uses `inkOf(context).withValues(alpha: .7)` — near-black in light mode, off-white `0xFFECECEC` at
  70 % in dark mode — so the contrast is right in both themes. Six call sites: the Active/Released
  chips, the Villages pill, the Filter pill's two label/icon pairs, and the Gold/Silver/Mixed metal
  chips. Nothing else changed; selected chips keep their gold fill and `kGoldDark` label.
- **Phone check (v1.2.2):** with Dark mode on, **Active · Released · Villages · Filter** and
  **Gold · Silver · Mixed** all read clearly as light grey/white on the dark background (previously
  black-on-black). No layout shift and the tap behaviour is unchanged.
- **Build:** v1.2.2 / versionCode 38, `mobile/jewellery_suite_v1.2.2.apk` (`98,982,780` bytes), SHA-256
  `448243793c51ec3ad36fb193ecb39e2aec60e361b4f99bd22bcce68bb73e8b33`, `flutter analyze lib` clean.
- **#063 ✅ phone-verified on the same build** (details in the 1d table): chip tap-to-clear, search by  name / ID / amount, and the loan-date range all behave as specified, and the summary strip follows the
  filters (₹0/₹0/₹0 when nothing matches).

### 2026-11-02 — v1.2.3 — #06A move gate repaired, #064 and #065 phone-checked

**What the phone found first.** On v1.2.2, **Pawn Loans → ⋮ → Move to another pawn profile →
Pawn_Removed** moved the pledge instantly with **no password prompt** (*“Moved to Pawn_Removed.”*).
`AppState.verifyPawnMovePassword` had been written for #06A and **was never called from anywhere** —
the gate existed in the state layer only, so the tracker's “asks for the simple pawn-move password”
was never true on the device.

- **#06A fixed.** `_chooseCategory` (`lib/features/pawn/screens/pawn_screen.dart`) now asks the secret
  through `confirmAdmin` (`verify: state.verifyPawnMovePassword`), fails closed, carries
  **Type pawn-move password** / **Move**, and skips a no-op tap on the category the loan already has.
  The dedicated secret is used when one is set; otherwise it falls back to the admin password —
  a fallback, not a bypass.
- **A second defect found by the new test:** `confirmAdmin` created its `TextEditingController` and
  disposed it in a `finally` as soon as `showDialog` returned. The route is still animating out and
  rebuilds the `TextField` once more, so Flutter threw *“A TextEditingController was used after being
  disposed”* — the same trap recorded for the amount-range dialog in #06G. The controller now lives in
  a small `_SecretPrompt` `StatefulWidget` and is disposed when the dialog is really gone. This was
  breaking three other widget tests (collection reminder, pawn profile, KYC name) as well.
- **New regression test:** `test/pawn_profile_ui_test.dart` → *“moving a pledge asks the pawn-move
  password (#06A)”* — with a dedicated secret set, tapping a category must show the prompt, a wrong
  secret must leave `category` NULL, and the right one must set it to `Pawn_Removed` with the
  `Moved to Pawn_Removed.` confirmation. The old code fails this test at the first assertion.
- **#064 ✅ phone-verified.** Filter menu shows **All categories · Forgot_Slip_List · Pawn_Removed**;
  **Pawn Categories** listed both with `0 loan(s)`; **Add Custom** created **QA_Cat** (`0 loan(s)`) and
  its **Remove category → OK** removed it again. The v16 category table is live and writable.
- **#065 🟧 PARTIAL phone-checked.** **One-time code delivery** accepted `https://shop.local/otp` +
  **SMS** → *“Codes will be sent by SMS.”*; **Remove gateway** → *“Gateway removed — codes are shown on
  this phone.”* The offline fallback is back on the phone. **No real send was observed** — there is no
  gateway account on the test phone, so the network path still needs the shop's URL.
- **Checks:** `flutter analyze lib test` → **No issues found**; `flutter test` → **349 pass**, exit 0
  (348 + the #06A case). Run with `TMPDIR=$PWD/.dart_tool/tmp`.
- **Build:** v1.2.3 / versionCode 39, `mobile/jewellery_suite_v1.2.3.apk` (`98,982,780` bytes),
  SHA-256 `479cae9542dda36a6844077a87aec6e728bb0831cf87b713cfdde91992c71579`, release-signed with the
  same upload keystore (certificate SHA-256 `54f98332…ab61c09`), `assembleRelease` 163.8 s.
- **Installed in place** over v1.2.2 → **Success**, `dumpsys` reports **1.2.3 / versionCode 39**;
  cold start went straight to **Home** with the ledger (₹20,000 pawn, ₹1,000 khata) intact.
- **Left on the phone:** the test pledge is uncategorised again and the only categories are the two
  seeded names; no loan, collection or cashbook row was created or deleted this round.
- **Still open for #06A (at v1.2.3):** a dedicated pawn-move password could not be set from the UI
  (`setPawnMovePassword` had no caller, despite #06A and `Temp_Passwords_readme.md` row 5 both saying
  Password Settings could change it), and the admin password on this phone was **not** `Admin@123` —
  a correct-secret move was never observed on the device. **Both were closed in v1.2.5 — see the next
  entry.**

### 2026-11-02 — v1.2.4 / v1.2.5 — Pawn-move password card, and the digits-only prompt behind it

- **#06A gets its own secret (v1.2.4).** Password Settings carries a **Pawn-move password** card
  between the delete/release card and the admin card. It says whether the move asks for the admin
  password or its own, offers **Set a password / Change password**, and **Use admin password** to
  drop the dedicated secret again. New `AppState.clearPawnMovePassword()` backs that last action;
  `verifyPawnMovePassword` was already there and is now actually called.
- **Why setting it looked broken (found on the phone).** The card asked for the current secret with
  `askPinDialog` — the MPIN dialog, which carries `FilteringTextInputFormatter.digitsOnly` and
  `maxLength: 6`. Typing `Admin@123` delivered `123` to the verifier, so the card reported a wrong
  password while the code was correct. The **admin** card's *Change password* had the same flaw, so
  the admin password could only ever be digits. Both now use a new `askPasswordDialog`
  (`lib/ui/secret_dialogs.dart`): plain text field, controller owned by the dialog's `State` so it
  cannot be disposed while the route animates out.
- **Tests:** `test/secret_test.dart` gains two state cases (admin fallback → dedicated secret →
  clear, and the secrets staying independent) plus a widget case asserting the prompt returns
  `Admin@123` unchanged. `flutter analyze lib test` → **No issues found**; **352 tests pass**, exit 0.
- **Builds:** v1.2.4 / versionCode 40, SHA-256 `128e227c…a9ff633` (intermediate, superseded).
  **v1.2.5 / versionCode 41** — `mobile/jewellery_suite_v1.2.5.apk` (`98,999,244` bytes), SHA-256
  `db39a8ba5b1834912ef2749b4033e6e1b03b1bf1bc105a670744880f46579a1b`, release-signed with the same
  upload keystore, `assembleRelease` 94.6 s; installed in place over v1.2.4 (`dumpsys` 1.2.5 / 41).
- **Phone pass (v1.2.5, 2026-11-02):** `Admin@123` was rejected, so the admin password was reset
  through **Admin password → Forgot password?** → **Send code** (offline code `256725`) → **Verify** →
  **New admin password**. `Pawn-move password → Set a password` then accepted `Admin@123` and saved
  `Move@1234`; the card read *“Moving a pledge asks for this password, not the admin one.”*
  **Pawn Loans → ⋮ → Move to another pawn profile → Pawn_Removed** asked **Type pawn-move password**,
  and `Move@1234` produced *“Moved to Pawn_Removed.”* Moving the same pledge back produced
  *“Category removed.”*, and **Use admin password** produced *“Move will ask for the admin password.”*
  with the card reverted to the fallback.
- **State left on the phone:** the test pledge is uncategorised again, the pawn-move secret is unset
  (admin fallback, `Admin@123`), and no loan, collection or cashbook row was created or deleted.
- **#06A is ✅ DONE.**

### 2026-11-02 — v1.2.6 — #048 automatic daily backup (phone-verified)

- **Settings → Automatic backup.** While the switch is on, one **verified** backup is written per
  calendar day. It starts after the first frame (`main()` calls `AppState.runAutoBackupIfDue()` through
  `unawaited`), so a ten-second photo archive can never delay opening the shop, and the runner
  swallows its own failures — a phone that cannot write a backup still opens.
- **Rules (in `lib/util/auto_backup.dart`):** off unless the shop turns it on; at most one copy per
  **calendar day** (`auto_backup_last`), however many times the app is opened; a failed or unverified
  archive does **not** update that marker, so the next start tries again instead of pretending the day
  is covered; the newest `auto_backup_keep` copies are kept (default 7, clamped 1–30, so a bad setting
  can never mean "keep none").
- **Pruning is scoped.** `BackupService.createBackup()` gained a `prefix` argument, so automatic copies
  are named `auto_jewellery_suite_<stamp>.zip` and pruning only ever considers `auto_` files. The
  shop's own backups — the copies that get handed over — are never deleted by this feature.
- **Tests:** new `test/auto_backup_test.dart` (4 cases) — does nothing while off; one copy per day and
  none for a second run the same day, with a new one the next day; pruning leaves exactly the newest 3
  automatic copies and keeps a manual backup; the retention setting clamps. `flutter analyze lib test`
  → **No issues found**; **356 tests pass**, exit 0.
- **Build:** v1.2.6 / versionCode 42 — `mobile/jewellery_suite_v1.2.6.apk` (`99,015,628` bytes),
  SHA-256 `015c8746986389a1d15ccca567ce789cf9f86c1694f677f8c5a647feb0b0f4da`, release-signed with the
  same upload keystore, `assembleRelease` 91.3 s; installed in place over v1.2.5 (`dumpsys` 1.2.6 / 42).
- **Phone pass (v1.2.6, 2026-11-02):** Settings showed **Automatic backup — Off — turn on to get a
  verified backup every day**; tapping it turned the switch on and toasted *“Automatic backup on — the
  first copy runs next time the app starts.”* After a force-stop and relaunch the card read **“Last
  automatic backup 02-11-26 08:53 · keeps the newest 7”**, and **Backup & data** listed
  `auto_2026-11-02_08-53-00.zip` (10 KB) under *Saved backups (1)* with its verified status line.
- **Not verified on the phone:** that the 8th day's copy removes the oldest (a day boundary cannot be
  faked on the device) — that is covered by the pruning test.
- **Kept on for the phone:** the switch is left **on**, so the test phone now makes one automatic
  backup a day; the shop's test rows are disposable, and this is the behaviour the release should ship.

### 2026-11-02 — v1.2.7 / v1.2.8 — #041 CSV report export (phone-verified)

- **Reports → app-bar export.** The Reports screen gained an export action that writes the **visible
  tab’s own figures** — `lib/util/report_csv.dart` is fed the `_r` map each view already computed, so the
  spreadsheet cannot disagree with the screen. Khata exports the summary plus overdue / today /
  village / customer lists; Pawn exports the metric cards plus every loan in view. Cells are quoted per
  RFC 4180, rows end CRLF, and amounts are plain numbers so a spreadsheet reads them as money.
- **Why CSV and not PDF.** `~/.pub-cache` has no `pdf`, `printing` or `excel` package, so PDF/Excel
  cannot be built on this machine. `share_plus` and `intl` are already dependencies, so this slice ships
  today and the number keeps its remainder (PDF/Excel + charts) for when the packages exist.
- **A crash found by the phone pass, not by the suite (v1.2.7 → v1.2.8).** `_exportCsv` read the tab with
  `DefaultTabController.of(context)` using the `_ReportsScreenState` context — which sits **above** the
  `DefaultTabController` that build() returns — so it threw *“Null check operator used on a null value”*
  on every tap and nothing happened on screen. The index is tracked in `_tab` and updated from
  `TabBar.onTap`. **Lesson for the tracker:** an `AppBar` action that reads an inherited widget created
  *inside its own build* must not use the State's context.
- **Tests:** new `test/report_csv_test.dart` (4 cases) — quoting rules, CRLF rows, the Khata summary plus
  a comma-containing customer name, the Pawn loan table, and both file names. `flutter analyze lib test`
  → **No issues found**; **360 tests pass**, exit 0.
- **Builds:** v1.2.7 / versionCode 43 SHA-256 `acb59224…7e3b312` (crashed on export, superseded).
  **v1.2.8 / versionCode 44** — `mobile/jewellery_suite_v1.2.8.apk` (`99,032,012` bytes), SHA-256
  `1bf11e52159933e632fb5ecb26233ae12c1346117c8bf077af40098894470c58`, release-signed with the same
  upload keystore; installed in place.
- **Phone pass (v1.2.8, 2026-11-02):** **Reports → export** opened the Android share sheet reading
  *“Sharing 1 file”* with `jewellery_suite_khata_2026-11-02_09-07.csv`; logcat showed no
  `Unhandled Exception`. The sheet was dismissed without sending the file.
- **Not verified on the phone:** opening the CSV in a spreadsheet app, and the **Pawn** tab’s export
  (same code path, different builder — covered by the unit test).
- **Deliberately not changed:** the *same* hard-coded `kInk.withValues(alpha: .7)` pattern still exists
  in `lib/features/khata/screens/khata_screen.dart` and
  `lib/features/customers/screens/customer_profile_screen.dart`. They are outside this report; if the
  shop sees dim text on those screens in dark mode, fix them the same way (`inkOf(context)`), not by
  changing the palette.
