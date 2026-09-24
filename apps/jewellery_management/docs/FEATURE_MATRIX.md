# FEATURE MATRIX — Jewellery ERP industry research (2026-09-24)

Researched products:
Marg Jewellery, MMI Jwelly, Ornate, Online Munim, TallyPrime (jewellery),
Synergics (SEA), JewelSteps, Akrut Jewellery ERP, ERIONT / Jewellery Software
(gold-control class), GehnaERP. Plus comparative context looked at while
searching: MetaERP, JewelerPOS, Ornexa, Aurum, KaratOS, Jwellex, Auromine.

Purpose: a source-of-truth map of what these products configure, calculate and
link, and how each item maps to **jewellery_management** (built / building / V2 /
out of scope). So the next feature request can be answered from a table instead
of re-research.

Legend:
- ✅ BUILT    — implemented, fixture-versioned, sample-data verified in this app
- 🔨 BUILDING — agreed packet, being built next (see §3)
- ⏳ V2       — explicitly deferred by owner; do not build without instruction
- 🚫 OUT      — hardware/external service/out of owner's stated scope

-----------------------------------------------------------------------
## 1. WHAT THESE PRODUCTS SHARE (the industry consensus kernel)

Every researched product, regardless of vendor, contains:

| # | Capability | Marg | Jwelly | Ornate | O.Munim | Tally | Synergics | JewelSteps | Akrut | ERIONT | GehnaERP |
|---|------------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 1 | Daily gold/silver rate per purity + history | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2 | Weight-based billing (gross/net/wastage/making) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 3 | Karigar job work: issue metal → receive finished, wastage, labour | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 4 | Old gold exchange (deduction calc, setoff in bill) | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 5 | GST billing + GSTR-1/3B + e-invoice/e-way bill | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 6 | HUID / BIS hallmark registry, HUID on invoice | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ⚠️ | ✅ | ✅ | ✅ |
| 7 | Stock valuation by FIFO / Average / Current rate | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 8 | Schemes (gold saving / kitty / instalments) | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ⚠️ | ✅ | ⚠️ | ✅ |
| 9 | Girvi / gold loans (interest calc, due alerts) | ✅ | ✅ | ⚠️ | ✅ | 🚫 | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ✅ |
| 10 | CRM: customer history, reminders, loyalty | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ⚠️ | ⚠️ |
| 11 | Repairs / job-order tracking with status flow | ✅ | ✅ | ⚠️ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 12 | Multi-branch stock + consolidated reporting | ✅ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 13 | Barcode / RFID tagging + scale integration | ✅ | ✅ | ⚠️ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ |

## 2. KEY CALCULATIONS / CONFIGURATION USED BY THE PRODUCTS

C1. Billing: weight = net−else−gross; wastage % ⇒ chargeable weight;
     making charges (per gram / fixed / %); GST (gold 3% split CGST 1.5 +
     SGST 1.5 intra-state; IGST inter-state) applied on metal+making combined.

C2. Karigar: issue gross weight → receive net weight; wastage = issue − receive
     (per job, per karigar); labour paid on delivered **fine** weight × rate;
     karigar gold balance = issued − returned (grams).
     Marg/Ornate/Jwelly all warn when wastage exceeds allowance.

C3. Old gold: gross − stones/deduction = net; net × assay/estimate % = fine;
     credit = fine × rate; old gold accepted as part-payment in the sales bill;
     net cash due = bill total − old gold credit. (URD purchase → reverse
     charge in GST.)

C4. Valuation: FIFO / Average Rate / GP / Last Purchase / Current Rate.
     Realized profit = sale value − FIFO cost of metal consumed.
     Unrealized = remaining stock × (current rate − lot rate).

C5. Melt (refinery): expected fine = Σ input net × assay %; recovery % =
     actual fine ÷ expected; wastage/loss = expected − actual.

C6. GST data: GSTR-1 (B2B/B2C summary + HSN summary), GSTR-3B, ITC
     reconciliation vs GSTR-2A/2B, TCS on cash sales > ₹10L (1%; 5% no PAN),
     e-invoice IRN for B2B above threshold.

C7. Schemes: monthly instalments → maturity date → redemption against bill;
     incentives; passbook.

C8. Girvi: principal vs valuation, simple/compound interest, due date,
     reminder, maturity/lapse; separate party ledger.

## 3. MAPPING TO jewellery_management (what we will build)

### 3.1 Already built (✅)
- Rates per purity + date/time (Metal Rate, RATE- series) ✅
- Weight/purity inventory ledger (Jewellery Stock Transaction) ✅
- Order flow w/ advance, 5 frozen statuses, kanban ✅
- Karigar: order-level worker assignment, worker other charges, settlement
  ledger (gold grams + cash separate), worker balances ✅
- Old gold: Receipt (estimate vs assay), Melt (expected vs actual variance),
  sale exchange-credit ✅
- HUID registry (status life-cycle, Register report) ✅
- GST on sales/purchase incl. 0% + GST Summary ✅
- Repairs (token + balance) ✅
- Dashboard (KPIs, metal position, trend, activity) ✅
- Roles + workspace + prints scrubbed of worker data ✅
- Barcode field on Retail Stock Item ✅

### 3.2 Agreed build packet (🔨 building in order)
A. Server-side totals mirror (sales/purchase/order/opening) —
   protects against API/import math bypass (handoff §12 P1).
B. Stock submit + cancellation reversal — JST posts as submitted when the
   source doc submits; cancelling a source reverses its ledger effect.
C. FIFO metal ledger + stock valuation report + realized/provisional profit
   (Marg/Ornate/Jwelly valuation methods; core of "profit" features).
D. Sales Return / Purchase Return DocTypes (invoice lookup, return credit,
   stock reversal).
E. GST filing: TCS on sales (> threshold, configurable), GSTR-1 export,
   e-invoice JSON payload export (IRP submission = external, documented).
F. New reports (Munim/Marg style): Daily Sales Summary, Supplier Payable,
   Stock Ageing (old-stock by last IN), Item Rate Card/Price List.
G. Settings-driven defaults: default GST rate pre-fill on new bills.

### 3.3 V2 (⏳ do not build without owner instruction)
- Savings schemes / chit / kitty (C7) — explicit V2 per owner.
- Girvi / gold loans (C8) — explicit V2 per owner.
- CRM: loyalty points, birthday/anniversary reminders, WhatsApp/SMS — V2.
- Multi-branch, branch transfers — explicit V2.
- Diamonds / 4Cs / Kundan — explicit V2 ("diamonds out").
- Manufacturing BOM / casting / department routing — V2.
- Dedicated POS touch screen / salesman & counter mgmt — V2.

### 3.4 Out of scope (🚫 hardware / external services)
- RFID hardware scanners, weighing-scale integration.
- Live market-rate feeds (rates stay manual entry until owner asks).
- e-invoice IRN submission to IRP / e-way bill generation (needs GSTIN +
  portal credentials + live APIs; we export the payload instead).
- WhatsApp/E-comm storefront, mobile customer app.

-----------------------------------------------------------------------
## 4. NOTES FOR THE NEXT AGENT
- Keep the two-world rule: Order Sale never touches stock; stock moves only
  via Purchase/Sale/Opening/Order-Transfer IN.
- Delivered NET weight is the only weight that moves stock or settles workers.
- History rows are append-only; FIFO is computed on the fly from
  Jewellery Stock Transaction — never a rewritten ledger.
- Fixtures are the schema truth; export after every DB change; never run
  `bench migrate` with unexported changes.