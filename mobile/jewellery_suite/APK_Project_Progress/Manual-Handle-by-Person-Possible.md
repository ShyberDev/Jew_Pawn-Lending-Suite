# Manual Handle by a Person Possible

**What this file is:** a split between the work **you** can do on the phone or in
git, the work **you can learn** with a short checklist, and the work that should
stay with the coding agent. When something lands in the last bucket and you don't
want to hand it over, say so — there is a place for that at the end.

**How to use it:** pick the task, follow the steps, and write down what you saw.
If a step fails or you don't understand it, say *"I can't do this one"* and it
moves to the agent's queue. Nothing here needs you to read Dart.

---

## A. You can do this yourself ✅

### A1. Unlock the app

1. Open **`APK_Project_Progress/PASSWORDS.md`** and read the PIN.
2. Type it on **“Jewellery Suite is locked”** and tap **Unlock**.

**Never change the PIN or the admin password to "test" them.** They are written
down so nobody has to. Changing them is the single biggest time-waster this
project has had.

### A2. Connect the phone and install a build

```bash
adb mdns services                  # find the wireless-debug port (it changes)
adb connect <ip>:<port>
adb devices                        # the phone must say "device", not "offline"
adb -s <ip>:<port> install -r mobile/jewellery_suite_v1.4.20-arm64-v8a.apk
```

Then open the app and check **Settings** (or the drawer) shows the version you
just installed. If `adb devices` is empty, the phone is asleep or wireless
debugging was switched off — fix that before anything else.

### A3. Run a phone pass (the job the tracker keeps asking for)

1. Note the build number and what you are testing (the `#0xx` item).
2. Do the flow on the phone, slowly, **once**.
3. Write down the exact words on screen, not a summary. *“Return is more than the
   weight still on this sale.”* is evidence; “it refused” is not.
4. Note the money/weight before and after (dashboard tiles are enough).
5. Screenshot the result: `adb -s <ip>:<port> exec-out screencap -p > shot.png`.
6. Add a dated section to **`VERIFICATION.md`**, and only then flip the item to ✅
   in `TRACKER.md`. A code-only change stays 🟨 until a person or agent sees it on
   the phone.

### A4. Check a module still works

| Module | Open | Good looks like |
|---|---|---|
| Dashboard | Home | Today’s sales/collected match the last sale you made; no negative stock |
| Khata | Khatabook → a customer | Their due equals what the ledger rows add up to |
| Pawn | Pawn Loans → a pledge | Outstanding = principal + interest for the months shown |
| Cashbook | Cashbook | Total in − total out = the day’s net balance |
| Jewellery sale | Jewellery → New Sale | Line total = weight × rate + making; saving changes stock and the credit book |
| Jewellery purchase | Jewellery → New Purchase | Payable = lines + shared expense; deleting it puts the grams back |
| Credit book | Jewellery → Customer Credit Book | Dues + advances, and the strip totals match |
| Workers | Jewellery → Workers | Metal reserve falls when an order is delivered (`settled` when nil) |
| Backup | Settings → Backup & data | A new archive appears and says how many tables it holds |

Anything you cannot explain in one sentence is worth reporting.

### A5. Make a backup and restore it

1. **Settings → Backup & data → Create backup**; if **Include database key** is
   on, choose a passphrase and write it on paper for that day only.
2. Note the file size and the “9 → 10” style table count.
3. To restore, pick the file; a wrong passphrase must be **refused** — if it opens
   anything, that is a bug, stop and report it.
4. The app writes a safety copy before restoring; keep it until the ledger looks
   right.

### A6. Hand a failure to the agent

Paste, do not paraphrase:

```text
build: 1.4.20 / 2072
screen: Jewellery → Workers → Test Worker
tapped: Deliver, weight 5.000
expected: Delivered
got: "Enter the delivered gross weight."   (screenshot: shot.png)
```

Plus `adb logcat -d | grep -A20 "FATAL EXCEPTION"` if the app crashed.

---

## B. You can learn this 🟡

These are safe to practise on a branch; nothing here can break the phone ledger.

### B1. Git, in the order you need it

| You want to… | Command | Notes |
|---|---|---|
| see what changed | `git status` | Read-only, always safe |
| read the change | `git diff` | Add a path to narrow it |
| keep a change | `git add <file>` | Only the files of one topic |
| save it with a message | `git commit -m "why this change"` | Say **why**, not “update file” |
| see history | `git log --oneline -10` | Your undo map |
| throw an edit away | `git checkout -- <file>` | Destructive to that file only |
| send it to GitHub | `git push` | **Ask first** — the agent never pushes on its own |

Rules for this repo: one topic per commit, never commit
`APK_Project_Progress/.secrets.local.md` (it is gitignored on purpose), and never
`push` a half-finished pass.

**Practice:** after your next phone pass, commit only
`APK_Project_Progress/VERIFICATION.md` and `TRACKER.md` with the message
`docs(verification): pass #0xx on the phone`. That is a complete, useful commit.

