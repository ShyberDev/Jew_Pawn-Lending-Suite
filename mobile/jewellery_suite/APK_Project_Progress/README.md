# Jewellery Suite — Master Task & Feature Tracker

**Folder:** `mobile/jewellery_suite/APK_Project_Progress/`
**Last updated:** 2026-10-29
**App version installed for testing:** v1.1.1 (versionCode 27, debug-signed) — still installed; cannot be upgraded in place (signing key change)
**Release build ready:** v1.1.2 (versionCode 28, **release-signed**) — `mobile/jewellery_suite-release.apk`, SHA-256 `1beb0a1a8f52421ade4c2f40495a66d7ed1c12716ea7609f810fb4d2959d1a3c`
**Next target:** v1.1.3 — deferred features #040–#043, plus any phone-verification fixes from this batch

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

## 1b. Bug-fix round — #020–#039 (v1.1.2, code complete)

All twenty items are implemented. The status is **🟨 CODE DONE** until the phone checks below are done. #025, #027, #028, #029 and #033 are fully closed.

**Verification already run**

- `flutter analyze`: **No issues found**.
- `flutter test`: **314 tests pass**, and the plain command now exits by itself (#025). New regressions: `reports_due_test.dart` (4), `cashbook_linkage_test.dart` (8), `secret_test.dart` (8), `money_layout_test.dart` (3), a metal-filter test, plus 3 restore tests in `backup_service_test.dart`.
- **Signed release build:** v1.1.2 / versionCode 28, `mobile/jewellery_suite-release.apk` (97.8 MB).
  - SHA-256 `1beb0a1a8f52421ade4c2f40495a66d7ed1c12716ea7609f810fb4d2959d1a3c`
  - Signer: `CN=Jewellery Suite, OU=Mobile, O=ShyberDev, L=India, ST=India, C=IN`
  - Certificate SHA-256 `54f9833223d1a85278a749b89ffa613cecc88e147dca25fa1cf6bad52ab61c09`
- `android/key.properties` and `android/app/upload-keystore.jks` exist locally, are gitignored, and **must be backed up together**. Losing them means Play cannot accept an update. Credentials are never written into this tracker.

**Phone checklist**

1. **#020** Reports → Khata → Overdue accounts shows today + arrears, not the whole balance.
2. **#021** Profile, khata row and schedule stay readable at 320 dp / 2× text.
3. **#022** Profile app bar title is not squeezed; ⋮ holds Call / SMS / WhatsApp / Move / Edit.
4. **#023** Khata filter says **No reminder**.
5. **#024 / #034** Money shows lakh/crore grouping (`₹83,33,500`); pawn weights show three decimals.
6. **#026** Dark mode: home avatar, dialogs, khata dividers/progress and status chips.
7. **#030–#032** Edit/zero/delete a loan or collection and confirm Cashbook follows; delete sample data and confirm demo cash is gone.
8. **#031** Refinance writes Cash OUT for fresh cash only.
9. **#035 / #036** Create a backup, change a customer, restore, confirm the change is undone and a safety backup exists.
10. **#037** Enable the PIN, background and reopen the app; wrong PIN stays locked.
11. **#038** First run demands a new admin password; `admin` and anything under 6 characters are refused.
12. **#039** About App shows the real installed size, not 95 MB.

> **Upgrade warning:** the phone currently has **v1.1.1 / versionCode 27 signed with the Android debug key**. The new APK uses the shop’s release key, so Android will refuse an in-place update. Keep an exported backup (or let the installer migrate the data) before uninstalling the old build.

---

## 2. Open bugs carried forward (from v1.0.24 audit)

| # | Status | Severity | Page / option | Problem | Suggested fix / file |
|---|---|---|---|---|---|
| **#020** | 🟨 CODE DONE | Critical | **Reports → Khata → Overdue accounts** | Shows the loan’s **whole outstanding**, not what is due today + arrears. Gives the shopkeeper a wrong collection figure. | Fixed: `dueNowForReports()` sums only scheduled installments / billed interest periods whose date has arrived, with collections applied oldest-first. `test/reports_due_test.dart` (4 cases). |
| **#021** | 🟨 CODE DONE | High | **Customer Profile header, khata member header, payment schedule** | Three money columns collide at large values (e.g. `₹100,002,0₹0`). | Fixed: flexible columns + `FittedBox`/ellipsis on the profile hero, schedule stats and khata row. Widget tests at 320 dp and 2× text. |
| **#022** | 🟨 CODE DONE | Medium | **Customer Profile app bar** | Five icons squeeze the title to `Custo…`. | Fixed: Call / SMS / WhatsApp / Move / Edit live in one ⋮ menu; the title has room again. |
| **#023** | 🟨 CODE DONE | Medium | **Khata filter “No Due Date”** | Actually filters “no reminder set”, not “no schedule”. Misleading. | Fixed: chip renamed **No reminder**; the existing predicate was already correct. |
| **#024** | 🟨 CODE DONE | Medium | **Every money figure** | Indian grouping missing in places (`₹8,333,500` instead of `₹83,33,500`). | Fixed: `moneyWhole` / `moneyWholeDown` now use true lakh/crore grouping; old Western-grouping test updated. |
| **#025** | ✅ DONE | Low | `flutter test` | Full run intermittently hangs in `migration_v9_test` teardown. | Fixed: reproduced (all 314 pass, then the runner never exits at the default one-isolate-per-core setting). `dart_test.yaml` caps concurrency at 2; plain `flutter test` now exits 0. |
| **#026** | 🟨 CODE DONE | Low | **Settings → Dark mode (Beta)** | Some screens are not fully dark. | Fixed: home avatar, dialog hints, khata dividers/progress track and red/green/blue status chips now use `surfaceOf` / `mutedOf` / `inkOf` / `redSoftOf` etc. Phone visual check pending. |
| **#027** | ✅ DONE | Critical (Play) | **Release build** | APK is signed with the Android **debug** key. Play Store rejects it; cannot upgrade a real install. | Fixed: local upload keystore + `android/key.properties` (both gitignored). v1.1.2 APK verified with `apksigner`: `CN=Jewellery Suite, O=ShyberDev`, SHA-256 `54f9…1c09`. |
| **#028** | ✅ DONE | Critical (Play) | **Gradle signing** | Must fail loudly if `key.properties` is absent — never silently fall back to debug. | Fixed: Gradle task-graph guard checks the file, all four keys and the `.jks` path. Verified: `assembleRelease` fails with “Release signing is not configured…” when the file is moved away. |
| **#029** | ✅ DONE | High (Play) | **AndroidManifest** | Camera / media permissions review still pending for photo capture. | Audited with the Play policy scanner: **only `INTERNET`**. Photos use system camera / Photo Picker intents; the ML Kit scanner runs in Play services — no CAMERA or storage/media permission is required or declared. Cleartext HTTP stays for LAN (#042). |
| **#030** | 🟨 CODE DONE | Critical | **Cashbook auto-entries** | Editing or deleting a Khatabook/Pawn source row does not update/remove its cashbook entry → duplicated or stale cash. | Fixed: create/edit/zero/delete hooks for pawn loans & releases, khata loans/collections/given, member and khata deletion. Collections reference the collection UUID; legacy loan-keyed rows are migrated. `test/cashbook_linkage_test.dart`. |
| **#031** | 🟨 CODE DONE | High | **Refinance** | No **Cash OUT** entry is written for fresh cash handed over during refinance. | Fixed: `executeRefinance` writes `KHATA_REFINANCE` OUT for the **fresh cash only**; the rolled balance is a transfer, not cash. |
| **#032** | 🟨 CODE DONE | High | **Backup → Remove sample data** | Removes loans but leaves cashbook rows behind. | Fixed: sample removal deletes linked cashbook rows by reference/category and leaves real rows untouched. Covered by `test/cashbook_linkage_test.dart`. |
| **#033** | ✅ DONE | Medium | **Pawn dashboard → metal filter** | Filter only affects the reserve figure, not the loan list. | Already correct in the current code: `_metal` filters both `rows` and the summary strip in `pawn_screen.dart`. Tracker entry was stale; re-audited 2026-10-29. |
| **#034** | 🟨 CODE DONE | Medium | **Pawn dashboard** | Raw doubles shown (e.g. `1234.5600000001`). | Fixed: money uses `moneyWhole`; weights render to three decimals. Covered by `test/money_layout_test.dart`. |
| **#035** | 🟨 CODE DONE | High | **Backup** | Photos duplicated; several tables omitted from the snapshot. | Fixed: all 20 v15 tables tracked (including `migration_log` on fresh installs); photo paths deduped. `test/backup_service_test.dart`. |
| **#036** | 🟨 CODE DONE | High | **Backup → Restore** | No in-app restore; user must be walked through it. | Fixed: ⋮ → **Restore this backup** validates the archive, takes a verified safety backup, replaces DB + photos, then reloads `AppState`. Covered by 3 restore tests. |
| **#037** | 🟨 CODE DONE | Medium | **App start** | Opens already logged in; no lock. | Fixed: optional offline **4–6 digit PIN** app lock, salted hash, startup + background gate. Off by default; no recovery except clearing app data. `test/secret_test.dart`. |
| **#038** | 🟨 CODE DONE | Critical (Play) | **Admin password** | Default is `admin`. | Fixed: forced first-run setup; minimum 6 characters; `admin` refused; salted hash stored, plain-text key removed. `test/secret_test.dart`. |
| **#039** | 🟨 CODE DONE | Low | **About App** | APK size hard-coded as 95 MB. | Fixed: reads the installed package size from Android through the `AppSize` MethodChannel; no hard-coded claim. Phone display check pending. |

---

## 3. Planned features (v1.1.2 and later)

| # | Status | Area | Feature | Notes |
|---|---|---|---|---|
| **#040** | 🔵 DEFERRED | Reminders | Local notifications for due / overdue members | Deferred from v1.1.1; needs notification permission. |
| **#041** | 🔵 DEFERRED | Reports | Export (PDF/Excel) and charts | Deferred from v1.1.1. |
| **#042** | 🔵 DEFERRED | Sync / Security | Enforce HTTPS for server sync | Keep LAN HTTP working for v1.1.1; revisit certificate/pinning. |
| **#043** | 🔵 DEFERRED | Jewellery module | Full buy/sell/stock/valuation module | The Home card currently says “coming soon”. |
| **#044** | ⬜ TODO | Cashbook | Manual entry edit (currently add/delete only) | Useful once #030 lands. |
| **#045** | ⬜ TODO | Cashbook | Date-range view (“This month”, “All time”) | Today-only view today; source filter is now in place. |
| **#046** | ⬜ TODO | Customer Profile | Show payment mode on You Gave rows | The row now stores `payment_mode`; display it. |
| **#047** | ⬜ TODO | Pawn | Filter/search pledge list by metal, status, due date | Partly exists; complete the list side (#033). |
| **#048** | ⬜ TODO | Backup | Scheduled/automatic local backup | Manual only today. |
| **#049** | ⬜ TODO | Security | App lock, encrypted local DB | After #037 + #038. |

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
| Number / date formatting | `lib/util/format.dart` |
| Database schema + migrations | `lib/data/local_db.dart`, `lib/data/migration_v*.dart` |
| Home screen KPIs / greeting | `lib/ui/home_screen.dart` |
| Android manifest / permissions | `android/app/src/main/AndroidManifest.xml` |
| Release signing | `android/app/build.gradle.kts`, `android/key.properties` |

---

## 5. Change log

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
