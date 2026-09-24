# AI Agent Handoff — jewellery_management (Frappe/ERPNext)

Created: 2026-09-24. Author: outgoing coding agent. Purpose: let a different AI
agent continue this project without access to the prior conversation.

Rules for this document: facts below were verified with the commands noted.
Anything not verified is explicitly marked NOT VERIFIED or as an assumption.

---

## 1. PROJECT CURRENT STATE

- **App location:** `~/frappe-bench/apps/jewellery_management`
  (absolute: `/home/shyam/frappe-bench/apps/jewellery_management`)
- **Site:** `library.local` (`http://library.local:8000/`), bench root `/home/shyam/frappe-bench`
- **Company:** Sri Sai Krishna Jewellery (shop display name; full legal name NOT VERIFIED — owner was asked, see §12)
- **Frappe:** `17.x.x-develop` (commit `8a43de0`), branch `develop`
- **ERPNext:** `17.x.x-develop` (commit `8c24c5b`), branch `develop`
- **jewellery_management:** version `0.0.1` (from `jewellery_management/__init__.py`), branch `develop`
- **Current Git commit (HEAD):** `42c1de0` — "docs: update AI handoff brick tracker" (branch `opencode/v1-complete-erp`; Brick A `c66290f`, B `60b0825`, C `5763ea4`, D `a8f6371`, G `9f56721`, kanban fix `9922ca8`, E+F `287b872`)
- **Remote:** `https://github.com/ShyberDev/jewellery_management.git` (fetch + push)
- **Push status:** NOT VERIFIED whether remote contains these commits. No push was
  performed during this session (explicit owner instruction: never push; GitHub is backup only).
- **Working tree:** CLEAN at handoff creation (verified `git status --short` → empty;
  the only new file after that check is this `docs/AI_HANDOFF.md` itself, intentionally uncommitted).
- **Installed apps on site:** `['erpnext', 'frappe', 'jewellery_management', 'lending', 'pawn_shop']`
  (`library_management` exists in `apps/` but is NOT installed on this site).
  `lending` = frappe/lending integration (Money Lending desk app); `pawn_shop` =
  custom Pawn Shop + Khatabook app. See §18.
- **DB:** MariaDB (credentials encountered during work — [SECRET/ CREDENTIAL OMITTED]).
- **Developer mode:** ON (`developer_mode: 1` in `common_site_config.json`).
- **Module ownership anomaly (important):** all 24 custom DocTypes have
  `module = "Jewellery"` whose Module Def `app_name` is `"frappe"`, NOT the app's
  `"Jewellery Management"` module (which owns 0 DocTypes). Verified via
  `tabDocType` query. Consequence: packaging relies on `hooks.fixtures`
  DocType export (which is in place and current), not on module ownership.
  Do not "fix" ownership without a migration plan — DocType JSON fixtures are the source of truth.

---

## 2. WHAT YOU WERE ASKED TO DO

**Original objective (session start):** read-only inspection of the bench, then an
architecture/migration proposal. Constraints at that time: change nothing.

**Evolved objective (explicit owner decisions during work):** build a complete,
production-usable Jewellery ERP on Frappe/ERPNext, V1 simplicity first, with the
custom jewellery workflow as primary. Owner later granted: proceed autonomously
without per-step permission, create test data freely (backup exists), break/rebuild
custom artifacts as needed — with hard limits: never touch Frappe/ERPNext core,
never push to GitHub.

**Key scope decisions made with the owner (all explicit):**
1. Priority 1+2 first: net-weight stock fix, Worker field cleanup. Then full ERP build.
2. Custom architecture is primary; do NOT replace it with standard ERPNext
   Item/Stock-Ledger/GL/BOM flows unless explicitly requested. ERPNext GL/BOM
   migration is a stated long-term direction, NOT V1 scope.
3. Order status flow frozen: `Advance Received → Ordered to Worker →
   Worker Finished → Received → Delivered`. No renames, no new statuses, submit only when Delivered.
4. Previous client scripts are REFERENCE ONLY — rewrite/replace freely.
5. All prior DB DocTypes/scripts/reports are reference; may break/reinstall/modify/delete.
6. Shop name for UI: Sri Sai Krishna Jewellery.
7. GST must include a 0% mode; rates configurable per invoice, never hardcoded.
8. Build order approved: Settlement → GST → Old Gold → HUID → Dashboard/Reports →
   Repairs(minimal)/Returns/Ledgers → Counter hardening.
9. Home screen must show a Sri Sai Krishna app tile opening a full dashboard.
10. Sample/test data is explicitly wanted, must be recognizable (`_sample_data`).

---

## 3. EVERYTHING ACTUALLY CHANGED

Git history this session (oldest → newest, branch `develop`; `76c35a2` and
`e1917ff` predate the session):

1. `30d2d98` — Order Transfer IN/OUT switched from `delivered_gross_weight` to
   `delivered_net_weight` (strict, throw-and-block, no fallback).
   File: `jewellery_management/jewellery_management/stock_hooks.py`. Tested: PASS (§7).
2. `adc1325` — P2 worker cleanup + first fixtures export.
   - `Jewellery Order.worker` (Link→Worker, parent, non-mandatory) ADDED.
   - `Jewellery Order Item.worker` (accidental duplicate) REMOVED after verifying 0 non-empty rows.
   - `worker_received_date` label renamed to `Received Date`.
   - `worker_other_charge_details` Table ADDED on Order Item (later relocated, see 4).
   - `update_worker_dates()` removed from `Client Script: Jewellery Order calculation`.
   - Retail transfer dialog label → "Delivered Net Weight".
   - `hooks.fixtures` + first `fixtures/*.json` export. Tested: PASS.
3. `f80c33e` — charge table relocated to Order parent + `order_item_idx` ref;
   parent-grouped rollup rewrite of calculation script. (Superseded by 4.)
4. `3c5530c` — **Two-world model**: deleted `create_order_stock_out_on_submit`
   (125 lines) + its `on_submit` hook. Transfer creates IN only; Stock Sale creates
   OUT; Order Sale never touches stock. Tested end-to-end: PASS.
5. `f259101` — NEW `Worker Settlement` DocType + `settlement.py` + hooks.
   Gold/cash separate ledger, 8 event types, balances API. Tested: PASS.
6. `c658f73` — GST: `gst_rate`/`gst_amount`(`gst`) fields, calc updates, NEW
   `GST Summary` report. Tested (math + SQL): PASS; browser totals NOT VERIFIED by agent.
7. `c33df8a` — Old Gold Receipt/Melt (+`old_gold.py`), sales exchange-credit fields,
   HUID fields + `HUID Register`, `Jewellery` workspace, `Worker Balances` +
   `Customer Outstanding` reports, `Jewellery Repair` (+`workshop.py`),
   `Jewellery Settings` single, Metal Rate `rate_time`, RSI `barcode`,
   additive counter roles, print worker-field removal. Tested: PASS (server-side).
8. `a4fb72d` — Apps-screen tile + `jewellery-dashboard` Page + `dashboard.py`.
9. `eccc543` — Page module fix (`Jewellery` → `Jewellery Management`; without this
   the dashboard served empty — root cause verified).
10. `9bd75c3` — Metal Rate naming-series fix + Silver 999 purity master (fixtures).
11. `f65a9c5` + `df135a2` — dashboard reload-on-return fix + cash/bank query fix.

**Files created (in app):** `.../jewellery_management/{settlement,old_gold,workshop,dashboard}.py`,
`.../page/jewellery_dashboard/{__init__.py,.js,.json}`,
`.../public/images/logo.svg`, `fixtures/workspace.json` (+ 7 other fixture files on first export).
**Files modified:** `hooks.py`, `stock_hooks.py`, `fixtures/{doctype,client_script,report,print_format,workflow,kanban_board}.json`.
**Files deleted:** none (only code deletion inside `stock_hooks.py`).
**`kanban_board.json` churn:** card-position runtime state deliberately reverted out of
commits twice; committed copy holds board structure only.
**Server scripts:** none (all server logic is committable `.py` files, intentional).
**DB DocType changes (24 total, module `Jewellery`, all `custom=1`):** see fixture list in §9;
field-level detail verified in `fixtures/doctype.json` (committed, current).
**Migrations run:** yes, several `bench --site library.local migrate` (schema sync only).
**No Frappe/ERPNext core file was modified** (verified: `git -C apps/frappe status`,
`git -C apps/erpnext status` were clean at inspection; re-verify on start).

