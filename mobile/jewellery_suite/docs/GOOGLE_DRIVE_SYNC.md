# Google Drive backup + multi-device sync — design

**Status:** designed, not implemented. Blocked on one input from the shop: a Google
OAuth client ID for the app (see *What you must create* at the end).

## Why "I added my Gmail" did not connect anything

Typing a Gmail address into the app is only a label. Google Drive access needs
**OAuth consent**: the app has to ask Google for the `drive.appdata` scope and
receive a token, and Google only lets an app ask if that app was registered in
Google Cloud Console with the package name and the release certificate's SHA-1.
There is no way around that registration, and no way to do it from inside the
app. Once the client ID exists, the flow below works with any Google account the
shopkeeper signs in with.

## Two different problems

1. **Backup** — one copy of the ledger, kept off the phone, restorable on a new
   phone. Not live, no conflicts.
2. **Multi-device sync** — the owner's phone, an employee's phone and (later) a
   tablet all read and write the same books, and the owner sees the changes.

These should share one Drive folder but be built in that order. Backup is safe
today; sync needs conflict rules.

## Storage on Drive

Use the **app folder** (`appDataFolder`), not the visible "My Drive":

* invisible to the user's other files, cannot be accidentally deleted from the
  Drive UI, only this app can read it;
* survives uninstall/reinstall and phone changes;
* free of Drive quota surprises and of the "share a folder with myself" problem.

Layout inside the app folder:

```
jewellery-suite/
  shop.json            # shop id, name, created_at, main_device_id, schema version
  devices/<deviceId>.json   # device registry: name, model, role, last_seen, revoked
  ledger/head.json     # revision pointer + last full snapshot id + writer device
  ledger/snap-<rev>.db # encrypted SQLCipher snapshots (rolling, newest 7)
  ledger/changes-<rev>.jsonl  # change batches since the snapshot
```

The Android keystore key is **per device**, so a Drive copy cannot be opened on
another phone with it. Snapshots must be encrypted with a **shop key** derived
from the shop's own passphrase (PBKDF2/Argon2 → SQLCipher raw key), and that
passphrase is what a new device asks for when joining. Losing the passphrase
means losing the cloud copy — the phone's local ledger is still readable, so the
app must say that plainly when the passphrase is created.

## Main device — the method to use

Khatabook and the khata apps in this market all converge on the same model:
**the account owner's phone is the main device; staff join it, they do not create
the shop.** Concretely:

1. **The first device to create the shop is the main device.** Its id is written
   to `shop.json` as `main_device_id` at creation time under a Drive revision
   check, so a second device cannot race it into existence.
2. **Every other device joins with a pairing code.** The main device shows a
   short code (6 digits) or QR from *Settings → Devices → Add a device*. The new
   phone enters it; the main device sees "Employee phone wants to join" and
   approves. This is the same trusted-pairing idea as WhatsApp Web and Khatabook's
   staff invites, and it works without the shop owning a server.
3. **The main device is the tie-breaker.** If two devices edit the same record,
   the main device's version wins and the other version is kept as a conflict
   copy the owner can open. A device that is revoked cannot write at all.
4. **Main device can be moved, deliberately.** *Settings → Devices → Make this
   the main device* requires the admin password on the current main device (or
   the shop passphrase if that phone is lost). Never automatic — a phone that
   simply reinstalled must not silently become the owner.

## Device registry (what the owner sees)

*Settings → Devices* lists every paired device: name (from the model, editable),
role (**Main** / **Employee**), last sync time, and app version. Each row has
**Remove**; a removed device's next sync is refused and it keeps only its local
copy, clearly labelled "no longer connected".

Recorded per device: `device_id` (random, generated once and kept in settings),
`name`, `role`, `joined_at`, `last_seen_at`, `last_rev`, `revoked`.

## Sync mechanics

The database already carries `dirty` flags and `updated_at` on rows, so sync can
be change-based rather than whole-file:

1. Each write stamps `updated_at` (already stored) and queues the row in
   `changes-<rev>.jsonl` with the device id.
2. A device flushes its queue to Drive when online (on entry save, every N
   minutes, and on app pause), then reads newer batches from the other devices.
3. Every 50 batches or 24 hours the flushing device writes a fresh encrypted
   snapshot and prunes to the newest 7, so a new device restores from one file
   instead of replaying a year of changes.
4. Conflicts: same table + uuid + both changed since the reader's `last_rev` →
   main device's row wins, loser is written to `conflicts/<uuid>.json` and shown
   in *Settings → Devices → Conflicts*.

What "immediately" means: Drive polling is not a socket. Realistic latency is
5–30 seconds with an active poll while the app is open, and near-instant only if
a push channel is added later. The UI must not promise live typing.

## Photographs

Customer and ID photos are files, not rows. They go to the app folder as
`photos/<sha256>.<ext>` with the path rewritten in the row, so the same photo is
stored once and a restore on a new phone brings its pictures back.

## Google Sign-In in the app

* `google_sign_in` for the account and `googleapis/drive/v3` for the files,
  scopes `drive.appdata` + `email` only (no full Drive access).
* One Google account per shop. The account is *transport*, not identity: the main
  device and the pairing code decide who may write, so a staff member signing in
  with their own Gmail still only joins as an employee.
* Tokens are never stored on disk; the sign-in is silent on each cold start and
  falls back to "offline — last synced 09:12" when there is no network.

## What you must create (one-time, ~10 minutes)

1. Google Cloud Console → new project "Jewellery Suite".
2. **Enable APIs** → Google Drive API.
3. **OAuth consent screen** → External, add your Gmail as a test user (or
   publish later). Scopes: `drive.appdata`, `email`.
4. **Credentials → Create OAuth client ID → Android**:
   * package name: `com.shyberdev.jewellery_suite`
   * SHA-1 of the release keystore (and the debug keystore if you want it while
     developing): `keytool -list -v -keystore <keystore> -alias <alias>`
5. Also create an **OAuth client ID → Web application**, and send that **Web
   client ID**. On Android `google_sign_in` needs it as `serverClientId`; the
   Android client (package + SHA-1) alone is not enough. Neither client ID is a
   secret — both are embedded in the app.

Until that exists, **Settings → Backup & data** keeps writing encrypted backups
to the phone, and the share sheet can already send them to Drive by hand, which
is the honest fallback.

## Build order once the client ID exists

1. Drive sign-in + "back up now to Drive" + restore from Drive (no sync).
2. Device registry, main device, pairing code, remove device.
3. Change-based sync with conflict copies.
4. Photos, then move-main-device.
