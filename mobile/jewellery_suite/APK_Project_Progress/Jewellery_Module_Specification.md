# Jewellery Module --- Final Specification (Pre-Implementation)

**Project area:** `APK_Project_Progress/Jewellery_Module/`\
**Status:** Specification baseline approved. The **jewellery feature batch is
code-complete (2026-11-03, schema v20)** and unit-tested; a consolidated phone
pass is still pending. Built: the calculation engine, rate history,
sale/purchase/order documents, payments, old-metal vouchers and register,
stock movements, the **Customer Credit Book** (sales ledger + receipts), the
**Supplier Payable Book** (purchase ledger + payments), customer orders with
delivery, worker ledgers/orders, linked returns, stock valuation and on-screen
reports with a package-free six-month chart. The core (sale/purchase/old
metal/payments/stock) was phone-checked on v1.2.8; the new batch has not been
installed yet. PDF/Excel export remains blocked by unavailable packages.\
**Purpose:** Define separate screens and shared business rules for
sales, purchases, customer orders, worker orders and settlements, stock,
calculations, and reports.

## 1. Decisions confirmed by the business owner

1.  **Purchase purity/payment:** Use the owner's selected formula:
    `Item Weight × (Item Purity % + agreed making-charge %) ÷ 100 × 100%-purity metal rate`.
    This is the currently selected business rule, not a general
    jewellery-industry assumption.
2.  **Making charges:** Support either a percentage or a fixed weight,
    selected per transaction/order. The selected mode and value must be
    stored.
3.  **Worker costing:** Show both order-date estimated cost/profit and
    actual settlement cost/profit.
4.  **Customer colour:** Green when cumulative customer collections
    exceed item actual cost; light green at exact break-even; red when
    collections are below actual cost; grey for
    inactive/cancelled/non-applicable accounts. Outstanding balance
    remains separately visible.
5.  **Late fees:** Manual entry only; do not auto-generate fees.
6.  **Worker balances:** Maintain cash and metal balances separately and
    optionally show a rupee-equivalent summary at a selected rate.
7.  **Inventory:** Track raw gold/silver, finished jewellery,
    work-in-progress/customer orders, and metal reserved with workers
    separately.
8.  **Old-metal exchange:** Create a separate old-metal voucher linked
    to the sales invoice and reflect the accepted value as an invoice
    deduction, without counting the metal twice.
9.  **Invoice identifiers:** Every record gets a unique immutable
    internal ID and a readable business document number. Linked
    customer/worker orders share the same parent order reference while
    individual transactions retain unique IDs.
10. **Retail sale pricing is not purchase pricing.** A sale/order line is
    priced by the weight the customer buys, not by the item's purity:
    - **KDM:** `(net weight + wastage%) × rate + flat making charge`.
      Example: 10 g, 10% wastage, ₹15,000/g, ₹1,000 making →
      11 g × ₹15,000 = ₹1,65,000 + ₹1,000 = **₹1,66,000**. Net weight
      stays 10 g.
    - **Non-KDM:** `net weight × rate + flat making charge`. Example:
      10 g × ₹15,000 = ₹1,50,000 + ₹1,000 = **₹1,51,000**.
    - The item's **actual purity** (60%, 80%, 85%, …) is recorded only to
      derive fine metal content and compare the sale with the **actual
      cost to the shop** for profit/loss. It must never change the retail
      selling price.
    - A purchase keeps the owner's raw-metal formula:
      `weight × purity% × rate` plus the supplier's making mode.
    - Existing pre-v20 sale rows keep `billing_basis = raw` so their
      historical totals are never recalculated.

## 2. Proposed folder and screen structure