---

## 4. FILES INSPECTED

### Core application files
- `jewellery_management/hooks.py` — full hook map (current content verified in §1 context); fixtures list; apps-screen tile.
- `jewellery_management/__init__.py` — version only.
- `modules.txt` (`Jewellery Management`), `patches.txt` (empty skeleton — NO patches used).

### Python (`jewellery_management/jewellery_management/`)
- `stock_hooks.py` — purchase/sale/opening/transfer IN creators, sales validator,
  candidate/transfer whitelisted APIs, kanban-delete cleanup. No OUT creator (deleted by design).
- `settlement.py` — settlement validation + `get_worker_balances` (tested).
- `old_gold.py` — receipt/melt validation + melt expected/variance math (tested).
- `workshop.py` — repair balance guard (tested).
- `dashboard.py` — read-only dashboard aggregator (tested via API).
- `page/jewellery_dashboard/jewellery_dashboard.js` — dashboard UI (syntax-checked only).

### JavaScript
- `public/js/jewellery_kanban.js` (1295 lines, global via `app_include_js`) — compact
  cards/tooltip/expand; inspected, NOT rewritten; known perf/fragility issues (§10).
- 7 DB Client Scripts (inspected + edited): Order calculation / Retail Stock /
  Submission Control / Opening / Sales / Purchase / RSI Smart Fields.

### Reports (DB, fixture-exported)
Retail Stock Balance (pre-existing), GST Summary, HUID Register, Worker Balances,
Customer Outstanding. All query SQL executed at least once: PASS.

### Hooks / Configuration
- `pyproject.toml` (read once; untouched), `site_config.json` (installed apps only),
  `common_site_config.json` (dev mode, ports).
- Print Formats `Jewellery Order Receipt` / `Jewellery Purchase Invoice Receipt`:
  inspected; worker column removed from Order Receipt (verified 0 refs).

### Templates/UI
- `templates/`, `www/` — EMPTY (no portal pages). No Jinja work done.
- Workspace `Jewellery` (DB + `fixtures/workspace.json`) — HTML-nav workspace.

### Tests
- No Frappe `tests/` directory exists. All verification was ad-hoc `bench execute`
  scripts in `/tmp/opencode/` (ephemeral, NOT committed) plus `node --check` and
  `py_compile`. See §7.

---

## 5. COMMANDS AND TOOLS USED

Conventions: [MODIFYING] changed system/DB/files; [READ-ONLY] did not.

- `bench --site library.local execute "exec(open('/tmp/opencode/*.py').read())"` — [MODIFYING]
  (all DB writes) and bare-expression form for reads — [READ-ONLY].
- `bench --site library.local migrate` — [MODIFYING] (schema sync; NOTE: also
  reimports fixtures, which twice reverted unexported DB work — see §10).
- `bench --site library.local export-fixtures --app jewellery_management` — [MODIFYING]
  (writes fixture JSON in app dir; does not touch DB).
- `bench --site library.local clear-cache` — [MODIFYING] (cache only).
- `bench list-apps`, `bench --site library.local list-apps` — [READ-ONLY].
- `bench build --app jewellery_management` — [MODIFYING] (built assets incl. logo).
- `git -C apps/<app> {status,log,diff,add,commit,checkout,branch,remote}` — commits are
  [MODIFYING] (local repo only; never pushed).
- `node --check <file>` — [READ-ONLY]. `python3 -m py_compile` — [READ-ONLY].
- `ps`, `curl` (login page 200; whitelisted-method probe → 403 as expected) — [READ-ONLY].
- `mariadb`/`mysql` clients directly: NOT USED (all DB access via bench).
- `sed -i` (2 uses: fixture label fix, naming probe cleanup) — [MODIFYING] (own temp/app files).
- `websearch` (exactly 2 calls: one cancelled, one commodity jewellery-ERP feature
  survey: Nexao/JSoft/ERIONT/SourceForge/APPIT/SthirApp/GehnaERP) — [READ-ONLY].
  Used only for the competitor feature map; no code taken from anywhere.
- No MCP servers, no npm/pnpm direct installs, no pip installs, no linter/formatter runs.

---

## 6. DATABASE

- Type: MariaDB. Name/user: known to agent at runtime — [SECRET/ CREDENTIAL OMITTED].
- Tables inspected (read-only SQL unless noted): `tabDocType`, `tabDocField`,
  `tabJewellery Order [Item]`, `tabJewellery Stock Transaction`, `tabRetail Stock Item`,
  `tabWorker Settlement`, `tabMetal Purity`, `tabMetal Rate`, `tabGL Entry`,
  `tabAccount`, `tabPayment Entry` (via API), `tabClient Script` (via API).
- Schema changes (all via DocType API + `migrate`): parent `worker`,
  `worker_other_charge_details` (parent), `total_worker_cost`, `Received Date` label,
  removed item `worker`, GST fields, old-gold credit fields, HUID fields, barcode,
  rate_time, all §3 DocTypes/fields, role permission rows (additive).
- Physical orphan: `tabJewellery Order Item.worker` column remains (Frappe never drops
  columns); unused since DocField removal. Harmless.
- Data created: ~10 rates/purities masters; 10 RSI samples; 10 submitted purchases;
  10 submitted sales; 10 orders (8 draft, 2 submitted); 1 worker + 3 settlements;
  2 receipts + 1 melt; 2 repairs; 2 ERPNext parties; 2 COA accounts; 10 Payment Entries;
  6 earlier draft sample bills. All test rows documented in §7/§8; full cleanup was
  performed for volatile tests (`REMAIN=0` verified), seed data intentionally left.
- Data deleted: test-only rows I created (cancel → delete), plus DocField deletions
  above (after 0-usage verification). No real/user data deleted (all data is test data).
- Fixtures: `fixtures/*.json` exported 4+ times; final export verified field-by-field
  before each commit. Fixture files ARE the reinstall path (fresh-install proof NOT done).
- Assumption (clearly marked): remote Git state NOT VERIFIED (no fetch/push performed).

---

## 7. TESTING AND VERIFICATION

Ad-hoc scripts only; no committed test suite. Frappe `tests/` does not exist.

| Test | Command/action | Expected | Actual | Result |
|---|---|---|---|---|
| Net-weight block | new order, `delivered_net_weight=0` → `get_order_stock_candidates` | throw "Delivered Net Weight is required", no "Gross" | exact | PASS |
| Net-weight pass | same order net=9.5 → candidates | `delivered_net_weight: 9.5`, no gross key | exact | PASS |
| Transfer IN | `send_items_to_retail_stock` | IN 9.8, available 9.8 | exact | PASS |
| No OUT on submit | Delivered + submit | txns stay `[In 9.8]` | exact | PASS |
| Stock-sale OUT | submit Sales Invoice 9.8 | OUT 9.8, available 0.0 | exact | PASS |
| Cleanup | cancel+delete all cycle docs | `REMAIN=0`, ref history intact | exact | PASS |
| Settlement math | earning +9.8, gold-given 10g@75%, advance +20000, convert −10000/−1g | gold 2.3→1.3, cash 10000 | exact | PASS |
| Settlement guards | gold on cash event; empty entry | throws | throws | PASS |
| Old-gold math | 25−1.5g @82%/80% @10000; melt actual 18.5 | net 23.5, est 19.27, assay 18.8, var −0.3 | exact | PASS |
| Repair math/guard | 2000−500; advance>estimate | 1500; throw | exact | PASS |
| GST SQL | `GST Summary` query 2020–2030 | 5 submitted bills listed | 5 rows | PASS |
| HUID SQL | `HUID Register` Full View | 6 RSI, all unhallmarked | exact | PASS |
| Dashboard API | `get_data` Sep + all-time | KPIs incl. cash 65k/bank −20k | exact | PASS |
| Parent charge table | 2 items + 3 tagged charges save/load | rows persist with tags | exact | PASS |
| Page serving | `desk_page.get('jewellery-dashboard')` | script len>0 + onload | 6708 chars | PASS |
| Apps tile hook | `get_hooks('add_to_apps_screen')` | tile entry | exact dict | PASS |
| HTTP smoke | `curl /login`; unauth API probe | 200; 403 (found, blocked) | exact | PASS |
| JS syntax | `node --check` on 3 edited scripts | pass | pass | PASS |
| py_compile | all new/edited `.py` | pass | pass | PASS |

