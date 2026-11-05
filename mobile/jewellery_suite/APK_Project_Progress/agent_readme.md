# Agent Readme — what we meant, what we built, and what went wrong

**Purpose of this file:** the task tracker (`README.md`) records *what* is done. This file records
*why* it was done, *how far it really got*, and *where the agent got it wrong*. A new session should
read this before touching code, so it does not repeat the same mistakes or re-litigate decisions the
shop already made.

- **App:** Jewellery Suite — offline-first pawn lending + khatabook + cashbook for one shop.
- **Platform:** Flutter (Android APK), local SQLite, no server required.
- **Branch for APK work:** `Apk_Develop_Branch_01_11` (created 01/11/2026).
- **Tracker:** `APK_Project_Progress/README.md` — permanent task numbers `#001`…`#06F`.
- **Last written:** 2026-11-05 (latest: **#075** closed the last three workflow-checklist boxes —
  draft purchases, shared expenses, manual late fees — on v1.4.7; before it **#074** audited the whole
  checklist and wired the allocation engine that had tests but no caller, and **#073** closed the
  dark-mode ink debt. Before that, **#041** CSV report export shipped and phone-verified on
  v1.2.8 (its first build v1.2.7 crashed on the tap — §4); before that **#048** automatic daily backup
  shipped and phone-verified on v1.2.6; before that §4 #06A was closed — the move asks its own password, Password Settings has the card, and the password prompts are text prompts again; §5 item 14 records how the digits-only prompt hid for so long).

---

## 1. What the shop actually asked for (intent, in order)

1. **An app that runs the shop on one phone.** Pawn (gold/silver pledges), khatabook lending, a
   cashbook that never disagrees with the modules, backup/restore, and no dependency on a server.
2. **A codebase a human or an AI can navigate.** The original `lib/ui/` held a 3,000-line
   `pawn_screen.dart`; the request was one screen per file, widgets and logic separated by feature,
   without changing behaviour.
3. **A pawn screen that matches how a counter works.** Long-press a pledge to get the caller actions,
   delete by dragging it to a bin, filter the list by category / date / amount, and see the promised
   date and the actual due date separately.
4. **Everyday passwords, not a long one.** Delete and release should ask the **MPIN** the shop types
   all day, not the admin password.
5. **A paper trail.** Every round must be written into `APK_Project_Progress/README.md` before the
   session ends, because sessions get interrupted and context is lost.

---

## 2. What is really built (and how sure we are)

| Area | State | Evidence |
|---|---|---|
| Database schema v16 + migrations | ✅ working | Migrated in place on the phone (v1.1.4 → v1.1.5). |
| Pawn loans: create, interest, paying/requesting, release, ledger | ✅ working | Used on the phone with the shop's own data. |
| Khatabook, collections, refinance, cashbook linkage | ✅ working | Phone-verified; `test/cashbook_linkage_test.dart`. |
| Backup / restore via the Android file picker | ✅ working | Phone-verified with a safety backup. |
| Release signing (upload keystore) | ✅ working | `apksigner` verified; keystore is local + gitignored. |
| Account login + stay-signed-in (#057) | ✅ phone-verified 2026-11-01 (v1.1.9) | Cold start → PIN → Home, no login screen; `test/account_session_test.dart` (6 cases) covers the lost-session case. Logout → login form verified on v1.2.0. |
| Pawn filters + search (#063) | ✅ phone-verified 2026-11-01 (v1.2.2 / versionCode 38) | Chip tap-to-clear, name / ID / amount search and the loan-date range all behave as specified on the phone; the summary strip follows the filters (₹0/₹0/₹0 when nothing matches). |
| Dark-mode pawn chips readable (#06L) | ✅ phone-verified 2026-11-01 (v1.2.2) | Unselected chip/pill labels used hard-coded `kInk` (near-black at 70 %) so **Released / Gold / Silver / Mixed** were black-on-black in dark mode. Now `inkOf(context)` — readable in both themes. |
| Dark-mode ink debt closed (#073) | ✅ phone-verified 2026-11-05 (v1.4.5) | The rest of that same pattern — Khata chips + summary card, Reports tabs, interest-calculator chips, Settings pager dots and customer-profile ledger stamps — now uses `inkOf(context)`; read in dark mode on the phone and returned to light afterwards. `test/dark_mode_ink_test.dart` (4 cases). The **Outstanding ₹0** statistic was missed by the first build and found on the phone. |
| Jewellery workflow checklist closed (#074/#075) | 🟨 code + tests, form phone-checked 2026-11-05 (v1.4.7) | Every §2 box in `Calculations_and_Test_Cases.md` is now satisfied. #074 wired `allocatePayment` (receipts split across invoices, excess kept as customer credit), added the saved-rate graph and the WIP rows. #075 added schema **v21** (`shared_expense`, `late_fee_total`, `jewellery_charges`): a draft purchase posts nothing until **Confirm purchase** (idempotent), a shared expense splits by net weight, and a late fee raises only the balance. `test/jewellery_receipt_test.dart` (6) + `test/jewellery_draft_contract_test.dart` (7); suite **502 passing**. Seen on the phone: schema v21 migrated in place and **SAVE AS DRAFT** on the purchase form. Still owed a data-bearing phone pass: confirm→stock, the shared-expense split and the late-fee dialog. |
| App shell + password launch gates (#06K) | ✅ phone-verified 2026-11-01 (v1.2.1 / versionCode 37) | Cold start went straight to **Home** — no PIN, no admin-password form, no login — with the dark theme and the ledger intact. `lib/app.dart` restored from `0ae051f`; gates skipped by `kDevPasswordGateDisabled` in `lib/util/secret_dev.dart` (set it `false` for release). See §4 #06K. |
| Dev credentials written down | ✅ `APK_Project_Progress/Temp_Passwords_readme.md` | Account password reset through the Forgot-password OTP flow so any agent can sign in; delete before handover. |
| Password centre, Forgot-password OTP (#058/#059/#065) | 🟨 #065 card phone-checked 2026-11-02 | The **One-time code delivery** card saved `https://shop.local/otp` + **SMS** (*“Codes will be sent by SMS.”*) and **Remove gateway** restored the offline fallback (*“Gateway removed — codes are shown on this phone.”*). A real send still needs the shop's gateway URL. |
| Pawn tile density, caller menu, categories, filters | ✅ category table phone-checked 2026-11-02 (#064) | Filter menu showed **All categories · Forgot_Slip_List · Pawn_Removed**, **Add Custom** created **QA_Cat** and its menu removed it again. |
| CSV report export (#041, first slice) | ✅ phone-verified 2026-11-02 (v1.2.8) | **Reports → export** opened the share sheet (*“Sharing 1 file”*, `jewellery_suite_khata_2026-11-02_09-07.csv`). v1.2.7 crashed on the tap (`DefaultTabController.of` through the screen’s own context) — fixed in v1.2.8 by tracking `_tab`.
| Automatic daily backup (#048) | ✅ phone-verified 2026-11-02 (v1.2.6) | Settings → **Automatic backup** on; after a restart the card read *“Last automatic backup 02-11-26 08:53 · keeps the newest 7”* and **Backup & data** listed `auto_2026-11-02_08-53-00.zip`. Pruning/off-by-default covered by `test/auto_backup_test.dart`. |
| Pawn move asking its own password (#06A) | ✅ phone-verified 2026-11-02 (v1.2.5) | Password Settings → **Pawn-move password** → **Set a password** accepted `Admin@123` + `Move@1234`, the pledge moved with `Move@1234` (*“Moved to Pawn_Removed.”*), moved back (*“Category removed.”*), and **Use admin password** restored the fallback. |
| Pawn tile sync cloud + visible ⋮ caller icon (#06J) | ✅ verified on the phone 2026-11-01 (v1.1.8) | Gold `cloud_upload` badge on row 2 and ⋮ on row 1 of the Phone QB tile; tapping ⋮ opened Call / SMS / WhatsApp / Move / Edit. Test in `test/pawn_profile_ui_test.dart`. |
| Feature-folder refactor (`lib/features/...`) | 🟨 partly done | Screens moved; some helpers still in `lib/ui/`. |
| Drag-to-delete bin | 🟨 fixed in code 2026-11-01, covered by 2 new tests, not yet phone-checked | Root cause found (§4). |
| Delete / release asking the MPIN | 🟨 code changed 2026-11-01, not yet phone-checked | `askPasswordIfEnabled` now verifies the MPIN first. |
| Pawn profile header layout | 🟨 crash fixed 2026-11-01 | `RenderFlex … unbounded` thrown on every profile open; see §4. |
| Amount-range filter in the pawn Filter menu | 🟨 code done 2026-11-01 (#06G) | From/To dialog, open-ended either side, Clear; covered by a widget test. |
| Release build v1.1.9 (#057, #044/#046 checks) | ✅ built + installed in place | `mobile/jewellery_suite_v1.1.9.apk`, SHA-256 `10e1449…a74af1`; `dumpsys` reports 1.1.9 / versionCode 35. |
| Release build v1.1.8 (#06J) | ✅ built + installed in place | `mobile/jewellery_suite_v1.1.8.apk`, SHA-256 `8554642c…bcd836`; `dumpsys` reports 1.1.8 / versionCode 34, no crash in logcat, shop data kept. |
| Cashbook manual-row edit (#044) | ✅ phone-verified 2026-11-01 (v1.1.9) | Edit sheet reopened pre-filled, saved over the same row (CASH→UPI, ₹750 kept, no duplicate), then reverted. |
| You Gave payment mode on ledger rows (#046) | ✅ phone-verified 2026-11-01 (v1.1.9) | Row read `₹50 · Bal ₹1,150 · Late fee — test · UPI`. |
| Release build v1.1.6 published on GitHub | ✅ built + uploaded, not installed | Asset `jewellery_suite_v1.1.6.apk`, SHA-256 `a2da42f4…3adcf583`. |
| Due reminders (#040) | ✅ phone-verified 2026-11-01 (v1.2.0) | Toggle in Settings raised the Android permission prompt, Allow accepted, card then read “One 9:00 notification…” |
| Report export (#041), HTTPS (#042) | 🔵 deferred | Not started. |
| Biometric unlock (#066) | 🔵 deferred | `local_auth` needs a `FlutterFragmentActivity` and device enrolment. |

**Rule of thumb:** 🟨 means *compiles and is unit-tested*, not *seen working*. Never mark something ✅
DONE without a phone observation written into `README.md`.

---

## 3. The real plan versus the plan that was reported

**What was reported:** “Refactor the app into feature folders, then continue with the planned
features.”

**What actually happened, in order:**

1. Audit of `lib/` and a proposal (correct, but the proposal was never trimmed to what the shop
   needed — it listed ~25 folders, far more than the app has screens).
2. Screen files were moved into `lib/features/<feature>/screens/`. Helpers (`widgets.dart`,
   `palette.dart`, `admin_guard.dart`, `photo_local*.dart`) were left in `lib/ui/` on purpose, to keep
   imports and platform behaviour intact.
3. The refactor consumed several sessions and stalled the actual shop-facing work (pawn list, filters,
   passwords). The shop asked twice to stop refactoring and finish the app.
4. Pawn UI rework (#06C) landed: due-date label, three-dot menu in the profile, tile cleanup, one
   `Filter` menu. The Amount-range entry inside it was left as a toast placeholder.
5. Phone reports then arrived: the drag bin does not delete, and delete/release asks the admin
   password. Both are now fixed in code (#06D–#06F) but not yet installed and checked.

**Lesson recorded:** a structural refactor is not progress the shop can see. If the request is a bug
on a screen, fix the screen.

---

## 4. Where the errors are

### #06D — the drag-to-delete bin never deleted (root cause found)

The bin was not the problem. **The drag never started.** On the pawn list the tile is wrapped in

```
DragToDeleteTile (LongPressDraggable)  →  InkWell(onLongPress: showActions)
```

Flutter resolves competing long-press recognisers by depth: the **inner** one wins the gesture arena.
So holding a pledge opened the caller sheet and `LongPressDraggable` never fired — the bin stayed
hidden, and the shop read that as “Hold and drag to delete is not working”.

Fix (2026-11-01): `DragToDeleteTile` is now stateful and takes an `onLongPress` callback. It measures
finger travel during the drag; releasing in place (< 12 px) opens the tile menu, releasing after a real
move lets the tile be dropped on the bin. The pawn tile no longer owns `InkWell.onLongPress`. The drop
zone is also the full bottom band (104 px) instead of only the pill, so a slightly-off release still
deletes.

### #06E — delete / release asked the admin password

`askPasswordIfEnabled` always verified against the admin hash. Fix: it verifies the **screen-lock MPIN**
first (`AppLock.isEnabled` + `AppLock.verify`) and only falls back to the admin password when no MPIN
is set — a fallback, not a bypass, so a shop with no PIN is never locked out of its own delete button.
The dialog label and keyboard follow the secret being asked for.

### #06F — Password Settings described the old behaviour

The card said “Ask Password for Delete / Release”. It now says **Ask MPIN for Delete / Release** and
states which secret will actually be asked, based on whether the screen lock is on.

### Pawn profile header — a crash nobody reported (found by the suite)

The #06C three-dot menu put an `Expanded` around the status pill inside a `Row` that is itself a child
of the header `Row`. A `Row` gives its children unbounded width, so the inner `Expanded` threw
**“RenderFlex children have non-zero flex but incoming width constraints are unbounded”** every time a
customer pawn profile opened. It never reached the shop as a bug report because the profile still
rendered; the red error box showed up in the widget tests. Fixed by letting the pill shrink-wrap.
**Lesson: a green analyzer says nothing about layout — run the widget tests.**

### Environment trap: `/tmp` is a 437 MB tmpfs

This machine's `/tmp` fills up; when it does, `flutter test` first hangs and then dies with “The target
device is full” while copying `listener.dart.dill`. Run tests with
`TMPDIR=$PWD/.dart_tool/tmp flutter test`. Before blaming a hanging test command, check `df -h /tmp`.

### Still open / risky

- **Report export (#041) is blocked by the offline pub cache, not by design.** Checked 2026-11-02:
  `~/.pub-cache/hosted/pub.dev` has `intl-0.20.3` and `share_plus-13.3.0` but **no `pdf`, `printing`
  or `excel`**. The **CSV slice shipped in v1.2.8** (`lib/util/report_csv.dart` + the Reports app-bar
  action); PDF/Excel and charts still need the packages, so do not promise a PDF export on this
  machine without them.
- **A widget built inside `build()` cannot be read back through the State's own `context`.**
  `DefaultTabController.of(context)` in a Reports app-bar handler returned null because the
  `DefaultTabController` is created *by* that build method — the tap crashed silently on the phone
  (v1.2.7), the suite stayed green, and only logcat showed it. Track the index in state, or put the
  action below the controller.

- **Amount range** in the pawn Filter menu is done (#06G); the old stub note here was stale and is removed.
- **Visual state deleted during cleanup, twice.** #06C dropped the tile's cloud badge and move dot while
  restyling the row, and #06J was the result. If a tile loses a badge, move it into a test in the same commit.
- **Duplicate ledger rows**: pawn interest rows are written per period; re-running an interest payment
  twice is only guarded by the release/interest checks, not by a unique constraint.
- **No DB encryption** (#049). The PIN and admin hashes are salted, but the SQLite file is plain.
- **Sync is untested against a live server** — the shop runs offline, so pull/push paths have unit
  coverage only.
- **Widget tests did not cover gestures** (fixed 2026-11-01: `test/drag_to_delete_test.dart`). The
  long-press conflict shipped precisely because no test ever simulated a long-press-drag on a tile.
- **Placeholders are now finished, keep it that way.** The old amount-range toast is gone (#06G); if a
  menu entry cannot work yet, do not ship it looking finished.

### #06K — placeholder shell removed, password gates off for this dev pass (2026-11-01)

**Read this before touching `lib/app.dart`.** A previous session could not clear three VSCode problems
(`lib/app.dart`, `lib/ui/app_lock_gate.dart`, `lib/util/secret_dev.dart`) and kept rewriting
`lib/app.dart` until the analyzer was happy — by turning the app shell into placeholders
(`_AuthShell`, `_SignedInShell`, `_ScreenRouter`, the literal text *“Auth shell placeholder”*). The
result compiled and analyzed clean but **was not the app**: no `MaterialApp`, so no theme, no dark
mode, no Smart-fit zoom, no `AdminPasswordGate`; and `_ScreenRouter` rebuilt `_SignedInShell` around
itself, so a signed-in user would have recursed forever. `flutter analyze` green says nothing about
whether the screen exists — the same lesson as the `Expanded` crash earlier in this section.

**State after #06K:**

| File | State | Why |
|---|---|---|
| `lib/app.dart` | ✅ restored from `HEAD` (`0ae051f`) + one dev flag — phone-verified on v1.2.1 | Real shell: gold theme, dark mode, Smart-fit + in-app Zoom `MediaQuery` in `builder`, `AdminPasswordGate` on `home`. `builder` skips `AppLockGate` and `home` uses `_StartRoute` (Home/Login) **only** while the dev flag is on. |
| `lib/util/secret_dev.dart` | ✅ analyzer clean (new, 21 lines) | One documented `const bool kDevPasswordGateDisabled = true`. No password or PIN value in it. Delete or flip before release. |
| `lib/util/app_lock.dart` | ✅ reverted to `HEAD` | The added `AppLock.isActive(db)` helper returned `db.path != null` (always true when the DB is open), so it could never express “should lock”; removed. |
| `lib/ui/app_lock_gate.dart` | ✅ untouched | The real gate and its 4 tests are unchanged; the dev flag only decides whether it is mounted. |
| `lib/ui/app_lock_gate_disabled_placeholder.dart` | ❌ deleted | Invented this round, never part of the app. Do not recreate it. |

#### Why the gates are off now

The shop explicitly said: turn off the password section for this dev pass, because typing a PIN every
session was costing time and the AI kept entering it wrong; the password flow gets a **manual check at
final release**. So:
- No PIN screen on launch, no forced admin-password form, no password re-testing each session.
- **Nothing was weakened.** PIN/admin hashes, `AppLock`, `AdminPasswordGate`, Password Settings,
  `askPasswordIfEnabled` (#06E) and all password unit tests still exist and still pass.
- `DELETE / RELEASE` still follows #06E: it asks the MPIN when one is set, admin password otherwise.
- No password/PIN values in code or in this tracker — they live in `Temp_Passwords_readme.md` only.

#### What is NOT done

- **#06K is ✅ phone-verified (2026-11-01, v1.2.1 / versionCode 37).** Force-stop → cold start landed
  on **Home** with no PIN, no admin-password form and no login form; the shop's dark theme and the
  ledger (₹20,000 pawn, ₹1,000 khata, 11 sync changes) were intact. Nothing else was tapped.
- **The gates stay off until the release build.** `kDevPasswordGateDisabled = false` plus a manual PIN
  check is the last step before shipping; if that is forgotten the release ships without a lock.
- `AdminPasswordGate`'s forced-setup step is skipped while the flag is on, so a phone that somehow
  reverts its admin password to the default will not be asked to change it during this dev pass.
- The phone's wireless-debugging address was not re-confirmed this session; check
  `Temp_Passwords_readme.md` and `adb -s <addr> shell echo alive` before installing.

---

## 5. What the agent did wrong (honest list)

These are recorded so the next session does not repeat them.

1. **Claimed checks that had not run.** In interrupted sessions the summary said “screens moved,
   analyzer clean” while the tree was mid-move. A later session had to rediscover that. Rule: run the
   check in the session that reports it.
2. **Deleted its own tracker note.** A cleanup script (`awk`) removed the only copy of a progress
   note. It had to be rebuilt from the conversation. Rule: edit the tracker with the file tools, not
   with stream editors.
3. **Left a duplicated heading** (“Apk Develop Branch snapshot” twice) in the tracker for a full
   round. Fixed 2026-11-01.
4. **Patched by guessing.** Several `str_replace` calls failed (path resolution / stale anchors) and
   the agent then patched with `perl -0pe` and Python scripts, which broke braces in
   `pawn_screen.dart` and needed a second repair pass. Rule: re-read the exact block before editing;
   the file tools work when the anchor is real.
5. **Shipped a gesture conflict without testing gestures.** #06C removed the tile's move dot and moved
   actions into menus, but left `InkWell.onLongPress` inside the draggable. No test, no phone check,
   no note that the two long-press behaviours had never coexisted. This is the exact bug the shop then
   reported.
6. **Added a placeholder and called the item done.** “Amount range” was listed as part of the Filter
   menu while only printing a toast.
7. **Over-scoped the refactor.** A ~25-folder proposal for a shop app with ~20 screens; time went into
   moving files instead of fixing the screen the shop was using.
8. **Wrote the tracker in past tense for unverified work.** Some entries read as done when they were
   only written. The tracker now distinguishes 🟨 CODE DONE from ✅ DONE — keep that distinction.
9. **Left a stray nested copy of the tree.** `mobile/jewellery_suite/mobile/jewellery_suite/` held two
   files from an earlier refactor attempt (`lib/core/refactor_audit.py` and
   `lib/refactor_checkpoint/app_state.dart.checkpoint`). They were tracked in git, which is why nobody
   noticed, and they confused path resolution — a file written to `mobile/jewellery_suite/...` landed
   *inside* it. **Removed 2026-11-01**; the real app is `mobile/jewellery_suite/lib` only.
10. **Left a lockout inside a security gate.** #057's auto-continue fallback was written as
    `else if (!hasAccount)`, which quietly assumed “no account” means “old phone”. The first phone
    that had an account **and** a lost session flag went straight to Login with its ledger sitting
    behind it. A fallback that protects users must be tested in the state the user is actually in,
    not only in the clean install case.
11. **Almost shipped a placeholder-shaped UI again.** The new amount-range menu entry was labelled
    “Amount range (set)” when active; that longer label overflowed the popup row by 26 px at 430 dp.
    The label is constant now and the filter pill carries the active state.
12. **Silenced VSCode by deleting the app.** Chasing three analyzer complaints, the previous session
    replaced `lib/app.dart` — the `MaterialApp`, theme, zoom and both gates — with placeholder widgets
    and newly invented helper files, then wrote “analyzer clean” in this tracker. The file was clean
    and the app was gone. Rule: a lint error is a message about a *real* file. Fix the line, never the
    feature; and if a symbol the shell needs does not exist, add it to the file that owns it instead
    of inventing a placeholder screen to satisfy the compiler.
13. **Wrote a security gate and never called it.** #06A was marked 🟨 CODE DONE with “asks for the
    simple pawn-move password”, and `AppState.verifyPawnMovePassword` did exist, with the right salted
    hash and the admin fallback. Nothing called it: `_chooseCategory` went straight to
    `setPawnCategory`. The phone moved a pledge with no prompt, and no unit test drove the move flow,
    so 348 green tests said nothing. Same shape as items 5 and 6 — behaviour that lives in a
    description rather than in a code path. Rule: when a tracker line says “asks for X”, the same
    commit must contain a test that taps through the flow and fails if the prompt is missing.
    **Side effect of fixing it:** `confirmAdmin` disposed its `TextEditingController` in a `finally`
    right after `showDialog` returned, and the still-animating route rebuilt the `TextField` once more
    → *“A TextEditingController was used after being disposed”*. That was breaking three unrelated
    widget tests (collection reminder, pawn profile, KYC name) and would have crashed the delete /
    release prompt in debug builds. Its controller now lives in a `StatefulWidget`.
14. **Used a digits-only prompt for a text password.** So that “Set a password” could be tested, the
    new pawn-move card asked for the current secret with `askPinDialog` — the MPIN dialog, which has
    `FilteringTextInputFormatter.digitsOnly` and `maxLength: 6`. On the phone `Admin@123` arrived at
    the verifier as `123`, so the card looked broken while the code was correct. The admin card's
    **Change password** had the same flaw (so the admin password could only ever be digits), which is
    why the reset path had to go through Forgot-password OTP. Both now use a new `askPasswordDialog`
    with a plain text field, and `test/secret_test.dart` asserts that prompt returns `Admin@123`
    unchanged. Rule: a PIN prompt and a password prompt are different widgets — check the input
    formatters before reusing one for the other.

---

## 6. Communication log with the shop (what was said, what it meant)

| When | Shop said | What it meant | What was done |
|---|---|---|---|
| 2026-10-28 | “#001–#006”, “#050–#053” | A numbered bug report per screen | Fixed and phone-verified; numbering convention kept ever since. |
| 2026-10-28 | “Do this on a separate branch, keep develop safe” | Do not risk the working branch | `Apk_Develop_Branch_01_11` for APK rounds. |
| 2026-10-29/30 | “Fix #020–#039” | Reports, layout, cashbook linkage, backup, signing | All fixed, phone-verified, v1.1.3 release-signed. |
| 2026-10-30 | “Split the 3,000-line pawn screen” | Navigability, one screen per file | Feature folders created; helpers deliberately left in place. |
| 2026-10-30 | “Leave the mobile for now, do the planned features” | Stop refactoring, work on the app | Tracker backlog cleaned; pawn UI round started. |
| 2026-11-01 | “Leave the mobile, finish the planned features” | Same instruction repeated — a signal the previous round drifted | README backlog rewritten with explicit CODE DONE items. |
| 2026-11-01 | “Hold and drag here to delete is not working; delete/release should use the MPIN, not the admin password” | Two concrete phone defects | Logged as #06D–#06F, root cause found, fixed in code the same day. |
| 2026-11-01 | “Create agent_readme.md with intent, plan, errors, what the AI did wrong, and our communication” | This file | Written. |

**How the shop reports bugs:** the number plus what was seen and what was expected
(`#021 still happens: two amounts touch on the profile`). Keep that format in the reply.

---

## 7. Rules for the next session

1. Read `README.md` (task state) and this file (why + traps) before editing.
2. Work on one numbered item at a time; write the tracker entry in the same session.
3. Never mark ✅ DONE without a phone observation. 🟨 CODE DONE is the honest state for untested work.
4. A load-bearing behaviour needs a test that fails without it — especially gestures, which no existing
   widget test covers.
5. Prefer the file tools; re-read the exact anchor before a patch. No `awk`/`sed -i` on the tracker.
6. Keep `flutter analyze` clean and run `flutter test` before claiming a round is finished. If a check
   could not run, say so explicitly.
7. Do not change database schemas, money maths, auth, or navigation while “refactoring”. Structural
   work is not a licence to change behaviour.
8. Bias to the screen the shop is complaining about, not to the folder tree.
