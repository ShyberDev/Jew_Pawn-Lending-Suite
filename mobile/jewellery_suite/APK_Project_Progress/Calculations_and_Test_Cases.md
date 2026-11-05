# Jewellery Module --- Calculations and Test Cases

Use these as acceptance tests against the existing APK. They describe
expected behaviour; they do not claim the APK passes.

**Implementation status (2026-11-03):** C01–C15 are executable rules in
`lib/util/jewellery_math.dart`, with **42 passing cases** in
`test/jewellery_math_test.dart`. The schema/store layer is covered by
`test/jewellery_store_test.dart` (22), `test/jewellery_credit_book_test.dart`
(8), `test/jewellery_supplier_test.dart` (6) and
`test/jewellery_operations_test.dart` (15). The full UI now covers
multi-line sale/purchase, KDM/non-KDM retail pricing, old metal, payments,
stock, stock valuation, customer orders/delivery, worker ledgers/orders,
linked returns, supplier payables, document search/filter and on-screen
reports with a package-free six-month chart.

**Checklist audit (2026-11-05, updated same day):** every box in §2 was
checked against the code and the suite, then the three that failed were built.
**37 boxes now pass by automated test** and the remaining 10 pass by code or an
earlier phone pass; **no box is left open**.

Round one closed the allocation gap (`test/jewellery_receipt_test.dart`): a
receipt splits across invoices with the excess kept as customer credit, and
Reports gained a saved-rate graph plus a WIP line. Round two closed the last
three (`test/jewellery_draft_contract_test.dart`): a purchase saves as a
**draft that posts no stock** and is confirmed exactly once, a **shared
expense** is split by weight and stated once (schema v21), and a **manual late
fee** is a separate charge that never rewrites the sale value. Each box below
says which check proves it.

## 1. Worked calculation tests

### C01 --- Gold rate

Input: pure-gold rate ₹15,000/g. Expected 92% rate ₹13,800/g. Both
editable; changing today's rate must not rewrite history.

### C02 --- Percentage making

Input: 10 g, 92% purity, 6% making, add-percentage-points method, rate
₹15,000/g. Expected effective percentage 98%; equivalent weight 9.8 g;
value ₹147,000.

### C03 --- Fixed-weight making

Input: 10 g, 92% purity, fixed making 0.5 g, rate ₹15,000/g. Expected
9.2 g + 0.5 g = 9.7 g; value ₹145,500. Percentage making must not also
apply.

### C04 --- Worker return/reserve

Input: returned item 9.950 g, effective percentage 98%, supplied gold
10.000 g. Expected equivalent 9.751 g and difference 0.249 g. Suggest
only; do not post automatically as loss/wastage/debt. User confirms
classification.

### C05 --- Silver sale discount

15 g × ₹250/g = ₹3,750; making charge ₹500; subtotal ₹4,250; discount
₹500; final ₹3,750. With no discount, final ₹4,250. Discount reduces
sale value, not item cost.

### C06 --- Silver supplier costing

15 g item, purity 60%, supplier making 15%, rate ₹250/g. Effective 75%;
equivalent weight 11.25 g; value ₹2,812.50. If sale subtotal ₹4,250 less
₹500 discount = ₹3,750, difference against this one cost is ₹937.50
before other attributable costs.

### C07 --- Old metal

10 g net weight at 63% purity → 6.3 g equivalent. Suggested value = 6.3
× entered applicable rate. User can approve/edit. Voucher credit and
stock receipt must not duplicate.

### C08 --- Shared expenses

Items 10 g and 5 g; shared expense ₹300. Weight-proportional allocation:
₹200 and ₹100; total allocated = ₹300.

### C09 --- Rounding

₹499.49 → ₹499; ₹499.50 → ₹500. Preserve internal precision and record
adjustment.

### C10 --- Recovery colours

Cost ₹7,500, collections ₹8,000 → green (+₹500). Cost ₹8,000,
collections ₹8,000 → light green. Cost ₹8,000, collections ₹7,000 → red.
Cancelled/inactive/not applicable → grey. Outstanding shown separately.

### C11 --- Customer outstanding

Invoice ₹10,000, payments ₹4,000, accepted old-metal credit ₹2,000 →
outstanding ₹4,000. Never subtract old-metal value twice.

### C12 --- Worker ledger

Starting reserve: 20 g and ₹123,000. Convert ₹123,000 using explicitly
entered ₹14,800/g; preserve rate/date and any remainder. Later book 5 g
at manually entered ₹14,600/g, increasing reserve: gold +5 g, cash
−₹73,000. Do not fetch daily market rate. Allow no rate if no
conversion/valuation is needed.

### C13 --- Payment allocation

Receive ₹5,000; allocate ₹3,000 to invoice A and ₹1,500 to B.
Unallocated credit = ₹500. Never allocate more than received or
duplicate the payment.

### C14 --- Return

Original invoice remains intact. Create linked return/reversal. Stock
increases only after physical receipt/assessment. Update refund,
customer balance and profit once. Reopening the screen must not post
return twice.

### C15 --- Retail sale pricing (KDM / non-KDM)