``` text
APK_Project_Progress/
└── Jewellery_Module/
    ├── Jewellery_Module_Specification.md
    ├── Calculations_and_Doubts_and_Questions.md
    ├── 01_Sales/
    │   ├── Sales_Gold.md
    │   ├── Sales_Silver.md
    │   └── Customers_on_Sales_Credit.md
    ├── 02_Purchases/
    │   ├── Purchase_Gold.md
    │   └── Purchase_Silver.md
    ├── 03_Jewellery_Orders/
    │   ├── Gold_Jewellery_Order.md
    │   └── Silver_Jewellery_Order.md
    ├── 04_Workers/
    │   ├── Worker_Order_Details.md
    │   ├── Worker_Transactions.md
    │   └── Worker_Cost_Profit_Analysis.md
    ├── 05_Calculations/
    ├── 06_Reports/
    └── 07_Doubts_and_Questions/
```

The above is the planned documentation layout. This package supplies the
two requested baseline documents; the other per-screen files are planned
artifacts, not falsely claimed as already created.

## 3. Main navigation / distinct screens

### 3.1 Sales

-   Gold Sales: KDM and non-KDM item handling. **Built:** each line has a
    **KDM / Non-KDM** choice. KDM bills `net + wastage%`; Non-KDM bills
    net weight. Both add a flat rupee making charge. The form shows the
    billing weight and the rupee breakdown live, and records actual purity
    and an optional **cost to shop** for profit/loss.
-   Silver Sales: normal and special silver item handling. **Built** on the
    same retail form with the silver rate and flat making.
-   Customer Credit / Customer Ledger. **Built:** the Credit Book groups
    sale invoices by customer name (case-insensitive) and shows billed,
    received and outstanding. Each customer opens a ledger with sale debits,
    receipt credits, payment mode and running balance. A receipt can be
    posted from the ledger; a purchase payment posts to the cashbook as OUT.
    Purchases (supplier payables) never appear in the customer book. v1
    groups by name, so two customers with the same name merge until the
    customer-table link is added.
-   Sales invoice list with search/filter by date, invoice number,
    customer, metal, payment status, and profit-recovery status. **Built**
    as the dashboard document list, with search on doc no / party / notes
    and chips for document type, metal and payment status; orders are kept
    out of the sale list.
-   Each sale supports multiple item rows, item weight,
    metal/purity/rate, making-charge mode where applicable, additional
    costs, discount, payments, old-metal exchange, and notes. **Built**:
    multi-line entry, KDM/Non-KDM, wastage %, flat making ₹, actual purity
    %, cost-to-shop ₹, additional ₹, discount, old metal and notes.
-   **Sale and purchase are deliberately different forms.** The sale form
    shows KDM/Non-KDM, wastage and retail billing weight; the purchase form
    shows supplier making modes and purity-based raw metal. This prevents a
    sale being entered with purchase-style purity pricing.

### 3.2 Purchases

-   Gold Purchase and Silver Purchase are distinct screens with a shared
    form pattern.
-   Supplier details, purchase date, metal/category, item description,
    gross/item weight, purity, making-charge mode/value, pure-metal
    rate, additional charges, total amount, payment details, and
    outstanding supplier balance.
-   Purchase records create stock movements only when the material is
    received/confirmed; drafts must not change stock.

### 3.3 Customer jewellery orders

**Built (code complete, phone pass pending):** orders reuse
`jewellery_invoices` with `doc_type = ORDER`, the same items/payments tables
and new delivery fields. A new order is **Pending**; it can be marked
**Ready**, **Cancelled** or **Delivered**. Orders never move stock until
delivery, when the delivered net weight leaves finished stock once. Retail
KDM/Non-KDM pricing is captured at order time, and the order-date rate snapshot
is preserved.

-   Separate Gold Order and Silver Order screens.
-   Order slip fields: readable order number, order date, promised
    delivery date, customer, mobile, address, metal rate captured at
    order time, item description, one or more item rows, ordered weight,
    making-charge mode/value, additional charges
    (e.g. HUID/hallmark/certificates/stones), item total, discount,
    advance, balance, photos and slip photo.
-   Delivery fields: ordered weight, actual delivered gross weight,
    stone/pearl weight if any, net weight, difference weight, extra
    amount due or refund, amount actually collected/refunded, delivery
    date and final status.
