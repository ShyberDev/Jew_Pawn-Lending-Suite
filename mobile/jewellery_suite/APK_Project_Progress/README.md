# Jewellery Suite — Master Task & Feature Tracker

**Folder:** `mobile/jewellery_suite/APK_Project_Progress/`
**Last updated:** 2026-11-05 (**v1.4.5 / versionCode 57** is installed on the phone — **#073 dark-mode labels is ✅ phone-verified**: the hard-coded near-black ink the 2026-11-02 note left behind is gone from the Khata filter chips, the Khata summary card, the Reports tabs, the interest-calculator chips and the customer-profile ledger stamps, and light mode is unchanged). **v1.4.4 / versionCode 56** was the previous install — **#071 Reports is ✅ phone-verified**: the Khata tab shows the Pawn-style filters and metric cards, and the single **Share** button offers PDF / Excel / CSV then reaches the real Android share sheet). **#071 Reports:** the Khata tab is now filters + metric cards + the collection list (Pawn layout) instead of eleven tappable rows, and one **Share** button asks for **PDF / Excel / CSV** and then opens Android's share sheet. **#072 Google Drive backup + multi-device sync is designed, not coded** — see `docs/GOOGLE_DRIVE_SYNC.md`; it is blocked on a Google OAuth client ID for the app, which only the shop can create in Google Cloud Console. **#070 Indian mobile numbers:** a number is accepted as 10 digits or +91 and the 10 digits, Call/SMS dial the agreed `+91` form, and WhatsApp now carries the country code `wa.me` requires — the old link dropped it, so an Indian number never opened the right chat. **#049 encrypted local database is ✅ phone-verified**: the plaintext ledger migrated to SQLCipher on the device, the key sits in the Android keystore, and two migration defects were found and fixed on the phone (see the 2026-11-04 #049 change log). Before that, **v1.3.5 / versionCode 2051** carried **#066 fingerprint unlock ✅ phone-verified** after two lock-screen defects were found and fixed on the device; earlier: **#06L** dark-mode chip contrast fixed on the phone, and **#063** pawn filters/search ✅ phone-verified. **v1.2.1** restored the real app shell (**#06K** ✅). **v1.2.0** carried **#040 due reminders**; **#06G/#06H/#06I/#06J**, **#057**, **#044**, **#046** and **#040** phone-verified — see sections 1d/1e/1g/3 and the change log). Latest code change: **#043 jewellery is ✅ DONE (phone-verified on v1.3.0)** (schema v20) — **KDM / Non-KDM retail sale pricing**, separate sale/purchase forms, **Customer Credit Book · Orders · Workers · Old Metal · Returns · Reports**, **Supplier Payables**, **stock valuation**, **document search/filter** and a package-free **six-month sales/purchases chart** are built. **#047** pawn due-date filtering and **#070** Indian mobile numbers are ✅ phone-verified on v1.4.4. `flutter analyze` clean, **485 tests passing**. **The jewellery batch shipped in v1.3.0 (versionCode 2046) and is carried by the installed v1.4.4 build** — **#043** is fully phone-verified (KDM/non-KDM pricing, order → delivery, credit book, supplier payments, cashbook directions, returns, workers, old metal, filters, stock valuation and the chart), and the pawn **Due date range** filter is live.
**Working branch for APK + GitHub traceability:** `Apk_Develop_Branch_01_11` (created 01/11/2026). This branch is the current APK develop loop: release-sign the build → install on the phone via wireless debugging → do the hands-on phone pass → record the result here → commit and push on this branch.
**App version installed for testing:** **v1.4.5 (versionCode 57, release-signed, arm64 split)** — installed in place on 2026-11-05 over wireless debugging to the Redmi Note 8 Pro at **`10.52.61.148:42895`** with `adb install -r`, data kept; `dumpsys` reports `versionName=1.4.5`, and the encrypted DB opened as `SQLCipher encrypted, schema v20`. The address changes every session (this one replaced the stale `10.235.54.202:41273`); discover it with `adb mdns services`, then confirm with `adb shell echo alive`. It carries **#049**: the ledger is now SQLCipher-encrypted, so logcat shows `[db] open: SQLCipher encrypted, schema v20` and About → Storage reads **Encrypted (SQLCipher)**. The phone went unreachable at the end of the pass (mDNS advertised `10.235.54.202:41273`, connection refused), so re-discover the address before the next install. **The password gates are armed again** (`kDevPasswordGateDisabled = false` in `lib/util/secret_dev.dart`), because the dev switch skips `AppLockGate` and `AdminPasswordGate` entirely — with it on, neither the lock screen nor the biometric prompt can be reached. The phone is left with screen lock **Every time** + fingerprint **on**; set the lock to **Off** in Password Settings to skip the prompt while developing. Cold start → lock screen → one touch → `MainActivity`, no crash in logcat.
**Release build:** v1.4.5 (versionCode 57, **release-signed**, arm64 split) — `mobile/jewellery_suite_v1.4.5-arm64-v8a.apk` (`45,660,940` bytes), SHA-256 `bff3c554c1ab3a662f3b6d703efde810db8f55d2b33dcbc5e3a667236b7bcb96`, **installed in place on 2026-11-05 at `10.52.61.148:42895`, data kept**. It carries **#073** (dark-mode ink). An intermediate v1.4.5 build from the same round, SHA-256 `06b7da4ca659061848b293a0be8d5e3146becef0e3da625838d840168e8d8a7a`, was installed and then replaced in place because the Khata summary card was still dark. Previous: v1.4.4 (56) — `mobile/jewellery_suite_v1.4.4-arm64-v8a.apk` (`45,660,940` bytes), SHA-256 `3b7452bdaf55a9dca9df100db96d7f7cb46cd1a7e6510140de61f38bc6c614f5`, installed in place on 2026-11-04, data kept. Earlier in the round: v1.4.3 (55) carried #070 Indian mobile numbers, SHA-256 `0c1d6d68…eefa7361b87`, superseded before install. Previously installed: v1.4.2 (54) — `mobile/jewellery_suite_v1.4.2-arm64-v8a.apk` (`45,661,104` bytes), SHA-256 `6f65f123c0ce7dfcf4ea520982d21627690745353b18618526080d3a10dacdee`, installed in place over v1.4.1, data kept. Earlier in the same round: v1.4.1 (2053) hardened the migration, v1.4.0 (2052) was the first SQLCipher build and was superseded because of the schema-version defect. Previous: v1.3.2 (versionCode 2048, **release-signed**, arm64 split) — `mobile/jewellery_suite_v1.3.2-arm64-v8a.apk` (`39,920,526` bytes), SHA-256 `27640c4592f96952822b8798e5ca73be006998d1b1aca5a42fd799c8f350ab13`, built and **installed in place, data kept** on 2026-11-03. Previous v1.3.1 (versionCode 2047, **release-signed**, arm64 split) — `mobile/jewellery_suite_v1.3.1-arm64-v8a.apk` (`38,483,916` bytes), SHA-256 `60ae17f2c3ca5db0319d3dba5c75081a773c9fed94c47bb7cd47662283eb7a47`, built 2026-11-03 and **installed in place, data kept**. Previous v1.3.0 (2046) — `mobile/jewellery_suite_v1.3.0-arm64-v8a.apk` (`37,172,836` bytes), SHA-256 `bf6ef15f318fecaa8163921f4b9b8b6280a1d6f4c87df8c71313bfb80127d36b` from `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. **Installed in place on 2026-11-03 (data kept).** Use split APKs (`flutter build apk --release --split-per-abi`): the universal versionCode 46 cannot upgrade the installed split build. Previous: v1.2.8 (44) SHA-256 `1bf11e52159933e632fb5ecb26233ae12c1346117c8bf077af40098894470c58`; v1.2.7 (43) SHA-256 `acb59224…7e3b312`; v1.2.6 (42) SHA-256 `015c8746…b0f4da`; v1.2.5 (41) SHA-256 `db39a8ba…6579a1b`; v1.2.4 (40) SHA-256 `128e227c…a9ff633`; v1.2.3 (39) SHA-256 `479cae95…2c71579`; v1.2.2 (versionCode 38) SHA-256 `44824379…73e8b33`; v1.2.1 (versionCode 37) SHA-256 `cbb22833…af727ee1`; v1.2.0 (versionCode 36) SHA-256 `36b9a2a7…1b7171`
**Published APK:** GitHub release **v1.4.4** (2026-11-04) — assets `jewellery_suite_v1.4.4-arm64-v8a.apk` (45,660,940 bytes, SHA-256 `3b7452bd…c614f5`), `jewellery_suite_v1.4.4-armeabi-v7a.apk` (38,335,066 bytes, SHA-256 `4e232ef4…dc2cfbe`) and `jewellery_suite_v1.4.4-x86_64.apk` (48,423,383 bytes, SHA-256 `fd8ee43d…7fc4d5f7`); tag `v1.4.4` points at `6315c2c`. This is the first published build since **v1.1.6** — `mobile/.gitignore` excludes `*.apk`, so APKs ship as release assets. **Release asset verified end-to-end:** the arm64 asset was re-downloaded from the release, its SHA-256 matched, and `adb install -r` over the phone kept the data (`versionCode 2056 / 1.4.4`, `SQLCipher encrypted, schema v20`, Home still ₹10,000 pawn investment).
**Next target:** **#075 is 🟨 CODE DONE (v1.4.7)** — every box in the §2 workflow checklist is now satisfied. #074 built the allocation engine's missing caller, the saved-rate graph and WIP reconciliation; #075 closed the last three (schema v21): a purchase saves as a **draft that moves no stock** and is confirmed exactly once, a **shared expense** is split by weight, and a **manual late fee** is a separate charge. **#073 is ✅ DONE (v1.4.5)** — the dark-mode ink debt noted on 2026-11-02 is closed and phone-verified. **#049 is ✅ DONE (v1.4.2)** — SQLCipher with a keystore-held key, a one-time plaintext migration, encrypted backups and a self-repair for version-less ciphertext files — so every planned item is closed except the parked work. Remaining: **#072** Google Drive backup + multi-device sync (needs the shop's Android OAuth client ID), a real SMS/e-mail gateway for **#065** (needs the shop's provider account/URL) and HTTPS + certificate pinning for **#042** (deferred until the server has TLS). **#043** (jewellery module), **#041** (CSV/PDF/Excel + chart), **#066** (fingerprint), **#06A** (v1.2.5), **#048** (v1.2.6), **#064** (v1.2.3), **#040**, **#057**, **#044**, **#046** and **#06J** are all ✅ phone-verified. **Play Store work is parked until v2.**


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

Everything below was 🟨 **CODE DONE** in v1.1.4. The hands-on pass on v1.1.7 now marks
**#055, #056, #061, #062 and #06B** ✅ DONE; the rest still need their own phone check.

| # | Status | Area | Page / option | Request | What was changed |
|---|---|---|---|---|---|
| **#055** | ✅ DONE | Home / Customers | **Home → General → Customers** | The name should read **Customers** Book | Drawer tile and the screen title now say **Customers Book**. Phone check: both read **Customers Book**. |
| **#056** | ✅ DONE | Settings | **Settings → Ask password for delete / release** | The switch is available in two places | Removed from Settings. It lives only in **Password Settings** now, with its per-action switches. Phone check: Settings no longer carries the switch. |
| **#057** | ✅ DONE | Login / account | **Login screen** | Create one account per shop with a **Gmail or mobile number**, sign in with a password **or a one-time code**, and stay signed in until Logout | New local account (identifier + salted password hash). Login screen has **Create account** and **Sign in**, password or OTP, and an optional collapsible **shop server** login for sync. The session persists across restarts; **Logout** clears it. An existing phone that already holds the ledger is never locked out (auto-continues). **Bug found on the phone 2026-11-01 (v1.1.8) and fixed in v1.1.9:** after the PIN the app showed the account login instead of Home even though the ledger was on the phone. `AppState.load()` applied the “phone already holds the ledger” fallback only when **no account existed**, so an account without an active session (lost during an in-place install / restore) fell to Login. The fallback now runs whenever the phone holds records, and a new `account_signed_out` marker keeps a deliberate **Logout** honoured — the only way back to the login form. **Phone check (v1.1.9):** cold start → PIN `1234` → **Home** (“Good Afternoon”, ₹20,000 pawn), no account login. Covered by `test/account_session_test.dart` (6 cases). |
| **#058** | ✅ DONE | Passwords | **Every password** | A **Forgot password** path for each one | Admin password, login password and screen-lock PIN/MPIN each have **Forgot …?**. The flow sends a 6-digit code to the account identifier and then asks for the new secret. Codes are hashed, valid 10 minutes, blocked after 5 wrong tries. **Phone check (v1.1.9/v1.2.0):** the shop's own login password was unknown to everyone, so **Forgot password?** was run end-to-end — **Send code** → *Offline code (valid 10 minutes)* `298947` → **Verify** → **New login password** → **Save**, and the dialog closed back to Password Settings. The **Forgot PIN?** and admin **Forgot …?** buttons open the same shared OTP flow. **Not verified:** signing back in with the newly set password — the sign-in form kept flipping into one-time-code mode between taps, and `Change login password → Current password` returned to the card without opening the new-password dialog, so the stored password could not be confirmed from the phone. The reset path itself is what #058 asks for; the account password is still recorded in `Temp_Passwords_readme.md` with the OTP fallback spelled out. |
| **#059** | ✅ DONE | System / Security | **Home → System → Biometric & screen lock** | Move it into Password Settings; add a **Daily MPIN**; let each password be enabled/disabled | The drawer entry is gone. Password Settings now holds **Account & login**, **Biometric & screen lock** (Off / Every time / **Daily MPIN**), **Delete / Release**, and **Admin password**. Every one can be changed and reset, and login-by-password / login-by-code are individual switches. **Phone check (v1.1.9/v1.2.0):** the drawer no longer carries a separate lock entry; Password Settings shows **Account & login** (identifier, two method switches, Change/Forgot password), the lock row **Off · Every time · Daily MPIN** with **Change PIN / Forgot PIN?**, the **Ask MPIN for Delete / Release** card with its per-action switches, and the admin password card. The three lock chips (Off / Every time / Daily MPIN) were all reachable and tappable, and every password card carries its own Change and Forgot entry. **Not verified:** the once-per-calendar-day behaviour of Daily MPIN (it needs a day boundary to observe). |
| **#060** | ✅ DONE | Pawn list | **Pawn Loans → loan tiles** | Two rows; highlight ID, name and amount; drop the **Active** word; a real sync-state cloud | Row 1: photo, **Name** (bold) and **₹Amount** (bold gold). Row 2: gold **ID badge**, village, date and item, then the cloud state — `cloud_done` green when synced, `cloud_upload` when waiting. Active is no longer written on the tile; a released loan is muted with a small **Released** tag. **Phone check:** the two rows, ID badge, name/amount and Released tag are correct; the missing sync-state cloud was logged as **#06J** and is now rendered and phone-verified on v1.1.8. |
| **#061** | ✅ DONE | Pawn actions | **Pawn Loans → tile menu** | Caller functions like Khatabook | Every tile has a ⋮ / long-press menu: **Call · SMS · WhatsApp · Move to another pawn profile · Edit**. Edit changes principal (only when nothing is paid), interest rate and both dates, and recalculates interest/payable/balance. Phone check: long-press opens **Call / SMS / WhatsApp / Move / Edit**. |
| **#062** | ✅ DONE | Pawn categories | **Pawn Loans → Categories** | Categories beside Active / Released / Villages, with custom names and multi-move | New **Categories ▾** filter seeded with **Forgot_Slip_List** and **Pawn_Removed**. Manage screen adds custom categories, renames them (loans follow) and removes labels. App-bar checklist turns on **multi-select**; the bottom bar moves every selected loan in one go. Phone check: both seeded names plus **Add Custom** are present. |
| **#063** | ✅ DONE | Pawn filters / search | **Pawn Loans → filters** | Toggle chips off, search by name/ID/amount, date range | Tapping the selected **Active**, **Released**, **Gold**, **Silver** or **Mixed** chip clears it (shows everything). Search matches **name, book ID, amount**, phone or village. New **Date** chip opens a from–to range on the loan date and can be cleared. **Phone check (v1.2.2, 2026-11-01):** tapping **Active** cleared it and the list then showed both **Phone QA A03 · ₹60,000 · Released** and **Phone QB A04 · ₹20,000**; search `A04` and `20000` both kept the ₹20,000 row, `A049` emptied the list (*No pawn loans here.*) and zeroed the strip to ₹0/₹0/₹0, `Phone` showed both accounts; **Date range** applied `1 Nov – 30 Nov` (pill + caption under the summary, loan kept) and then `1 Dec – 31 Dec`, which emptied the list and zeroed the summary. | |
| **#064** | ✅ DONE | Database | **Schema** | — | **v16**: `pawn_loans.category` + `pawn_categories` table, seeded once. Backups track the new table, and restore now keeps the phone's account + lock settings across the replacement. **Phone check (v1.2.3, 2026-11-02):** the pawn Filter menu listed **All categories · Forgot_Slip_List · Pawn_Removed** and the move sheet listed both seeded names, so the v16 table is live on the device; **Pawn Categories** showed both with `0 loan(s)`, and a custom **QA_Cat** was added from **Add Custom** (appeared as `0 loan(s)`) and removed again through its menu → OK (*Remove the category "QA_Cat"?*). The phone was left with the two seeded categories only. |

> **OTP delivery — known limitation.** The app is offline and ships no SMS/e-mail gateway, so
> the one-time code is generated on the phone and shown in the dialog, clearly marked
> **Offline code (valid 10 minutes)**. The verification itself is real (salted hash, expiry,
> attempt cap). Connecting an SMS or e-mail service later only changes
> `LocalAccount.issueOtp` in `lib/util/account.dart`.

---

## 1e. v1.1.5 — cashbook edit, ranges, payment mode, real OTP delivery

**#045**, **#044** and **#046** are ✅ DONE (the last two on the v1.1.9 phone pass); **#065** is still
🟨 **CODE DONE** and needs the shop's SMS/e-mail gateway URL.

| # | Status | Area | Page / option | What changed |
|---|---|---|---|---|
| **#044** | ✅ DONE | Cashbook | **Cashbook → a manual row → edit icon** | The entry sheet reopens pre-filled and saves over the same row (amount, category, mode, party, notes, date). Module-owned rows are refused with an explanation. **Phone check (v1.1.9):** the manual **Edit Test** row’s **Edit this entry** button opened **Edit Cash IN** pre-filled (Customer Payment, CASH, ₹750); switching to **UPI** and **SAVE CASH IN** changed that same row to `Edit Test | UPI | 11:31:04 • CUSTOMER PAYMENT • manual row | +₹750` — amount kept, no duplicate row — and it was then reverted to **CASH**. |
| **#045** | ✅ DONE | Cashbook | **Cashbook → VIEW chips** | **Day · This month · All time · Range**. The list and the tally both use the chosen span; `Range` opens a date-range picker. Phone check: all four chips and the date picker work. |
| **#046** | ✅ DONE | Customer Profile | **You Gave ledger rows** | The stored payment mode is appended to the row note (`Late fee — note · UPI`). **Phone check (v1.1.9):** the **Phone QA (A03)** ledger row read `01 Nov 26 11:38 AM | ₹50 | Bal ₹1,150 | Late fee — test · UPI` — the note, the stored reason and the mode together. |
| **#065** | 🟧 PARTIAL | Passwords / OTP | **Password Settings → One-time code delivery** | Optional gateway URL + SMS/E-mail channel. Codes are really sent when it is set; otherwise the on-phone fallback stays, so nobody is locked out. **Phone check (v1.2.3, 2026-11-02):** the card took `https://shop.local/otp`, the **SMS** channel and **Save gateway** → *“Codes will be sent by SMS.”*; **Remove gateway** → *“Gateway removed — codes are shown on this phone.”* and the offline fallback was restored. **Not verified:** an actual send to a provider — the test phone has no gateway account, so the network path is exercised only by `test/cashbook_edit_range_test.dart`'s config case. |


---

## 1f. v1.1.6 — pawn tile density, caller actions, due-date labels, pawn-move gate, category defaults

The hands-on pass on v1.1.7 marks **#068, #069 and #06B** ✅ DONE. **#067** became 🟧 PARTIAL on
that pass because the tile density was right but the sync cloud and caller icon were missing; that
gap was **#06J**, fixed and phone-verified on v1.1.8, so **#067** is ✅ DONE too. **#06A** still
needs its own phone check.

| # | Status | Area | Page / option | What changed |
|---|---|---|---|---|
| **#067** | ✅ DONE | Pawn list | **Pawn Loans → loan tiles** | Removed the wide customer-name / ID / three-dot gap. Row 1 is now photo + **Name** + **₹Amount** only; row 2 is a highlighted gold **ID** badge, village, loan date and item. The wasted **Active** word is gone and a released tile is muted with a **Released** tag. **Phone check:** density and tag are correct; the missing sync-state cloud and caller icon were logged as **#06J**, fixed and phone-verified on v1.1.8 (gold `cloud_upload` badge + ⋮ on the tile). |
| **#068** | ✅ DONE | Pawn list | **Pawn Loans → each tile** | Caller functions: every pledge now offers **Call · SMS · WhatsApp · Move to another pawn profile · Edit** from the long-press menu, and Customer KYC & Details stays inside the customer/pawn profile beside the phone number. Phone check: all five actions appear on long-press. |
| **#069** | ✅ DONE | Pawn profile | **Customer Pawn Profile → Loan details** | Added a **Due Date (promised)**, an **Actual Due Date** and **Outstanding** that always refers to the actual due date. The form now also keeps the promised/actual due separate, and the **Edit** sheet keeps the actual column when the shop closes the date. Phone check: the three labels read correctly. |
| **#06A** | ✅ DONE | Pawn list | **Pawn Loans → Move to another pawn profile** | The move action asks for the simple pawn-move password (independent of delete/release; defaults to the admin secret, swappable in Password Settings), then moves one or many selected loans into a category. **Defect found on the phone (v1.2.2, 2026-11-02):** the move happened with **no prompt at all** — `AppState.verifyPawnMovePassword` existed but nothing ever called it. **Fixed in v1.2.3:** `_chooseCategory` now goes through `confirmAdmin` with `verifyPawnMovePassword`, fails closed, and the label reads **Type pawn-move password**. **Phone check (v1.2.3):** choosing **Pawn_Removed** raised *“Are you sure to move to another pawn profile?”* with **Cancel / Move**, and a wrong secret left the loan uncategorised (both categories still `0 loan(s)`). **Closed in v1.2.5 (phone-verified 2026-11-02):** Password Settings gained a **Pawn-move password** card — it states whether the move asks for the admin password or its own, with **Set a password / Change password** and **Use admin password** to drop the dedicated secret again (`AppState.clearPawnMovePassword`). On the phone: the admin password was first reset through **Forgot password?** (offline code) because `Admin@123` was rejected; **Set a password** then accepted it and saved `Move@1234`, the card read *“Moving a pledge asks for this password, not the admin one.”*, the move asked **Type pawn-move password** and `Move@1234` produced *“Moved to Pawn_Removed.”*, moving the pledge back produced *“Category removed.”*, and **Use admin password** produced *“Move will ask for the admin password.”* with the card back to the fallback. | The delete / release ask-password prompt still lives only in **Settings** and **Password Settings** — it is not duplicated on the tile. |
| **#06B** | ✅ DONE | Pawn categories | **Pawn Loans → Categories** | Seeded defaults are **Forgot_Slip_List** and **Pawn_Removed**; **Add Custom** creates a new named category any time. Names can be renamed later and loans follow. Phone check: both defaults and **Add Custom** are present. |


---

## 1g. v1.1.7 — drag-to-delete, MPIN gate and pawn filters (#06D–#06J)

Reported from the phone on 2026-11-01. The v1.1.7 pass marks **#06D–#06I** ✅ DONE. **#06J** was a
new partial finding from the same pass — fixed in code and **phone-verified on v1.1.8** on
2026-11-01, so every item in this section is now closed.

| # | Status | Area | Page / option | Problem / request | What was changed |
|---|---|---|---|---|---|
| **#06D** | ✅ DONE | Pawn list / Khata / Ledger | **Long-press and drag a tile to the bottom “Hold and drag here to delete” bin** | The bin never deleted anything. **Root cause: the drag never started.** On the pawn list the tile wrapped `InkWell(onLongPress: …)` *inside* `LongPressDraggable`; Flutter gives the innermost long-press recogniser the gesture, so the caller sheet opened and the tile was never lifted. | `DragToDeleteTile` is now stateful and takes its own `onLongPress`: a hold-and-release in place (< 12 px travel) opens the tile menu, hold-and-move lifts the tile for the bin. The pawn tile no longer owns `InkWell.onLongPress`. The drop zone is the whole bottom band (104 px, full width) instead of only the pill, so a slightly-off release still deletes. Fixed in `lib/ui/widgets.dart` + `lib/features/pawn/screens/pawn_screen.dart`. **Phone check:** the tile lifted, the red bin appeared, the MPIN prompt accepted `1234`, and the loan was deleted. |
| **#06E** | ✅ DONE | Security / Passwords | **Delete and Release prompts (Pawn delete, Pawn release, Khata / Customer delete, Ledger row delete)** | Delete / Release asked for the **admin password**; it must ask for the **general MPIN**. | `askPasswordIfEnabled` now verifies the screen-lock MPIN (`AppLock.isEnabled` + `AppLock.verify`) and only falls back to the admin password when no MPIN is set, so a shop without a PIN is never locked out. The dialog label (“Type MPIN” / “Type admin password”) and the numeric keypad follow the secret being asked for. Call sites are unchanged. **Phone check:** Release asked **Type MPIN**, accepted `1234`, and moved the loan to Released. |
| **#06F** | ✅ DONE | Password Settings | **Password Settings → Delete / Release** | The card still described an admin-password step. | Card is now **Ask MPIN for Delete / Release** with its switch relabelled **Ask MPIN**, and a live note says which secret will be asked: MPIN when the screen lock is on, admin password otherwise. All per-action switches are unchanged. **Phone check:** without an MPIN the note names the admin password; with an MPIN it names the MPIN and says the admin password is not needed. |
| **#06G** | ✅ DONE | Pawn list | **Pawn Loans → Filter → Amount range** | The entry was a placeholder that only showed “coming next”, while looking finished in the menu. | A real dialog: **From ₹** and **To ₹** with either side blank for an open end (above ₹50,000 / under ₹5,000), a **Clear** action and **Cancel**. The pill then reads `≥ ₹50,000`, `≤ ₹5,000` or the band. **Phone check (v1.1.7):** with ₹60,000 and ₹20,000 loans, `≥ ₹50,000` left only the ₹60,000 row and the summary became **₹60,000 / ₹5,400 / ₹65,400** with the `≥ ₹50,000` caption; the old build left the summary at the unfiltered ₹80,000. The list and strip now share `_filteredRows()` so they cannot disagree. |
| **#06H** | ✅ DONE | New Pawn Loan | **New Pawn Loan → + (Full KYC form) → SAVE → back on the loan form** | Returning from + KYC filled the Customer ID but left the visible **Customer name** box blank, so SAVE then failed with `Enter customer name` even though the customer had saved. | The `Autocomplete` owns a separate text controller, so writing only `_customerNameController` never moved the visible field. `_setCustomerName()` now writes the saved value and both controllers, and the Autocomplete listener is registered once. **Phone check (v1.1.7):** two runs returned with **Phone QA / A03** and **Phone QB / A04** visible in the name and ID boxes; SAVE worked without retyping. |
| **#06I** | ✅ DONE | Security / Release | **Customer Pawn Profile → Release → MPIN prompt** | The MPIN confirmation button said **Delete** even though the action was a release. | The release call now passes `confirmLabel: 'Release'` to `askPasswordIfEnabled`. **Phone check (v1.1.7):** the prompt read **Are you sure to release this pawn loan?** with a **Release** button; `1234` completed the release. |
| **#06J** | ✅ DONE | Pawn list | **Pawn Loans → loan tile** | #060/#067 promised a real sync-state cloud and a visible caller-menu icon on every tile. | **Phone check (v1.1.7):** the released tile is muted with a **Released** tag and no **Active** word, but neither a cloud icon nor a ⋮ caller icon is rendered. **Fixed in code (v1.1.8):** every tile now renders the sync state from the row itself — `cloud_upload` (gold) while the server has not named the pledge or a local edit is still queued (`server_name` empty or `dirty ≠ 0`), `cloud_done` (green) once it is synced — plus a visible **⋮** button on row 1 that opens the same Call / SMS / WhatsApp / Move / Edit sheet as the long-press. Hidden while the multi-select checklist is on. Covered by a new case in `test/pawn_profile_ui_test.dart` (synced vs queued icon, two ⋮ buttons, menu contents). **Phone check (v1.1.8, `10.235.54.186:35879`):** the Active list showed the **Phone QB / ID A04 / ₹20,000** tile with a gold `cloud_upload` badge at the right of row 2 (nothing synced) and a **⋮** on row 1; tapping ⋮ opened the sheet headed **Phone QB / ₹20,000 · 01-11-26** with **Call · SMS · WhatsApp · Move to another pawn profile · Edit**. |


> **Decision taken with this round:** turning the MPIN off does **not** un-gate destructive actions —
the gate falls back to the admin password. Backup Restore and History Clear therefore keep a working
secret either way. If the shop wants those two to stay admin-only, add a per-action secret choice later.

---

## 2. Open bugs carried forward (from v1.0.24 audit)

> **From the v1.1.7 phone pass:** **#06J** — the pawn tile rendered neither the sync-state cloud
> nor a visible caller-menu icon. **Fixed and phone-verified on v1.1.8** (section 1g): a gold
> `cloud_upload` badge and a ⋮ button are on the tile, and ⋮ opens Call / SMS / WhatsApp / Move /
> Edit. Everything in the table below is closed, and no defect from that pass is still open.

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
| **#040** | ✅ DONE | Reminders | Local notifications for due / overdue members | **v1.2.0:** Settings → **Due reminders** switch, one 9:00 summary naming who is collectable today (never the outstanding), scheduled with `flutter_local_notifications` + `timezone`, Android 13+ permission requested when the switch is turned on, `POST_NOTIFICATIONS` and `RECEIVE_BOOT_COMPLETED` declared, boot receiver re-arms after a reboot, Gradle core-library desugaring enabled. The arithmetic lives in `lib/util/due_reminders.dart` (7 tests: arrears + arrived installment, oldest-first collections, closed loans silent, no-schedule skipped, ordering, wording). **Phone check (v1.2.0):** turning the switch on raised *“Allow Jewellery Suite to send you notifications?”*, **Allow** was accepted (`appops … POST_NOTIFICATION` → default allow) and the card then read **“One 9:00 notification with who is due or overdue today”**. |
| **#041** | ✅ DONE | Reports | Export (PDF/Excel) and charts | Deferred from v1.1.1. **Blocked by the offline pub cache (checked 2026-11-02):** `~/.pub-cache` holds `intl` and `share_plus` but **no `pdf`, `printing` or `excel`**, so PDF/Excel cannot be built on this machine without network access. The app already has `share_plus` + the SAF save channel (`BackupFiles.saveCopy`), so a **CSV** export is the slice that can ship today if the shop accepts CSV as the first step; the charts and PDF/Excel stay behind the same number once the packages are available. **CSV shipped in v1.2.8:** the Reports app bar has an **export** action that writes the visible tab’s own figures (`lib/util/report_csv.dart`, fed by the views’ `_r`) and opens the Android share sheet. **Phone check (v1.2.8, 2026-11-02):** the share sheet opened with *“Sharing 1 file”* and `jewellery_suite_khata_2026-11-02_09-07.csv`, and logcat showed no exception. **Fixed in the same round:** the first build crashed on the tap because the export read the tab from `DefaultTabController.of(context)` using the screen State’s own context, which sits *above* the controller it builds — the index is tracked in state now (v1.2.7 → v1.2.8). **Charts shipped 2026-11-03 without packages:** Jewellery → Reports now has a **Sales vs purchases · last 6 months** grouped bar chart, fed by `JewelleryStore.monthlyTotals()` and drawn with ordinary widgets. Orders and cancelled documents are excluded; the six-month view is independent of the Day/Month/All money chips. Unit-tested in `test/jewellery_store_test.dart` (six-month fill, order/cancelled exclusion, shorter window); phone check pending. **PDF shipped in v1.3.1:** the Reports app bar has **Export this tab as PDF**, built by `lib/util/report_pdf.dart` from the same `khataReportRows` / `pawnReportRows` the CSV uses. **Phone check (v1.3.1, 2026-11-03):** on the Khata tab the share sheet read *Sharing 1 file* with `jewellery_suite_khata_2026-11-03_12-32.pdf`, and on the Pawn tab `jewellery_suite_pawn_2026-11-03_12-35.pdf`; logcat held no exception. **Excel shipped in v1.3.2:** the same app bar has **Export this tab as Excel**, written as OOXML by hand in `lib/util/report_xlsx.dart` because every spreadsheet package wants `archive 3.x` while this app's backups run on `archive 4.x`; text is inline (Tamil survives) and amounts stay numeric. **Unicode PDFs (v1.3.2):** `assets/fonts/` carries Noto Sans + Tamil + Devanagari (939 KB, APK 38.5 → 39.9 MB) and `report_pdf.dart` registers them as base + fallback, so Tamil/Devanagari names print instead of `?` — the generated PDF embeds `NotoSansTamil`. **Phone check (v1.3.2, 2026-11-03):** Excel gave `jewellery_suite_khata_2026-11-03_12-52.xlsx`, PDF gave `jewellery_suite_khata_2026-11-03_12-53.pdf`, no exception in logcat. **#041 is complete:** CSV, PDF, Excel and the six-month chart all ship. |
| **#042** | 🔵 DEFERRED | Sync / Security | Enforce HTTPS for server sync | Keep LAN HTTP working for v1.1.1; revisit certificate/pinning. |
| **#043** | ✅ DONE | Jewellery module | Full buy/sell/stock/valuation module | **Feature batch code-complete 2026-11-03 (schema v20); APK build + consolidated phone pass pending.** Home → **Jewellery** dashboard has saved gold/silver rates, raw/finished/old-metal stock, today's figures, documents with **search + type/metal/payment-status filters**, and tiles for **Customer Credit Book · Supplier Payables · Orders · Workers · Old Metal · Returns · Reports**. **Sale/order and purchase are now different forms.** Retail sale/order lines choose **KDM** (`(net + wastage%) × rate + flat making`) or **Non-KDM** (`net × rate + flat making`), show billing weight live, and record actual purity + optional cost-to-shop for profit. Purchase keeps `weight × purity% × rate` and supplier making modes. Multi-line entry, old-metal exchange, payments, notes, whole-rupee round-off and stored rate snapshots are in place. **Customer Credit Book** groups sales by customer name, shows billed/received/outstanding, and posts receipts. **Supplier Payables** mirrors it for purchases: one row per supplier, a ledger with purchases as credits and purchase payments as debits, and **Pay supplier** posts cash **OUT**. **Orders** are Pending → Ready → Delivered/Cancelled and move stock only on delivery. **Workers** have signed cash/gold ledgers and worker orders. **Returns** are linked credit notes that never rewrite the sale and guard against over-return. **Old-metal register** and **Reports** are built; Reports now include **stock valuation** (fine grams × latest saved pure rate, old metal included as an asset) and a package-free **six-month sales/purchases bar chart**. Schema **v18 + v19 + v20** tracked by backups; cashbook: sale/order receipts IN, purchase payments OUT. Tests: maths 42 (C01–C15), store 22, credit book 8, operations 15, supplier 6; full suite **456 passing**, `flutter analyze` clean. **Phone-verified (v1.3.0, 2026-11-03):** dashboard (gold 16,000/g · 92 % = 14,720/g, raw 10.000 g, old gold 1.260 g, outstanding ₹2,65,750 over 2 open documents, credit book ₹1,12,750, supplier payables ₹1,53,000); **KDM** 10 g + 10 % → **₹1,77,000** and the same line as **Non-KDM** → **₹1,61,000**, both 9.200 g fine @ 92 %; search `PUR` → 1 of 2 documents and the **Sales** / **Dues** chips → 1 of 2; credit-book receipt ₹1,000 → **Received ₹27,000 · Outstanding ₹1,11,750**; supplier payment ₹1,000 → **Paid ₹1,000 · Payable ₹1,52,000**; cashbook `+₹1,000 JEWELLERY COLLECT` / `-₹1,000 JEWELLERY PURCHASE`, net ₹0; Old Metal 1.260 g · ₹15,750 · 1 voucher; Reports stock valuation (total ₹20,160) and the six-month chart; Returns, Orders and Workers screens plus the New Order form. **Order → delivery:** `ORD-20261103-0001` (Shyam, 2 g + 10 % → billing 2.200 g × ₹16,000 + ₹500 = **₹35,700**) saved as **Pending**, **Mark Ready** → Ready, **DELIVER ORDER** → Delivered with **Gross 2.000 g · Net 2.000 g · difference 0.000 g**; the pipeline went **1 pending · 0 ready · 0 delivered → 0 · 0 · 1** and finished stock moved at delivery (**−10.001 g → −12.001 g**). **Return:** **1 g** against `SAL-20261102-0001` saved **RET-20261103-0001 · ₹13,800**, left the sale at **₹1,38,750** with a **Return credit ₹13,800** line, cut customer dues **₹1,11,750 → ₹97,950**, restocked **+1.000 g** (finished **−11.001 g**) and Reports showed **Returns ₹13,800**. **Worker:** a ₹500 **Shop gave** cash movement for *QA Worker* read **Held by workers ₹500 · Cash reserve ₹500** and posted `QA · JEWELLERY WORKER · -₹500` in the cashbook. **Still open:** PDF/Excel export (offline packages); encrypted DB/biometric/real OTP gateway. |
| **#044** | ✅ DONE | Cashbook | Manual entry edit (v1.1.5) | A hand-typed row has an **edit** icon that reopens the entry sheet pre-filled (amount, category, mode, party, notes, date). Rows created by Khatabook / Pawn / Jewellery are refused — they must be corrected in their own module, so source and cash never disagree. `test/cashbook_edit_range_test.dart`. |
| **#045** | ✅ DONE | Cashbook | Date-range view (v1.1.5) | New **VIEW** row: **Day · This month · All time · Range**. Month/range use an inclusive `from`/`to` in the database, and the tally card follows the same filter. |
| **#046** | ✅ DONE | Customer Profile | Payment mode on You Gave rows (v1.1.5) | The ledger note now ends with the stored mode (`Late fee — note · UPI`). |
| **#047** | ✅ DONE | Pawn | Filter/search pledge list by metal, status, due date | **2026-11-03:** metal (Gold/Silver/Mixed) and Active/Released were already on the list; the missing **due-date** filter is now built. **Filter ▾ → Due date range** picks an inclusive from–to on the **actual due date**, falling back to the promised `due_date` when no actual date is set. The same predicate feeds the list and the summary strip, so they cannot disagree. **Clear date filters** clears loan-date and due-date ranges together. Covered by `PawnMath.dueDateIso` / `PawnMath.dueBetween` tests in `test/pawn_math_test.dart` and a menu-presence widget test in `test/pawn_profile_ui_test.dart`. **Phone check (v1.3.0, 2026-11-03):** Pawn Loans → **Filter ▾** lists **All categories · Forgot_Slip_List · Pawn_Removed · Loan date range · Due date range · Amount range · Manage categories…**, so the new entry is live on the device; the range itself was not exercised because the phone currently holds no pawn loans (Investment / Interest due / Outstanding all ₹0). **Phone-verified (v1.4.4 / 56, 2026-11-04):** with the shyam loan due **02-02-27**, a due-date range of **1 Nov – 30 Nov 2026** hid the loan and the summary read **₹0 / ₹0 / ₹0** with *“No pawn loans here.”*; **Clear date filters** brought back the loan and **₹10,000 investment / ₹900 interest due / ₹10,900 outstanding**; a **1 Feb – 28 Feb 2027** range included the loan again. |
| **#048** | ✅ DONE | Backup | Scheduled/automatic local backup | **v1.2.6:** Settings → **Automatic backup**. While on, one **verified** copy is written per calendar day, started after the first frame so it never delays opening the app. Archives are named `auto_jewellery_suite_*.zip`, the newest 7 are kept, and pruning can only delete copies this feature made — a manual backup is never touched. A failed or unverified attempt does not mark the day covered, so the next start retries. **Phone check (v1.2.6, 2026-11-02):** switching it on read *“One verified backup a day, kept in Backup & data (newest 7)”*; after a force-stop and relaunch the card read *“Last automatic backup 02-11-26 08:53 · keeps the newest 7”* and **Backup & data** listed `auto_2026-11-02_08-53-00.zip` (10 KB) under *Saved backups (1)*. Covered by `test/auto_backup_test.dart` (4 cases: off, one per day, pruning keeps manual copies, retention clamp). **Re-checked on v1.4.4 (2026-11-04):** Backup & data listed **4 saved backups** (latest `auto_2026-11-04_12-57-04.zip`, 409 KB); the row menu offered **Restore this backup · Save or share · Save a copy to Downloads… · Delete backup**, and **Save or share** opened Android's share sheet with the zip and Gmail / Quick Share / Bluetooth. |
| **#049** | ✅ DONE | Security | Encrypted local DB | **v1.4.2:** the ledger opens through **SQLCipher** on Android/iOS with a 256-bit key generated on the phone and kept in the platform keystore (`flutter_secure_storage`) — never derived from the PIN. `lib/data/db_crypto*.dart` (conditional import) does the opening, the one-time plaintext→encrypted migration, integrity verification, encrypted snapshots and re-keying a backup from another phone; web/Linux keep the plain driver and About → Storage reports which one is in use. Backups ship as ciphertext, so a pulled `.db` file is unreadable without the phone's keystore. **Phone-verified (v1.4.2 / 54):** `plaintext database migrated to SQLCipher` → `open: SQLCipher encrypted, schema v20`, Home opened with the ledger intact, and **Create backup now** wrote a verified 409 KB archive. **Two device defects fixed:** `sqlcipher_export` drops `PRAGMA user_version`, which made the migrated file (and restored snapshots) reopen as schema 0 and let sqflite delete it — the version is now carried across, a version-0 encrypted file is self-repaired on open (seen on the phone: *repaired the missing schema version on the encrypted file*), and the manifest records the schema version. **Restore round-trip ✅ phone-verified (v1.4.4 / 56, 2026-11-04):** from **Backup & data**, restoring the fresh `jewellery_suite_2026-11-04_15-07-06.zip` showed the confirmation with the file name, took admin password `Admin@123`, wrote a pre-restore safety copy `jewellery_suite_2026-11-04_15-08-34.zip`, and reopened as `[db] open: SQLCipher encrypted, schema v20`; Home and Pawn Loans still showed the shyam loan with **₹10,000 investment / ₹900 interest due / ₹10,900 outstanding**. |
| **#065** | 🟧 PARTIAL | Login / OTP | Deliver one-time codes by real SMS / Gmail | v1.1.5 adds **Password Settings → One-time code delivery**: paste an SMS/e-mail gateway URL, choose SMS or E-mail, and the app POSTs `{to, channel, purpose, code, message}`. Any 2xx counts as sent; the code is only shown on the phone when no gateway is set or the send fails. **Still needs the shop's gateway URL** (provider account) to leave the phone in production. |
| **#071** | ✅ DONE | Reports | Khata report in the Pawn layout + one share button | **Khata tab redesigned to match Pawn:** two filter rails (**Period** All/This month/This year, **Loans** All/Active/Overdue), a six-card metric grid (**Collected in view · Active loans · Outstanding · Overdue accounts · Collectable now · Interest earned**), then the collections themselves as rows (date · customer · ₹) with a count/total footer, and an **All time** card holding the old summary figures. Overdue mode lists the loans behind the collectable figure. **Export:** the three app-bar icons are replaced by one **Share** button → **PDF / Excel (.xlsx) / CSV** → Android's share sheet (Drive, Files, WhatsApp, Gmail…). Exports are fed by the same `_r` map, so the file still matches the screen. Covered by new `test/reports_ui_test.dart` (3 widget cases: layout, overdue switch, chooser). **Phone check (v1.4.4 / 56, installed in place at `10.235.54.202:40933`, data kept):** the Khata tab showed **PERIOD** (All / This month / This year), **LOANS** (All / Active / Overdue), the six cards (**Collected in view · Active loans in view · Outstanding · Overdue accounts · Collectable now · Interest earned**), **COLLECTIONS IN VIEW** (*No collections in this period.*), and the **ALL TIME** card; the app bar had a single **Share this report**; tapping it opened **PDF / Excel (.xlsx) / CSV**, and **PDF** produced the Android share sheet with `jewellery_suite_khata_2026-11-04_12-58.pdf`, **CSV** produced `jewellery_suite_khata_2026-11-04_12-59.csv` — Gmail, Quick Share and Bluetooth listed, so a report can go to Drive by hand today. No `FATAL EXCEPTION` / `E/flutter` in logcat. |
| **#072** | ⬜ BLOCKED | Backup / Sync | Google Drive backup + multi-device sync | **Designed 2026-11-04 — `docs/GOOGLE_DRIVE_SYNC.md`.** A Gmail address in the app is a label, not a Drive link: Drive needs OAuth consent, which needs an **Android OAuth client ID** (`com.shyberdev.jewellery_suite` + release SHA-1) created in Google Cloud Console with the **Google Drive API** and `drive.appdata` + `email` scopes. Design: backups and sync live in the hidden **app folder**, snapshots encrypted with a **shop passphrase** (the Android keystore key is per-device, so it cannot open a Drive copy); **the first device to create the shop is the main device**, staff join with a 6-digit/QR pairing code the owner approves, the main device is the conflict tie-breaker, every device is listed with role / last sync and can be **removed**, and moving the main device needs the admin password. Build order: Drive backup/restore → device registry + pairing → change-based sync → photos. **Blocked on the client ID** (steps in the doc); until then backups go to the phone and the share sheet can send them to Drive by hand. |
| **#075** | 🟨 CODE DONE | Jewellery / Purchases, credit book | **Draft purchases, shared expenses, manual late fees** | The audit left three boxes unbuilt rather than tick them: a saved purchase moved stock immediately (no draft), `allocateSharedExpense` had still never been fed (item-specific cost existed, a document-wide expense did not), and the jewellery module had no fee entry at all. | **Schema v21**: `shared_expense` and `late_fee_total` on `jewellery_invoices`, plus a `jewellery_charges` table. The purchase form has **SAVE AS DRAFT**; a draft stores the document and its lines but posts no stock, no payment and no old metal, and the document sheet's **Confirm purchase · receive stock** calls `confirmInvoice`, which clears any leftover movement first and refuses a second confirm — stock cannot post twice. `saveInvoice(sharedExpense:)` splits the amount by net weight into each line's additional cost through `allocateSharedExpense` and stores the total once. **Add late fee** on a sale files a charge and raises `outstanding`; the item total and recorded cost are untouched, the ledger shows **Late fee** as its own debit, and nothing is ever generated automatically. Drafts are excluded from supplier payables and monthly totals, and deleting a document removes its fees. | New `test/jewellery_draft_contract_test.dart` (7 cases). Full suite **502 passing**, `flutter analyze` clean. Phone: purchase form shows **SAVE AS DRAFT**, `[db] open: SQLCipher encrypted, schema v21`. The confirm→stock step and the late-fee dialog still need a phone pass with real documents. |
| **#074** | 🟨 CODE DONE | Jewellery / Calculations checklist | **§2 workflow boxes audited 2026-11-05** | The checklist showed three rules that existed only as maths: `JewelleryMath.allocatePayment` had **no caller** (a receipt could go to one invoice only, an overpayment was refused with *“Payment is more than the outstanding balance.”*, and an advance had nowhere to live); “graph reflects saved daily gold rates” had no chart; and stock reconciliation had no WIP line. | `JewelleryStore.receiveCustomerPayment` splits one receipt across the customer's open invoices — a **manual per-invoice split** from the new dialog, else oldest-first — trims every part to what that invoice still owes, and stores the excess as an unallocated advance (`invoice_uuid = ''`). The Credit Book counts the advance as received and takes it off the outstanding; the ledger shows **Advance received**, so nothing hides inside a zero balance. `AppState.receiveJewelleryReceipt` posts one `JEWELLERY_COLLECT` **IN** row per part, so the cashbook still reconciles. Reports gained **Saved gold rates** (one bar per saved day, last seven) and **WIP · gold/silver (open orders)** rows with a note that WIP is neither shelf stock nor worker reserve. New `test/jewellery_receipt_test.dart` (6 cases: oldest-first split, manual split, never over-allocating, advance as credit, refusal of a zero receipt, one cashbook row per part). Full suite **495 passing**, `flutter analyze` clean. **Not phone-verified:** the phone currently holds no jewellery documents or saved rates, so the receipt dialog and rate chart could not be driven there this round — the Reports cards were opened on v1.4.6 and render, and the flow is covered by the tests. |
| **#073** | ✅ DONE | System UI / Dark mode | **Every label the 2026-11-02 note left behind** | The v1.2.8 change log recorded `kInk.withValues(alpha: .7)` on the Khata and customer-profile screens as *deliberately not changed*, and the same fixed near-black ink sat on the Reports tab labels, the interest-calculator chips, the Settings pager dots, the **NO LOAN** tag and the Khata **Outstanding** figure — all black-on-black once **Dark mode (Beta)** was on. | Each site now uses `inkOf(context)` from `lib/ui/palette.dart`, the same helper #026 and #06L used, so light mode keeps exactly the ink it had and dark mode gets the off-white. Deliberate dark-on-gold cards and white-on-dark pills were left alone. New `test/dark_mode_ink_test.dart` (4 cases: report tabs, interest-calculator chips, khata filter chips in dark mode, and the same chips staying ink in light mode). **Phone check (v1.4.5 / 57, 2026-11-05):** with **Dark mode (Beta)** on, the Khata filter chips (**All · Due · Upcoming · No reminder**), the summary card (**Investment / Outstanding / To Collect / Members**, all four figures light), the Reports tabs (**KHATA / PAWN**), the interest-calculator **Compound** chip, **Khata Books**, the **General** customer list and **Settings** all read as light text on the dark surface. The **Outstanding ₹0** was still near-black on the intermediate v1.4.5 build, which is how the missed `_stat` call was found; it is correct after the rebuild. The phone was returned to light mode afterwards. |
| **#070** | ✅ DONE | Customers / Dialler | Indian mobile numbers, one rule everywhere | **A number is either a 10-digit Indian mobile or the same number with +91.** `lib/util/phone.dart` is the single rule: it strips spaces / dashes / brackets, drops a trunk `0` or `0091`, requires a 10-digit number starting 6–9, and builds the links — `tel:+91…`, `sms:+91…?body=…` and `https://wa.me/91…?text=…`. **Three hidden defects fixed:** (a) WhatsApp was opened as `wa.me/<10 digits>` with **no country code**, which WhatsApp rejects, so Call/SMS worked but WhatsApp never reached the customer; (b) Call/SMS passed the raw saved text (`98765 43210`, `+91-…`) straight into the URI; (c) `LocalAccount.isMobile` accepted any 10 digits (landlines too) and any 12 digits starting `91`, while `create()` validated the *already truncated* identifier, so a longer number ending in 10 digits passed. Now enforced in Add/Edit customer, the new-pawn-loan form, jewellery order mobile, User Details, and the account identifier; login still accepts `9876543210` and `+91 98765 43210` as one account, and older accounts keep their stored 10 digits. Covered by `test/phone_test.dart` (9 cases). **Phone-verified (v1.4.4 / 56, 2026-11-04):** in **Customers Book → Edit Customer**, `1234567890` was refused with *“Use a 10-digit mobile number, or +91 and the 10 digits.”* and the form stayed open; `+919121376318` saved and the list showed it. From the pawn tile menu, **Call** opened the dialler as **+91 91213 76318**, and **WhatsApp** produced `api.whatsapp.com/send/?phone=919121376318&…` (this phone has no WhatsApp app, so the link fell back to the browser — the `91` country code is present). |
| **#066** | ✅ DONE | Security | Fingerprint / face unlock | **v1.3.3:** `local_auth` 3.0.2 is in and `MainActivity` now extends `FlutterFragmentActivity` (BiometricPrompt needs a fragment host); `USE_BIOMETRIC` is declared. `lib/util/biometrics.dart` wraps availability + prompt and fails closed on every path. Password Settings → **Biometric & screen lock** gains **Unlock with fingerprint** (only offered when the lock is on and a finger/face is enrolled); the lock screen shows **Use fingerprint** and auto-prompts once, with the PIN field always present as the fallback. Covered by `test/biometric_lock_test.dart` (2 fail-closed cases). **Phone-verified (v1.3.5, 2026-11-04):** turning the lock to **Every time** enables the switch in the same session and it persists (`checked=true`); a cold start shows *“Jewellery Suite is locked”* and auto-prompts *“Touch the fingerprint sensor”* (`owner=com.shyberdev.jewellery_suite`, `requestReason=BiometricPromptAuthentication`); **one touch opened Home** (`FingerprintAuthenticationClient … success: true`) with no second prompt; a cancelled prompt fell back to *“Fingerprint not recognised — enter your PIN.”* with **Use fingerprint** and the PIN field, and PIN `1234` opened the app. **Two defects found and fixed on the device:** the switch stayed disabled after turning the lock on, and the prompt looped about three times because the gate re-locked on the resume that the prompt itself causes — see the 2026-11-04 change log. |

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
| Test suite runner (keeps temp on project disk) | `tool/test.sh` |
| Database schema + migrations | `lib/data/local_db.dart`, `lib/data/migration_v*.dart` |
| Home screen KPIs / greeting | `lib/ui/home_screen.dart` |
| Android manifest / permissions | `android/app/src/main/AndroidManifest.xml` |
| Release signing | `android/app/build.gradle.kts`, `android/key.properties` |

---

## 5. Change log

### 2026-11-05 — #075 draft purchases, shared expenses and late fees close the checklist (v1.4.7)
- **Why this round happened:** #074 ended with three `Calculations_and_Test_Cases.md` boxes deliberately left unticked. Ticking them without code would have been the exact dishonesty §5 item 8 of `agent_readme.md` warns about, so they were built.
- **Draft purchases (schema v21).** A purchase can now be saved as a **Draft**: the document and its lines are stored, but no stock movement, no payment and no old-metal stock are posted. The document sheet shows *Draft · stock is not received until you confirm* with **Confirm purchase · receive stock**, which posts the `PURCHASE_IN` movement once. `confirmInvoice` removes any leftover movement for that document before posting and refuses anything that is no longer a draft, so a double tap or a retry cannot receive stock twice. Drafts are excluded from supplier payables and the reports' period totals, so a document that is not a real purchase never becomes a debt.
- **Shared expenses.** The form takes one **shared expense** for the whole document (freight, hallmarking, stones for the lot). `saveInvoice` splits it across the lines by net weight with `allocateSharedExpense` — the function that had tests but no caller — adds each line's share to that line's additional cost and stores the total once on the invoice. The preview adds it to the payable and subtracts it from estimated profit, and the invoice total remains exactly the sum of its lines.
- **Manual late fees.** A sale's sheet has **Add late fee**. The fee is a `jewellery_charges` row; the invoice's item total and recorded cost are never rewritten, `late_fee_total` and `outstanding` grow instead, and the customer ledger shows **Late fee** as a separate debit. Deleting the document deletes its fees. Nothing generates a fee automatically, which is what the specification asks for.
- **Checks:** `flutter analyze` → **No issues found**; full suite **502 passing, exit 0** (`./tool/test.sh`), including new `test/jewellery_draft_contract_test.dart` (7 cases: draft posts nothing, confirm posts once and refuses a second, draft stays out of supplier payables, weight split, zero shared expense, fee raises only the balance, fee removed with its sale).
- **APK:** v1.4.7 / versionCode 59, `mobile/jewellery_suite_v1.4.7-arm64-v8a.apk` (`45,726,740` bytes), SHA-256 `8bb235cbbfa72f4311dfbea8d5ae843b6459e5e1b85f8af9f62a805f8c80f9c2`, **installed in place at `10.52.61.148:42895`, data kept** (`[db] open: SQLCipher encrypted, schema v21`).
- **Phone check:** the v21 migration ran on the existing ledger without loss, and the purchase form shows **SAVE AS DRAFT** beside **SAVE PURCHASE**. The phone still holds no jewellery documents, so the draft confirm, the shared-expense split and the late-fee dialog have no data to run against — those are covered by the tests and marked 🟨, not ✅.

### 2026-11-05 — #074 workflow checklist audited; receipts allocated, rate graph and WIP added (v1.4.6)
- **The audit:** every box in `Calculations_and_Test_Cases.md` §2 was checked against the code and the suite, not just ticked. **34 boxes are proven by automated tests**, 10 by code or an earlier phone pass, **2 are genuinely open** (draft purchases, shared expenses) and the late-fee box is partial (nothing auto-generates a fee, but the jewellery module has no manual fee entry yet). The document now records which check proves each box.
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

