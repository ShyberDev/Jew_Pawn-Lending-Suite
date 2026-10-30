# Jewellery Suite — Master Task & Feature Tracker

**Folder:** `mobile/jewellery_suite/APK_Project_Progress/`
**Last updated:** 2026-11-01
**Working branch for APK + GitHub traceability:** `Apk_Develop_Branch_01_11` (created 01/11/2026). This branch is the current APK develop loop: release-sign the build → install on the phone via wireless debugging → do the hands-on phone pass → record the result here → commit and push on this branch.
**App version installed for testing:** v1.1.5 (versionCode 31, **release-signed**) — installed over v1.1.4 in place over wireless debugging (`10.235.54.6:36647`, Redmi Note 8 Pro); existing data preserved
**Release build:** v1.1.5 (versionCode 31, **release-signed**) — `mobile/jewellery_suite-release.apk` (98.6 MB), SHA-256 `91b4f83801ac6c4e82c222dd353924104efde99dc40b814d9280ae7ae8f2dbb2`
**Published APK:** GitHub release **v1.1.5**, asset `jewellery_suite_v1.1.5.apk` — `mobile/.gitignore` excludes `*.apk`, so the APK ships as a release asset (same convention as v1.1.0), not as a tracked file
**Next target:** v1.2.0 — first finish the phone pass on this branch over the CODE DONE items that are sitting on the device right now: **#055–#065** (account, password centre, pawn list, OTP gateway) and **#067–#06B** (pawn tile density, caller actions, due-date labels, pawn-move gate, category defaults). These need a hands-on phone verdict before they count as ✅ DONE. After that pass, continue with the deferred items **#040–#043** (notifications, report export, HTTPS, jewellery module) and **#066** (fingerprint). **Play Store work is parked until v2.**

---

## How to use this file

1. Every task has a **permanent number** (`#001`, `#002`, …). Numbers never change and are never reused.
2. To report a problem, just send the number plus what you saw:
   **“#021 still happens: two amounts touch on the profile.”**
3. Status meanings:

| Icon | Status | Meaning |
|---|---|---|
| ✅ | **DONE** | Built, tested, and verified on the phone |
| 🟨 | **CODE DONE** | Written and unit-tested, waiting for phone verification |
| 🟧 | **PARTIAL** | Works, but not as intended — needs adjustment |
| ⬜ | **TODO** | Not started |
| 🔴 | **BUG** | Known defect, not fixed |
| 🔵 | **DEFERRED** | Planned for a later version |

4. Completed tasks are **kept**, not deleted. That is how we remember what exists and avoid adding the same feature twice.
5. At final release, move this whole folder to `Unnecessary content/` — do not delete it before then.

**Reporting format that saves the most time:**

```
#003 — screen: Customer Profile → Refinance tile
Did: refinanced sample_refinanced, fresh ₹25,000, interest ₹5,000
Expected: ₹63,000 on top, ₹33,000 refinanced below
Got: only ₹33,000, no label
Screenshot: (if visual)
```

---

## 1. Latest round — reported on 2026-10-28 after installing v1.1.0