### B1a. Your first commit, start to finish (10 minutes)

A safe first change: add one row to the log in section E of this file.

1. Open this file in the editor and add a row under the table in section E, e.g.
   `| 07-11-26 | Phone pass #080 | need a second phone | Shop + agent |`.
2. `git status` — the file appears under **Changes not staged for commit**.
   Nothing is saved yet; the edit still exists only on your disk.
3. `git diff` — read your own change. A mistyped row shows up here before anyone
   else sees it.
4. `git add APK_Project_Progress/Manual-Handle-by-Person-Possible.md` — stages
   **one file**, not the whole project.
5. `git status` — the same file now appears under **Changes to be committed**.
6. `git commit -m "docs: note what is blocked on a second phone"` — the message
   says what changed and why, never "update" or "changes".
7. `git log --oneline -3` — your commit is the top line, with a short hash. That
   hash is how you and the agent refer to it later.
8. Changed your mind before step 6? `git checkout -- <file>` throws that edit
   away. After step 6, don't rewrite history — make a second, correcting commit.

That is the whole loop: **edit → status → diff → add → commit → log**. Nothing
leaves the computer until somebody runs `git push`, and that is asked for first.

### B2. Build and test

```bash
cd mobile/jewellery_suite
flutter analyze                # must say "No issues found!"
./tool/test.sh                 # must end "All tests passed!" with a count
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Bump the version first in `pubspec.yaml` (`version: 1.4.22+74` → `1.4.23+75`) so
the phone can prove which build you tested.

**Trap:** if tests hang with “The target device is full”, `/tmp` filled up — run
them through `./tool/test.sh`, which points `TMPDIR` somewhere bigger.

### B3. Editing the progress files

Open them in any editor and edit by hand. **Do not use `sed -i` or `awk` on
`TRACKER.md`** — a cleanup script once deleted the only progress note. Keep the
table shape (`| #0xx | ✅ | … |`) and one row per item.

---

## C. Leave these to the agent ❌

| Task | Why it needs the agent |
|---|---|
| New features / new screens | Needs the data model, the store and the tests designed together |
| Database schema changes | A migration that misses the cipher path loses the ledger |
| Money, weight, interest or tax maths | Wrong arithmetic here is invisible until the shop loses money |
| Backup encryption, restore, sync | A small mistake makes every backup unreadable |
| Auth / password / PIN logic | Needs the salted-hash and gate wiring, not a quick edit |
| Dependency or SDK upgrades | Version conflicts across Flutter, Android and the plugins |
| Finding a bug from a log or a symptom | Needs code search across `lib/` and a reproduction test |
| Writing or repairing tests | The suite is the safety net for everything above |

The agent's rule of thumb is the mirror of this file: it does **not** rotate
credentials, `push`, or delete documents without asking.

---

## C1. Tasks waiting for a person right now (2026-11-07)

| Task | What is needed | Guide |
|---|---|---|
| **#080 cross-phone restore** | A second Android phone: install the same APK, back up here with **Include database key** + a passphrase, restore there. A wrong passphrase must be refused. | A5 above |
| **#065 real OTP gateway** | The gateway URL and shared secret from the SMS/e-mail provider | `docs/SETUP_OTP_GATEWAY.md` |
| **#072 Drive backup** | A **Web client ID** from Google Cloud console | `docs/SETUP_GOOGLE_DRIVE_OAUTH.md` |
| **#081 Firebase** | A Firebase project and its `google-services.json` | `docs/SETUP_FIREBASE.md` |

Nothing in `TRACKER.md` is 🟨 right now — **#085** and **#086** were passed on
v1.4.22 (2026-11-07): **Forgot PIN?** → **Send code** raises the six-digit code
box, a wrong code is refused with *“The code is wrong or has expired.”* and the
phone stays locked. The open rows above are blocked on an input rather than on a
pass; check the legend at the top of the tracker before assuming one is owed.

---

## D. When you can't do something

Say it plainly, in one line, and it goes to the agent:

> “I can't do the phone pass for #079 — the form field won't take my taps.”
> “I don't know how to make a backup, show me once.”
> “I don't want to commit this myself, you do it.”

The agent should then either do it, or write the steps here so the next attempt is
yours. Nothing is expected to be done by you that is not on this page.

---

## E. “I can't / I don't know” log

Fill this in as things come up, so no question is lost between sessions.

| Date | Task | What blocked me | Who takes it |
|---|---|---|---|
|    |    |    |    |

---

## F. Never do these

1. Never change the PIN or admin password to test them — read `PASSWORDS.md`.
2. Never **clear app data** or uninstall to “fix” a problem: the encryption key
   lives with the data and the ledger goes with it.
3. Never `git push`, delete a branch, or reset history without asking.
4. Never delete a document, worker or receipt that holds real money without the
   shop's approval.
5. Never build or install while a phone pass is running — the phone is
   single-tenant.
