# README FIRST — Jew_Pawn-Lending-Suite (one bundle)

> **Read this file first.** This is the single onboarding document for the
> **Jew_Pawn-Lending-Suite** — a complete, open-source business suite that
> bundles **Frappe + ERPNext + Jewellery ERP + Pawn Shop/Khatabook + Money
> Lending** in **one repository**.
>
> Repo: `https://github.com/ShyberDev/Jew_Pawn-Lending-Suite` (branch `develop`).

---

## 0. TL;DR — what this is and how you install it

**You do not install Frappe first and then the apps.** This repo is a *bundle*:
one download, one command, and the installer takes care of Frappe, ERPNext, the
database, the site and all three apps.

```bash
# 1. Get the bundle (one repo — everything is inside)
git clone https://github.com/ShyberDev/Jew_Pawn-Lending-Suite.git
cd Jew_Pawn-Lending-Suite

# 2. Install everything (asks for your MariaDB root password)
chmod +x install.sh
./install.sh

# 3. Run it
sudo systemctl start mariadb
cd ~/frappe-bench
bench start
# open http://library.local:8000/desk
```

That's it. `install.sh` will:

1. install the system packages (git, python, node, yarn, MariaDB, Redis, …),
2. install the `bench` CLI,
3. clone **Frappe** and **ERPNext** at the pinned commits in `versions.env`,
4. copy the **vendored apps** (`jewellery_management`, `lending`, `pawn_shop`)
   straight from this repo,
5. create the site `library.local`,
6. install ERPNext + the three suite apps in the right order,
7. build the front-end assets.

> **Why is Frappe downloaded instead of sitting in the repo?** Frappe and ERPNext
> are each ~500 MB of upstream code that changes daily. Copying them into this
> repo would make it enormous and impossible to update. Instead the installer
> pins the **exact tested commits** (see `versions.env`) and fetches them for you
> — you still never install them separately. The three *custom/patched* apps are
> fully vendored, so the bundle is self-contained for everything that is ours.

---

## 1. What is in this bundle