NOT performed: browser/manual UI testing by agent (no browser tool); login-as-counter-role
permission test; fresh-site reinstall proof; load/perf tests; GSTR-1 format validation;
e-invoice/TCS; returns flow; any Frappe/ERPNext upgrade regression.

---

## 8. BUSINESS LOGIC (owner-established)

Legend: IMPLEMENTED = live + tested server-side. Others as labeled.

- Ordered weight is an ESTIMATE; delivered net weight rules everything. IMPLEMENTED
  (`delivered_net_weight` strict; submit blocks when 0; gross never used for order stock).
- Worker uses OWN resources; shop never issues stock to worker. IMPLEMENTED (no such code path exists by design).
- Worker payable = actual delivered net × (purity% + item wastage%) × fine (biscuit) rate.
  Wastage-%-first; cash making derives from it. IMPLEMENTED (client calc; server mirror DEFERRED).
- Customer final = delivered-based quoted + delivery weight/amount adjustments; payments
  mixed cash/UPI/etc.; balance floors at 0. IMPLEMENTED (client calc).
- Customer book vs worker book are SEPARATE; meet only in analysis; prints NEVER carry
  worker fields. IMPLEMENTED (print scrub verified).
- Visit lumps (bus fare) are tagged to item sets or whole order, NEVER split.
  IMPLEMENTED (`applicable_items` "1,2,3"/blank; order total counts once).
- Three costs: customer order-date, worker order-date reference, actual settlement
  (rate moved → variance). First two IMPLEMENTED; settlement-date realized P&L PLANNED
  (needs FIFO auto-allocation).
- Order Sale (no stock touch) vs Stock Sale (stock OUT) are separate worlds; unclaimed
  items enter stock ONLY via explicit Transfer to Stock (IN with net weight).
  IMPLEMENTED + cycle-tested.
- Purchase/Sales/Opening create IN/OUT on submit with duplicate guard
  (`exists(reference…)`) — IMPLEMENTED, but atomicity/race hardening DEFERRED (§10).
- Worker running balance (gold grams and cash SEPARATE; bulk/advance/either-direction;
  cash never auto-converts). Ledger + balances IMPLEMENTED; FIFO auto-allocation PLANNED.
- Old gold: intake estimate vs assay kept separate; melt expected-vs-actual variance;
  outs = exchange-credit at sale OR sale-to-worker. IMPLEMENTED.
- GST per-invoice configurable incl. 0%; subtotal×rate (2dp); total includes GST.
  IMPLEMENTED client-side; server mirror + GSTR-1 filing format DEFERRED.
- HUID lifecycle per piece (Not→Sent→Hallmarked + HUID + date); registry shows
  sold/unsold. IMPLEMENTED (registry live; all stock currently unhallmarked — matches owner).
- Rates: daily default + intraday reprice (`rate_time`); bill uses rate at bill time.
  Schema IMPLEMENTED; auto-feed UNKNOWN (manual entry today).
- Order statuses frozen (5); kanban 5 columns; compact cards/tooltip preserved. IMPLEMENTED.
- Roles: System Manager full + additive Sales/Purchase/Stock/Accounts reads/writes.
  IMPLEMENTED but login-as-role NOT VERIFIED.
- Repairs rare → token + balance only. IMPLEMENTED.
- UNKNOWN/owner-open: full legal company name; 18K rate value; village-wise analytics;
  scheme/chit (explicit V2); diamonds/4Cs, multi-branch, RFID, PMLA (explicit out).

---

## 9. CURRENT ARCHITECTURE

**Standard ERPNext used:** Customer link (orders), Warehouse links, `Customer`/`Supplier`/
`Payment Entry`/`GL Entry`/`Account` (sample money flow → dashboard cash/bank),
`Metal Rate`-adjacent masters are custom; `Kanban Board`, `Workflow` (exists, INACTIVE),
`Print Format`, `Report`, `Workspace`, `Page`, `Client Script` frameworks.

**Deliberately custom (owner directive):** Item/Sales/Purchase/Opening/Order/Stock-ledger
(`Jewellery Stock Transaction` grouped by retail_stock_item+purity),
payments-as-child-tables, worker costing/settlement, old-gold, HUID, GST math,
dashboard. NO ERPNext Stock Ledger/GL posting/BOM/Work Order/Subcontracting in V1.

**Custom DocTypes (24, all module `Jewellery`, `custom=1`):** Jewellery Order (+Item,
+Payment children), Purchase Invoice (+Item, +Payment), Sales Invoice (+Item, +Payment),
Opening Stock (+Item), Stock Transaction, Retail Stock Item, Jewellery Item Type,
Metal Purity, Metal Rate, Worker, Worker Other Charge (child), Worker Settlement,
Old Gold Receipt, Old Gold Melt (+Item child), Jewellery Repair, Jewellery Settings (single).

**Server logic:** `stock_hooks.py`, `settlement.py`, `old_gold.py`, `workshop.py`,
`dashboard.py` (+ page JS). No Server Scripts in DB (intentional).

---

## 10. KNOWN ISSUES (do not hide)

1. **Stock transactions post as DRAFT (`docstatus=0`)** — `insert()` without `submit()`
   everywhere. Dashboard/validators count non-cancelled rows to match. Fix = submit-on-source-submit + backfill; NOT DONE.
2. **No cancel/amend reversal** for stock/invoice flows. Cancelling orphans ledger rows.
3. **Idempotency is check-then-insert** (race-prone); no DB unique index, no locks.
4. **`bench migrate` reimports fixtures** — wiped unexported DB work twice this session.
   Standing rule: DB change → verify → export → commit; never migrate mid-flow.
5. **Kanban JS (1295 lines, global)** — MutationObserver + per-card requests; works but
   heavy/fragile; scoped rewrite DEFERRED.
6. **Totals math is client-side only** (orders/invoices); API/import bypasses it.
7. **Permissions added but never login-tested** as counter roles.
8. **6 early draft sample bills use realistic names WITHOUT `_sample_data`** and their
   `remarks` were silently dropped (verified: Sales Invoice has NO remarks column —
   verify before relying on remarks anywhere; Purchase Invoice remarks NOT VERIFIED).
   Identifiable only by names/dates (JSI-2026-09-24-02…07).
9. **Settings singles row empty** (`shop_name` reads blank until first UI save).
10. **Workflow `Jewellery Order Workflow` inactive** + orphan `workflow_state` field.
11. **Silver Metal Rate 240/g entered; 18K rate missing** (owner to provide; ~11700 est. NOT entered).
12. **Sample Bank reads −₹20,000** (samples overpaid — data artifact, math correct).
13. **No FIFO auto-allocation, no fresh-install proof.** Returns (Brick D),
    e-invoice/TCS/GSTR-1 (Brick E) and the 4 new reports (Brick F) are DONE.
14. **Frappe/ERPNext on `develop` (17.0.0-dev)** — upstream churn risk; pin before go-live.

---

## 11. THINGS THAT MUST NOT BE CHANGED (owner constraints)

