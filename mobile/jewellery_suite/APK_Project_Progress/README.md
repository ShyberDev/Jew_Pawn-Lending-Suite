# Jewellery Suite — Master Task & Feature Tracker

**Folder:** `mobile/jewellery_suite/APK_Project_Progress/`
**Last updated:** 2026-10-28
**App version installed for testing:** v1.1.0 (versionCode 25, debug-signed)
**Next target:** v1.1.1 — fixes only (money, data, Play Store, backup, Cashbook/Reports)

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
| **#001** | 🟨 CODE DONE | System / Calculations | **New Pawn Loan → SAVE** | SAVE did nothing for a new customer. Root causes: (a) blank Customer ID was forced to `A01`, which is usually already used → duplicate-ID error; (b) the new customer was written with `id_front` / `id_back`, but the customers table has `id_photo_front` / `id_photo_back`; (c) the save was async with no error handler, so every failure looked like a dead button. | Blank ID now takes the next free book number. Photo columns corrected. Save wrapped in try/catch with a visible error message and a saving spinner. Selecting an existing customer now also loads their saved ID photos. |
| **#002** | 🟨 CODE DONE | System / Data | **Customer Profile → You Gave → Add** | Late fee / interest / principal could not be added after the first loan. `khatabook_given` had no `payment_mode` column, but every write sent one → SQL error, silently swallowed. | Schema v15 adds `khatabook_given.payment_mode`. The dialog now validates the amount (no more silent no-op) and shows a message if the save fails. |
| **#003** | 🟨 CODE DONE | System UI / Calculations | **Customer Profile → ledger → refinance transfer** | The old loan’s ₹33,000 transfer was shown without saying what it was, next to the new ₹63,000 loan. Could not tell which amount was refinanced and which was fresh cash. It also sorted ABOVE the new loan because same-day rows all tied at midnight. | Transfer tile now headlines the **new loan total ₹63,000** (“new loan”), then a gold line: **Refinanced amount ₹33,000 • Fresh cash ₹25,000**, then the balance. Same-day ledger rows now order by their entry time, and the transfer is stamped one second before the new loan, so the ₹63,000 row sits directly above the ₹33,000 line. The “moved, not paid” note stays. |
| **#004** | 🟨 CODE DONE | System UI | **Customer Profile → ledger → balance line** | Lowercase `bal ₹…` looked unfinished. | Now **`Bal ₹…`**. |
| **#005** | 🟨 CODE DONE | System UI / Cashbook | **Cashbook → filters** | Only Cash / UPI / Bank could be filtered. Could not isolate Khatabook, Pawn, Jewellery or manual entries. The daily tally also ignored the active filters. | Two filter rows: **Source** = All / Khatabook / Pawn / Jewellery / Manual, and **Payment** = All modes / Cash / UPI / Bank. Both combine. The total-in / total-out / net card now follows the filters exactly. Jewellery and Manual filter chips are ready for future modules. |
| **#006** | ✅ DONE | Documentation | **Project tracking** | No single place to see done / todo / improve. | This folder and file. |

> **Phone verification pending for #001–#005.** The APK must be rebuilt and installed before they can be marked ✅.

---

## 2. Open bugs carried forward (from v1.0.24 audit)

