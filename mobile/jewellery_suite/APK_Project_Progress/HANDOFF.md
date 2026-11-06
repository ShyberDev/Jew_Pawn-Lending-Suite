# Handoff — phone, secrets, traps, working rules

**Read this before touching the app or the phone.** `README.md` is the dashboard,
`TRACKER.md` is the task list, `VERIFICATION.md` is the phone evidence.

---

## 1. Current state (2026-11-06)

| Thing | Value |
|---|---|
| Test phone | Redmi Note 8 Pro (`infinity_begonia`), Android wireless debugging |
| Address | **`10.52.61.148:42895`** — changes every session |
| Installed build | **1.4.15 / versionCode 2067**, release-signed, arm64 |
| Database | `SQLCipher encrypted, schema v21` |
| Branch | `Apk_Develop_Branch_01_11` |
| Last **published** release | **v1.4.4 / 2056** (GitHub release, three split APKs) |
| Tests / analyzer | 518 passing, `flutter analyze` clean at the last check |

The address is not stable. Discover it with `adb mdns services`, then:

```bash
adb connect <ip>:<port>
adb -s <ip>:<port> shell echo alive
```

Do not trust a written-down port. The phone has moved mid-session more than once.

---

## 2. Secrets

**The real values are in `APK_Project_Progress/.secrets.local.md`**, which is
gitignored and must never be committed. This file deliberately contains no
passwords or PINs.

| Secret | Where it is set |
|---|---|
| Screen-lock PIN / MPIN | Password Settings → Biometric & screen lock |
| Shop account (Gmail / mobile) + password | Login screen, or Password Settings → Account & login |
| Admin password | Password Settings → Admin password |
| Pawn-move password | Password Settings → Pawn-move password (unset → falls back to admin) |
| OTP gateway | Password Settings → One-time code delivery |

**Security debt (#080):** these values were previously tracked in
`Temp_Passwords_readme.md` in a **public** repository. The file has been removed
from the current tree and moved to the local secrets file, but it remains in git
history. **Rotate the admin password and the PIN before any public handover.**
The keystore password lives in `android/key.properties` (gitignored) — back it up;
losing it means Play cannot accept an update.

---

## 3. Environment traps

1. **`/tmp` is a small tmpfs.** A full `/tmp` makes `flutter test` hang, then die
   with “The target device is full”. Always run:
   `TMPDIR=$PWD/.dart_tool/tmp flutter test`
2. **The device address changes every session.** mDNS can advertise a stale
   record that refuses connections. Re-discover, then `adb shell echo alive`.
3. **The database is ciphertext.** `adb pull` of `databases/jewellery_suite.db`
   will not open in a normal SQLite browser. Use **Settings → Backup & data**.
   Do not clear app data to “fix” encryption — that destroys the keystore key and
   the ledger together.
4. **`kDevPasswordGateDisabled` in `lib/util/secret_dev.dart`** skips the PIN and
   forced-admin gates. It must be `false` for a release build. The release
   behaviour was re-armed on v1.4.4; check the flag before shipping.
5. **The drawer page is snapshot-timing dependent.** If **CORE MODULES** is not
   visible, close and reopen the drawer; do not tap from a stale screenshot.
6. **Widget tests do not cover gestures by default.** The drag-to-delete bug
   shipped because no test simulated a long-press-drag. If a behaviour is a
   gesture, add the gesture test in the same commit.
7. **A green analyzer says nothing about layout or a missing screen.** Run the
   widget tests and open the screen.

---

## 4. Working rules

1. **One writer at a time.** Two agents in one checkout left `backup_service.dart`
   half-rewritten (49 analyzer errors) on 2026-11-04. Use a separate worktree for a
   second writer, or one agent owns `lib/` until it hands off.
2. **One numbered item per change.** Write the tracker row in the same session.
3. **✅ DONE needs a phone observation.** 🟨 CODE DONE means written and tested but
   not seen on the device. Never blur the two.
4. **Handoff gate:** `flutter analyze` clean, `flutter test` green with the count,
   committed, and a note listing item / files / commands / what is **not** verified.
5. **No schema, money-maths, auth, or navigation changes** outside the item.
6. **The phone is single-tenant.** Do not build or install while another pass is
   running.
7. **Do not use `sed -i`/`awk` on the tracker.** Re-read the exact block and use
   the file tools. A cleanup script once deleted the only progress note.
8. **Bias to the screen the shop is complaining about**, not to the folder tree.

---

## 5. Lessons that cost real time

- **A derived balance must list every input.** Adding `late_fee_total` later broke
  both recompute paths; a payment silently wiped the fee (#076).
- **A label computed from the wrong flag is invisible to a green suite.** The
  late-fee row read “-₹0” until it keyed on `debit > 0`.
- **A security gate that exists but is never called is not a gate.** #06A had the
  verifier and no caller; the phone moved a pledge with no prompt.
- **A PIN prompt is not a password prompt.** `digitsOnly` + `maxLength: 6` turned
  `Admin@123` into `123`; use `askPasswordDialog` for text secrets.
- **A structural refactor is not progress the shop can see.** Fix the screen.
- **A widget created inside `build()` cannot be read through the State’s own
  context.** The Reports export crashed on v1.2.7 while the suite stayed green.
- **Visual state deleted during a cleanup needs a test in the same commit.** The
  pawn tile lost its cloud badge twice (#06C → #06J).

---

## 6. Before a public handover

- [ ] Rotate the PIN and admin password (the old values are in public git history).
- [ ] Delete `.secrets.local.md` from the machine that is handed over.
- [ ] Remove `APK_Project_Progress/` from the shipped repo, or keep only the
  sanitized `README.md` / `TRACKER.md` / `VERIFICATION.md` / `CHANGELOG.md`.
- [ ] Confirm `kDevPasswordGateDisabled = false`.
- [ ] Confirm the release keystore and `key.properties` are backed up offline.
- [ ] Confirm no APK or keystore is tracked (`git ls-files | grep -E '\.(apk|jks)$'`).
