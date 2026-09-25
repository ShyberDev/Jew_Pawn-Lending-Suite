# Mobile ↔ Laptop Sync — Design

> **Status: Phase 1 DONE (server sync API shipped & tested); the Android app is
> next.** The server half now lives in `pawn_shop/api/sync.py` with DocTypes
> `Sync Device`, `Sync ID Map`, `Sync Log`. The client will be a **native
> Android (Flutter)** app (owner's decision), not a PWA. See §8 for what remains.

---

## 1. Goal

Let a **phone** and the **laptop** both hold the shop's data locally, and **sync
both ways whenever they are connected**, so the shop can keep working when the
phone is away from the laptop (village collections, counter sales, pawn intake).

Concretely:

- The **laptop** runs the Frappe/ERPNext server (the "source of truth").
- The **phone** can **create and read** records with **no connection**.
- When the phone reconnects (same Wi-Fi, hotspot, or internet), changes made on
  each side **merge** without duplicates or data loss.

---

## 2. What already exists (grounding)

- The apps are normal Frappe DocTypes, so every record is already a **REST
  endpoint** (`/api/resource/<DocType>`, `/api/method/<method>`).
- `pawn_shop` already sets `use_json_request_body = True` (clean JSON APIs).
- `pawn_shop` has an `api/` package (`permission.py`) — a natural home for sync
  endpoints.
- Transactional DocTypes are **submittable and append-only** (Pawn Loan, Pawn
  Release, Khatabook Loan/Collection/Refinance, Sales/Purchase Invoice). This is
  a gift for sync: append-only data rarely conflicts.
- **No** service-worker/PWA support exists in Frappe core — we add it.

---

## 3. The hard constraints (must be designed around)

| Constraint | Impact |
|------------|--------|
| **Service workers require HTTPS** (or `localhost`) | A PWA on `http://192.168.x.x` **cannot** cache offline. For true offline we need HTTPS (self-signed cert the phone trusts, or a real domain + Let's Encrypt, or a tunnel). |
| **iOS PWA limitations** | iOS Safari has no Background Sync; sync happens while the app is open. Android Chrome supports Background Sync. |
| **Frappe is desktop-first** | The desk is not usable on a phone; we build a small dedicated mobile UI. |
| **Offline conflict** | Two devices editing the same *master* record can diverge; transactions are append-only so they don't. |
| **Clock skew** | Never trust device time; use **server time** as the sync cursor. |

---

## 4. Options compared

| Option | Offline? | Android | iOS | Effort | Notes |
|--------|----------|---------|-----|--------|-------|
| **A. LAN web only** (phone browser → laptop IP) | ❌ | ✅ | ✅ | Tiny | No local storage; needs Wi-Fi always. Fails the requirement. |
| **B. Offline-first PWA** (recommended) | ✅ | ✅ | ⚠️ partial | Medium | Install to home screen, no app store. iOS sync only while open. Needs HTTPS for offline. |
| **C. Native app** (Flutter/React Native) | ✅✅ | ✅ | ✅ | High | Best offline + camera/barcode/notifications/background sync. Needs APK/Play distribution. |
| **D. Existing Frappe Mobile (Flutter)** | ⚠️ mostly online | ✅ | ✅ | Low | Generic, not tailored to pawn/khatabook; limited offline. |

**Recommendation: Option B (offline-first PWA) as the MVP, with a clean sync API
that Option C could reuse later.** If the shop truly needs camera-based intake,
barcode, or guaranteed background sync on iPhone, go straight to Option C.

---

## 5. Recommended architecture

```
 ┌─────────────────────┐         HTTPS/JSON         ┌──────────────────────────┐
 │   PHONE (PWA)       │  ───────────────────────►  │  LAPTOP (Frappe)         │
 │                     │                            │                          │
 │  UI (mobile screens)│  ◄───────────────────────  │  REST + sync API         │
 │  IndexedDB (Dexie)  │   pull(delta) / push(batch)│  DocTypes (source of     │
 │  Mutation queue     │                            │  truth) + Sync Device    │
 │  Service worker     │                            │  + client_uuid dedupe    │
 └─────────────────────┘                            └──────────────────────────┘
```

### 5.1 Server side (new `sync` module)

Add to `pawn_shop` (or a new `suite_sync` app later — it must cover jewellery
DocTypes too):

- **New fields**: `client_uuid` (Data, unique, read-only) on every synced
  DocType, plus `origin_device` (Link → Sync Device). Added via **Custom Field**
  fixtures so core DocTypes (Sales Invoice etc.) aren't modified.
- **New DocTypes**:
  - `Sync Device` — name, user, platform, last_sync (datetime), enabled.
  - `Sync Log` — device, direction, doctype, count, status, error (audit).
- **Whitelisted methods** (`pawn_shop.api.sync`):
  - `register_device(device_name, platform)` → device id + credentials.
  - `pull(since, doctypes)` → `{ server_time, docs: {...} }` (only rows with
    `modified > since`, permission-filtered).
  - `push(mutations)` → apply in order, dedupe by `client_uuid`, return
    `{ server_time, results: [{client_uuid, server_name, status, error}] }`.
  - `status()` → server time + per-doctype counts (for the sync screen).

### 5.2 Client side (PWA)

- **Stack**: a small static app (Svelte/Preact or plain JS) served from
  `/assets/pawn_shop/mobile/`, plus a `manifest.webmanifest` and `sw.js`.
- **Local store**: IndexedDB via **Dexie.js** — tables mirror the synced DocTypes
  plus a `_outbox` (pending mutations) and `_meta` (last_pull cursor).
- **Write path**: every create/update writes to IndexedDB first (works offline)
  and appends a mutation to `_outbox`.
- **Sync engine**:
  - `push()` flushes `_outbox` in order (chunked), marks rows synced on 2xx.
  - `pull()` fetches rows changed since `_meta.last_pull` and upserts locally.
  - Runs on app open, on `online` event, and periodically while open.
  - Android: register **Background Sync** so it flushes even when closed.
- **Idempotency**: the server dedupes on `client_uuid`, so a retried push never
  double-creates.

### 5.3 Conflict rules

| Data | Rule |
|------|------|
| Transactions (submittable) | **Append-only.** Create is idempotent by `client_uuid`; once submitted, never edited. No conflicts. |
| Masters (Customer, Village, Item) | **Last-write-wins by server `modified`.** If the client's base `modified` is older than the server's, the server wins and the client is told (`status: "server_wins"`). |
| Deletes | Soft-delete only (a `disabled`/`cancelled` flag) so a delete can sync. |

---

## 6. Mobile screens (MVP)

1. **Home** — today's collections, active pawn loans, sync status/badge.
2. **Pawn intake** — customer (search/create) + items (metal, weight, hallmark) +
   amount → creates `Pawn Loan`.
3. **Pawn release** — search loan → pay principal+interest → `Pawn Release`.
4. **Khatabook collection** — pick village → pick loan → amount → flags
   `is_irregular` → `Khatabook Collection`.
5. **Customers** — list/search/create/edit.
6. **Sync** — last sync, pending count, manual "Sync now", errors.

(Read-only dashboards can be added later.)

---

## 7. Security

- Login once with the Frappe user; store a **per-device API key/secret** (or
  session) securely on the device (not in plain localStorage if avoidable).
- The sync API enforces the **same Frappe permissions** as the desk (per DocType,
  per user role) — a phone can only push/pull what its user may.
- Every synced row records `origin_device` for audit.
- **HTTPS is required** for a real deployment (and mandatory for service workers).

---

## 8. Phased roadmap

| Phase | Deliverable | Status |
|-------|-------------|--------|
| **0** | Design + owner answers | ✅ done |
| **1** | Sync API (`pull`/`push`/`register_device`) + `client_uuid` idempotency + test | ✅ **DONE** |
| **2** | Native Android (Flutter) app: SQLite store, the screens, online sync | ✅ **DONE** |
| **3** | Offline queue + camera/photos (done) · background sync + conflict UI (next) | 🟡 mostly done |
| **4** | Lending + jewellery-sales screens; per-device roles | ⏳ next |

**Phase 1 is shipped** — see §11 for the endpoints and DocTypes. Because the
client is a **native Flutter app** (owner's decision), the HTTPS/service-worker
constraint does **not** apply: native apps may use plain HTTP on the LAN and have
real background sync.

---

## 9. Why this fits the suite

- Reuses the existing Frappe REST API and permissions — no new backend stack.
- Append-only transactions make sync genuinely safe.
- One sync API serves pawn, khatabook, jewellery and lending.
- Stays inside the one-bundle repo (`apps/pawn_shop/.../api/sync.py` +
  `apps/pawn_shop/.../public/mobile/`), so new users still install one thing.

---

## 10. Owner decisions (recorded)

| Question | Decision |
|----------|----------|
| Platform | **Android only** — native **Flutter** app (owner's choice, not a PWA) |
| Offline depth | **Fully offline**; sync when reconnected |
| Data captured | **All**: new pawn loans, pawn releases, khatabook collections, jewellery sales, read-only dashboards |
| Devices | **2–5** staff phones (per-device tracking via `Sync Device`) |
| Photos | **Yes** — item and customer photos in v1 (stored on the phone, uploaded to the server after the record syncs) |
| Connectivity | Same Wi-Fi (LAN); internet later if needed |

---

## 11. Phase 1 — what actually shipped (reference)

**Code:** `apps/pawn_shop/pawn_shop/api/sync.py`
**Test:** `apps/pawn_shop/pawn_shop/tests/test_sync_api.py`
(`bench --site library.local execute pawn_shop.tests.test_sync_api.run`)

**New DocTypes**

| DocType | Purpose |
|---------|---------|
| `Sync Device` | One row per phone (`device_name`, `user`, `platform`, `last_sync`, `enabled`). `register_device` returns its name; pass it as `device` on `push`. |
| `Sync ID Map` | The idempotency ledger: `client_uuid` → (`reference_doctype`, `reference_name`). Unique on `client_uuid`. |
| `Sync Log` | Audit of every push/pull (device, direction, count, status, error). |

**Whitelisted endpoints** (all permission-checked with `frappe.has_permission`)

| Method | Args | Returns |
|--------|------|---------|
| `pawn_shop.api.sync.register_device` | `device_name`, `platform` | `{ device, server_time }` |
| `pawn_shop.api.sync.status` | `device` (opt) | `{ server_time, user, doctypes, registry }` |
| `pawn_shop.api.sync.pull` | `since`, `doctypes`, `limit` | `{ server_time, docs }` — full docs incl. child tables, `modified > since` |
| `pawn_shop.api.sync.push` | `mutations`, `device` | `{ server_time, results }` |

**Mutation shape**

```json
{ "op": "create", "doctype": "Pawn Loan", "client_uuid": "<uuid>",
  "submit": false, "data": { "...": "..." } }
```

**Idempotency rule:** if a `client_uuid` already exists in `Sync ID Map`, `create`
returns the existing server name and does **not** insert a duplicate — so a phone
may safely retry a push any number of times.

**Sync-enabled DocTypes (registry in `sync.py`):** Village, Business, Pawn
Customer, Pawn Loan, Pawn Release, Khatabook Loan, Khatabook Collection,
Khatabook Refinance, Jewellery Order, Jewellery Sales Invoice, Jewellery Purchase
Invoice.

**Verified on `library.local`:** register → create (idempotent re-push returns the
same name, count stays 1) → transaction create → delta pull → update by
`client_uuid` → non-registry DocType rejected with an error.

---

## 12. Phase 2 — the Android app (shipped)

**Code:** `mobile/jewellery_suite/` (Flutter 3.47.5 / Dart 3.13, Android SDK 36,
JDK 17). Build: `mobile/build-apk.sh`. Docs: `mobile/README.md`.

**Local store** (`lib/data/local_db.dart`): SQLite tables mirroring the server
field names — `customers`, `villages`, `pawn_loans`, `pawn_items`,
`pawn_releases`, `khatabook_loans`, `khatabook_collections`,
`khatabook_refinances`, plus `outbox` (pending mutations) and `photo_queue`.

**Sync engine** (`lib/data/sync_service.dart`):

1. Register the device once (`device_name` stored locally).
2. **Push** every pending outbox mutation in one batch; on success store the
   returned `server_name` and mark the row clean; failures are kept with their
   error for the Sync screen.
3. **Upload** queued photos for documents that now exist on the server
   (`/api/method/upload_file`, private, attached to the doc).
4. **Pull** the delta since `last_pull` and upsert by `server_name` (child
   `items` replaced for pawn loans).

Repeated offline edits collapse to one pending mutation per record
(last-write-wins). Transactions are pushed with `submit: true` where the server
DocType is submittable.

**Loan ownership rule.** The server controllers mutate the parent loan on submit,
so the app never pushes a second loan update:

| App action | Client creates | Client does locally |
|---|---|---|
| Pawn release | Pawn Release only | loan → Released, `dirty=0` |
| Khatabook collect | Khatabook Collection only | loan totals bumped, `dirty=0` |
| Khatabook refinance | Khatabook Refinance only | old loan → Closed, `dirty=0` |

The server creates the replacement loan for a refinance, so the client does not
send `new_loan`. Before pushing, `_toMutation` (now async) resolves each
transaction's link field from the linked row's local `server_name`
(`Pawn Release.pawn_loan`, `Khatabook Collection.khatabook_loan`,
`Khatabook Refinance.khatabook_loan`).

**Retry.** Outbox rows that failed (e.g. a link target had not synced yet) are
kept with `status='error'` and shown on the Sync screen; **"Retry failed
changes"** calls `LocalDb.retryFailed()` to reset them to `pending`.

**Screens** (`lib/ui/`): Login, Home dashboard, Customers (+photo), Pawn
(intake with item photos + release), Khatabook (loan + collect + refinance),
Sync.

**Rounding** (`lib/util/format.dart`) mirrors the server exactly: money ceiling
to 2 dp, weights round half-up to 3 dp, interest
`principal × rate%/month × days/30` with money ceiling.

**Not yet built:** jewellery-sales and lending screens, background/periodic
sync, a conflict-resolution UI (not needed while transactions are append-only),
and per-device role restrictions.

## 13. Phase 3 — on-device backup & Excel export (v1.0.1)

The phone also holds business data (SQLite) and must be able to protect it
independently of the laptop. Design locked with the owner:

| Requirement | Design |
|---|---|
| **No duplicate backups** | A change-fingerprint is stored after each backup (SHA-256 over `rowid` count + `MAX(rowid)` per table, plus a sentinel `updated_at` on the loans tables). If the fingerprint is unchanged since the last backup, the auto-backup job is **skipped** — nothing new is written, so Drive never fills with identical copies. |
| **Excel-format backup** | Backup job opens the SQLite DB **read-only** and writes the same four workbooks the desktop uses: `FULL`, `Khatа`, `Pawn`, `Customers` (same sheet names, same column order — files can be merged across devices). |
| **Data protection** | Exports are pure reads — they never alter the DB. Files are written to a temp name then atomically renamed, and old exports are only pruned after the new one succeeds. An app crash mid-export leaves the previous good files untouched. The DB itself is protected with WAL mode + `PRAGMA foreign_keys` and is never deleted by the app. |
| **Google Drive backup** | Auto-backup uploads the four `.xlsx` files (and the SQLite snapshot) to a user-chosen Drive folder through the **owner's own Google account** (OAuth, no shared secrets). Upload uses resumable chunked transfer so a dropped connection resumes rather than duplicating. |
| **Export / share system** | Manual "Export" button on Settings writes fresh Excel files and opens the system **share sheet**, so files can be sent via WhatsApp/email or saved to Files/Drive — a personal copy the owner controls. |
| **Fast data collection format** | Besides Excel, a compressed single-file `.jswallet` (SQLite snapshot + manifest with schema version) is written for fast restore; Excel remains the human-readable share format. |
| **When to run** | Auto-backup runs after a sync settles and on app open (if >24 h since last), with the fingerprint skip rule above. |

Implementation lands with the v1.0.1 port of the Khata + Pawn flows
(`lib/services/backup_service.dart`, `excel` + `share_plus` + `googleapis/drive`).