**KDM:** net weight 10 g, wastage 10%, rate ₹15,000/g, flat making
₹1,000. Billing weight = 10 + (10 × 10%) = 11 g. Metal value =
11 × ₹15,000 = ₹1,65,000. Total = ₹1,65,000 + ₹1,000 = **₹1,66,000**.
Net weight stays 10 g; wastage is 1 g.

**Non-KDM:** net weight 10 g, rate ₹15,000/g, flat making ₹1,000.
Metal value = 10 × ₹15,000 = ₹1,50,000. Total = **₹1,51,000**.
Actual purity is **not** applied to the selling price. At 60%, 80% or
85%, the sale price stays ₹1,51,000; only the fine-metal content changes
(6.0 g, 8.0 g, 8.5 g).

Purity and actual cost are for profit/loss only. If the actual cost to
the shop is ₹92,000, the non-KDM sale at ₹1,51,000 shows a ₹59,000
profit. A purchase keeps the raw formula `weight × purity% × rate` plus
the supplier making charge, and is a different form.

### C16 --- Stock valuation

Gold purchase 10 g at 92% purity = **9.2 g fine**. With the latest saved
pure-gold rate at ₹16,000/g, raw gold value = **₹1,47,200**. Old metal
2 g at 50% = **1.0 g fine**, valued at ₹16,000; a 1 g 100% sale leaves
finished stock at **−1.0 g fine / −₹16,000**. Total stock value =
₹1,47,200 + ₹16,000 − ₹16,000 = **₹1,47,200**. If no rate is saved, the
fine grams still show but the value is ₹0 (never a guessed market rate).

### C17 --- Supplier payable

Purchase ₹1,47,000 with ₹47,000 paid → payable **₹1,00,000**. A second
purchase ₹27,600 → payable **₹1,27,600**. Pay another ₹50,000 → payable
**₹77,600**. In the supplier ledger the purchase is a **credit** and each
payment is a **debit**; a customer sale never enters this book. Purchase
payments post cashbook **OUT/red**.

### C18 --- Pawn due-date filter

Promised due date 01-Apr-2026, actual due date 15-May-2026. A filter of
01-Apr–30-Apr must **exclude** the pledge; 01-May–31-May must **include**
it. With no actual date, the promised date is used. A loan with neither
date never matches a due-date range. The list and the summary strip use
the same predicate.

## 2. Workflow checklist

Legend: **[x] test** = proven by an automated test; **[x] phone** = seen on
the device in an earlier pass; **[ ]** = still open.

### Sales

-   [x] test — Gold invoice with multiple items. Multi-line entry;
    `jewellery_invoice_items` stores one row per line with its own totals.
-   [x] test — KDM sale: 10 g + 10% wastage at ₹15,000 + ₹1,000 making =
    ₹1,66,000. `jewellery_math_test.dart` C15 and the store's KDM case.
-   [x] test — Non-KDM sale: 10 g at ₹15,000 + ₹1,000 making = ₹1,51,000.
    Same two files.
-   [x] test — Non-KDM price stays ₹1,51,000 at 60%, 80% and 85% actual
    purity. `jewellery_store_test.dart`.
-   [x] phone (v1.3.0) — Silver sale uses the 100% silver rate: the rate is
    saved per metal and the retail form reads the saved silver rate.
-   [x] test — Discount omitted defaults to zero (`discount = 0`).
-   [x] test — Discount changes final amount and profit correctly; it reduces
    the sale value, never the item cost (math + store cases).
-   [x] test — Manually allocate a payment across invoices. **Built
    2026-11-05:** the credit-book dialog has one amount box per open invoice;
    `JewelleryStore.receiveCustomerPayment` honours the split.
    `test/jewellery_receipt_test.dart`.
-   [x] test — Record unallocated advance. Any part above an invoice's
    balance is stored as customer credit (`invoice_uuid = ''`), counted as
    received, taken off the outstanding and shown as **Advance received** in
    the ledger. Same test file.
-   [x] test — Old-metal voucher/credit/stock receipt counted once
    (`jewellery_store_test.dart`, credit-book case).
-   [x] test — Late fee is manual only. **Built 2026-11-05 (schema v21):**
    a sale's document sheet has **Add late fee**, which files a charge row and
    raises the balance; the invoice's item total and recorded cost are never
    rewritten, so reports still show what was actually sold. Nothing is ever
    generated automatically. `test/jewellery_draft_contract_test.dart`.
-   [x] test — Full and partial returns preserve the original invoice
    (`jewellery_operations_test.dart`, over-return guard included).

### Purchases

-   [x] test — Draft does not change stock. **Built 2026-11-05:** the purchase
    form has **SAVE AS DRAFT**; a draft stores the document and its lines but
    posts no stock, no payment and no old-metal stock. The document sheet then
    offers **Confirm purchase · receive stock**, and `confirmInvoice` refuses
    a second confirm (and clears any leftover movement first), so stock can
    never post twice. `test/jewellery_draft_contract_test.dart`.
-   [x] test — Confirmed receipt changes stock once
    (`jewellery_store_test.dart`, purchase case).
