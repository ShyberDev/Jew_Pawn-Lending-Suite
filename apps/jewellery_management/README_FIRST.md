# README FIRST — Frappe Jewellery, Pawn & Lending Suite

> **⚠️ Looking to install? Use the one-repo bundle instead.**
> The whole suite (Frappe + ERPNext + jewellery + pawn + lending) now ships as a
> single repository with a one-command installer:
> **https://github.com/ShyberDev/Jew_Pawn-Lending-Suite** (`develop` branch) —
> `git clone … && ./install.sh`.
> The guide below is kept as the detailed reference for the jewellery app and the
> suite's internals; its install section describes the older, separate-app route.

> **Read this file first.** It is the single onboarding document for the
> **Frappe Jewellery, Pawn & Lending Suite** — a complete, open-source business
> suite built on top of the [Frappe Framework](https://frappeframework.com) and
> [ERPNext](https://erpnext.com).
>
> GitHub branch for this suite: **`Frappe Jewellery, Pawn & Lending Suite`**
> (repo: `https://github.com/ShyberDev/jewellery_management`).

---

## 0. TL;DR — the exact steps that are known to work

These are the steps the current owner uses every day on the machine this was
built and tested on (site name `library.local`):

```bash
# 1. Start the database (MariaDB)
sudo systemctl start mariadb

# 2. Go to the bench folder
cd ~/frappe-bench

# 3. Start all Frappe services (web, socketio, redis, workers)
bench start

# 4. Open the desk in any browser
#    http://library.local:8000/desk
```

That is the whole day-to-day workflow. Everything else in this file is about
**how it was installed**, **how to reproduce it on a fresh machine**, **how to
fix the known issues**, and **what the software can do**.

---

## 1. What is in this suite

This is **not one app — it is a suite of three business apps** that run side by
side in the same Frappe desk, sharing one database and one login:

| # | App (technical name) | On the Apps screen | What it does | Route |
|---|----------------------|--------------------|--------------|-------|
| 1 | `jewellery_management` | **Sri Sai Krishna Jewellery** | The original jewellery ERP: orders → workers → settlement, purchases/sales with GST, weight-based stock ledger, old-gold melt, HUID registry, repairs, rates, dashboard, reports. | `/app/jewellery` · `/app/jewellery-dashboard` |
| 2 | `pawn_shop` | **Pawn Shop** | Custom Pawn Shop + Khatabook-style village lending: pledge gold/silver, interest, release/withdrawal, weekly khatabook collections, refinance, combined accounting. | `/app/pawn` |
| 3 | `lending` | **Lending** | The official open-source [frappe/lending](https://github.com/frappe/lending) app: Loan Application → Loan → Disbursement → Repayment, loan products, security types, reports. | `/app/lending` |

All three appear on the Apps screen and as workspaces in the left workspace
rail (dock) of the desk.

### 1.1 Modules inside the apps

- **Jewellery Management** app ships module `Jewellery Management` (workspace
  `Jewellery`) and 24 custom DocTypes under the `Jewellery` module, plus a
  `Jewellery Dashboard` page.
- **Pawn Shop** app ships module `Pawn Shop` with 11 DocTypes and 6 reports.
- **Lending** ships modules `Loan Origination` and `Loan Management`.

---

## 2. Tested & working system configuration

This suite was **built, installed and end-to-end tested** on the following
configuration. Treat this as the reference "known-good" stack.

| Component | Tested version |
|-----------|----------------|
| Operating system | **Kali GNU/Linux Rolling** (Debian-based; Ubuntu/Debian work the same) |
| Kernel | 7.1.5+kali-amd64 (x86_64) |
| Python | **3.14.6** |
| Node.js | **v24.18.0** |
| npm | 11.16.0 |
| Yarn | 1.22.22 |
| Bench CLI | **5.31.0** |
| Frappe Framework | **17.0.0-dev** |
| ERPNext | **17.0.0-dev** |
| MariaDB | **11.8.8** |
| Redis | **8.0.6** |
| Site name | `library.local` |
| Web port | `8000` |
| Socket.IO port | `9000` |
| Redis cache / queue | `13000` / `11000` |
| Mode | `developer_mode = 1`, `bench start` (development server) |

> ⚠️ **Version pinning matters.** Frappe/ERPNext `develop` (17.x) is a moving
> target. Before a production go-live, pin exact commits/tags of `frappe`,
> `erpnext`, `lending` and record them here.

### 2.1 Where it works

- ✅ Linux (Debian/Ubuntu/Kali) with a standard Frappe bench — **verified**.
- ✅ Any modern browser (Chrome/Chromium/Firefox/Edge) at `http://<site>:8000/desk`.
- ✅ Single machine (web + DB + redis on the same host) — **verified**.
- ⚠️ Production (nginx + supervisor, HTTPS, multiple workers) — supported by
  Frappe but **not yet exercised** in this build.
- ❌ Windows/macOS are not the tested path (Frappe supports Linux primarily).

---

## 3. Two ways to install — and why "just install the file" is not possible

A very important expectation to set for new users:

> **These are Frappe *apps*, not standalone software.** They cannot run by
> themselves. They need the **Frappe Framework** (and, for the jewellery side,
> **ERPNext**) already installed in a **bench**. There is no `.exe`, no `.deb`,
> and no single installer file that magically creates the whole system.

So there are three practical options:

### Option A — You already have a working Frappe/ERPNext bench *(recommended)*
Add the apps to your existing bench. This is the fastest and the least
error-prone. Jump to **§5**.

### Option B — Start from scratch *(Frappe framework first)*
You install Linux dependencies, MariaDB, Node, Redis, the `bench` CLI, then
create a bench, then add ERPNext and these apps. This is more work and is where
new users usually get stuck. Full recipe in **§5.0**.

### Option C — Ship/restore a complete image *(best for non-technical users)*
Because a from-scratch install is a real hassle for beginners, the best way to
hand this to a non-technical user is **not** to send them the source and hope
they can install Frappe. Instead, ship a **complete ready-to-run environment**:

- a **VM image / disk snapshot** of this exact working machine, or
- a **Docker image / `docker-compose`** bundling MariaDB + Redis + the bench + a
  pre-created site, or
- a **restore bundle** (`bench backup` of `library.local` + the three app repos)
  that a technician restores in minutes.

This removes the framework-install burden entirely. See **§12** for the
backup/restore bundle. (A prebuilt Docker/VM image is *recommended future work*;
see §10.)

---

## 4. What "integration into your system" means

You do **not** merge this into some other software. "Integration" here means:

1. The three apps live inside one **bench** (`~/frappe-bench`).
2. They are installed into one **site** (`library.local`).
3. They share the **same database, same users, same desk**.
4. They appear on the **Apps screen** and in the **workspace rail**.
5. The jewellery and pawn apps **read each other's data** for the combined
   accounting report (see §8.4) — no external integration needed.

If you already run ERPNext for other business, you can add these apps to the
**same bench/site** and they coexist. To keep them isolated, use a **separate
site** on the same bench (Frappe supports many sites per bench).

---

## 5. Installation — step by step

### 5.0 Option B: install the Frappe framework from scratch (Linux)

```bash
# --- System packages (Debian/Ubuntu/Kali) ---
sudo apt update
sudo apt install -y git python3-dev python3-venv python3-pip \
  mariadb-server mariadb-client redis-server \
  nodejs npm yarnpkg wkhtmltopdf \
  libmysqlclient-dev pkg-config cron
# (Node 18+ is required by modern Frappe; install via nvm/nodesource if apt is old)

# --- Enable services ---
sudo systemctl enable --now mariadb
sudo systemctl enable --now redis-server

# --- Secure MariaDB (set a root password) ---
sudo mysql_secure_installation

# --- Configure MariaDB for Frappe (utf8mb4 + no strict ONLY_FULL_GROUP_BY issues) ---
# Edit /etc/mysql/mariadb.conf.d/50-server.cnf and add under [mysqld]:
#   character-set-client-handshake = FALSE
#   character-set-server = utf8mb4
#   collation-server = utf8mb4_unicode_ci
#   [mysql]
#   default-character-set = utf8mb4
sudo systemctl restart mariadb

# --- Install the bench CLI (as your normal user, NOT root) ---
pip install --user frappe-bench      # or: npm install -g frappe-bench
export PATH="$HOME/.local/bin:$PATH"

# --- Create the bench ---
cd ~
bench init frappe-bench --frappe-branch version-15   # use the branch you intend
cd frappe-bench
```

> Pick the Frappe/ERPNext branch deliberately. This build used the `develop`
> (17.x) branches. Use matching branches for `frappe`, `erpnext` and `lending`.

### 5.1 Get ERPNext (needed by the jewellery app)

```bash
cd ~/frappe-bench
bench get-app erpnext            # or: bench get-app --branch version-15 erpnext
```

### 5.2 Get the three suite apps

```bash
cd ~/frappe-bench

# 1) Jewellery ERP (this repository)
bench get-app https://github.com/ShyberDev/jewellery_management --branch "Frappe Jewellery, Pawn & Lending Suite"

# 2) Money Lending (official Frappe app)
bench get-app https://github.com/frappe/lending

# 3) Pawn Shop  (custom app — hosted in the Jew_Pawn-Lending-Suite repo)
bench get-app https://github.com/ShyberDev/Jew_Pawn-Lending-Suite --branch develop
```

> **Note:** the whole suite (Frappe + ERPNext + jewellery + pawn + lending) ships
> as the **one-repo bundle**
> `https://github.com/ShyberDev/Jew_Pawn-Lending-Suite` (branch `develop`) — use
> its `install.sh` rather than getting the apps separately. The repo is **public**.

### 5.3 Create a site and install the apps

```bash
cd ~/frappe-bench

# Create the site (this prompts for the MariaDB root password)
bench new-site library.local \
  --admin-password '<a-strong-admin-password>' \
  --mariadb-root-password '<your-mariadb-root-password>'

# Install ERPNext first, then the suite apps
bench --site library.local install-app erpnext
bench --site library.local install-app jewellery_management
bench --site library.local install-app lending
bench --site library.local install-app pawn_shop

# Enable developer mode (needed to export fixtures / edit DocTypes in UI)
bench --site library.local set-config developer_mode 1

# Build front-end assets (workspace icons, logos, bundles)
bench build --app jewellery_management
bench build --app pawn_shop
bench build --app lending

# Make the site reachable on the LAN / by name (optional)
bench --site library.local set-config host_name "http://library.local:8000"
```

If `library.local` is not in DNS, add it to `/etc/hosts`:

```bash
echo "127.0.0.1 library.local" | sudo tee -a /etc/hosts
```

### 5.4 Run it

```bash
sudo systemctl start mariadb
cd ~/frappe-bench
bench start
# browse to http://library.local:8000/desk
```

Log in with the `Administrator` account you created, or create a user and assign
the **System Manager** role (needed to see all three apps).

### 5.5 Production mode (optional, later)

```bash
cd ~/frappe-bench
sudo bench setup production <your-linux-user>
bench restart
```

This installs nginx + supervisor and runs Frappe as a service instead of
`bench start`.

---

## 6. The Apps screen and the desk workspace rail

After installation, open `http://library.local:8000/desk`:

- The **Apps screen** (click the grid/apps icon) shows:
  **ERPNext**, **Sri Sai Krishna Jewellery**, **Lending**, **Pawn Shop**.
- The **left workspace rail (dock)** shows the pinned workspaces:
  **Jewellery**, **Lending**, **Pawn** (plus ERPNext's).
- Each workspace has its own **left sidebar** with shortcuts, sections and
  reports.

Routes:

| Workspace | URL |
|-----------|-----|
| Jewellery | `http://library.local:8000/app/jewellery` |
| Jewellery dashboard (app landing) | `http://library.local:8000/app/jewellery-dashboard` |
| Pawn | `http://library.local:8000/app/pawn` |
| Lending | `http://library.local:8000/app/lending` |

---

## 7. THE SIDEBAR / APP-CONTEXT FIX (if you ever see a gray page or a missing sidebar)

This is the fix the owner hit and asked to be documented. **If a new install
shows a gray screen, a missing sidebar, or a sidebar header that shows the user's
name instead of the app name**, it is almost always one of these three things.

### 7.1 Symptom → cause

| Symptom | Cause |
|---------|-------|
| Left rail icons are plain gray letters, header shows the username | The workspace is **not `standard`** (`standard = 0`). The desk treats non-standard workspaces as "app-less". |
| Gray/blank icon in the rail or header | The workspace `icon` is **not a real lucide icon name** (e.g. `assets`, `loan`). |
| Clicking an app shows a blank page with **"No Sidebar Items"** | The app's workspace has **no authored `sidebar_items`**, so `bootinfo.workspace_sidebar_item` has no entry for it. |

### 7.2 The rules (Frappe v15/16/17 desk)

1. **App-shipped workspaces must be `standard = 1`.** In `Sidebar.get_sidebar_app()`
   and `set_current_app()` the code is:
   ```js
   workspace && !workspace.standard ? null : (workspace.app || sidebar.app)
   ```
   A non-standard workspace resolves to **no app**, so the header loses its
   app/module name and the dock loses its app logo.

2. **Workspace `icon` must be a bare lucide symbol name** that exists in
   `apps/frappe/frappe/public/icons/lucide/icons.svg`, **without** the `icon-`
   prefix. Valid examples: `gem`, `hand-coins`, `banknote`, `package`, `wallet`.
   Invalid examples: `assets`, `loan` (these render a blank gray `<use>`).

3. **`bootinfo.workspace_sidebar_item` is keyed by the workspace title
   lowercased** (`"Pawn"` → `"pawn"`, `"Lending"` → `"lending"`). If a workspace
   has no `sidebar_items`, there is no key for it, `Sidebar.prepare()` throws
   internally and the page renders **"No Sidebar Items"**. The auto-generated
   fallback only creates **module-name** keys (e.g. `"loan management"`), never
   the workspace key.

### 7.3 The fix (already applied in this repo)

- **Jewellery** workspace: `standard = 1`, `app = jewellery_management`,
  `icon = gem` → `apps/jewellery_management/jewellery_management/fixtures/workspace.json`
- **Pawn** workspace: `standard = 1`, `icon = hand-coins` →
  `apps/pawn_shop/pawn_shop/pawn_shop/workspace/pawn/pawn.json`
- **Lending** workspace: `standard = 1`, `icon = banknote`, plus an authored
  20-item `sidebar_items` table →
  `apps/lending/lending/loan_management/workspace/lending/lending.json`

To re-apply on a fresh DB, either run `bench migrate` (imports the workspace
files/fixtures), or set the values directly:

```bash
bench --site library.local execute \
  "frappe.db.set_value('Workspace','Pawn',{'standard':1,'icon':'hand-coins'}); \
   frappe.db.set_value('Workspace','Lending',{'standard':1,'icon':'banknote'}); \
   frappe.db.set_value('Workspace','Jewellery',{'standard':1,'app':'jewellery_management','icon':'gem'}); \
   frappe.db.commit()"
```

Then **hard-refresh the browser** (`Ctrl+Shift+R`): the boot payload is cached
per page load.

### 7.4 ⚠️ A Frappe trap to avoid

A **forced** re-import of an existing Workspace
(`frappe.model.sync.sync_for(app, force=True)`) **deletes the workspace's own
source file** (`import_doc` → `delete_old_doc` → `Workspace.after_delete` →
`delete_folder`), and the re-insert skips export because
`frappe.flags.in_import` is set. This is a Frappe behaviour, not an app bug.

- `bench migrate` calls `sync_all(force=0)` → **safe** (skips by timestamp).
- If you ever run a forced sync, **regenerate the workspace JSON** from source
  before committing. For Pawn, use the generator script referenced in
  `docs/AI_HANDOFF.md` §18.5.

---

## 8. Features & options

### 8.1 Jewellery ERP (`jewellery_management`)

**Counter / billing**
- Jewellery **Sales Invoice** and **Purchase Invoice** with line items,
  multiple payments (cash / UPI / etc.), GST per invoice (including 0%),
  server-side totals mirror.
- **Sales & Purchase Returns** with automatic stock reversal.
- **TCS** on sales above a threshold (kept as a separate `tcs_amount` field, not
  folded into `grand_total`), **GSTR-1** export and **e-invoice** payload.

**Orders & workshop**
- **Jewellery Order** lifecycle with **5 frozen statuses** and an **Order
  Kanban** board.
- **Workers** use their own resources (the shop never issues stock to a worker);
  **Worker Settlement** computes worker payable from delivered net weight ×
  (purity% + wastage%) × fine rate; worker running balance in **grams and cash,
  kept separate**.
- **Old Gold**: intake estimate vs assay, melt expected-vs-actual variance,
  exchange-credit or sale-to-worker.
- **HUID registry**: per-piece hallmarking lifecycle (Not → Sent → Hallmarked +
  HUID + date).

**Stock**
- Custom **weight-based stock ledger** (`Jewellery Stock Transaction`) grouped
  by retail stock item + purity; FIFO metal ledger.
- **Opening Stock**, **Retail Stock Item**, **Transfer to Stock** for unclaimed
  order items.
- **Repairs** (token + balance).

**Masters & reports**
- Jewellery Item Type, Metal Purity, **Metal Rate** (daily default + intraday
  `rate_time`), Jewellery Settings.
- Reports: Retail Stock Balance, GST Summary, HUID Register, Worker Balances,
  Customer Outstanding (query reports) + **Daily Sales Summary, FIFO Metal
  Ledger, Item Rate Card, Jewellery Stock Ageing, Supplier Payable** (script
  reports).
- **Jewellery Dashboard** page with live tiles.

### 8.2 Pawn Shop + Khatabook (`pawn_shop`)

**Pawn**
- **Pawn Customer** (name, address, phone; shared by pawn + khatabook).
- **Pawn Loan** with multiple **Pawn Items** (metal, hallmarked yes/no, gross/net
  weight, valuation); market valuation from the **Metal Rate** master (with a
  Settings fallback); **LTV**; balance = principal + accrued interest − payments.
- **Interest:** simple `loan_amount × rate%/month × (days/30)`, rounded up
  (ceil). Default rate from the customer override, else **Pawn Settings**
  (default **gold 3%/month, silver 4%/month**).
- **Pawn Release** (submittable): pays principal + interest → loan becomes
  `Released`, balance 0 (withdrawal / release of the pledged item).
- Gold/silver/weight **valuations**, hallmarked vs non-hallmarked split.

**Khatabook (village lending)**
- **Village** master; 12-weekly collection schedules
  (e.g. ₹5000 principal + ₹1000 interest = **12 × ₹500**), with
  `installment_amount = ceil(total_payable / count)`.
- **Khatabook Collection** (submittable): allocates oldest-first, flags
  `is_irregular` (late or partial) — irregular-payment tracking.
- **Khatabook Refinance** (submittable): closes the old loan and creates a new
  one with principal = old outstanding and flexible interest.
- **Good/bad customer rating** via the customer record.

**Reports & accounting**
- **Pawn Monthly Profit and Loss** (chart), **Pawn Valuation**, **Pawn
  Outstanding**, **Khatabook Collection Sheet**, **Khatabook Outstanding**,
  **Combined Business Profit and Loss** (chart).

### 8.3 Money Lending (`lending` — official Frappe app)

- Full **Loan Origination** and **Loan Management**: Loan Application → Loan →
  Loan Disbursement → Loan Repayment / Closure.
- Loan Products, Loan Security Types, Loan Security Assignment, dashboards,
  number cards, charts and reports (Loan Repayment and Closure, Loan Security
  Status, Loan Outstanding, Statement of Account, cashflow reports, etc.).
- Standard Frappe roles: **Loan Manager**, plus System Manager.

### 8.4 Combined 3-business accounting

The **`Business`** master types the businesses as **Shop / Money Lending / Pawn
/ Khatabook**. The **Combined Business Profit and Loss** report aggregates:

- **Shop** — from `Jewellery Sales Invoice` / `Jewellery Purchase Invoice`
- **Money Lending** — from `Loan` / `Loan Repayment` (defensive import)
- **Pawn** — pawn loans and releases
- **Khatabook** — khatabook loans and collections

…into one report with a **TOTAL** row, while each business stays isolated in its
own workspace. Verified sample totals: shop income ₹22,13,087 / purchases
₹33,66,397; pawn principal ₹1,50,000; khatabook ₹9,700.

---

## 9. Why this open-source stack (advantages)

- **Zero licence cost.** Frappe Framework, ERPNext, frappe/lending and this
  suite are all open source (MIT / GPL-compatible). No per-user fees.
- **One platform, many businesses.** Accounting, HR, CRM, buying/selling,
  manufacturing, stock, projects and website come free with ERPNext. This suite
  *adds* jewellery, pawn and lending on top.
- **Real database, not a spreadsheet.** MariaDB + audit trail; every document is
  versioned, submittable and reportable.
- **Customisable without forking.** DocTypes, custom fields, print formats,
  workflows, roles and reports can be changed from the UI.
- **API-first.** Every DocType is automatically a REST API, so you can integrate
  with POS hardware, payment gateways, WhatsApp, Tally, etc.
- **Portable.** Runs on any Linux server or laptop; your data is a SQL dump you
  own.
- **Proven framework.** Same engine used by thousands of ERPNext deployments
  worldwide.

---

## 10. Known issues / future problems to fix

These are honest, known limitations. None block daily use; they are the roadmap.

**Jewellery app**
1. Stock transactions post as **draft** (`docstatus=0`); dashboard/validators
   count non-cancelled rows to compensate. Fix = submit-on-source-submit +
   backfill.
2. **No cancel/amend reversal** for stock/invoice flows — cancelling orphans
   ledger rows.
3. Idempotency is **check-then-insert** (race-prone); no DB unique index/locks.
4. **`bench migrate` reimports fixtures** and can silently revert unexported DB
   changes. Standing rule: **DB change → verify → `export-fixtures` → commit;
   never migrate mid-flow.**
5. Kanban JS (~1300 lines, global) works but is heavy/fragile; scoped rewrite
   deferred.
6. Totals math is **client-side only** for orders/invoices; API/import bypasses
   it (server mirror done for invoices via Brick A).
7. Permissions added but **login-as-role not fully tested**.
8. 6 early draft sample bills lack `_sample_data` markers (identifiable by
   names/dates).
9. Settings singles row empty until first UI save.
10. Workflow `Jewellery Order Workflow` is inactive; orphan `workflow_state`
    field.
11. Silver Metal Rate entered; **18K rate missing** (owner to provide).
12. Sample Bank reads −₹20,000 (samples overpaid — data artifact, math correct).
13. **No FIFO auto-allocation** yet (planned).
14. Frappe/ERPNext on `develop` (17.x) — **upstream churn risk; pin before
    go-live.**

**Suite / ops**
15. **No prebuilt Docker/VM image yet** — new users must install Frappe
    themselves (see §3 Option C, §12).
16. The repos (`ShyberDev/jewellery_management` and
    `ShyberDev/Jew_Pawn-Lending-Suite`) are **public** now.
17. The Lending workspace patch lives in the third-party `apps/lending` checkout;
    a future `bench get-app`/update of lending would drop it. A normal
    `bench migrate` keeps it (sync skips by timestamp).
18. Production mode (nginx/supervisor/HTTPS) not yet exercised.
19. No automated test suite in CI; verification so far is scripted and manual.
20. **Mobile sync — Phase 1 (server API) is DONE.** `pawn_shop.api.sync`
    (`register_device` / `pull` / `push`, idempotent by `client_uuid`; DocTypes
    `Sync Device`, `Sync ID Map`, `Sync Log`). The native Android (Flutter) app is
    next. Design: `docs/MOBILE_SYNC_DESIGN.md`.
21. **Off-site backup is documented, not yet scheduled.** `backup-to-gdrive.sh` +
    `docs/BACKUP_AND_RECOVERY.md` push nightly snapshots to Google Drive (rclone).
22. **Workspace orphan-cleanup trap (fixed):** `bench migrate` deletes any public
    Workspace that has an `app` set but no file under the app's `workspace/`
    folder. The Jewellery workspace now ships as an app file
    (`jewellery_management/.../workspace/jewellery/jewellery.json`). **Never ship
    a workspace only as a fixture.**

---

## 11. Daily operations, backup & restore

### Start / stop
```bash
sudo systemctl start mariadb          # database
cd ~/frappe-bench && bench start      # dev server (Ctrl+C to stop)
# production:
sudo supervisorctl status             # check services
bench restart
```

### Backup (do this before any upgrade)
```bash
cd ~/frappe-bench
bench --site library.local backup --with-files
# files land in sites/library.local/private/backups/
```

### Off-site backup → Google Drive (recommended)
Disaster recovery (laptop lost → restore everything), separate from mobile sync:
```bash
cd ~/Jew_Pawn-Lending-Suite && ./backup-to-gdrive.sh   # backup + upload + prune
# nightly — add to `crontab -e`:
#   15 2 * * *  /home/shyam/Jew_Pawn-Lending-Suite/backup-to-gdrive.sh >> ~/backup.log 2>&1
```
Full walkthrough (rclone setup, encryption, restore): `docs/BACKUP_AND_RECOVERY.md`.

### Restore onto a fresh bench
```bash
bench new-site library.local --admin-password '<pw>'
bench --site library.local restore /path/to/<db>-database.sql.gz \
  --mariadb-root-password '<root-pw>'
bench --site library.local restore /path/to/<files>.tar  # if --with-files
bench --site library.local migrate
bench --site library.local install-app jewellery_management
bench --site library.local install-app lending
bench --site library.local install-app pawn_shop
bench build && bench restart
```

### Export code changes (fixtures) — the golden rule
```bash
# after ANY change made in the UI/DocType manager:
bench --site library.local export-fixtures --app jewellery_management
cd apps/jewellery_management && git add -A && git commit -m "..."
# never push unless the owner asks
```

---

## 12. Shipping a complete environment (recommended for beginners)

To save new users from the framework-install pain, package the whole thing:

1. **VM snapshot / image** of this machine (simplest; includes OS + MariaDB +
   bench + site + data). Hand over the image; they boot it and run
   `sudo systemctl start mariadb && cd ~/frappe-bench && bench start`.
2. **Docker image** — write a `Dockerfile`/`docker-compose.yml` that installs
   MariaDB + Redis + bench, creates the site, installs the apps, and builds
   assets. This is the cleanest portable option and is **recommended next work**.
3. **Restore bundle** — a `bench backup --with-files` tarball + the three app
   repos. A technician restores it in minutes (§11).

Until one of these ships, the honest answer to "can I just install one file?" is:
**no — install the Frappe framework first, then the apps.**

---

## 13. Repository & branch layout

| Repo | Branch | Contents |
|------|--------|----------|
| `ShyberDev/jewellery_management` | **`Frappe-Jewellery-Pawn-Lending-Suite`** | Jewellery ERP app + this README + `docs/AI_HANDOFF.md` |
| `ShyberDev/Jew_Pawn-Lending-Suite` | `develop` | Pawn Shop + Khatabook app |
| `frappe/lending` *(upstream)* | `develop` | Money Lending app (install from upstream) |

The ShyberDev repos are **public**; `frappe/lending` is the upstream project.

> Branch names with spaces/commas are allowed by git but awkward in URLs. The
> machine-friendly slug is `Frappe-Jewellery-Pawn-Lending-Suite`; use whichever
> your tooling prefers.

The detailed engineering log (every change, decision, verification and warning)
is in **`docs/AI_HANDOFF.md`**. Read §16–§18 for the current state, the Brick
Tracker, and the two new apps.

---

## 14. Support & handoff

- **First read:** this file.
- **Deep detail:** `docs/AI_HANDOFF.md` (sections 1–18).
- **Owner constraints (must not change):** never modify `apps/frappe`,
  `apps/erpnext`, `apps/library_management`; never push without explicit
  instruction; delivered **net** weight is the only stock/settlement weight;
  customer and worker books stay separate; history rows are append-only.
- **Before asking for help, collect:** `bench version`, `bench --site
  library.local list-apps`, the browser console errors, and the output of
  `bench --site library.local doctor`.

---

*Built with the Frappe Framework + ERPNext. Licensed MIT. Tested on Kali
GNU/Linux Rolling / Python 3.14.6 / MariaDB 11.8.8 / Node 24 / Bench 5.31.0.*
