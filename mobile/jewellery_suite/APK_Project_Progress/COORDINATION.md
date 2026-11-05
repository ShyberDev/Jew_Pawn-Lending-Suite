# Coordination — two agents, one repository

**Last updated:** 2026-11-05
**Branch:** `Apk_Develop_Branch_01_11`
**Why this file exists:** on 2026-11-04 two agents wrote the same checkout at once.
`backup_service.dart` / `backup_screen.dart` were left half-rewritten (49 analyzer
errors, unfinished methods, no tracker entry) and the committed v1.4.4 files had to
be restored. This file is the single claim board. **Read it before editing; append
your claim before you start.**

## Current snapshot

| Thing | State |
|---|---|
| Origin head | `270ada7` — docs(release): verify the downloaded v1.4.4 asset on the phone |
| Local head | `646d44b` — #080, **10 commits ahead of origin** (freebuff's #073–#080 work) |
| Working tree | freebuff edits: `lib/data/backup_service.dart`, `lib/features/backup/screens/backup_screen.dart`, `pubspec.yaml` (1.4.15+67), new `test/backup_manifest_test.dart` |
| `flutter analyze` | clean at 2026-11-05 23:40 snapshot |
| Phone | `10.52.61.148:42895` (Wi-Fi changed from `10.235.54.202:40933`) |
| Phone build | **1.4.15 / versionCode 2067**, `SQLCipher encrypted, schema v21` |
| Push | GitHub git-push returns HTTP 500; publish through the GitHub API (`/tmp/opencode/publish_docs.py`) |
| Release | `v1.4.4` tag at `6315c2c`; release assets are the last published build |

## Lanes

| Lane | Owner | Write scope |
|---|---|---|
| Implementation | **freebuff** | `lib/**`, `test/**`, `android/**`, `pubspec.yaml` — in its own worktree/branch |
| Verification & release | **opencode (me)** | `flutter analyze`, `flutter test`, phone pass, `APK_Project_Progress/**`, `docs/SETUP_*.md`, tags, GitHub releases |
| Phone | **opencode (me)** | one build/install at a time on `10.52.61.148:42895` |
| Tracker / handoff notes | **opencode (me)** | `APK_Project_Progress/README.md`, `Temp_Passwords_readme.md`, this file |

## Active claims

| Item | Owner | Files | Started | Status |
|---|---|---|---|---|
| backup archive/manifest work | freebuff | `backup_service.dart`, `backup_screen.dart`, `pubspec.yaml`, `test/backup_manifest_test.dart` | 2026-11-05 | in progress — **do not touch these files** |
| #065 OTP gateway setup guide | opencode | `docs/SETUP_OTP_GATEWAY.md` | 2026-11-05 | docs only |
| #072 Drive OAuth setup guide | opencode | `docs/SETUP_GOOGLE_DRIVE_OAUTH.md` | 2026-11-05 | docs only |
| Firebase agenda | opencode | `docs/SETUP_FIREBASE.md`, tracker | 2026-11-05 | docs only |

## Rules

1. **One writer per file at a time.** Claim it above before editing. If a file is
   claimed, do not reformat, rename, or "clean up" it.
2. **freebuff works in a separate worktree** (`git worktree add ../jewellery_freebuff
   -b freebuff/work`) or, if it must use this checkout, it owns `lib/` and `test/`
   until it hands off. I do not edit `lib/` while it is active.
3. **Handoff gate — all four, or it is not a handoff:**
   - `flutter analyze` → `No issues found!`
   - `flutter test` → all green, with the count
   - committed (no partial files left behind)
   - a note listing: item number, files touched, commands run, what is **not**
     verified on the phone
4. **No schema, money-maths, auth, or navigation changes** outside the item.
5. **Never leave uncommitted partial work at handoff.** The last revert happened
   exactly because this rule was skipped.
6. **Phone is single-tenant.** Nobody builds or installs while the other is
   mid-pass. Announce the item and the expected duration first.
7. **Tracker is mine.** freebuff reports the item and evidence; I write the row.
   A `🟨 CODE DONE` row is not `✅ DONE` until a phone observation is recorded.
8. **No secrets in git.** `android/key.properties` and the keystore stay ignored.
   `Temp_Passwords_readme.md` is tracked today and holds shop credentials — it
   must be removed before any public handover (#080 open item).

## Handoff template (paste this back)

```text
ITEM: #0xx
FILES: lib/..., test/...
COMMANDS: flutter analyze -> No issues found
          flutter test -> NNN passing
COMMIT: <sha>
PHONE: not run / ran on 1.4.15 (2067) and saw ...
NOT VERIFIED: ...
NEXT: ...
```

## Verification queue (phone passes owed)

| Item | Needs |
|---|---|
| #074 | receipt dialog split + saved-rate chart on the phone |
| #075 | late-fee dialog on a real sale (confirm→stock was covered under #076) |
| #077 | advance-only customer visible in Credit Book |
| #078 | create order → deliver → reopen → deliver refused; over-return refused |
| #079 | worker order delivered twice refused |
| #080 | manifest flags re-checked in the built APK; archive-key/credentials items still open |

## Release state

- `v1.4.4` is the last published release; its arm64 asset was downloaded,
  SHA-256 matched, installed, and kept the data.
- Local `1.4.15+67` is **not** released. Do not tag or upload until the full
  analyze + test + phone gate passes and the tracker rows are written.
- Git push is broken at the endpoint; the API publisher creates blobs/tree/commit
  on top of the current origin head. Update `PARENT` and the commit message
  before each run.