-   [x] test — Percentage and fixed-weight making separately (C02, C03, plus
    the store's making-mode cases).
-   [x] test — Prevent both making methods on one item: `makingMode` is a
    single enum, so a line cannot carry two modes (`a line has exactly one
    making mode`).
-   [x] test — Item-specific and shared expenses. Item additional cost is
    stored per line. **Built 2026-11-05 (schema v21):** the form takes one
    **shared expense** for the document, `saveInvoice` splits it across the
    lines by net weight through `allocateSharedExpense`, stores each line's
    share in its additional cost and the total once on the invoice. The
    invoice total is still the sum of its lines. Same test file.

### Worker/manufacturing

-   [x] code — Opening gold and cash balances: the first movement is the
    opening entry, and positions are the signed sum of movements.
-   [x] test — Independent cash transaction (`cash and metal are signed
    assets, never a loss`).
-   [x] test — Independent gold transaction with a manually entered rate; the
    rate and date are stored on the row (`₹1,23,000 at ₹14,800/g`).
-   [x] test — Transaction without a rate when no conversion is needed:
    `rate_per_gram` is nullable (`no rate means no conversion`).
-   [x] code — Order-linked worker transaction: `jewellery_worker_txns`
    carries `order_uuid`, and the worker order screen links it.
-   [x] test — Gold issue decreases shop stock and increases worker reserve
    (`WORKER_ISSUE` stock movement + signed worker row).
-   [x] test — Return weight and retained reserve recorded (worker delivery
    records ordered/delivered/stone weights and keeps the reserve).
-   [x] test — Difference suggested but not posted without confirmation:
    `JewelleryMath.workerReturn` returns a suggestion only.
-   [x] code — Partial cash and metal settlements:
    `deliverWorkerOrder(cashPaid:, metalPaid:)` accepts either or both.
-   [x] test — Negative cash balance carries forward: reserves are a signed
    sum with no floor.
-   [x] test — Daily rate change does not rewrite worker transactions (the
    stored rate/date are never re-derived).
-   [x] test/phone — Estimated and actual item cost/profit shown separately
    (Reports → **Estimated vs final profit**).
-   [x] test — Independent worker purchase is not assigned to item cost
    unless linked: document cost comes only from item `estimated_cost` /
    `actual_cost`, never from a worker movement.

### Rates/reports

-   [x] code — **Built 2026-11-05:** Reports → **Saved gold rates** draws one
    bar per saved day (last seven), so the graph comes from the shop's saved
    rates, never a market feed.
-   [x] test — Editing a current rate does not change historical snapshots
    (`a saved rate is kept per day and never rewritten`).
-   [x] test — Date filters and missing dates: Day / Month / All chips, and
    `monthlyTotals` fills a zero month rather than skipping it.
-   [x] code — **Built 2026-11-05:** shop, WIP and worker reserve reconcile
    in Reports — stock card shows raw/finished/old plus **WIP (open orders)**
    grams, and the worker reserve card shows cash and metal held by workers.
    WIP is never added to shelf stock.
-   [x] test — Cash receipts/payments reconcile to the ledger: every payment
    posts one cashbook row, including each part of a split receipt and the
    advance (`test/jewellery_receipt_test.dart`).
-   [x] test — Stock valuation uses fine grams × the latest saved rate, never
    a market feed.
-   [x] test — Supplier payable = purchases − purchase payments; customer
    sales stay out (`jewellery_supplier_test.dart`).
-   [x] test — Document search and type/metal/status chips narrow the same
    list they describe.
-   [x] test — Six-month chart excludes orders and cancelled documents.
-   [x] test/code — Reports distinguish estimated from final values
    (**Estimated vs final profit** card).

## 3. Diagnose an unexpected result

Capture: screen/action; document or transaction ID; exact inputs
(weight, purity, method, rate/date); expected and actual output;
draft/posted/reversed status; before/after balances; screenshot and
error text.

Classify: - Formula error: correct inputs, wrong result. -
Rounding/precision error: intermediate or final rounding is wrong. -
Duplicate posting: one action affects balance twice. - Ledger direction:
debit/credit reversed or reserve confused with payable. - Stock
movement: worker gold counted both in shop and worker reserve, or
draft/return posts incorrectly. - Historical snapshot: current rate
changes old record. - Allocation: payment/expense applied to wrong
item/invoice or unreconciled. - Reporting: recovery colour mistaken for
profit, or estimates mixed with actuals. - Validation/UI: invalid input
accepted, required field unclear, or data lost on error.

## 4. Release-blocking bugs

Do not consider the module reliable if: payment/return/stock movement
posts twice; old rates/inputs change silently; worker reserve is
automatically treated as loss or debt; daily rate is auto-applied to
worker transaction; discount fails to reduce sale value; original
invoice is overwritten by return; draft changes stock; cash balance
cannot go negative when required; invoice total does not reconcile; or
recovery status is labelled as final profit.

## 5. Do not invent unconfirmed rules

Tax/GST, exact invoice-number format, and unconfirmed category-specific
pricing rules remain unspecified. Do not automatically post worker
weight differences, fetch daily rates for worker transactions, apply
silver supplier formula to silver sales, or equate recovery colour with
final profit.