| # | Status | Severity | Page / option | Problem | Suggested fix / file |
|---|---|---|---|---|---|
| **#020** | 🔴 BUG | Critical | **Reports → Khata → Overdue accounts** | Shows the loan’s **whole outstanding**, not what is due today + arrears. Gives the shopkeeper a wrong collection figure. | Use the schedule/`To Collect` engine. `lib/ui/reports_screen.dart:150` |
| **#021** | 🔴 BUG | High | **Customer Profile header, khata member header, payment schedule** | Three money columns collide at large values (e.g. `₹100,002,0₹0`). | Flexible columns + `FittedBox`/ellipsis. Widget test at 320 dp and 2× text. |
| **#022** | 🔴 BUG | Medium | **Customer Profile app bar** | Five icons squeeze the title to `Custo…`. | Move secondary actions into an overflow menu. |
| **#023** | 🔴 BUG | Medium | **Khata filter “No Due Date”** | Actually filters “no reminder set”, not “no schedule”. Misleading. | Rename to “No reminder” or change the predicate. `lib/ui/khata_screen.dart:1151` |
| **#024** | 🔴 BUG | Medium | **Every money figure** | Indian grouping missing in places (`₹8,333,500` instead of `₹83,33,500`). | Apply `moneyWhole`/`moneyWholeDown` consistently; check `format.dart`. |
| **#025** | ⬜ TODO | Low | `flutter test` | Full run intermittently hangs in `migration_v9_test` teardown. | Close every DB handle; condition-based wait. |
| **#026** | ⬜ TODO | Low | **Settings → Dark mode (Beta)** | Some screens are not fully dark. | Theme audit. |
| **#027** | 🔴 BUG | Critical (Play) | **Release build** | APK is signed with the Android **debug** key. Play Store rejects it; cannot upgrade a real install. | Configure `key.properties` + release keystore; fail build when missing. `android/app/build.gradle.kts` |
| **#028** | ⬜ TODO | Critical (Play) | **Gradle signing** | Must fail loudly if `key.properties` is absent — never silently fall back to debug. | Add explicit check in Gradle. |
| **#029** | ⬜ TODO | High (Play) | **AndroidManifest** | Camera / media permissions review still pending for photo capture. | Declare only what is used; verify with Play policy skill. |
| **#030** | 🔴 BUG | Critical | **Cashbook auto-entries** | Editing or deleting a Khatabook/Pawn source row does not update/remove its cashbook entry → duplicated or stale cash. | Cashbook entry must follow its source row (update + delete hooks). `app_state.dart` |
| **#031** | 🔴 BUG | High | **Refinance** | No **Cash OUT** entry is written for fresh cash handed over during refinance. | Add cashbook hook in `executeRefinance`. |
| **#032** | 🔴 BUG | High | **Backup → Remove sample data** | Removes loans but leaves cashbook rows behind. | Delete cashbook rows by reference/category in the sample remover. |
| **#033** | 🔴 BUG | Medium | **Pawn dashboard → metal filter** | Filter only affects the reserve figure, not the loan list. | Apply the filter to the list query too. |
| **#034** | 🔴 BUG | Medium | **Pawn dashboard** | Raw doubles shown (e.g. `1234.5600000001`). | Use the money formatter everywhere. |
| **#035** | 🔴 BUG | High | **Backup** | Photos duplicated; several tables omitted from the snapshot. | Track every v15 table; dedupe photo paths; test restore round-trip. `backup_service.dart` |
| **#036** | ⬜ TODO | High | **Backup → Restore** | No in-app restore; user must be walked through it. | Add restore flow + validation + auto-backup before restore. |
| **#037** | ⬜ TODO | Medium | **App start** | Opens already logged in; no lock. | Optional PIN / biometric lock; keep offline-first. |
| **#038** | 🔴 BUG | Critical (Play) | **Admin password** | Default is `admin`. | Force change on first run; store a hash, not plain text. |
| **#039** | 🔴 BUG | Low | **About App** | APK size hard-coded as 95 MB. | Read real package size or remove the claim. |

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

### 2026-10-28 — v1.1.1 development round 1
- Added **#001–#006** (this round).
- Added schema **v15** (`khatabook_given.payment_mode`).
- Added regression suite `test/v1_1_1_regression_test.dart` (8 tests).
- `flutter analyze`: clean. **284 tests pass** (276 old + 8 new).
- Same-day ledger ordering fixed (`ledgerWhen`) so a refinance transfer sits below the new loan.
- Built **v1.1.1 / versionCode 26** APK; awaiting device connection for install and verification.
- Committed as `82835f7` on `develop` (not pushed).
- APK `mobile/jewellery_suite-release.apk`, SHA-256 `549a6110…29cc5a1`, still **debug-signed** — release signing remains #027/#028.

### 2026-10-28 — v1.1.0 installed for testing
- Commit `488b4c8`: personalised greeting, editable Khata type, Lolugu map default.
- Installed v1.1.0 / versionCode 25; user reported **#001–#005**.
