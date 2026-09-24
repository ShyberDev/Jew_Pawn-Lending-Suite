# Mobile ↔ Laptop Sync — Design

> **Status: DESIGN (not built yet).** This document analyses the requirement and
> proposes an architecture. It needs the owner's answers to the *Open Questions*
> (§10) before implementation.

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

| Phase | Deliverable | Value |
|-------|-------------|-------|
| **0** | This design + owner answers | Align on scope |
| **1** | Sync API (`pull`/`push`/`register_device`) + `client_uuid` fields + tests | Server ready, testable with curl |
| **2** | Mobile PWA (online first) with the 6 screens | Usable on phone over Wi-Fi |
| **3** | Offline queue + service worker + HTTPS | True offline + auto-sync |
| **4** | Background Sync (Android), conflict UI, photos | Polished |
| **5** (optional) | Native app reusing the same API | iOS background sync, camera |

**Phase 1 can be built and verified now** (no phone or HTTPS needed — it's pure
server code testable with the existing bench).

---

## 9. Why this fits the suite

- Reuses the existing Frappe REST API and permissions — no new backend stack.
- Append-only transactions make sync genuinely safe.
- One sync API serves pawn, khatabook, jewellery and lending.
- Stays inside the one-bundle repo (`apps/pawn_shop/.../api/sync.py` +
  `apps/pawn_shop/.../public/mobile/`), so new users still install one thing.

---

## 10. Open questions (need owner input)

1. **Platform**: Android only, or iPhone too? (Decides PWA vs native.)
2. **Offline depth**: must it work with **no Wi-Fi at all**, or is **same-Wi-Fi**
   access enough? (Decides whether we must set up HTTPS + service workers.)
3. **What is captured on the phone?** (new pawn loans? collections? releases?
   jewellery sales? read-only?) — pick the MVP set.
4. **How many phones?** One, or several staff devices?
5. **Photos?** Do you need to attach item/customer photos from the phone?
6. **Connectivity**: same Wi-Fi only, or also over mobile data / internet?