- Never modify Frappe/ERPNext core files. Never push to GitHub (backup-only remote).
- Do not replace custom jewellery logic with standard ERPNext stock/GL/BOM without
  explicit owner request (long-term direction, not license).
- Order statuses frozen; submit-only-when-Delivered; no per-item delivery status in V1.
- Delivered NET weight is the only stock/settlement weight; never fall back to gross.
- Customer and worker books stay separate; worker data never on customer prints.
- Visit lumps never split across items. Cash never auto-converts to gold.
- History rows are never rewritten (rates, assays, estimates, settlements append-only).
- Do not delete data to simplify implementation; test data deletes only when owner-approved.
- Preserve working kanban tooltip/status behavior; V1 simplicity over completeness.
- Verify DB state after every mutating step; never trust a success message alone.

---

## 12. DEFERRED WORK

**Priority 1:** ~~server-side mirrors of order/invoice totals~~ ✅ DONE (Brick A, see §17);
FIFO auto-allocation (+ realized vs provisional profit); stock-transaction submit flow +
backfill; cancel/amend reversals.
**Priority 2:** Sales/purchase returns; e-invoice + TCS; GSTR-1 filing format; barcode
scan-to-bill; rate-lock at bill start; login-as-role permission proof; Settings defaults
save; 18K rate entry (owner); legal-name confirmation (owner).
**Later:** Dashboard charts polish; low-stock thresholds per item; kanban rewrite;
fresh-install proof (needs DB-root coordination); intra-day rate feed.
**Deferred (explicit):** savings schemes/chit (V2); diamonds/4Cs; multi-branch; RFID;
PMLA automation; manufacturing BOM; Tally sync.
**Not decided:** which account heads for making/hallmark income; UPI mode-of-payment
master additions (used Cash for UPI/Card entries — "Wire Transfer"/"Credit Card" used
for bank legs); village-wise analytics.

---

## 13. NEXT AGENT INSTRUCTIONS

1. Read this file fully, then `git -C apps/jewellery_management status` and
   `git log --oneline -5` — expect clean tree on `opencode/v1-complete-erp` at the
   Brick A commit.
2. Change nothing until you reproduce: `bench --site library.local execute`
   dashboard `get_data` smoke test (§7) and confirm fixtures match DB for anything
   you plan to touch.
3. Inspect first: `jewellery_management/hooks.py`,
   `.../jewellery_management/{calculations,stock_hooks,settlement,old_gold,dashboard}.py`,
   `fixtures/doctype.json` (source of truth for schema), open `Page: jewellery-dashboard`.
4. Never run `migrate` with unexported DB changes (§10.4). Never push.
5. Continue from §17 Brick D (sales/purchase returns with stock reversal).

---

## 14. GIT STATE

- Current branch: `opencode/v1-complete-erp`
- Current commit: `42c1de0` docs update; before it Bricks E+F `287b872`, D `a8f6371`,
  G `9f56721`, kanban fix `9922ca8` (A `c66290f`, B `60b0825`, C `5763ea4`).
  New apps are separate repos: `apps/pawn_shop` (branch `develop`, commit `48550ea`);
  `apps/lending` is an upstream checkout.
- Remote: `https://github.com/ShyberDev/jewellery_management.git` (push NOT performed; remote state NOT VERIFIED)
- Working tree: CLEAN after Brick C commit. `docs/AI_HANDOFF.md` is tracked (updated in-session each brick).

---

## 15. RESOURCE USAGE / EXTERNAL RESOURCES

- **Agent model:** per session instructions, "Muse Spark 1.3 Free" via provider
  `opencode` — stated as given; underlying infrastructure NOT VERIFIED by agent.
- **Subagents:** requested 3× `explore` subagents at session start; all failed
  (provider free-tier restriction); all inspection done directly. No other agents/MCP used.
- **Websites consulted:** one commodity websearch survey of jewellery-ERP vendors
  (Nexao, JSoft ERP, ERIONT, SourceForge jewellery vertical, APPIT/FlowSense,
  SthirApp, GehnaERP) for the competitor feature map only. No code, docs, or repos
  consumed. Frappe/ERPNext official docs: NOT consulted (all framework behavior
  verified from local source under `apps/frappe`, `apps/erpnext`).
