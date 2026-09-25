# Backup & Disaster Recovery (Google Drive + rclone)

> **Read this with [`README_FIRST.md`](../README_FIRST.md).** This covers the
> "what if the laptop dies?" half of the suite. The mobile app
> ([`MOBILE_SYNC_DESIGN.md`](MOBILE_SYNC_DESIGN.md)) covers the *live two-way
> sync* half. They are different jobs — don't mix them up.

---

## 1. Backup vs sync — the one thing to understand

| | **Backup** (this doc) | **Sync** (mobile app) |
|---|---|---|
| What | A complete **snapshot** of the whole site | Individual **records** moved both ways |
| Direction | One-way (laptop → Google Drive) | Two-way (phone ⇄ laptop) |
| Frequency | Nightly / on demand | Continuous while connected |
| Purpose | Recover from a **lost/damaged laptop** | Keep phone and laptop **in agreement** |
| Medium | Google Drive (a file store) | Frappe REST API + local SQLite |

Google Drive is **excellent** for backup and **unsuitable** for live sync (no
transactions, no conflict resolution, API rate limits, a bad edit on one side
can corrupt the file). So:

- **Backup → Google Drive.**
- **Sync → the Frappe sync API.**

---

## 2. What a backup contains

`bench --site <site> backup --with-files` produces three files in
`sites/<site>/backups/`:

| File | Contents |
|------|----------|
| `<stamp>_database.sql.gz` | The **entire database** (all customers, loans, invoices, settings) |
| `<stamp>_files.tar` | **Public** files (logos, uploaded images, generated PDFs) |
| `<stamp>_private_files.tar` | **Private** files (attachments marked private) |

Restoring those three files reconstructs the whole business.

---

## 3. One-time setup

### 3.1 Install rclone

```bash
curl https://rclone.org/install.sh | sudo bash
rclone version
```

### 3.2 Connect Google Drive

```bash
rclone config
```

- `n` (new remote)
- name: **`gdrive`**
- storage: **`drive`** (Google Drive)
- `client_id` / `client_secret`: leave blank (uses rclone's own; fine for
  personal use) — or create your own in Google Cloud Console for higher limits.
- scope: **`1`** (full access) or `3` (drive.file) if you prefer tighter scope.
- `root_folder_id`: blank
- `service_account_file`: blank
- Edit advanced config: **`n`**
- Use auto config: **`y`** (opens a browser to sign in) — on a headless machine
  answer `n` and run `rclone authorize "drive"` on a machine with a browser,
  then paste the token.
- Configure as Shared Drive: `n`
- Confirm: **`y`**, then `q` to quit.

Test it:

```bash
rclone lsd gdrive:
```

### 3.3 (Recommended) Encrypt the backups

So that even if the Google account is compromised, the data is unreadable:

```bash
rclone config
# n -> name: gdrive-crypt
# storage: crypt
# remote: gdrive:JewelleryBackups
# filename_encryption: standard
# directory_name_encryption: true
# password: <choose one>          (generate one with: rclone obscure -)
# password2: <choose a salt>      (generate one with: rclone obscure -)
```

Then set `RCLONE_REMOTE="gdrive-crypt:JewelleryBackups"` in `backup.env`.

> **Keep the passwords safe.** Without them, the encrypted backups cannot be
> restored by anyone — including you.

### 3.4 Configure the script

Create `backup.env` next to `backup-to-gdrive.sh`:

```bash
SITE="library.local"
BENCH_DIR="$HOME/frappe-bench"
RCLONE_REMOTE="gdrive:JewelleryBackups"   # or gdrive-crypt:... if encrypted
RETENTION_DAYS="30"
```

Make the script executable:

```bash
chmod +x backup-to-gdrive.sh
```

### 3.5 Test it once, manually

```bash
./backup-to-gdrive.sh
```

Then confirm the files are on Drive:

```bash
./backup-to-gdrive.sh --list
```

### 3.6 Schedule it (nightly)

```bash
crontab -e
```

Add (2:15am every night):

```
15 2 * * *  /home/shyam/Jew_Pawn-Lending-Suite/backup-to-gdrive.sh >> /home/shyam/backup.log 2>&1
```

Check `~/backup.log` after the first night.