-   Maintain an amount ledger for each order. Advance is a payment
    transaction, not a second discount.
-   Preserve the order-date rate snapshot even when rates later change.

### 3.4 Worker orders and settlements

**Built (code complete, phone pass pending):** a worker list opens a cash/gold
ledger and worker-order list. Cash and metal movements are signed assets;
positive cash means the shop paid the worker, positive gold means the shop
issued metal. Worker-order delivery receives finished stock. Deleting a
movement removes its stock movement and cashbook reference.

-   Worker order is linked to the same parent jewellery-order reference;
    worker order/settlement transactions each have unique IDs.
-   Record worker, order date, expected delivery date, actual delivery
    date, item/photo, metal, category, ordered weight, delivered gross
    weight, stone weight, net weight, making-charge mode/value, agreed
    additional costs, cash paid, metal paid, and remaining cash/metal
    obligations.
-   Support multiple partial settlements, mixed cash and metal
    settlement, advance cash, advance metal, and reserve balances.
-   A worker may hold business cash or metal for future work. Show this
    as a separate asset/reserve position, not as a payment obligation or
    stock physically in the shop.
-   Record the settlement rate and date for every metal/cash conversion
    or agreement that uses a rate.

### 3.5 Customer and supplier ledgers

-   Customer profile: photo; invoice/order numbers and dates; customer
    name; relationship field (S/o, W/o, D/o, H/o); mobile; village;
    address; outstanding balance; transaction history; payment modes;
    manual late-fee entries.
-   Individual customer ledger shows date, transaction type,
    debit/credit direction, amount, payment mode (cash/UPI/bank/other),
    reference number, notes, and running balance.
-   Supplier ledger similarly tracks purchases, payments, credit
    notes/returns, and outstanding balance. **Built:** **Supplier Payables**
    groups purchases by supplier name, shows billed/paid/outstanding, and
    opens a ledger with purchases as credits and purchase payments as debits.
    **Pay supplier** posts cash **OUT**; customer sales never appear in this
    book.
-   Never overwrite old ledger rows silently. Corrections should be
    traceable reversal/adjustment entries.

### 3.6 Inventory

Maintain separate quantities for: - Raw gold and raw silver, with
purity/fineness metadata. - Finished gold and silver jewellery/items. -
Items reserved for a customer order / work in progress. - Gold/silver
held by each worker as business reserve. - Old metal received through
exchange, with voucher, measured weight, assessed purity, and assessed
value. - Stock movements: purchase receipt, sale/delivery, issue to
worker, worker return/delivery, reserve transfer, customer exchange,
return, correction/adjustment. - Every movement must link to a source
transaction and include quantity, unit, date, metal/category, and
reason.

### 3.7 Reports

-   Daily/monthly sales and purchases by gold/silver.
-   Cashbook and bank/UPI collection/payment summary.
-   Customer outstanding and ageing; customers who are overdue based on
    manually entered due dates, if due dates are used.
-   Supplier outstanding.
-   Worker-wise cash payable/advance, metal payable/reserve, and
    settlement history.
-   Raw/finished/in-worker stock position and stock movement history.
    **Built:** Reports shows raw/finished/old grams per metal and a **stock
    valuation** at the latest saved pure rate (fine grams × rate; old metal
    included as an asset).
-   Order pipeline: pending, in production, ready, delivered, cancelled.
-   Estimated vs final profit by invoice/order and by period.
-   Discounts, manual late fees, additional costs, old-metal exchanges,
    returns, and adjustments.
-   **Built chart:** a package-free **Sales vs purchases · last 6 months**
    grouped bar chart, fed by invoice totals and excluding orders/cancelled
    documents. The six-month view is independent of the Day/Month/All money
    range chips.
-   Reports must state the chosen date range and whether figures are
    estimates or finalised.

## 4. Identifier and linking rules

-   Internal IDs are unique and immutable, e.g. UUID-style IDs; they are
    not shown as the primary customer-facing number.