| # | Status | Area | Page / option | What was wrong | What was changed |
|---|---|---|---|---|---|
| **#001** | ✅ DONE | System / Calculations | **New Pawn Loan → SAVE** | SAVE did nothing for a new customer. Root causes: (a) blank Customer ID was forced to `A01`, which is usually already used → duplicate-ID error; (b) the new customer was written with `id_front` / `id_back`, but the customers table has `id_photo_front` / `id_photo_back`; (c) the save was async with no error handler, so every failure looked like a dead button. | Blank ID now takes the next free book number. Photo columns corrected. Save wrapped in try/catch with a visible error message and a saving spinner. Selecting an existing customer now also loads their saved ID photos. |
| **#002** | ✅ DONE | System / Data | **Customer Profile → You Gave → Add** | Late fee / interest / principal could not be added after the first loan. `khatabook_given` had no `payment_mode` column, but every write sent one → SQL error, silently swallowed. | Schema v15 adds `khatabook_given.payment_mode`. The dialog now validates the amount (no more silent no-op) and shows a message if the save fails. |
| **#003** | ✅ DONE | System UI / Calculations | **Customer Profile → ledger → refinance transfer** | The old loan’s ₹33,000 transfer was shown without saying what it was, next to the new ₹63,000 loan. Could not tell which amount was refinanced and which was fresh cash. It also sorted ABOVE the new loan because same-day rows all tied at midnight. | The ₹63,000 new-loan row stays on top. The transfer tile directly below it now headlines **₹33,000 “refinanced”** (the amount that moved), with **New loan ₹63,000 • Fresh cash ₹25,000** underneath, then `Bal ₹0`. Same-day ledger rows now order by their entry time, and the transfer is stamped one second before the new loan. |
| **#004** | ✅ DONE | System UI | **Customer Profile → ledger → balance line** | Lowercase `bal ₹…` looked unfinished. | Now **`Bal ₹…`** on every ledger row. |
| **#005** | ✅ DONE | System UI / Cashbook | **Cashbook → filters** | Only Cash / UPI / Bank could be filtered. Could not isolate Khatabook, Pawn, Jewellery or manual entries. The daily tally also ignored the active filters. | Two filter rows: **Source** = All / Khatabook / Pawn / Jewellery / Manual, and **Payment** = All modes / Cash / UPI / Bank. Both combine. The total-in / total-out / net card now follows the filters exactly. Jewellery and Manual filter chips are ready for future modules. |
| **#006** | ✅ DONE | Documentation | **Project tracking** | No single place to see done / todo / improve. | This folder and file. |

> **All five were verified on the phone on 2026-10-28 (v1.1.1 / versionCode 26).**
>
> - **#001** — isolated QA install: brand-new customer “QA pawn” saved with auto ID `A01` and a ₹1,000 loan; the row appeared in Pawn Loans.
> - **#002** — isolated QA install: khata loan ₹1,000 + ₹100, then You Gave ₹50 late fee; balance became ₹1,150, the row appeared, and Cashbook received the ₹50 OUT entry.
> - **#003** — live install: ₹63,000 new-loan row on top; transfer tile below shows ₹33,000 refinanced, with “New loan ₹63,000 • Fresh cash ₹25,000”.
> - **#004** — live install: `Bal ₹…` on every ledger row.
> - **#005** — live install: Pawn filter shows the empty state and zero tally; Khatabook + Cash shows the two entries and the same ₹608 / ₹10,000 tally.

---

## 1a. UI/UX round 2 — approved 2026-10-28 (v1.1.1 fixes)

| # | Status | Area | Page / option | Request | Planned change |
|---|---|---|---|---|---|
| **#050** | ✅ DONE | System UI | **Customer Profile → Remind → Collection Reminder** | The **Calendar…** chip duplicates the **Pick date** button. | Remove the **Calendar…** chip. Keep the four quick choices and **Pick date**. The preview always shows the exact date picked. |
| **#051** | ✅ DONE | Pawn list | **Pawn Loans → loan rows** | Rows show only the customer name. They should show **Customer Name + Village**, keep **ID / loan date / item / amount**, and add the customer photo like Khatabooks. | Customer photo thumbnail; name + village; second line with ID, loan date, item and amount. Falls back to the customer’s saved village when the loan row has none. |
| **#052** | ✅ DONE | Pawn profile | **Pawn Loans → tap loan → Customer Pawn Profile** | Consolidate customer details and make them expandable; add a clear six-field loan section; keep items; reorder actions; photo should expand. | Header photo thumbnail opens a full-screen viewer. **Customer KYC & Details** expands to ID, name, village, address, mobile, KYC photos and **Edit customer**. Loan card shows Principal, Interest Rate, Loan Date, Due Date, Amount Paid, Outstanding. Actions in order: **Interest Paying, Amount Paying, Amount Requesting, Release**. **Delete Loan** stays separate. |
| **#053** | ✅ DONE | Pawn filters | **Pawn Loans → filter row** | Add a **Villages** filter beside **Active / Released**; the **All** chip is unnecessary. | Filter row becomes **Active · Released · Villages ▾** with **All villages** inside the menu. The chosen village filters the list and the summary figures. Default view is Active. |

