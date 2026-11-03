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
reports with a package-free six-month chart. The workflow boxes below are
**phone-acceptance** checks and stay open until the consolidated phone pass.

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

### Sales

-   [ ] Gold invoice with multiple items.
-   [ ] KDM sale: 10 g + 10% wastage at ₹15,000 + ₹1,000 making = ₹1,66,000.
-   [ ] Non-KDM sale: 10 g at ₹15,000 + ₹1,000 making = ₹1,51,000.
-   [ ] Non-KDM price stays ₹1,51,000 at 60%, 80% and 85% actual purity.
-   [ ] Silver sale uses 100% silver rate.
-   [ ] Discount omitted defaults to zero.
-   [ ] Discount changes final amount and profit correctly.
-   [ ] Manually allocate a payment across invoices.
-   [ ] Record unallocated advance.
-   [ ] Old-metal voucher/credit/stock receipt counted once.
-   [ ] Late fee is manual only.
-   [ ] Full and partial returns preserve original invoice.

### Purchases

-   [ ] Draft does not change stock.
-   [ ] Confirmed receipt changes stock once.
-   [ ] Test percentage and fixed-weight making separately.
-   [ ] Prevent both making methods on one item.
-   [ ] Test item-specific and shared expenses.

### Worker/manufacturing

-   [ ] Opening gold and cash balances.
-   [ ] Independent cash transaction.
-   [ ] Independent gold transaction with manually entered rate.
-   [ ] Transaction without a rate when no conversion is needed.
-   [ ] Order-linked worker transaction.
-   [ ] Gold issue decreases shop stock and increases worker reserve.
-   [ ] Return weight and retained reserve recorded.
-   [ ] Difference suggested but not posted without confirmation.
-   [ ] Partial cash and metal settlements.
-   [ ] Negative cash balance carries forward.
-   [ ] Daily rate change does not rewrite worker transactions.
-   [ ] Estimated and actual item cost/profit shown separately.
-   [ ] Independent worker purchase not assigned to item cost unless
    linked/allocated.

### Rates/reports

-   [ ] Graph reflects saved daily gold rates.
-   [ ] Editing a current rate does not change historical snapshots.
-   [ ] Check date/year filters and missing dates.
-   [ ] Reconcile shop, WIP and worker reserve stock.
-   [ ] Reconcile cash receipts/payments to ledger.
-   [ ] Stock valuation uses fine grams × the latest saved rate, never a market feed.
-   [ ] Supplier payable = purchases − purchase payments; customer sales stay out.
-   [ ] Document search and type/metal/status chips narrow the same list they describe.
-   [ ] Six-month chart excludes orders and cancelled documents.
-   [ ] Reports distinguish estimated from final values.

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