-   Human-readable document numbers include a date, document type, and
    sequence. The owner examples include `Inv021126PUR`, `Inv021126Sal`,
    and order style `InvO021126A`.
-   Final exact format is still a configuration decision. A suggested
    consistent format is `PUR-20261102-0001`, `SAL-20261102-0001`,
    `ORD-20261102-0001`, and `OLD-20261102-0001`; this is a proposal,
    not an already-approved format.
-   Never derive uniqueness from the date alone. Two same-type documents
    on the same date must still have different sequences.
-   Linked worker work must reference the parent customer order; its
    separate transaction entries retain their own internal IDs and
    readable transaction numbers.
-   Do not reuse or renumber an issued document number after
    cancellation. Mark the document cancelled and retain the audit
    trail.

## 5. Currency, weights and data-entry rules

-   Monetary amounts on bills are whole rupees; round payable/displayed
    bill totals upward to the next whole rupee as previously specified
    (e.g. ₹499.60 → ₹500). Keep calculation precision internally and
    record the rounding adjustment transparently.
-   Weight values retain decimal precision and display decimals,
    e.g. `10.230 g`; do not round weights to whole grams.
-   Store the rate, purity, making-charge mode/value, date, and formula
    inputs used at the time of each transaction. Historical records must
    not change when master rates or category settings change.
-   Input validation should reject negative weights/rates where invalid,
    missing required customer/supplier/worker links, and payments larger
    than allowed only where overpayment is not explicitly supported. If
    overpayment is allowed, represent it as customer credit/advance
    instead of hiding it.
-   All financial and stock-changing actions should be auditable, with
    created/modified timestamps and a clear reversal/adjustment
    mechanism.

## 6. Profit analysis and status semantics

Show these separately: 1. **Invoice/order sale value**: what was charged
to the customer. 2. **Customer collections**: cash/bank/UPI actually
received, excluding uncollected receivables. 3. **Metal/cost recovery
status**: collections compared with actual item cost, using the chosen
customer colour rule. 4. **Estimated profit**: sale value less estimated
cost using the order-date assumptions. 5. **Final profit**: final
recognised sale value less actual attributable costs after delivery,
settlement, extra weight, discounts, refunds, worker costs and other
applicable costs. 6. **Outstanding customer balance**: amount the
customer still owes, independently of the profit colour. 7. **Worker
position**: cash payable/advance and metal payable/reserve, kept in
separate units.

Customer colour is a recovery indicator, not a guarantee of
collectability and not a substitute for final profit reporting. Under
the selected rule: - Green: collections \> actual item cost. - Light
green: collections = actual item cost. - Red: collections \< actual item
cost. - Grey: inactive/cancelled/non-applicable account. A cancelled
invoice should be excluded from ordinary profit and stock totals after
its reversal entries are applied.

## 7. Payment and old-metal rules

-   Every receipt/payment is its own transaction, with date, amount,
    mode, reference, and linked invoice/order/customer/worker.
-   Cash, UPI, bank transfer, and other modes are distinguishable in
    ledgers and reports.
-   Late fee is entered manually and linked to the relevant customer
    account/invoice. It is a separate line/transaction and must not
    silently alter the original item price or item cost.
-   Old-metal voucher records old metal separately and links to the
    sales invoice. The invoice deduction and old-metal inventory receipt
    are two sides of one exchange workflow; do not duplicate the
    financial credit or stock quantity.
-   Refunds and returns create linked reversal/return transactions
    rather than editing the original sale.

## 8. Implementation boundaries

-   This document stays the business specification. The code that now
    implements the feature batch is listed in §9; anything not listed there
    is still unimplemented.
-   **No phone verification is claimed for the 2026-11-03 batch.** It is
    written, analyzed and unit-tested; the consolidated phone pass and APK
    install are still pending.
-   **Returns currently credit** `net weight × actual purity% × sale rate`,
    not the retail KDM/non-KDM selling price. The original sale is never
    rewritten. Whether a return should also reverse wastage/making is an open
    business question for the phone pass.