- **GitHub repos consulted:** none (remote is the project's own backup repo; never fetched).
- **External libraries/packages/APIs:** none installed; `node --check` (system node
  v24.18.0) and `curl` used read-only. No database GUI tools (bench CLI only).

---

## 16. FINAL HANDOFF SUMMARY

## CURRENT PROJECT STATE
Working single-shop Jewellery ERP: orders→workers→settlement, purchases/sales with
GST incl. 0%, custom weight-based stock ledger, old-gold two-leg flow, HUID registry,
repairs, rates, roles, workspace, home tile + live dashboard. Server-side totals mirror
(Brick A) live on all 4 billing DocTypes; 24 custom DocTypes, 5 reports, all
fixture-versioned on `opencode/v1-complete-erp`, tree clean, sample data in place and
reconciled to the current client math, ERP core untouched, nothing pushed.
Plus two desk apps (session 2): **Money Lending** (frappe/lending) and custom
**Pawn Shop + Khatabook** (`apps/pawn_shop`, branch `develop`, commit `48550ea`) with
6 reports and combined 3-business accounting — see §18.

## LAST COMPLETED TASK
Desk sidebar / app-context fix for the two new apps (owner-reported gray +
missing sidebar): marked Jewellery/Lending/Pawn workspaces `standard=1` with
valid lucide icons, and authored a 20-item sidebar on the Lending workspace
(§18.6). Pawn `624ec85`, Jewellery `d315e29`, Lending `f13f68e` (all local).
Before that: Bricks D/E/F complete. D: Sales/Purchase Returns with stock
reversal (commit `a8f6371`). E: TCS on sales over threshold + GSTR-1 export +
e-invoice payload (`gst.py`, commit `287b872`). F: 4 new Script Reports (Daily
Sales Summary, Supplier Payable, Jewellery Stock Ageing, Item Rate Card) +
default GST-rate pre-fill (commit `287b872`). Kanban board made code-defined
(`9922ca8`).

## CURRENT UNFINISHED TASK
None — both requested desk apps are installed and verified. Awaiting owner's
modification/improvement list before any further work (see §18 for details).

## NEXT ACTION
Owner **hard-refreshes** the browser (boot payload is cached per page load) and
verifies in the desk (`/desk`): apps screen shows **Lending** and **Pawn Shop**;
left workspace rail shows **Jewellery**, **Lending**, **Pawn** with coloured app
icons (not gray) and the header shows the app/module name. Then owner dictates
changes. Do NOT push to GitHub. Do NOT re-run `sync_for(force=True)` on pawn_shop
(see §18 warning).

## IMPORTANT WARNINGS
- `bench migrate` reimports fixtures and SILENTLY reverts unexported DB work.
- Stock/purchase/sale DocTypes live under module `Jewellery` (Frappe-owned), NOT the
  app's module — do not "fix" without a plan; fixtures are the truth.
- 6 early draft bills lack `_sample_data` markers (remarks column doesn't exist).
- Purchase Invoice `gst` is Currency precision=0 (decimal(21,0)): client computes grand
  from unrounded flt2 GST while the field stores whole rupees — mirror keeps that
  behaviour; compare that field with ±0.5 tolerance.
- Never push; never touch `apps/frappe`, `apps/erpnext`, `apps/library_management`.

---

## 17. BRICK TRACKER (owner-approved 5-workstream packet)

Research: `docs/FEATURE_MATRIX.md` maps all 10 competitor products
(Marg, MMI Jwelly, Ornate, Online Munim, TallyPrime, Synergics, JewelSteps, Akrut,
ERIONT, GehnaERP) to built / building / V2 / out-of-scope.

- **A. Server totals mirror — ✅ DONE**
  - `calculations.py` (new): `recalc_sales_invoice`, `recalc_purchase_invoice`,
    `recalc_order`, `recalc_opening_stock` + pure `compute_*` helpers.
  - hooks.py: `validate` added for Sales Invoice, Purchase Invoice, Order, Opening Stock.
  - Verified: 59/59 docs recompute == stored (0 mismatches); tampered totals restored on
    insert (validate hook fires); old-gold credit autofill/clamp mirrored.
  - Data migration: reconciled 59 docs + 25 sales/purchase JST rows to current client
    math (sample-data generator had drifted: 7 invoices stored ₹0, parent weight totals
    0, floor-rounding, pre-GST legacy docs). Dashboard deltas recorded (sales
    ₹22,05,905 → ₹22,13,087; purchases ₹33,52,393 → ₹33,66,397; orders-active
    ₹4,10,460 → ₹21,12,525 — 10 orders had ₹0 stored). Metal/stock-value unchanged.
  - Rounding contract: money ceil; weights round3 half-up; GST flt2 half-up; purchase
    `gst` field stores whole rupees (precision 0) but grand uses unrounded GST.

- **B. Stock submit + reversal flow — ✅ DONE**
  - `stock_hooks.py`: all 4 JST creators now `submit()` (purchase/sales/opening/
    order-transfer); `get_available_stock` reads `docstatus=1` only; all "existing"
    duplicate checks exclude cancelled rows (`docstatus < 2`); new
    `reverse_stock_transactions` cancels every live JST linked to a source doc.
  - hooks.py: `on_cancel` wired for Sales Invoice, Purchase Invoice, Opening Stock;
    `Jewellery Order` uses `on_trash` (list: `remove_order_from_kanban` +
    `reverse_stock_transactions`) — **frappe never dispatches `before_delete`**
    (verified in `apps/frappe/frappe/model/delete_doc.py`: only `on_trash` /
    `after_delete` run), so the pre-existing kanban hook on `before_delete` was dead and
    moved to `on_trash` where it actually fires.
  - Backfill: 31 of 33 draft JSTs submitted; **2 legacy orphans DELETED**
    (`JST-2026-08-17-01` referenced the CANCELLED `JSI-2026-08-17-01`; `JST-DDMMYY-001`
    referenced the MISSING `JPI-2026-00006`). Drafts cannot be cancelled (docstatus
    0→2 invalid), so deletion is the only valid cleanup for never-submitted orphans.
  - Verified cycles (scratch docs, fully cleaned up): sales submit→cancel restores
    stock + cancels JST (RSI-0014 silver 550→549→550); purchase submit→cancel likewise
    60→180→60; order transfer (JWO copy) delete cancels both transfer JSTs (22.22→33.33
    →22.22→restored). Dashboard metals corrected by the orphan cleanup: gold_22k
    100.5→**95.5**g, gold_total 116.11→**111.11**g, stock_value ₹19,67,316→**₹18,89,316**
    (= −5g×₹15,600 exactly); 18K 15.61g / silver 650g unchanged. Counts after: Sales 22,
    Purchase 18, Order 18, JST 31 (1 Opening + 5 Order Transfer + 13 Purchase + 12 Sale,
    all docstatus 1).

- **C. FIFO metal ledger — ✅ DONE**
  - `fifo.py` (new): submitted-JST FIFO per (Retail Stock Item, Purity) bucket —
    IN rows open lots, OUT rows consume oldest lot first. Cost basis = JST
    `rate_24k` per GROSS gram WITHOUT purity adjustment, deliberately matching
    the shop's invoice/dashboard convention (one rate per gram regardless of
    alloy). Realised P&L per OUT = OUT stock_value − FIFO cost of consumed
    grams; book value = open lots at purchase cost; provisional P&L = open
    weight × (current metal rate − lot rate). Current rates from `tabMetal
    Rate` (latest rate_date, active=1 — same rule as the dashboard).
  - **Script Report "FIFO Metal Ledger"** (13 columns: lot register with
    weight/rate/metal value/doc value/lot rate/FIFO cost/realised/balance +
    bucket totals + grand total). File-defined standard report under module
    **"Jewellery Management"** (NOT "Jewellery" — that module maps to the
    frappe app, and `get_report_module_dotted_path` would resolve to
    `frappe.jewellery.report…`; the app-own module resolves to
    `jewellery_management.jewellery_management.report…`). DB row inserted
    directly (no full `migrate`); not captured by the Report fixture filter
    (module=Jewellery) — the file is the source of truth.
  - Verified identities (sample data, all pass): per-bucket open weight ==
    `get_available_stock`; gold open 111.11g / silver 650g (== dashboard
    metals); book+provisional == 18,89,316 exactly (== dashboard stock_value);
    realised total 1,43,484 == Σ per-sale gross margin over FIFO metal cost
    (double-checked line by line); as_of cut-off works (RSI-0001 at
    2026-08-20 → 12g open, 0 realised); bucket/purity filters work.
  - Ledger design notes: order-transfer OUT rows pair with zero-rate transfer
    IN lots (net-to-zero realised) — keep transfer INs before any external OUT
    on the same bucket. Drafts/cancels excluded (docstatus=1 only). Rounding:
    weights half-up 3dp, money half-up 2dp (Decimal, never Python round).

- **D. Sales/Purchase Returns** with stock reversal — ✅ DONE (commit `a8f6371`)
  - JST `transaction_type` extended with `Sale Return` / `Purchase Return`.
  - JSI/JPI: `is_return`, `return_against`, `return_reason`, `returned_amount`
    custom fields; client + server clamp so old-gold credit never exceeds the
    original bill; return invoices never carry TCS; stock reversal via
    `reverse_stock_transactions` on cancel.

- **E. GST filing** — ✅ DONE (commit `287b872`)
  - Jewellery Settings: `gstin`, `business_state`, `tcs_rate` (0.1%),
    `tcs_threshold` (₹5,00,000).
  - JSI: `tcs_rate`, `tcs_amount`, `hsn_code` (default 7113).
  - `calculations.py` `_compute_tcs_amount`: `ceil(grand_total × rate%)` above
    threshold; returns never carry TCS; `grand_total` intentionally EXCLUDES TCS
    (kept goods-value to protect existing dashboard/payment math).
  - Client TCS mirror + boot props `jewellery_settings_tcs_threshold/_rate`
    via `boot_session` hook.
  - `gst.py`: `gstr1_export(from,to)` → B2B/B2C/summary aggregation;
    `einvoice_payload(invoice)` → IRN-style JSON.
  - Verified: 937300→938, small→0, return→0; GSTR-1 Aug-2026 b2b 0 / b2c 2 /
    summary rate 3.0 taxable 239250 cgst 3589 sgst 3589; e-invoice payload
    builds for JSI-2026-09-24-17; validate-path TCS 1,400,800→1401 correct.

- **F. New reports** — ✅ DONE (commit `287b872`)
  - Script Reports, module **"Jewellery Management"** (file-defined, DB row
    inserted directly like FIFO): **Daily Sales Summary**, **Supplier Payable**,
    **Jewellery Stock Ageing** (renamed to avoid core Stock Ageing collision),
    **Item Rate Card** (reuses `fifo.get_current_metal_rates`).
  - Default GST-rate pre-fill from Jewellery Settings on new JSI/JPI
    (`prefill_gst_rate` in both client scripts).
  - Verified: daily Aug total grand 246428; supplier payable OK; stock ageing
    grand weight 1238.81 / value 2970735; item rate card 16 rows.

- **G. Desk navigation: persistent Jewellery sidebar + Modules rail — ✅ DONE**
  - Reported bug: the sectioned nav (Counter / Orders & Workers / Stock &
    Hallmark / Masters) + FIFO Metal Ledger + Sri Sai Krishna dashboard only
    showed on the workspace page and vanished when entering a doctype form
    (`/desk/jewellery-order?name=...`); modules were not reachable.
  - Root cause: workspace "Jewellery" carried all navigation as HTML `content`
    blocks only; v17 `sidebar_items` (the child table that drives the left desk
    sidebar) was empty. The sidebar fell back to auto-generated module sidebars
    ("jewellery" → 3 doctypes + 5 reports; "jewellery management" → FIFO +
    dashboard), so opening a doctype switched to the wrong shell and the app was
    app-less (no header/app context, no modules in the dock).
  - Fix (DB + `fixtures/workspace.json`): authored 27 `sidebar_items` rows —
    Home, Sri Sai Krishna Dashboard (Page), and collapsible sections
    Counter / Orders & Workers / Stock & Hallmark / Masters — with
    `default_workspace=1` on every Jewellery entity item. The boot
    `default_workspace_map` now owns each Jewellery doctype/report/page to
    workspace "Jewellery", so the full nav persists on every list/form/report/
    workspace page; the generated fallback sidebars are suppressed (single
    authored "jewellery" payload, module "Jewellery Management"). Order Kanban is
    a URL item (`/app/kanban/Jewellery Order Kanban`, `open_in_new_tab=0`).
  - Modules rail: pinned `User.workspaces` (Administrator + Shyam) to a curated
    module list (Jewellery, Invoicing, Payments, Accounting, Financial Reports,
    Buying, Selling, Stock, Manufacturing, Projects, System, Users, Build) so the
    left workspace dock always shows the modules. DB-only user data (not a
    fixture), like kanban positions.
  - Verified against the boot payload: one "jewellery" sidebar with all 27 items;
    default map routes every Jewellery entity → "Jewellery"; `user_workspaces`
    list intact. No schema/server changes; fixtures re-exported and committed.

---

## 18. NEW DESK APPS (owner request, session 2)

Two additional desk apps were requested and delivered alongside the jewellery app.
Neither touches `apps/frappe`, `apps/erpnext`, `apps/library_management`, or the
jewellery fixtures. Nothing pushed.

### 18.1 Installed applications (site `library.local`)
`frappe`, `erpnext`, `jewellery_management`, `lending` (17.0.0-dev), `pawn_shop`.

### 18.2 Money Lending — frappe/lending integration
- Installed via `bench get-app https://github.com/frappe/lending` +
  `bench --site library.local install-app lending`. `install-app` runs a scoped
  `sync_for`/`sync_fixtures`, not a full migrate — jewellery DB verified intact.
- Provides modules `Loan Origination`, `Loan Management`, public workspace
  `Lending`, 35 sidebar items, 13 number cards, 4 charts.
- `Lending` pinned in `User.workspaces` for Administrator and
  `shyamsailolugu@gmail.com`; `Loan Manager` role granted to the owner user and
  `System Manager` added to the `Lending` workspace roles (DB-only user/role data)
  so the workspace is visible to both accounts. Route: `/app/lending`.

### 18.3 Pawn Shop + Khatabook — custom app `pawn_shop`
- Own git repo `apps/pawn_shop`, branch `develop`, license `mit`, commit
  `48550ea` (local only). Module **"Pawn Shop"**. Route `/app/pawn`. Logo
  `/assets/pawn_shop/images/pawn.svg` (built via `bench build --app pawn_shop`).
- **11 DocTypes:** Business, Village, Pawn Customer (naming `PC-.YYYY.-.#####`,
  shared by pawn + khatabook), Pawn Settings (Single), Pawn Item (child),
  Pawn Loan (`PL-`), Pawn Release (`PR-`, submittable), Khatabook Installment
  (child), Khatabook Loan (`KL-`), Khatabook Collection (`KC-`, submittable),
  Khatabook Refinance (`KR-`, submittable).
- **Rounding contract** mirrors jewellery: `pawn_shop/utils.py` `money` = ceil,
  `round3`/`round2`/`round_pct` = half-up (Decimal, never Python `round`).
- **Interest:** simple `loan_amount × rate%/month × (days/30)`, money ceil; rate
  default = Pawn Customer override, else Pawn Settings (gold 3%/mo, silver 4%/mo).
- **Pawn Loan:** multiple items (metal, hallmarked yes/no, gross/net weight,
  valuation), market valuation from `Metal Rate` master (latest active rate_date,
  fallback to Settings), LTV, balance = principal + accrued interest − payments.
  **Pawn Release** submittable: pays principal + interest → loan `Released`,
  balance 0.
- **Khatabook:** `installment_amount = ceil(total_payable / count)`; weekly due
  dates (e.g. 5000 principal + 1000 interest = 12 × 500). **Khatabook Collection**
  `on_submit` allocates oldest-first, flags `is_irregular` (late or partial).
  **Khatabook Refinance** closes the old loan (status `Closed`) and creates a new
  loan with principal = old outstanding, `refinanced_from` set, flexible interest.
- **6 Script Reports** (module "Pawn Shop", file-defined):
  Pawn Monthly Profit and Loss (chart), Pawn Valuation, Pawn Outstanding,
  Khatabook Collection Sheet, Khatabook Outstanding, Combined Business Profit and
  Loss (chart). Names deliberately avoid `&` (frappe report module path =
  `frappe.scrub(name)`; `&` breaks the Python import).
- **Combined accounting:** `Business` master types Shop / Money Lending / Pawn /
  Khatabook; Combined Business Profit and Loss aggregates shop (JSI/JPI),
  lending (`Loan`/`Loan Repayment`, defensive import), pawn, khatabook with a
  TOTAL row. Verified: shop income ₹22,13,087 / purchases ₹33,66,397 (matches
  jewellery baselines), pawn principal ₹1,50,000, khatabook ₹9,700.
- **Scheduler:** `pawn_shop.tasks.mark_overdue_loans` daily.
- **Workspace:** `Pawn` with 4 cards + 20 `sidebar_items`; boot
  `default_workspace_map` routes all Pawn entities → `Pawn`. Pinned in
  `User.workspaces` for both accounts (order Jewellery, Lending, Pawn, …).
- **Sample data** created and marked "SAMPLE DATA" (kept for owner verification):
  e.g. `PL-2026-00002` active (gold non-hallmarked 25g + silver hallmarked 200g,
  market ₹4,38,000, LTV 22.83, balance ₹1,01,500); collection ₹550 on
  `KL-2026-00002`.

### 18.4 End-to-end verification (all PASS)
- Apps screen (`frappe.apps.get_apps`): ERPNext, Sri Sai Krishna Jewellery,
  Lending (`/app/lending`), Pawn Shop (`/app/pawn`). Logo asset serves HTTP 200.
- Desk routes `/app/pawn`, `/app/lending`, `/app/jewellery`, `/login` → HTTP 200.
- 30/30 pawn/khatabook flow tests (defaults, interest, release, 12× schedule,
  regular + irregular collections, refinance, all reports).
- All 6 reports run through the real `frappe.desk.query_report.run` API with
  charts; Pawn Valuation splits gold non-hallmarked / silver hallmarked correctly.
- Jewellery DB intact after all installs: JST submitted 31, JSI 22, JPI 18,
  Order 18, kanban board + `field_name` intact, workspace 27 sidebar items.

### 18.5 ⚠️ WARNING — pawn_shop workspace source file
A **forced** re-import of a Workspace (`frappe.model.sync.sync_for(app, force=True)`
on an already-existing workspace) deletes the workspace's own source folder:
`import_doc` → `delete_old_doc` → `frappe.delete_doc(..., for_reload=True)` →
`Workspace.after_delete` → `delete_folder` (dev mode), and the subsequent
re-insert skips export because `frappe.flags.in_import` is set. This is a Frappe
behaviour, not an app bug. `bench migrate` calls `sync_all()` with `force=0`, which
skips the import by timestamp, so it is safe. **After any forced sync, regenerate
`apps/pawn_shop/pawn_shop/pawn_shop/workspace/pawn/pawn.json`** (generator
`/tmp/opencode/gen_pawn_workspace.py`) before committing. The same applies to any
app-shipped workspace.

### 18.6 Desk sidebar / app-context fix (owner-reported: gray + missing sidebar)
Owner reported the desk "not loading properly", no sidebar module information,
and a gray screen when switching Pawn → Lending. Root causes and fixes:

1. **Workspaces were not `standard`.** `frappe.current_app` and
   `Sidebar.get_sidebar_app()` both treat a non-standard workspace as app-less
   (`workspace && !workspace.standard ? null : ...`). Result: the sidebar header
   showed the session user instead of the app/module name, and the workspace dock
   lost its app logo. Fix: set `standard: 1` (and correct `app`) on **Jewellery**,
   **Lending**, **Pawn**. Jewellery `app` was also null → set to
   `jewellery_management`.
2. **Invalid workspace icons.** Workspace `icon` must be a bare lucide symbol
   name (no `icon-` prefix, must exist in
   `apps/frappe/frappe/public/icons/lucide/icons.svg`). `assets` (Pawn) and
   `loan` (Lending) do not exist → the dock/header rendered a blank gray
   `<use href="#icon-...">`. Fix: Pawn → `hand-coins`, Lending → `banknote`,
   Jewellery → `gem`.
3. **Lending had no authored sidebar.** `bootinfo.workspace_sidebar_item` is
   keyed by **workspace title lowercased**. Lending had no `sidebar_items`, so
   there was no `["lending"]` entry; `/app/lending` hit the `catch` in
   `Sidebar.prepare()` and rendered "No Sidebar Items" (the gray page). Fix:
   authored 20 `sidebar_items` on the Lending workspace (Home / Loan Management /
   Loan Origination / Reports) with `default_workspace=1`, saved through the ORM
   (dev mode auto-exported `apps/lending/.../workspace/lending/lending.json`).
   The module-keyed fallback (`loan management`) is now gone; every lending
   entity resolves to the `Lending` workspace via `default_workspace_map`.

Files changed (committed locally, never pushed):
- `apps/pawn_shop/pawn_shop/pawn_shop/workspace/pawn/pawn.json` (branch `develop`)
- `apps/jewellery_management/jewellery_management/fixtures/workspace.json`
  (branch `opencode/v1-complete-erp`; exported via
  `bench --site library.local export-fixtures --app jewellery_management`)
- `apps/lending/lending/loan_management/workspace/lending/lending.json`
  (lending is a third-party app — this is a local patch; a future
  `bench get-app`/`git pull` of lending would drop it, but a normal
  `bench migrate` will not, because sync skips by timestamp.)

Verification: `bootinfo.app_data` now groups each workspace under its own app
(`jewellery_management`/`lending`/`pawn_shop`); `workspace_sidebar_item` has
`jewellery` (27), `lending` (20), `pawn` (20) items; all three icons validate
against the lucide sprite; `default_workspace_map` routes lending + pawn +
jewellery entities correctly. Desk routes `/app/pawn`, `/app/lending`,
`/app/jewellery` → HTTP 200. **Owner must hard-refresh the browser** (the boot
payload is cached per page load).

### 18.7 README FIRST (GitHub onboarding) — branch `Frappe Jewellery, Pawn & Lending Suite`
The repo `https://github.com/ShyberDev/jewellery_management` is prepared for a
public push on the suite branch **`Frappe Jewellery, Pawn & Lending Suite`**
(slug `Frappe-Jewellery-Pawn-Lending-Suite`). Two new top-level docs were added:

- **`README_FIRST.md`** — the full "read this first" onboarding guide: the exact
  daily commands (`sudo systemctl start mariadb` → `cd ~/frappe-bench` →
  `bench start` → `http://library.local:8000/desk`), the **tested system
  configuration** (Kali GNU/Linux Rolling, Python 3.14.6, Node v24.18.0, Bench
  5.31.0, Frappe/ERPNext 17.0.0-dev, MariaDB 11.8.8, Redis 8.0.6, ports
  8000/9000/13000/11000), install-from-scratch (Frappe framework first) vs
  adding to an existing bench, why a single "install file" is impossible and how
  to ship a complete VM/Docker/backup image for non-technical users, the §7
  sidebar/app-context fix (standard=1 + valid lucide icons + authored
  `sidebar_items`), the forced-sync workspace-file trap, feature lists for all
  three apps, combined accounting, advantages of the open-source stack, known
  issues, and backup/restore.
- **`README.md`** — short landing page that points to `README_FIRST.md` and
  gives the quick start.

**Push status (DONE, owner-authorized):** on the owner's explicit instruction,
`opencode/v1-complete-erp` was pushed to the new remote branch
**`Frappe-Jewellery-Pawn-Lending-Suite`** of
`https://github.com/ShyberDev/jewellery_management` (a **private** repo).
Remote branch HEAD `1cb50f75aeb6def6d67e4bbed5679d61da41c312` == local. The token
used for the push was **not** stored in git config, and the temporary askpass
script was deleted. **The owner should revoke/rotate that PAT** (it was shared in
chat).

**pawn_shop (DONE, owner-authorized):** the owner requested a repo named
"Jew_Pawn & Lending Suite". GitHub does not allow spaces/`&` in repo names, so it
was created as **`ShyberDev/Jew_Pawn-Lending-Suite`** (private, default branch
`develop`) and the `pawn_shop` app was pushed there (`develop` HEAD
`cd0ad7457ae8faafa8742fe8122b309070dbecfe`). Its `bench get-app` URL is now
`https://github.com/ShyberDev/Jew_Pawn-Lending-Suite --branch develop`.
**The owner should revoke/rotate this second PAT too.**

Both repos are private. To let others `bench get-app` them, either make them
public or grant collaborator access.

### 18.8 ONE-BUNDLE SUITE — `Jew_Pawn-Lending-Suite` becomes the single download
Owner decision: the whole suite must ship as **one repo, one command** so a new
user never installs Frappe, ERPNext and the apps separately (which caused
breakage). The `ShyberDev/Jew_Pawn-Lending-Suite` repo was therefore converted
from "pawn app only" into the **bundle**:

- Root layout: `install.sh`, `versions.env`, `README_FIRST.md`, `README.md`,
  `LICENSE`, `.gitignore`, `docs/AI_HANDOFF.md`, and `apps/` containing the three
  vendored apps (`jewellery_management`, `lending`, `pawn_shop`).
- The pawn app was moved from the repo root to `apps/pawn_shop` (git history
  preserved via `git mv`). `jewellery_management` and the **patched** `lending`
  (with the §18.6 sidebar fix) were vendored in.
- **`install.sh`** is the one command: it apt-installs system deps, installs the
  `bench` CLI, `bench init`s Frappe at the pinned `FRAPPE_COMMIT`, gets ERPNext at
  the pinned `ERPNEXT_COMMIT`, copies the vendored apps, creates the site and
  installs **erpnext → jewellery_management → lending → pawn_shop**, then
  `bench build`. It is idempotent and supports `--site`, `--bench-dir`,
  `--admin-password`, `--db-root-password`, `--non-interactive`,
  `--skip-system-deps`.
- **`versions.env`** pins the tested commits:
  Frappe `8a43de00d7f1e304598c910f0aa35aa384d474d7` (develop),
  ERPNext `8c24c5bd68aa6fd6db155c46fb6f05e201cc6d69` (develop). Frappe/ERPNext are
  ~500 MB each and change daily, so they are **fetched at install time** rather
  than vendored; the three custom/patched apps **are** vendored, so the bundle is
  self-contained for everything that is ours.
- Bundle `develop` HEAD after the conversion: **`f892615`** (push
  `4a09d40..f892615`). The `jewellery_management` README/README_FIRST were updated
  to point at the bundle as the recommended install path.

**Remaining / future:** a prebuilt Docker/VM image is still the easiest handover
for a fully non-technical user (§12 of `README_FIRST.md`); the bundle's
`install.sh` is the current easy path. Both repos remain private.

### 18.9 Mobile sync (Phase 1) + Google Drive backup + workspace orphan-cleanup fix

**A. CRITICAL FIX — `bench migrate` deleted the Jewellery workspace.**
Root cause found by reading `frappe/model/sync.py`:
`remove_orphan_entities()` runs on every migrate and deletes any **public
Workspace with an `app` set that has no matching `*.json` under that app's
`workspace/` folder** (`create_entity_file_map` globs `{app_path}/**/workspace/**/*.json`).
The Jewellery workspace shipped **only as a fixture**
(`jewellery_management/fixtures/workspace.json`), so migrate wiped it → desk
sidebar broke again. Lending and Pawn survived because they are real app files.
Fix: added the workspace as an app file at
`jewellery_management/jewellery_management/jewellery_management/workspace/jewellery/jewellery.json`
(same content as the fixture). Re-imported, then ran migrate **twice** — it now
survives. Verified `/app/jewellery`, `/app/lending`, `/app/pawn`, `/desk` all
HTTP 200, and boot `workspace_sidebar_item` present (jewellery 27, lending 20,
pawn 20). **Rule for the future: never ship a workspace only as a fixture.**

**B. Mobile sync Phase 1 (server) — DONE.** Owner chose a **native Android
(Flutter)** app (not a PWA, not the third-party ERPExperts app, which only
"auto-reconnects" and has no real offline two-way sync). The server half now
ships in `apps/pawn_shop/pawn_shop/api/sync.py`:
- DocTypes `Sync Device`, `Sync ID Map` (client_uuid → server name, unique),
  `Sync Log`.
- `register_device` / `status` / `pull` (delta, full docs incl. child tables) /
  `push` (idempotent by `client_uuid`, permission-checked, per-mutation
  savepoints).
- Registry of sync-enabled DocTypes (pawn + khatabook + jewellery).
- Test `pawn_shop.tests.test_sync_api.run` — verified: register, create,
  idempotent re-push (same name, count 1), transaction create, delta pull, update
  by client_uuid, non-registry DocType rejected.
Design doc: `docs/MOBILE_SYNC_DESIGN.md` (§11 = endpoint reference).

**C. Google Drive backup (disaster recovery).** New `backup-to-gdrive.sh` (bench
backup --with-files → rclone → Drive, retention, optional crypt) and
`docs/BACKUP_AND_RECOVERY.md` (rclone setup, encryption, cron, restore runbook).
Rationale recorded: **Drive = backup/DR, not live two-way sync** (no
transactions/conflict resolution). Not yet scheduled — owner runs it once + adds
cron.

Commits: jewellery `534de5c`, pawn `cd9d6e2`, bundle (this commit). Both repos
remain **public**.

### 18.10 Mobile app (Phase 2) — native Android / Flutter, offline-first

**Owner decisions:** native Android (Flutter), **fully offline**, **photos in v1**,
and Flutter is to stay installed on this machine.

**Toolchain installed without sudo, under `~/development/`:** Flutter 3.47.5
(Dart 3.13.4), Android cmdline-tools + `platforms;android-36` +
`build-tools;36.0.0` + platform-tools, and Temurin **JDK 17** (the system has
Java 25, which Android's Gradle plugin rejects). `flutter doctor` is green for
Flutter + the Android toolchain. Setup scripts kept for reuse:
`~/development/setup_downloads.sh`, `~/development/setup_android_sdk.sh`.

**Project:** `mobile/jewellery_suite/` (Flutter, org `com.shyberdev`,
Android-only) plus `mobile/build-apk.sh` and `mobile/README.md`. `mobile/` is not
touched by `update-bundle.sh` (that only syncs `apps/*`).

**Architecture**
- `lib/data/local_db.dart` — SQLite tables mirroring server field names:
  customers, villages, pawn_loans, pawn_items, pawn_releases, khatabook_loans,
  khatabook_collections, khatabook_refinances, `outbox` (pending mutations),
  `photo_queue`.
- `lib/data/api_client.dart` — Frappe `sid`-cookie login, JSON `syncCall` for
  `pawn_shop.api.sync.*`, multipart `upload_file`.
- `lib/data/sync_service.dart` — register device → push (batch, idempotent) →
  upload queued photos → pull delta and upsert by `server_name` (child `items`
  replaced). `server doctype → table` map.
- `lib/state/app_state.dart` — session, save helpers (`saveEntity`,
  `savePawnLoan`, `savePhoto`), dashboard aggregates, sync orchestration.
- `lib/util/format.dart` — rounding contract mirrored from the server (money
  ceil 2dp, weights round3 half-up, simple interest).
- `lib/ui/` — Login, Home, Customers, Pawn (intake + release), Khatabook (loan +
  collect + refinance), Sync.

**Server:** no changes — reuses the Phase 1 `pawn_shop.api.sync` endpoints.
Confirmed `use_json_request_body = True` is compatible: `frappe/app.py::make_form_dict`
parses JSON bodies natively (`request.is_json`).

**Verification:** `flutter analyze` = **0 errors, 0 warnings** (16 info:
deprecated `DropdownButtonFormField.value` + context-across-async). Unit test
`test/widget_test.dart`. Release APK built with `flutter build apk --release`.

**Not built yet:** jewellery-sales + lending screens, background/periodic sync, a
conflict-resolution UI, per-device role restrictions.

### 18.11 Mobile flow ownership + Pawn Release settlement fix

**Who updates the loan?** The server controllers already mutate the parent loan
on submit, so the app must **not** push a second, competing loan update:

- `PawnRelease.on_submit` → adds `total_paid` to `amount_paid`, closes if settled.
- `KhatabookCollection.on_submit` → allocates the payment oldest-first, saves the loan.
- `KhatabookRefinance.on_submit` → **creates the new Khatabook Loan itself** and
  closes the old one.

Client changes (`lib/ui/pawn_screen.dart`, `lib/ui/khatabook_screen.dart`): create
only the transaction document; reflect the parent loan's new state locally with
`dirty = 0` so it is never queued. For refinance the client no longer creates a
new local loan or sends `new_loan` — it just marks the old loan Closed locally and
lets the next pull materialise the server-created replacement.

**Link resolution before push** (`lib/data/sync_service.dart`): a release /
collection / refinance may reference a loan that was created offline and has no
`server_name` yet. `_toMutation` is now `async` and resolves link fields from the
local `server_name` for:

| DocType | link field(s) |
|---|---|
| Pawn Release | `pawn_loan` |
| Khatabook Collection | `khatabook_loan` |
| Khatabook Refinance | `khatabook_loan` |

**Retry path:** `LocalDb.retryFailed()` resets outbox rows `status='error'` →
`'pending'`; exposed via `AppState.retryFailed()` and a **"Retry failed changes"**
button on the Sync screen. This covers the case where a link target had not synced
yet on an earlier attempt.

**Pawn Release settlement (server bug fix):** interest accrues by the day
(`days/30`), so a loan's stored `balance` is stale if it was last saved on an
earlier day. The old `PawnRelease.validate` compared `total_paid` against that
stale value, so a full settlement on a later day could be rejected or leave a
residual. `pawn_release.py` now recomputes the loan against `release_date`
(status `Released`) in both `validate` and `on_submit` before comparing/closing,
and `on_cancel` re-opens the loan. Verified by
`pawn_shop.tests.test_pawn_release.run`:

```
bench --site library.local execute pawn_shop.tests.test_pawn_release.run
{"settlement_total": 10450.0, "overpay_rejected": true,
 "after_status": "Released", "after_balance": 0.0, "passed": true}
```

**Toolchain note (build):** Gradle's own wrapper downloader timed out following the
GitHub redirect, so Gradle 9.3.1 was pre-seeded into the wrapper cache with `curl`.
The daemon then OOM-killed on this 7.6 GiB machine because Flutter's template sets
`org.gradle.jvmargs=-Xmx8G`; lowered to `-Xmx2G` (metaspace 1G, workers 2, no
parallel) in `mobile/jewellery_suite/android/gradle.properties`. The release APK
then built successfully: `app-release.apk` (54.3 MB), copied by `build-apk.sh` to
`mobile/jewellery_suite-release.apk` (git-ignored).