| # | App (technical name) | On the Apps screen | What it does | Route |
|---|----------------------|--------------------|--------------|-------|
| 1 | `jewellery_management` | **Sri Sai Krishna Jewellery** | Jewellery ERP: orders → workers → settlement, purchases/sales with GST, weight-based stock ledger, old-gold melt, HUID registry, repairs, rates, dashboard, reports. | `/app/jewellery` · `/app/jewellery-dashboard` |
| 2 | `pawn_shop` | **Pawn Shop** | Pawn Shop + Khatabook village lending: pledge gold/silver, interest, release/withdrawal, weekly khatabook collections, refinance, combined accounting. | `/app/pawn` |
| 3 | `lending` | **Lending** | Official open-source [frappe/lending](https://github.com/frappe/lending): Loan Application → Loan → Disbursement → Repayment, loan products, security types, reports. | `/app/lending` |

All three appear on the Apps screen and in the left workspace rail (dock).

### 1.1 Bundle layout

```
Jew_Pawn-Lending-Suite/
├── install.sh                 # the one command
├── versions.env               # pinned frappe/erpnext commits + defaults
├── README_FIRST.md            # this file
├── README.md                  # short landing page
├── apps/
│   ├── jewellery_management/  # vendored (full source, ready to install)
│   ├── lending/               # vendored (includes the desk sidebar fix)
│   └── pawn_shop/             # vendored
└── docs/
    └── AI_HANDOFF.md          # full engineering log
```

---

## 2. Tested & working system configuration

Built, installed and end-to-end tested on:

| Component | Tested version |
|-----------|----------------|
| Operating system | **Kali GNU/Linux Rolling** (Debian-based; Ubuntu/Debian work the same) |
| Python | **3.14.6** |
| Node.js | **v24.18.0** |
| Yarn | 1.22.22 |
| Bench CLI | **5.31.0** |
| Frappe Framework | **17.0.0-dev** (`8a43de0`) |
| ERPNext | **17.0.0-dev** (`8c24c5b`) |
| MariaDB | **11.8.8** |
| Redis | **8.0.6** |
| Site name | `library.local` |
| Web port | `8000` · Socket.IO `9000` · Redis cache/queue `13000`/`11000` |
| Mode | `developer_mode = 1`, `bench start` (development server) |

> ⚠️ Frappe/ERPNext `develop` (17.x) is a moving target. The exact commits this
> bundle was tested against are recorded in `versions.env`. Pin them before a
> production go-live.

### 2.1 Where it works

- ✅ Linux (Debian/Ubuntu/Kali) with a standard Frappe bench — **verified**.
- ✅ Any modern browser at `http://<site>:8000/desk`.
- ✅ Single machine (web + DB + redis on one host) — **verified**.
- ⚠️ Production (nginx + supervisor, HTTPS, workers) — supported by Frappe, not
  yet exercised here (§5.5).
- ✅ **Windows** — via **WSL2 + Ubuntu** (one script:
  `windows/install-windows.ps1`) or **Docker Desktop**; see §5.6.
- ✅ **macOS / any OS** — via **Docker**; see `docker/README.md`.
- ❌ Native Windows Python is not supported (Frappe targets Linux).

---

## 3. Why one bundle (and why not "install the apps separately")

The three apps **interact** — the jewellery and pawn apps share the `Business`
master and the **Combined Business Profit and Loss** report reads both shops'
data. Installing them piecemeal (Frappe, then ERPNext, then app A, then app B,
in the wrong order or on mismatched versions) is exactly how new users get
"it breaks / it errors". The bundle:

- installs everything in the **correct order**,
- pins **matching versions**,
- applies the **desk sidebar fix** automatically (the patched `lending` app is
  vendored with the fix already in it),
- means the new user runs **one command**, not seven.

> **Important for new users:** these are Frappe *apps*, not standalone `.exe`
> software. They cannot run without the Frappe framework. The bundle exists to
> hide that complexity — but under the hood a Frappe **bench** and a **site** are
> still created, and the bundle's installer does it for you.

### 3.1 If you already have a working Frappe/ERPNext bench

You can skip the bundle installer and add just the apps. Copy the three folders
from `apps/` into your bench's `apps/` directory, register them and install:

```bash
cd ~/frappe-bench
for a in jewellery_management lending pawn_shop; do
  cp -a /path/to/Jew_Pawn-Lending-Suite/apps/$a apps/$a
  grep -qxF "$a" sites/apps.txt || echo "$a" >> sites/apps.txt
done
bench setup requirements
bench --site <your-site> install-app jewellery_management
bench --site <your-site> install-app lending
bench --site <your-site> install-app pawn_shop
bench build
```

Use the **same Frappe/ERPNext branch** as the apps expect (`develop` / 17.x).

---

## 4. What "integration into your system" means

You do **not** merge this into other software. "Integration" here means:

1. The three apps live inside one **bench** (`~/frappe-bench`).
2. They are installed into one **site** (`library.local`).
3. They share the **same database, users and desk**.
4. They appear on the **Apps screen** and in the **workspace rail**.
5. The jewellery and pawn apps **read each other's data** for the combined
   accounting report (§8.4) — no external integration needed.

To keep this suite isolated from an existing ERPNext, use a **separate site** on
the same bench (Frappe supports many sites per bench).

---

## 5. Installation — step by step

### 5.0 The one-command install (recommended)

```bash
git clone https://github.com/ShyberDev/Jew_Pawn-Lending-Suite.git
cd Jew_Pawn-Lending-Suite
./install.sh
```

Useful flags:

```bash
./install.sh --site myshop.local --admin-password 'Secret123'
./install.sh --db-root-password 'rootpw' --non-interactive
./install.sh --skip-system-deps      # if your OS packages are already installed
```

Environment overrides: `SITE_NAME`, `BENCH_DIR`, `ADMIN_PASSWORD`,
`DB_ROOT_PASSWORD`.

### 5.1 What the installer does (so you can trust it)

1. Checks you are **not root** and that you are inside the bundle.
2. `apt-get install` of: git, python3-dev/venv/pip, MariaDB server+client,
   Redis, Node, npm, yarn, wkhtmltopdf, cron, xvfb and font libs.
3. Installs the `bench` CLI (`pipx` if available, else `pip --user`).
4. Starts and enables **MariaDB** and **Redis**.
5. `bench init` → clones **Frappe** at `FRAPPE_BRANCH`, then checks out the
   pinned `FRAPPE_COMMIT`.
6. `bench get-app erpnext` → checks out the pinned `ERPNEXT_COMMIT`.
7. Copies the vendored apps into the bench and registers them in `sites/apps.txt`.
8. `bench setup requirements`.
9. `bench new-site` (unless the site already exists).
10. Installs apps in order: **erpnext → jewellery_management → lending → pawn_shop**.
11. `bench build` (assets/icons/logos).
12. Prints the exact start commands.

The script is **idempotent**: re-running it reuses an existing bench/site and
only installs what is missing.

### 5.2 If `library.local` is not in DNS

```bash
echo "127.0.0.1 library.local" | sudo tee -a /etc/hosts
```

### 5.3 Manual install (if you prefer to see every step)

```bash
# --- system packages (Debian/Ubuntu/Kali) ---
sudo apt update
sudo apt install -y git python3-dev python3-venv python3-pip \
  mariadb-server mariadb-client redis-server nodejs npm yarnpkg \
  wkhtmltopdf libmariadb-dev pkg-config cron
sudo systemctl enable --now mariadb redis-server

# --- bench CLI ---
python3 -m pip install --user frappe-bench
export PATH="$HOME/.local/bin:$PATH"

# --- bench + Frappe (pinned) ---
cd ~
bench init frappe-bench --frappe-branch develop
cd frappe-bench
git -C apps/frappe checkout 8a43de00d7f1e304598c910f0aa35aa384d474d7

# --- ERPNext (pinned) ---
bench get-app erpnext --branch develop
git -C apps/erpnext checkout 8c24c5bd68aa6fd6db155c46fb6f05e201cc6d69

# --- vendored suite apps ---
for a in jewellery_management lending pawn_shop; do
  cp -a /path/to/Jew_Pawn-Lending-Suite/apps/$a apps/$a
  grep -qxF "$a" sites/apps.txt || echo "$a" >> sites/apps.txt
done
bench setup requirements

# --- site + apps ---
bench new-site library.local --admin-password '<admin-pw>' --mariadb-root-password '<root-pw>'
bench --site library.local install-app erpnext
bench --site library.local install-app jewellery_management
bench --site library.local install-app lending
bench --site library.local install-app pawn_shop
bench --site library.local set-config developer_mode 1
bench build
```

### 5.4 Run it

```bash
sudo systemctl start mariadb
cd ~/frappe-bench
bench start
# browse to http://library.local:8000/desk
```

Log in as `Administrator`, or create a user and give it the **System Manager**
role (needed to see all three apps).

### 5.5 Production mode (optional, later)

```bash
cd ~/frappe-bench
sudo bench setup production <your-linux-user>
bench restart
```

Installs nginx + supervisor and runs Frappe as a service instead of `bench start`.

### 5.6 Windows and Docker

**Windows (WSL2 + Ubuntu) — recommended.** Frappe does not run on native
Windows. Run the helper once in an **Administrator PowerShell**:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\install-windows.ps1
```

It enables WSL2 + VirtualMachinePlatform and installs Ubuntu. After a reboot,
open Ubuntu and run the normal `git clone … && ./install.sh`. You then browse to
**http://localhost:8000/desk** from Windows (WSL2 forwards localhost). Full guide:
`windows/README.md`.

**Docker (Windows / macOS / Linux).** Build the suite image and run it with the
maintained `frappe_docker` stack:

```bash
cd Jew_Pawn-Lending-Suite
./docker/build.sh                 # builds shyberdev/jew-pawn-lending:latest
# then follow docker/README.md (compose up + create site + install-app)
```

The Docker image tracks the upstream `develop` (v17) tag; for byte-exact parity
with the pinned commits use the native `./install.sh`. Docker was **not executed**
in the build environment (Docker unavailable) — see `docker/README.md`.

### 5.7 Keeping the bundle in sync (`update-bundle.sh`)

Your working bench and this bundle are separate copies. After you change the apps
in `~/frappe-bench/apps/*`, refresh the bundle:

```bash
./update-bundle.sh                 # copy bench apps -> bundle, show diff
./update-bundle.sh --commit --push # copy + commit + push
./update-bundle.sh --dry-run       # preview only
```

---

## 6. The Apps screen and the desk workspace rail

After installation, open `http://library.local:8000/desk`:

- **Apps screen** shows: **ERPNext**, **Sri Sai Krishna Jewellery**, **Lending**,
  **Pawn Shop**.
- **Left workspace rail (dock)** shows the pinned workspaces: **Jewellery**,
  **Lending**, **Pawn** (plus ERPNext's).
- Each workspace has its own left sidebar with shortcuts, sections and reports.

| Workspace | URL |
|-----------|-----|
| Jewellery | `http://library.local:8000/app/jewellery` |
| Jewellery dashboard (app landing) | `http://library.local:8000/app/jewellery-dashboard` |
| Pawn | `http://library.local:8000/app/pawn` |
| Lending | `http://library.local:8000/app/lending` |

---

## 7. THE SIDEBAR / APP-CONTEXT FIX (grey page or missing sidebar)

**If a new install shows a grey screen, a missing sidebar, or a sidebar header
that shows the username instead of the app name**, it is almost always one of
these three things.

### 7.1 Symptom → cause

| Symptom | Cause |
|---------|-------|
| Rail icons are plain grey letters; header shows the username | The workspace is **not `standard`** (`standard = 0`). The desk treats non-standard workspaces as "app-less". |
| Grey/blank icon in the rail or header | The workspace `icon` is **not a real lucide icon name** (e.g. `assets`, `loan`). |
| Clicking an app shows a blank page with **"No Sidebar Items"** | The workspace has **no authored `sidebar_items`**, so `bootinfo.workspace_sidebar_item` has no entry for it. |

### 7.2 The rules (Frappe v15/16/17 desk)

1. **App-shipped workspaces must be `standard = 1`.** In `Sidebar.get_sidebar_app()`
   / `set_current_app()` the code is
   `workspace && !workspace.standard ? null : (workspace.app || sidebar.app)` —
   a non-standard workspace resolves to **no app**, so the header loses its app
   name and the dock loses its logo.
2. **Workspace `icon` must be a bare lucide symbol name** that exists in
   `apps/frappe/frappe/public/icons/lucide/icons.svg`, **without** the `icon-`
   prefix. Valid: `gem`, `hand-coins`, `banknote`, `package`, `wallet`.
   Invalid: `assets`, `loan`.
3. **`bootinfo.workspace_sidebar_item` is keyed by the workspace title
   lowercased** (`"Pawn"` → `"pawn"`). No `sidebar_items` → no key → the page
   renders **"No Sidebar Items"**. The auto fallback only creates **module-name**
   keys, never the workspace key.

### 7.3 The fix (already applied in this bundle)

- **Jewellery** workspace: `standard = 1`, `app = jewellery_management`,
  `icon = gem`.
- **Pawn** workspace: `standard = 1`, `icon = hand-coins`.
- **Lending** workspace: `standard = 1`, `icon = banknote`, plus an authored
  20-item `sidebar_items` table — **this patch is already inside the vendored
  `apps/lending`**, which is why the bundle does not fetch lending from upstream.

To re-apply on an existing DB:

```bash
bench --site library.local execute \
  "frappe.db.set_value('Workspace','Pawn',{'standard':1,'icon':'hand-coins'}); \
   frappe.db.set_value('Workspace','Lending',{'standard':1,'icon':'banknote'}); \
   frappe.db.set_value('Workspace','Jewellery',{'standard':1,'app':'jewellery_management','icon':'gem'}); \
   frappe.db.commit()"
```

Then **hard-refresh the browser** (`Ctrl+Shift+R`) — the boot payload is cached
per page load.

### 7.4 ⚠️ A Frappe trap to avoid

A **forced** re-import of an existing Workspace
(`frappe.model.sync.sync_for(app, force=True)`) **deletes the workspace's own
source file**. `bench migrate` calls `sync_all(force=0)` → **safe**. If you ever
run a forced sync, regenerate the workspace JSON from source before committing
(see `docs/AI_HANDOFF.md` §18.5).

**Second trap — `bench migrate` deletes workspaces that are not app files.**
`remove_orphan_entities()` deletes any public Workspace with an `app` set that has
no matching `*.json` under that app's `workspace/` folder. A workspace shipped
**only as a fixture** is therefore deleted on the next migrate (this is exactly
what happened to the Jewellery workspace — fixed in §18.9). **Always ship a
workspace as an app file**, and re-check the desk rail after any migrate.

---

## 8. Features & options

### 8.1 Jewellery ERP (`jewellery_management`)

**Counter / billing** — Jewellery Sales/Purchase Invoices with line items,
multiple payments, GST per invoice (incl. 0%), server-side totals mirror;
Sales/Purchase Returns with stock reversal; **TCS** as a separate `tcs_amount`
field (not folded into `grand_total`), **GSTR-1** export and e-invoice payload.

**Orders & workshop** — Jewellery Order lifecycle with 5 frozen statuses and an
**Order Kanban**; **Workers** use their own resources; **Worker Settlement**
computes payable from delivered net weight × (purity% + wastage%) × fine rate,
with running balance in **grams and cash kept separate**; **Old Gold** intake vs
assay, melt variance; **HUID registry** per-piece hallmarking lifecycle.

**Stock** — custom weight-based stock ledger (`Jewellery Stock Transaction`) by
retail item + purity; FIFO metal ledger; Opening Stock, Retail Stock Item,
Transfer to Stock; **Repairs** (token + balance).

**Masters & reports** — Jewellery Item Type, Metal Purity, **Metal Rate** (daily
default + intraday `rate_time`), Jewellery Settings; reports: Retail Stock
Balance, GST Summary, HUID Register, Worker Balances, Customer Outstanding,
Daily Sales Summary, FIFO Metal Ledger, Item Rate Card, **Jewellery Stock
Ageing**, Supplier Payable; **Jewellery Dashboard** page with live tiles.

### 8.2 Pawn Shop + Khatabook (`pawn_shop`)

**Pawn** — Pawn Customer (name, address, phone); Pawn Loan with multiple Pawn
Items (metal, hallmarked yes/no, gross/net weight, valuation); market valuation
from Metal Rate (Settings fallback); LTV; balance = principal + accrued interest
− payments. **Interest:** simple `loan_amount × rate%/month × (days/30)`, rounded
up (ceil); default from customer override else Pawn Settings (**gold 3%/month,
silver 4%/month**). **Pawn Release** (submittable) pays principal + interest →
loan `Released`, balance 0. Gold/silver/weight valuations; hallmarked vs
non-hallmarked split.

**Khatabook (village lending)** — Village master; 12-weekly schedules
(e.g. ₹5000 principal + ₹1000 interest = 12 × ₹500) with
`installment_amount = ceil(total_payable / count)`; Khatabook Collection
(submittable) allocates oldest-first and flags `is_irregular`; Khatabook
Refinance closes the old loan and creates a new one; good/bad customer rating.

**Reports & accounting** — Pawn Monthly Profit and Loss (chart), Pawn Valuation,
Pawn Outstanding, Khatabook Collection Sheet, Khatabook Outstanding, **Combined
Business Profit and Loss** (chart).

### 8.3 Money Lending (`lending` — official Frappe app, patched)

Loan Origination + Loan Management: Loan Application → Loan → Loan Disbursement
→ Loan Repayment/Closure; Loan Products, Loan Security Types, Loan Security
Assignment, dashboards, number cards, charts, reports. Standard roles: **Loan
Manager**, plus System Manager.

### 8.4 Combined 3-business accounting

The **`Business`** master types businesses as **Shop / Money Lending / Pawn /
Khatabook**. **Combined Business Profit and Loss** aggregates shop (Jewellery
Sales/Purchase Invoice), money lending (Loan/Loan Repayment), pawn (pawn
loans/releases) and khatabook (loans/collections) into one report with a TOTAL
row, while each business stays isolated in its own workspace. Verified sample
totals: shop income ₹22,13,087 / purchases ₹33,66,397; pawn principal
₹1,50,000; khatabook ₹9,700.

---

## 9. Why this open-source stack (advantages)

- **Zero licence cost** — Frappe, ERPNext, frappe/lending and this suite are all
  open source. No per-user fees.
- **One platform, many businesses** — accounting, HR, CRM, buying/selling,
  manufacturing, stock, projects and website come free with ERPNext; this suite
  *adds* jewellery, pawn and lending on top.
- **Real database, not a spreadsheet** — MariaDB + audit trail; every document is
  versioned, submittable and reportable.
- **Customisable without forking** — DocTypes, custom fields, print formats,
  workflows, roles and reports can be changed from the UI.
- **API-first** — every DocType is automatically a REST API (POS hardware,
  payment gateways, WhatsApp, Tally, …).
- **Portable** — runs on any Linux server or laptop; your data is a SQL dump you
  own.
- **Proven framework** — the same engine behind thousands of ERPNext deployments.

---

## 10. Known issues / future problems to fix

**Jewellery app**
1. Stock transactions post as **draft** (`docstatus=0`); dashboard/validators
   count non-cancelled rows. Fix = submit-on-source-submit + backfill.
2. **No cancel/amend reversal** for stock/invoice flows — cancelling orphans
   ledger rows.
3. Idempotency is **check-then-insert** (race-prone); no DB unique index/locks.
4. **`bench migrate` reimports fixtures** and can silently revert unexported DB
   changes. Rule: **DB change → verify → `export-fixtures` → commit; never
   migrate mid-flow.**
5. Kanban JS (~1300 lines, global) works but is heavy; scoped rewrite deferred.
6. Totals math is **client-side** for orders/invoices (server mirror done for
   invoices).
7. Permissions added but **login-as-role not fully tested**.
8. 6 early draft sample bills lack `_sample_data` markers.
9. Settings singles row empty until first UI save.
10. Workflow `Jewellery Order Workflow` is inactive; orphan `workflow_state`.
11. Silver Metal Rate entered; **18K rate missing** (owner to provide).
12. Sample Bank reads −₹20,000 (sample artifact; math correct).
13. **No FIFO auto-allocation** yet (planned).
14. Frappe/ERPNext on `develop` (17.x) — **upstream churn risk; pin before
    go-live** (`versions.env` already pins the tested commits).

**Suite / ops**
15. **Docker files exist** (`docker/`) but were **not executed** in the build
    environment (Docker unavailable) — validate the image build before relying on
    it. No **prebuilt VM image** yet; a VM snapshot is still the simplest handover
    for a fully non-technical user (§12). Windows is supported via WSL2/Docker
    (§5.6).
16. Both repos are **public** now (verified by anonymous clone).
17. The Lending sidebar patch lives in the vendored `apps/lending`; a future
    upstream update of lending would need the patch re-applied (the bundle
    already ships the patched copy).
18. Production mode (nginx/supervisor/HTTPS) not yet exercised.
19. No automated test suite in CI; verification so far is scripted and manual.
20. **Mobile ↔ laptop sync — Phase 1 (the server API) is DONE; the phone app is
    next.** The client will be a **native Android (Flutter)** app (owner's
    choice) that stores data locally in SQLite. The server half already ships:
    `pawn_shop.api.sync` exposes `register_device` / `pull` / `push`, idempotent
    by `client_uuid` (DocTypes `Sync Device`, `Sync ID Map`, `Sync Log`).
    Verified end-to-end on this bench. Full design:
    **[`docs/MOBILE_SYNC_DESIGN.md`](docs/MOBILE_SYNC_DESIGN.md)**.
21. **Off-site backup is documented, not yet scheduled.** `backup-to-gdrive.sh` +
    **[`docs/BACKUP_AND_RECOVERY.md`](docs/BACKUP_AND_RECOVERY.md)** push a
    nightly `bench backup --with-files` snapshot to Google Drive via rclone
    (optional encryption). Run it once and add the cron line to make it live.
22. **Workspace orphan-cleanup trap (fixed, but remember it).** Frappe's
    `bench migrate` **deletes** any public Workspace that has an `app` set but no
    matching file under that app's `workspace/` folder. The Jewellery workspace
    used to ship only as a *fixture*, so every migrate wiped it and broke the
    desk sidebar. It now ships as an app file
    (`jewellery_management/.../workspace/jewellery/jewellery.json`). **Never
    ship a workspace only as a fixture.**

---

## 11. Daily operations, backup & restore

### Start / stop
```bash
sudo systemctl start mariadb          # database
cd ~/frappe-bench && bench start      # dev server (Ctrl+C to stop)
# production:
sudo supervisorctl status && bench restart
```

### Backup (before any upgrade)
```bash
cd ~/frappe-bench
bench --site library.local backup --with-files
# files land in sites/library.local/private/backups/
```

### Off-site backup → Google Drive (recommended)
This is the **disaster-recovery** path: laptop lost/stolen → restore everything.
It is separate from the **mobile two-way sync** (phone ⇄ laptop).
```bash
# one-time: install rclone + connect Google Drive (see docs/BACKUP_AND_RECOVERY.md)
cd ~/Jew_Pawn-Lending-Suite && ./backup-to-gdrive.sh   # backup + upload + prune
# nightly — add to `crontab -e`:
#   15 2 * * *  /home/shyam/Jew_Pawn-Lending-Suite/backup-to-gdrive.sh >> ~/backup.log 2>&1
```
Full walkthrough (rclone config, encryption, restore steps):
**[`docs/BACKUP_AND_RECOVERY.md`](docs/BACKUP_AND_RECOVERY.md)**.

### Restore onto a fresh bench
```bash
bench new-site library.local --admin-password '<pw>'
bench --site library.local restore /path/to/<db>-database.sql.gz --mariadb-root-password '<root-pw>'
bench --site library.local restore /path/to/<files>.tar   # if --with-files
bench --site library.local migrate
bench --site library.local install-app jewellery_management
bench --site library.local install-app lending
bench --site library.local install-app pawn_shop
bench build && bench restart
```

### Export code changes (fixtures) — the golden rule
```bash
bench --site library.local export-fixtures --app jewellery_management
cd apps/jewellery_management && git add -A && git commit -m "..."
```

---

## 12. Shipping a complete environment (best for beginners)

`install.sh` removes the framework-install burden on Linux. For Windows and for
truly non-technical users:

1. **Docker** — `docker/Containerfile` + `docker/build.sh` build a
   Frappe/ERPNext image with all three apps; `docker/README.md` runs it with the
   maintained [frappe_docker](https://github.com/frappe/frappe_docker) stack.
   Works on **Windows** (Docker Desktop), **macOS** and Linux. *(Not executed in
   the build environment — validate before shipping.)*
2. **Windows (WSL2)** — `windows/install-windows.ps1` + `windows/README.md`.
   Frappe cannot run on native Windows; WSL2 gives a real Ubuntu where
   `./install.sh` works unchanged.
3. **VM snapshot / disk image** — boot a pre-installed machine and run
   `sudo systemctl start mariadb && cd ~/frappe-bench && bench start`. Best
   handover for a non-technical user; distribute outside git.
4. **Restore bundle** — a `bench backup --with-files` tarball + the app folders.
   A technician restores it in minutes (§11).

---

## 13. Repository & branch layout

| Repo | Branch | Contents |
|------|--------|----------|
| `ShyberDev/Jew_Pawn-Lending-Suite` | `develop` | **The bundle** — all three apps + `install.sh` + docs |
| `ShyberDev/jewellery_management` | `Frappe-Jewellery-Pawn-Lending-Suite` | Jewellery app's own repo (mirror/history) |
| `frappe/lending` *(upstream)* | `develop` | Money Lending (patched copy is vendored in the bundle) |

Both ShyberDev repos are **public**.

> Branch names with spaces/commas are allowed by git but awkward in URLs; the
> machine-friendly slug is `Frappe-Jewellery-Pawn-Lending-Suite`.

The detailed engineering log (every change, decision, verification and warning)
is in **`docs/AI_HANDOFF.md`**. Read §16–§18 for the current state.

---

## 14. Support & handoff

- **First read:** this file.
- **Deep detail:** `docs/AI_HANDOFF.md`.
- **Owner constraints (must not change):** never modify `apps/frappe`,
  `apps/erpnext`, `apps/library_management`; delivered **net** weight is the only
  stock/settlement weight; customer and worker books stay separate; history rows
  are append-only.
- **Before asking for help, collect:** `bench version`,
  `bench --site library.local list-apps`, the browser console errors, and
  `bench --site library.local doctor`.

---

*Built with the Frappe Framework + ERPNext. Licensed MIT. Tested on Kali
GNU/Linux Rolling / Python 3.14.6 / MariaDB 11.8.8 / Node 24 / Bench 5.31.0.*