-   **Built in the 2026-11-03 completion round:** Supplier Payables
    (list + ledger + pay-supplier), stock valuation in Reports, document
    search/type/metal/payment-status filters, a package-free six-month
    sales/purchases chart, and the pawn due-date filter (#047).
-   **Not built / blocked:** PDF/Excel export (packages unavailable
    offline), encrypted DB, biometric unlock, and a real SMS/e-mail OTP
    gateway. Reports are on-screen + CSV (main Reports) only.
-   **Known v1 limitation:** the Credit Book groups by customer name
    (case-insensitive), not by a customer-table link, so two customers with
    the same name merge.

## 9. Implemented in the 2026-11-03 batch (schema v20)

| Layer | File | What it does |
|---|---|---|
| Calculations | `lib/util/jewellery_math.dart` | Raw purchase pricing (`weight × purity% × rate`), KDM retail pricing (`(net + wastage%) × rate + flat making`), non-KDM retail pricing (`net × rate + flat making`), actual fine metal, percentage/fixed-weight/flat purchase making, sales discount, worker return suggestion, old metal, shared-expense allocation, whole-rupee rounding, recovery colour, outstanding, worker cash↔metal conversion, payment allocation, estimated vs final profit, return netting. `test/jewellery_math_test.dart` — **42 cases, C01–C15**. |
| Schema | `lib/data/migration_v18.dart`, `v19.dart`, `v20.dart` | v18: rates, invoices/items, payments, old metal, stock movements. v19: order delivery fields, worker transactions/orders, linked returns. v20: `billing_basis`, `wastage_pct`, `making_charge`, `fine_weight`; old rows default to `raw`. All tracked by backups. |
| Store | `lib/data/jewellery_store.dart` | Rates per day, `SAL-/PUR-/ORD-YYYYMMDD-####` numbering, retail vs raw line totals, one old-metal deduction and stored round-off, payment re-derivation, delete cascade, stock totals/movements and fine-gram **stock valuation** at the latest saved rate, document search/type/metal/payment-status filters, customer credit positions and ledgers, **supplier payables and purchase ledgers**, old-metal register, orders/status/delivery, worker cash/gold ledgers and worker orders, linked returns with over-return guard, report totals, monthly chart series and profit. `test/jewellery_store_test.dart` (22) + `test/jewellery_credit_book_test.dart` (8) + `test/jewellery_supplier_test.dart` (6) + `test/jewellery_operations_test.dart` (15). |
| Cashbook | `lib/state/app_state.dart` | Sale receipt → `JEWELLERY_SALE` IN; purchase payment → `JEWELLERY_PURCHASE` OUT; order advance → `JEWELLERY_ORDER` IN; later receipt → `JEWELLERY_COLLECT` IN; return refund → OUT; worker cash follows its sign. Deleting a document removes its cash entries and stock together. |
| Screens | `lib/features/jewellery/screens/` | Dashboard with **Customer Credit Book, Supplier Payables**, Orders, Workers, Old Metal, Returns and Reports tiles plus search/filter chips; **separate sale/order and purchase forms** (KDM/Non-KDM, wastage, flat making, actual purity, cost-to-shop); supplier payable list/ledger with pay-supplier; old-metal register; order list/detail with status + delivery; worker list/ledger/transaction/order; returns list/form; Reports with stock valuation and a package-free six-month bar chart; shared invoice detail sheet with retail/raw breakdowns. Reached from **Home → Jewellery**. |

**Still open for the phone pass:** create a KDM sale (₹1,66,000), a non-KDM
sale (₹1,51,000 at 60/80/85% actual purity), an order and delivery, a worker
cash/gold movement, a linked return, check that purchase cash is OUT/red
while customer receipts are IN/green, open **Supplier Payables** and pay a
purchase, check **stock valuation** against saved rates, exercise the
document search/type/metal/status filters, and view the six-month chart.