---

## 4. Restoring after a laptop loss (step by step)

On the **new** machine:

1. **Install the suite** with the one command from `README_FIRST.md`
   (`install.sh`), so Frappe/ERPNext + the three apps exist again.
2. **Install rclone and reconnect Google Drive** (section 3.1–3.2), using the
   **same crypt passwords** if you encrypted.
3. **Download the newest backup:**

   ```bash
   rclone copy gdrive:JewelleryBackups ~/frappe-bench/sites/library.local/backups
   # (or gdrive-crypt:... if encrypted)
   ```

4. **Restore it:**

   ```bash
   cd ~/frappe-bench
   ./path/to/backup-to-gdrive.sh --restore <backup-base-name>
   ```

   (`<backup-base-name>` is the filename without `_database.sql.gz`.)

5. **Finish up:**

   ```bash
   bench --site library.local migrate
   bench --site library.local clear-cache
   ```

6. Log in to `/desk` and verify a few records.

> **Rehearse this once** on a test site so that on the bad day it is routine,
> not a discovery. An untested backup is not a backup.

---

## 5. Best-practice checklist

- [ ] Nightly `backup-to-gdrive.sh` on cron.
- [ ] Backups **encrypted** (`gdrive-crypt`).
- [ ] **Second off-site copy** — another cloud (`rclone` supports S3, Backblaze B2,
      OneDrive…) or a periodic copy to an external HDD. One provider is a single
      point of failure.
- [ ] `RETENTION_DAYS` long enough for your business (30–90 days).
- [ ] App **code** is on GitHub (already done).
- [ ] **Restore rehearsed** at least once.
- [ ] Keep the crypt passwords in a password manager **and** on paper somewhere safe.
- [ ] Optionally enable MariaDB **binary logs** for point-in-time recovery
      (recover to the minute, not just last night).

---

## 6. Quick reference

```bash
# Back up now (local + Excel exports + upload + prune)
./backup-to-gdrive.sh

# Local backup only (no upload)
./backup-to-gdrive.sh --no-upload

# Excel exports only — no DB backup, no upload (use for sharing)
./backup-to-gdrive.sh --export-only

# See what is on Drive
./backup-to-gdrive.sh --list

# Restore (interactive, overwrites the site)
./backup-to-gdrive.sh --restore 20260924_021500-library_local
```

---

## 7. Excel exports (shareable copies)

Every backup run also writes four **Excel workbooks** (via `tools/export_excel.py`,
which reads the database directly and never writes back to it — a safe side copy):

| File | Contents |
|------|----------|
| `<stamp>_full.xlsx`      | Every non-empty table in the whole site DB (complete data snapshot) |
| `<stamp>_khata.xlsx`     | Money-lending module — loans, installments, collections, refinances |
| `<stamp>_pawn.xlsx`      | Pawn module — loans, items, releases + customer/village master |
| `<stamp>_customers.xlsx` | Villages + businesses master list (handy to share) |

They are uploaded to Google Drive with the rest of the backup (`*.xlsx` is in the
rclone include list), so you always have a human-readable, spreadsheet-openable
copy next to the raw database dumps.

### Just want the Excel files (no backup)?

```bash
./backup-to-gdrive.sh --export-only
```

Writes the four files fresh into `sites/<site>/backups/` — perfect when someone
asks for "the current data" to store in a personal location.

---

## 8. No-duplicate backups (change detection)

`backup-to-gdrive.sh` stores a **fingerprint** (a SHA-256 over `CHECKSUM TABLE …
EXTENDED` of every table) in `sites/<site>/backups/.last-fingerprint`.

Before a run it recomputes the fingerprint:

- **Data changed** → normal backup + Excel exports + upload.
- **Nothing changed** → the whole job is skipped:
  `no data changes since last backup — skipping (no duplicates)`.

So Google Drive never accumulates identical snapshots, and night-after-night
cron runs don't fill the Drive with duplicate files. The fingerprint is also
written *after* a successful run, never before, so a failed backup can never
mask a real data change (you never get a false "skip").

> If you change the data *programmatically* and want to force the next run,
> delete `.last-fingerprint` (or just wait for the next data edit — any change
> flips the checksum).