> **All four were verified on the phone on 2026-10-28 (v1.1.1 / versionCode 27).**
>
> - **#050** — Collection Reminder shows only Today / Tomorrow / Next week / Next month plus **Pick date**. Picking 18 Nov 2026 changed the preview to `Remind 18-11-26 Wed`; the dialog was cancelled without saving.
> - **#051** — a temporary ₹1,000 pawn loan for `Sample_InLoss` displayed `Loss · ID A11` above `28-10-26 · Gold · ₹1,000`, with the avatar thumbnail. The temporary loan was deleted afterwards; totals returned to ₹15,000 / ₹900 / ₹15,900. The shop’s own pawn customer has no photo or village, so the initial + ID-only fallback is what shows for that row.
> - **#052** — the header avatar opened the full-screen viewer; **Customer KYC & Details** expanded to ID, name, village, address, mobile and **Edit customer**; the loan card showed the six agreed fields; actions ran **Interest Paying → Amount Paying → Amount Requesting → Release**, with **Delete Loan** separate below. Items stayed visible.
> - **#053** — the filter row is **Active · Released · Villages ▾** (no **All**); the menu held **All villages**, Loss and Pallipatti. Choosing Pallipatti showed `Villages: Pallipatti`, zeroed the summary and the list; **All villages** restored ₹15,000 / ₹900 / ₹15,900. Active is the default view.

---

## 1b. Bug-fix round — #020–#039 (v1.1.3, verified on phone)

All twenty items are implemented and ✅ **DONE**. Phone checks were run on the v1.1.3 release build on 2026-10-29/30.

**Verification already run**

