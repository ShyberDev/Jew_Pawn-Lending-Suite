# Jewellery Remaining Features — Implementation Plan

> **For agentic workers:** execute this plan natively in the current session. Do not phone-test until all tasks are complete.

**Goal:** Finish the jewellery module: correct purchase cash direction, show making/wastage in metal weight, and add Old Metal, Customer Orders, Worker Transactions, Returns, multi-line entry and on-screen reports.

**Architecture:** Keep the existing document model (`jewellery_invoices` + items + payments + stock movements). Add schema v19 for order delivery fields, worker orders/transactions and returns. All money and stock writes stay in `JewelleryStore`; `AppState` owns cashbook hooks. Screens only read through the store.

**Tech Stack:** Flutter, Provider, sqflite, existing `JewelleryMath` formulas.

**Spec:** `APK_Project_Progress/SPEC_JEWELLERY.md`, `APK_Project_Progress/CALCULATIONS.md`.

## Global Constraints

- No schema, money-maths, auth or navigation changes outside this plan.
- Whole-rupee invoice totals; weights keep 3-decimal precision.
- A sale is cash IN (green); a purchase is cash OUT (red). Direction follows the document type, never the screen that opened it.
- Historical rates stay snapshotted on each item.
- Old metal is credited once; returns never edit the original invoice.
- Worker reserve is an asset position, never a loss or payable.
- Every new screen is reachable from Home → Jewellery.
- `flutter analyze` clean; all tests pass. No phone verification in this pass.

---

### Task 1: Schema v19

**Files:** create `lib/data/migration_v19.dart`; modify `lib/data/local_db.dart`, `lib/data/backup_service.dart`.

- Add nullable order/delivery columns to `jewellery_invoices`.
- Create `jewellery_worker_orders`, `jewellery_worker_txns`, `jewellery_returns`, `jewellery_return_items` with client_uuid, dirty and updated_at.
- Open the DB at v19; fresh installs call v19 after v18.
- Register all four tables in `BackupService.trackedTables`.

### Task 2: Store — old metal, orders, workers, returns, reports

**Files:** modify `lib/data/jewellery_store.dart`; test `test/jewellery_operations_test.dart`.

- Add `wastageWeight` and `totalEquivalentWeight` to `JewelleryLine` (display only; existing totals unchanged).
- Old metal: `oldMetalVouchers({search, metal})`, `oldMetalTotals()`.
- Orders: extend `saveInvoice` with `promisedDate`, `mobile`, `address`, `photoPath`, `slipPhotoPath`; add `orders()`, `orderStatusSummary()`, `deliverOrder()`, `updateOrderStatus()`.
- Workers: `workerPositions()`, `workerTransactions(name)`, `saveWorkerTransaction()`, `workerOrders()`, `saveWorkerOrder()`, `deliverWorkerOrder()`.
- Returns: `saveReturn()`, `returns()`, `returnItems(uuid)`, `returnsForInvoice()`, `returnsForCustomer()`, `deleteReturn()`.
- Credit netting: customer totals, open invoices and ledger subtract net return credit `(total - refund)`; original invoice rows stay untouched.
- Reports: `reportTotals(from, to)`, `orderPipeline()`, `profitSummary(from, to)`.

### Task 3: AppState cash hooks

**Files:** modify `lib/state/app_state.dart`; test `test/jewellery_operations_test.dart`.

- `addJewelleryPayment` reads the invoice doc type: PURCHASE → OUT `JEWELLERY_PURCHASE`; ORDER → IN `JEWELLERY_ORDER`; SALE → IN `JEWELLERY_COLLECT`.
- Initial purchase payment at save is OUT.
- Add `saveJewelleryOrder`, `deliverJewelleryOrder`, `saveJewelleryWorkerTransaction`, `saveJewelleryReturn`, `deleteJewelleryReturn`.
- Extra order collection is IN; order refund/return refund is OUT; worker cash paid is OUT, worker cash returned is IN.

### Task 4: Wastage display + multi-line invoice form

**Files:** modify `lib/features/jewellery/screens/jewellery_invoice_screen.dart`, `lib/features/jewellery/widgets/jewellery_invoice_sheet.dart`.

- Refactor the form to a list of item lines with Add/Remove; each line keeps weight, purity, rate, making mode/value, additional and discount.
- Preview each line as: net weight, wastage weight (g), total equivalent weight × pure rate = metal + wastage amount.
- Rename making modes to Wastage %, Wastage weight (g), Making amount ₹.
- Fix purchase copy: “Paid now”, not “Amount received now”.
- Invoice sheet shows the same weight breakdown for every line.

### Task 5: Old Metal register

**Files:** create `lib/features/jewellery/screens/jewellery_old_metal_screen.dart`; modify dashboard.

- Summary: gold/silver equivalent grams and accepted value.
- Search by voucher/customer; metal filter; rows open the linked invoice sheet.

### Task 6: Customer Orders

**Files:** create `jewellery_orders_screen.dart`, `jewellery_order_screen.dart`, `jewellery_order_detail_screen.dart`; modify dashboard.

- Order form: customer, mobile, address, order date, promised date, metal, one or more lines, advance, notes.
- List with status/search filters and pipeline counts.
- Detail: items, payments, advance/balance; mark Ready/Cancelled; Deliver with actual gross, stone and net weights, extra amount, refund and delivery date.
- Delivery posts stock out once and keeps the order-date rate snapshot.

### Task 7: Worker Transactions

**Files:** create `jewellery_workers_screen.dart`, `jewellery_worker_screen.dart`, `jewellery_worker_order_screen.dart`; modify dashboard.

- Workers list shows cash reserve, gold reserve and last movement.
- Worker ledger shows every cash/gold movement with running positions.
- New transaction: cash paid/received, gold issued/returned, optional rate/purity, optional order link.
- Worker order form: parent customer order, worker, ordered weight, expected date, making/additional, notes; delivery records actual weights.

### Task 8: Returns

**Files:** create `jewellery_returns_screen.dart`, `jewellery_return_screen.dart`; modify invoice sheet and dashboard.

- Sale invoice sheet gets a Return action.
- Return form lists the original items with editable return weight, restock toggle, refund amount and date.
- Save posts stock in once (when restocked), cash OUT for the refund, and a linked credit in the customer ledger; original invoice is unchanged.

### Task 9: Reports + dashboard links

**Files:** create `jewellery_reports_screen.dart`; modify dashboard.

- Date range Day / Month / All.
- Sales, purchases, collections, returns, outstanding, old metal, stock, order pipeline, worker positions, estimated vs final profit.
- Dashboard tiles for Orders, Workers, Old Metal, Returns, Reports.

### Task 10: Verification and tracker

- `flutter analyze` → no issues.
- `TMPDIR=$PWD/.dart_tool/tmp flutter test` → all pass.
- Update `APK_Project_Progress/README.md` and the jewellery spec with CODE DONE status and the change log; no ✅ without a phone pass.
- Build the release APK only after the code and tests are green.