- `flutter analyze`: **No issues found**.
- `flutter test`: **325 tests pass**, exit 0, ~30 s. The plain command exits by itself (#025). New regressions: `reports_due_test.dart` (4), `cashbook_linkage_test.dart` (8), `secret_test.dart` (8), `money_layout_test.dart` (3), a metal-filter test, 3 restore tests in `backup_service_test.dart`, 4 app-lock gate tests in `app_lock_gate_test.dart`, plus offline-mode tests.
- **Signed release build:** v1.1.3 / versionCode 29, `mobile/jewellery_suite-release.apk` (97.8 MB; About shows the installed 93.3 MB).
  - SHA-256 `d6f0946cc278c3be9720c973e85589ae913317a2946c09cbc3f28de75d53b111`
  - Signer: `CN=Jewellery Suite, OU=Mobile, O=ShyberDev, L=India, ST=India, C=IN`
  - Certificate SHA-256 `54f9833223d1a85278a749b89ffa613cecc88e147dca25fa1cf6bad52ab61c09`
- `android/key.properties` and `android/app/upload-keystore.jks` exist locally, are gitignored, and **must be backed up together**. Losing them means Play cannot accept an update. Credentials are never written into this tracker.

**Phone verification — 2026-10-29/30**

1. **#020** Reports → Khata → Overdue accounts: **5 · ₹17,810**, with per-loan due-now amounts (₹960, ₹4,800, ₹1,900, ₹550, ₹9,600), not the whole outstanding.
2. **#021** Khata profile and payment schedule readable at normal and **2× system font**; the three money columns fit.
3. **#022** Profile ⋮ holds **Call / SMS / WhatsApp / Move to another khata / Edit**; the title is not squeezed.
4. **#023** Khata filter chip reads **No reminder**.
5. **#024** Indian grouping shown on live data: `₹1,63,600`, `₹8,210`, `₹1,57,500`, `₹1,57,700`.
6. **#026** Dark mode checked on Settings, Home, Khata Books and the User Details dialog; reverted to light afterwards.
7. **#030** Cashbook 28/10/2026 shows 8 rows including khata/pawn disbursements, collections and two **“Khata You-Gave extra”** OUT rows of ₹100 — source rows and cash rows agree.
8. **#031** A live refinance of `Sample_Refinanced` (fresh cash ₹100) wrote exactly one Cashbook row: **OUT ₹100 · KHATA REFINANCE · “Refinance — fresh cash handed over”**. The rolled ₹64,100 did not appear as cash.
9. **#032** **Check for sample data** reported 41 demo rows (11 customers, 13 khata loans, 11 collections, 4 You Gave, 2 refinances) and left them in place. The live #031 check added one demo refinance, so the next check will count **43** (14 khata loans, 3 refinances). The removal path is covered by `test/cashbook_linkage_test.dart`; removal itself was not run because this database is still the demo set.
10. **#035/#036** Restore from file completed with a verified safety backup (`jewellery_suite_2026-10-29_05-36-27.zip`); the 13-customer live data plus 16 pending changes came back.
11. **#037** Cold start locked; wrong PIN stayed locked; correct PIN opened the app. The gate was then moved above the Navigator so it also covers pushed screens, and the PIN was turned off afterwards.
12. **#038** Forced admin-password setup completed on the phone; `admin` and short passwords are refused.
13. **#039** About App shows the real installed size, **93.3 MB**, not the old hard-coded 95 MB.

> **Migration note:** the phone previously held v1.1.1 (`versionCode 27`, debug-signed), which Android cannot upgrade in place to a release-signed build. Its database and photos were exported, the app was uninstalled, v1.1.3 was installed, and the data was restored through the new in-app restore flow with a safety backup first. Future v1.1.x installs upgrade in place.

---

## 1c. Release-migration fixes — v1.1.3

| # | Status | Area | Page / option | What was wrong | What was changed |
|---|---|---|---|---|---|
| **#054** | ✅ DONE | Offline / login | **Login screen** | A fresh install, or a phone restored from a backup made without a server, was stuck on the server login even though the SQLite file already held the shop’s ledger. | Added **“Use without a server”** on the Login screen. It sets `offline_mode=1`; the app opens straight into Home with sync unavailable. A real login clears the flag, and **Logout** brings the form back. Tested in `test/offline_mode_test.dart` and on the phone. |

Also in this release:

- **#037 follow-up** — the PIN gate now sits in `MaterialApp.builder`, above the Navigator, so backgrounding the app on **Settings, a customer profile or the Cashbook** covers that screen too. The lock screen carries its own `Overlay` for text selection. Covered by 4 tests in `test/app_lock_gate_test.dart`.
- **Backup files** — **Save a copy to Downloads…** and **Restore from a file…** use Android’s file picker (SAF), so no storage permission was added. The manifest still declares only `INTERNET`.
- **Restore safety** — the archive is validated, a verified safety backup is taken, then the live DB and photos are replaced; the phone’s admin password / PIN / toggles are carried across the replacement.

---

## 1d. v1.1.4 — accounts, password centre, pawn list (#055–#064)

Everything below is 🟨 **CODE DONE**: implemented, `flutter analyze` clean and covered by the
suite (326 tests). v1.1.4 is **installed on the phone and starts cleanly** (2026-10-30, no crash in
logcat, schema v16 migrated in place), but each interaction below still needs a hands-on pass, so
none is marked ✅ DONE yet.

| # | Status | Area | Page / option | Request | What was changed |
|---|---|---|---|---|---|
| **#055** | 🟨 CODE DONE | Home / Customers | **Home → General → Customers** | The name should read **Customers** Book | Drawer tile and the screen title now say **Customers Book**. Nothing else about the screen changed. |
| **#056** | 🟨 CODE DONE | Settings | **Settings → Ask password for delete / release** | The switch is available in two places | Removed from Settings. It lives only in **Password Settings** now, with its per-action switches. |
| **#057** | 🟨 CODE DONE | Login / account | **Login screen** | Create one account per shop with a **Gmail or mobile number**, sign in with a password **or a one-time code**, and stay signed in until Logout | New local account (identifier + salted password hash). Login screen has **Create account** and **Sign in**, password or OTP, and an optional collapsible **shop server** login for sync. The session persists across restarts; **Logout** clears it. An existing phone that already holds the ledger is never locked out (auto-continues). |
| **#058** | 🟨 CODE DONE | Passwords | **Every password** | A **Forgot password** path for each one | Admin password, login password and screen-lock PIN/MPIN each have **Forgot …?**. The flow sends a 6-digit code to the account identifier and then asks for the new secret. Codes are hashed, valid 10 minutes, blocked after 5 wrong tries. |
| **#059** | 🟨 CODE DONE | System / Security | **Home → System → Biometric & screen lock** | Move it into Password Settings; add a **Daily MPIN**; let each password be enabled/disabled | The drawer entry is gone. Password Settings now holds **Account & login**, **Biometric & screen lock** (Off / Every time / **Daily MPIN**), **Delete / Release**, and **Admin password**. Every one can be changed and reset, and login-by-password / login-by-code are individual switches. |
| **#060** | 🟨 CODE DONE | Pawn list | **Pawn Loans → loan tiles** | Two rows; highlight ID, name and amount; drop the **Active** word; a real sync-state cloud | Row 1: photo, **Name** (bold) and **₹Amount** (bold gold). Row 2: gold **ID badge**, village, date and item, then the cloud state — `cloud_done` green when synced, `cloud_upload` when waiting. Active is no longer written on the tile; a released loan is muted with a small **Released** tag. |
| **#061** | 🟨 CODE DONE | Pawn actions | **Pawn Loans → tile menu** | Caller functions like Khatabook | Every tile has a ⋮ / long-press menu: **Call · SMS · WhatsApp · Move to another pawn profile · Edit**. Edit changes principal (only when nothing is paid), interest rate and both dates, and recalculates interest/payable/balance. |
| **#062** | 🟨 CODE DONE | Pawn categories | **Pawn Loans → Categories** | Categories beside Active / Released / Villages, with custom names and multi-move | New **Categories ▾** filter seeded with **Forgot_Slip_List** and **Pawn_Removed**. Manage screen adds custom categories, renames them (loans follow) and removes labels. App-bar checklist turns on **multi-select**; the bottom bar moves every selected loan in one go. |
| **#063** | 🟨 CODE DONE | Pawn filters / search | **Pawn Loans → filters** | Toggle chips off, search by name/ID/amount, date range | Tapping the selected **Active**, **Released**, **Gold**, **Silver** or **Mixed** chip clears it (shows everything). Search matches **name, book ID, amount**, phone or village. New **Date** chip opens a from–to range on the loan date and can be cleared. |
| **#064** | 🟨 CODE DONE | Database | **Schema** | — | **v16**: `pawn_loans.category` + `pawn_categories` table, seeded once. Backups track the new table, and restore now keeps the phone's account + lock settings across the replacement. |

> **OTP delivery — known limitation.** The app is offline and ships no SMS/e-mail gateway, so
> the one-time code is generated on the phone and shown in the dialog, clearly marked
> **Offline code (valid 10 minutes)**. The verification itself is real (salted hash, expiry,
> attempt cap). Connecting an SMS or e-mail service later only changes
> `LocalAccount.issueOtp` in `lib/util/account.dart`.

---

## 1e. v1.1.5 — cashbook edit, ranges, payment mode, real OTP delivery

All 🟨 **CODE DONE** (unit-tested; not yet checked by hand on the phone).

| # | Status | Area | Page / option | What changed |
|---|---|---|---|---|
| **#044** | 🟨 CODE DONE | Cashbook | **Cashbook → a manual row → edit icon** | The entry sheet reopens pre-filled and saves over the same row (amount, category, mode, party, notes, date). Module-owned rows are refused with an explanation. |
| **#045** | 🟨 CODE DONE | Cashbook | **Cashbook → VIEW chips** | **Day · This month · All time · Range**. The list and the tally both use the chosen span; `Range` opens a date-range picker. |
| **#046** | 🟨 CODE DONE | Customer Profile | **You Gave ledger rows** | The stored payment mode is appended to the row note (`Late fee — note · UPI`). |
| **#065** | 🟨 CODE DONE | Passwords / OTP | **Password Settings → One-time code delivery** | Optional gateway URL + SMS/E-mail channel. Codes are really sent when it is set; otherwise the on-phone fallback stays, so nobody is locked out. |

---

## 1f. v1.1.6 — pawn tile density, caller actions, due-date labels, pawn-move gate, category defaults

All 🟨 **CODE DONE** (unit-tested; not yet checked by hand on the phone).

| # | Status | Area | Page / option | What changed |
|---|---|---|---|---|
| **#067** | 🟨 CODE DONE | Pawn list | **Pawn Loans → loan tiles** | Removed the wide customer-name / ID / three-dot gap. Row 1 is now photo + **Name** + **₹Amount** only; row 2 is a highlighted gold **ID** badge, village, loan date and item, the sync-state cloud (`cloud_done` green / `cloud_upload` when waiting), and the caller menu icon is available from the left-side move dot and from the tile menu. The wasted **Active** word on released tiles is gone. |
| **#068** | 🟨 CODE DONE | Pawn list | **Pawn Loans → each tile** | Caller functions: every pledge now offers **Call · SMS · WhatsApp · Move to another pawn profile · Edit** from the long-press menu, and Customer KYC & Details stays inside the customer/pawn profile beside the phone number. |
| **#069** | 🟨 CODE DONE | Pawn profile | **Customer Pawn Profile → Loan details** | Added a **Due Date (promised)**, an **Actual Due Date** and **Outstanding** that always refers to the actual due date. The form now also keeps the promised/actual due separate, and the **Edit** sheet keeps the actual column when the shop closes the date. |
| **#06A** | 🟨 CODE DONE | Pawn list | **Pawn Loans → Move to another pawn profile** | The move action asks for the simple pawn-move password (independent of delete/release; defaults to the admin secret, swappable in Password Settings), then moves one or many selected loans into a category. The delete / release ask-password prompt still lives only in **Settings** and **Password Settings** — it is not duplicated on the tile. |
| **#06B** | 🟨 CODE DONE | Pawn categories | **Pawn Loans → Categories** | Seeded defaults are **Forgot_Slip_List** and **Pawn_Removed**; **Add Custom** creates a new named category any time. Names can be renamed later and loans follow. |

---

## 2. Open bugs carried forward (from v1.0.24 audit)

| # | Status | Severity | Page / option | Problem | Suggested fix / file |
|---|---|---|---|---|---|
| **#020** | ✅ DONE | Critical | **Reports → Khata → Overdue accounts** | Shows the loan’s **whole outstanding**, not what is due today + arrears. Gives the shopkeeper a wrong collection figure. | Fixed: `dueNowForReports()` sums only scheduled installments / billed interest periods whose date has arrived, with collections applied oldest-first. `test/reports_due_test.dart` (4 cases). |
| **#021** | ✅ DONE | High | **Customer Profile header, khata member header, payment schedule** | Three money columns collide at large values (e.g. `₹100,002,0₹0`). | Fixed: flexible columns + `FittedBox`/ellipsis on the profile hero, schedule stats and khata row. Widget tests at 320 dp and 2× text. |
| **#022** | ✅ DONE | Medium | **Customer Profile app bar** | Five icons squeeze the title to `Custo…`. | Fixed: Call / SMS / WhatsApp / Move / Edit live in one ⋮ menu; the title has room again. |
| **#023** | ✅ DONE | Medium | **Khata filter “No Due Date”** | Actually filters “no reminder set”, not “no schedule”. Misleading. | Fixed: chip renamed **No reminder**; the existing predicate was already correct. |
| **#024** | ✅ DONE | Medium | **Every money figure** | Indian grouping missing in places (`₹8,333,500` instead of `₹83,33,500`). | Fixed: `moneyWhole` / `moneyWholeDown` now use true lakh/crore grouping; old Western-grouping test updated. |
| **#025** | ✅ DONE | Low | `flutter test` | Full run intermittently hangs in `migration_v9_test` teardown. | Fixed: reproduced (all 325 pass, then the runner never exits at the default one-isolate-per-core setting). `dart_test.yaml` caps concurrency at 2; plain `flutter test` now exits 0. |
| **#026** | ✅ DONE | Low | **Settings → Dark mode (Beta)** | Some screens are not fully dark. | Fixed: home avatar, dialog hints, khata dividers/progress track and red/green/blue status chips now use `surfaceOf` / `mutedOf` / `inkOf` / `redSoftOf` etc. Checked on phone: Settings, Home, Khata Books and the User Details dialog. |
| **#027** | ✅ DONE | Critical (Play) | **Release build** | APK is signed with the Android **debug** key. Play Store rejects it; cannot upgrade a real install. | Fixed: local upload keystore + `android/key.properties` (both gitignored). v1.1.3 APK verified with `apksigner`: `CN=Jewellery Suite, O=ShyberDev`, SHA-256 `54f9…1c09`. |
| **#028** | ✅ DONE | Critical (Play) | **Gradle signing** | Must fail loudly if `key.properties` is absent — never silently fall back to debug. | Fixed: Gradle task-graph guard checks the file, all four keys and the `.jks` path. Verified: `assembleRelease` fails with “Release signing is not configured…” when the file is moved away. |
| **#029** | ✅ DONE | High (Play) | **AndroidManifest** | Camera / media permissions review still pending for photo capture. | Audited with the Play policy scanner: **only `INTERNET`**. Photos use system camera / Photo Picker intents; the ML Kit scanner runs in Play services — no CAMERA or storage/media permission is required or declared. Cleartext HTTP stays for LAN (#042). |
| **#030** | ✅ DONE | Critical | **Cashbook auto-entries** | Editing or deleting a Khatabook/Pawn source row does not update/remove its cashbook entry → duplicated or stale cash. | Fixed: create/edit/zero/delete hooks for pawn loans & releases, khata loans/collections/given, member and khata deletion. Collections reference the collection UUID; legacy loan-keyed rows are migrated. `test/cashbook_linkage_test.dart`. |
| **#031** | ✅ DONE | High | **Refinance** | No **Cash OUT** entry is written for fresh cash handed over during refinance. | Fixed: `executeRefinance` writes `KHATA_REFINANCE` OUT for the **fresh cash only**; the rolled balance is a transfer, not cash. |
| **#032** | ✅ DONE | High | **Backup → Remove sample data** | Removes loans but leaves cashbook rows behind. | Fixed: sample removal deletes linked cashbook rows by reference/category and leaves real rows untouched. Covered by `test/cashbook_linkage_test.dart`. |
| **#033** | ✅ DONE | Medium | **Pawn dashboard → metal filter** | Filter only affects the reserve figure, not the loan list. | Already correct in the current code: `_metal` filters both `rows` and the summary strip in `pawn_screen.dart`. Tracker entry was stale; re-audited 2026-10-29. |
| **#034** | ✅ DONE | Medium | **Pawn dashboard** | Raw doubles shown (e.g. `1234.5600000001`). | Fixed: money uses `moneyWhole`; weights render to three decimals. Covered by `test/money_layout_test.dart`. |
| **#035** | ✅ DONE | High | **Backup** | Photos duplicated; several tables omitted from the snapshot. | Fixed: all 20 v15 tables tracked (including `migration_log` on fresh installs); photo paths deduped. `test/backup_service_test.dart`. |
| **#036** | ✅ DONE | High | **Backup → Restore** | No in-app restore; user must be walked through it. | Fixed: ⋮ → **Restore this backup** validates the archive, takes a verified safety backup, replaces DB + photos, then reloads `AppState`. Covered by 3 restore tests. |
| **#037** | ✅ DONE | Medium | **App start** | Opens already logged in; no lock. | Fixed: optional offline **4–6 digit PIN** app lock, salted hash, startup + background gate. Off by default; no recovery except clearing app data. `test/secret_test.dart` + `test/app_lock_gate_test.dart`. |
| **#038** | ✅ DONE | Critical (Play) | **Admin password** | Default is `admin`. | Fixed: forced first-run setup; minimum 6 characters; `admin` refused; salted hash stored, plain-text key removed. `test/secret_test.dart`. |
| **#039** | ✅ DONE | Low | **About App** | APK size hard-coded as 95 MB. | Fixed: reads the installed package size from Android through the `AppSize` MethodChannel; no hard-coded claim. Phone shows **93.3 MB**. |

---

## 3. Planned features (v1.1.4 and later)

| # | Status | Area | Feature | Notes |
|---|---|---|---|---|
| **#040** | 🔵 DEFERRED | Reminders | Local notifications for due / overdue members | Deferred from v1.1.1; needs notification permission. |
| **#041** | 🔵 DEFERRED | Reports | Export (PDF/Excel) and charts | Deferred from v1.1.1. |
| **#042** | 🔵 DEFERRED | Sync / Security | Enforce HTTPS for server sync | Keep LAN HTTP working for v1.1.1; revisit certificate/pinning. |
| **#043** | 🔵 DEFERRED | Jewellery module | Full buy/sell/stock/valuation module | The Home card currently says “coming soon”. |
| **#044** | 🟨 CODE DONE | Cashbook | Manual entry edit (v1.1.5) | A hand-typed row has an **edit** icon that reopens the entry sheet pre-filled (amount, category, mode, party, notes, date). Rows created by Khatabook / Pawn / Jewellery are refused — they must be corrected in their own module, so source and cash never disagree. `test/cashbook_edit_range_test.dart`. |
| **#045** | 🟨 CODE DONE | Cashbook | Date-range view (v1.1.5) | New **VIEW** row: **Day · This month · All time · Range**. Month/range use an inclusive `from`/`to` in the database, and the tally card follows the same filter. |
| **#046** | 🟨 CODE DONE | Customer Profile | Payment mode on You Gave rows (v1.1.5) | The ledger note now ends with the stored mode (`Late fee — note · UPI`). |
| **#047** | ⬜ TODO | Pawn | Filter/search pledge list by metal, status, due date | Partly exists; complete the list side (#033). |
| **#048** | ⬜ TODO | Backup | Scheduled/automatic local backup | Manual only today. |
| **#049** | ⬜ TODO | Security | Encrypted local DB | PIN lock (#037) and admin password (#038) are done; encryption is the remaining piece. |
| **#065** | 🟨 CODE DONE | Login / OTP | Deliver one-time codes by real SMS / Gmail | v1.1.5 adds **Password Settings → One-time code delivery**: paste an SMS/e-mail gateway URL, choose SMS or E-mail, and the app POSTs `{to, channel, purpose, code, message}`. Any 2xx counts as sent; the code is only shown on the phone when no gateway is set or the send fails. **Still needs the shop's gateway URL** (provider account) to leave the phone in production. |
| **#066** | ⬜ TODO | Security | Fingerprint / face unlock | The entry now lives in Password Settings (#059). Deferred: `local_auth` is not in the offline pub cache and the prompt would need a `FlutterFragmentActivity` switch plus device enrolment to verify, so the PIN / Daily MPIN remains the only method for now. |

---

## 4. Where to change what (fast file map)

| Page / feature | Main file(s) |
|---|---|
| New / edit Pawn Loan | `lib/ui/pawn_screen.dart`, `lib/state/app_state.dart` (`savePawnLoan`) |
| Pawn dashboard, filters | `lib/ui/pawn_dashboard_screen.dart` |
| Customer Profile, ledger, You Gave, refinance tile | `lib/ui/customer_profile_screen.dart` |
| Refinance dialog | `lib/ui/refinance_sheet.dart`, `lib/state/app_state.dart` (`executeRefinance`) |
| Khata list, filters, schedule | `lib/ui/khata_screen.dart`, `lib/ui/khatabook_screen.dart` |
| Cashbook UI + filters | `lib/ui/cashbook_screen.dart` |
| Cashbook queries / auto-hooks | `lib/data/local_db.dart`, `lib/state/app_state.dart` |
| Reports / overdue math | `lib/ui/reports_screen.dart` |
| Backup / restore | `lib/ui/backup_screen.dart`, `lib/data/backup_service.dart` |
| Save/restore through the phone file picker | `lib/util/backup_files.dart`, `android/.../MainActivity.kt` |
| Offline login, admin gate | `lib/state/app_state.dart`, `lib/ui/login_screen.dart`, `lib/ui/admin_password_gate.dart` |
| App lock (PIN / Daily MPIN) | `lib/ui/app_lock_gate.dart`, `lib/ui/password_settings_screen.dart`, `lib/util/app_lock.dart` |
| Account, sign-in, Forgot-password OTP | `lib/util/account.dart`, `lib/ui/login_screen.dart`, `lib/ui/otp_flow.dart` |
| Password centre (all passwords) | `lib/ui/password_settings_screen.dart`, `lib/ui/secret_dialogs.dart`, `lib/ui/admin_guard.dart` |
| Pawn categories | `lib/ui/pawn_screen.dart`, `lib/ui/pawn_categories_screen.dart`, `lib/data/migration_v16.dart` |
| Number / date formatting | `lib/util/format.dart` |
| Database schema + migrations | `lib/data/local_db.dart`, `lib/data/migration_v*.dart` |
| Home screen KPIs / greeting | `lib/ui/home_screen.dart` |
| Android manifest / permissions | `android/app/src/main/AndroidManifest.xml` |
| Release signing | `android/app/build.gradle.kts`, `android/key.properties` |

---

## 5. Change log

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
