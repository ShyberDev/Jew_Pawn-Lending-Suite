# Calculation reference — Jewellery Suite

Every money figure the app shows, and every rule that produces it. This exists
so the rules can be **verified against tests** before any of them are changed,
and so a later Frappe/ERPNext server can be made to agree rather than to
disagree.

Reading order: pawn first (it is the most mathematically involved), then
khata, then the shared helpers both use.

Status column: `tested` means a test in `test/` locks the behaviour, including
the edge cases listed. `untested` means the rule is real but not yet pinned by
a test — treat those first when changing anything.

---

## 0. Shared primitives — `lib/util/format.dart`

| Rule | Value | Tested |
|---|---|---|
| Money rounding (pawn) | `Num.money(x)` → ceiling to 2 dp | ✅ |
| Money rounding (khata) | `Num.rupees(x)` → truncate to whole rupees, paise dropped | ✅ |
| Khata display | `moneyWholeDown(x)` → truncated Indian grouping | ✅ |
| Weight rounding | `Num.round3(x)` → 3 decimal places, half-up | ✅ |
| Input parsing | `parseMoney("10,000")` → `10000.0`; commas, ₹ and spaces stripped | ✅ |
| Simple interest | `simpleInterest(P, r%, days)` = `P × r/100 × days/30` | ✅ |
| Compound interest | `compoundInterest(P, r%, days)` = `P × ((1+r)^n − 1)`, `n = days/30` | ✅ |
| Date difference | `diffYmd(from, to)` in **whole** years/months/days | ✅ |

**The month is 30 days** for every rate calculation. This is the shop's
convention, not a calendar rule: a 45-day loan at 3% monthly accrues one and a
half months' interest, not one month and fifteen days of a real calendar.

`Num.money` is the only rounding applied to a stored amount. Intermediate
values inside a formula are **not** rounded — rounding happens once, on the
result. This is why `interestDue` returns an already-rounded figure but
`freshInterest` inside it does not round twice.

---

## 1. Pawn — `lib/util/pawn_math.dart` (single source of truth)

Nine tests in `test/pawn_math_test.dart` cover this section.

### 1.1 Interest

| | |
|---|---|
| **Input** | `loan_amount`, `interest_rate`, `last_interest_date`, `interest_accrued` (already settled) |
| **Formula** | `interestDue = interest_accrued + loan_amount × rate/100 × days(last_interest_date → today)/30` |
| **Anchor date** | `last_interest_date`, falling back to `due_date`, then `loan_date` |
| **Units** | Rupees. Rate is a percentage per 30 days. |
| **Rounding** | Once, 2 dp, at the end. |
| **Edge cases** | A released loan accrues nothing and is always ₹0. A future anchor date contributes 0 days, never negative. |
| **Partial period** | Handled by the 30-day month — see §0. |

The settlement date is what makes this correct. Before it existed, interest
only changed when a button was pressed: a three-month-old loan showed its
first-period interest and Release could settle for far less than was owed.

### 1.2 Outstanding

`outstanding = principal + interestDue − amountPaid`, floored at **0**.

### 1.3 The worked example

```
Principal 10,000 · 3% per month · 60 days since the settlement date

interest = 10,000 × 3/100 × 60/30  =  600.00
outstanding (nothing paid) = 10,000 + 600 − 0 = 10,600.00
```

### 1.4 Release

Release settles `total_paid` and **adds** it to `amount_paid`. It never
overwrites, so earlier payments are not thrown away. `principal_paid` can never
be written as a negative number. `ltv` uses one rounding rule everywhere
(2 dp, half-up).

### 1.5 LTV

`ltv = loan_amount / total_market_value × 100`, rounded to 2 dp, half-up, once.
No division by zero: a zero market value yields 0.

---

## 2. Khata (the passbook) — `lib/util/khata_math.dart` (single source of truth)

Until v1.0.12 these rules were derived independently in the book screen, the
customer profile and the ledger, with nothing enforcing that they agreed. They
are now one module with **22 tests** in `test/khata_math_test.dart` pinning the
behaviour that existed before, so the extraction could not quietly change a
number the shopkeeper relies on.

### 2.1 Installment

| | |
|---|---|
| **Input** | `total_payable`, `installment_count` |
| **Formula** | `installment_amount = total_payable / installment_count` |
| **Rounding** | **Truncate** to whole rupees; the final installment absorbs the remainder (10,000 ÷ 3 → 3333 + 3333 + 3334) |
| **Frequency** | `Weekly` = 7 days, `Biweekly` = 14, `Monthly` = 30, between `start_date` and each due date |
| **Payment types** | `INSTALLMENT` amortises a fixed total; `INTEREST_ONLY` bills one interest period at a time (`current_interest`, editable, history immutable) |

A part-payment does **not** mark a whole installment "Paid / On time" —
`paidInstallments` floors the division, so only money that actually covers a
whole installment counts.

### 2.2 Outstanding

`outstanding = total_payable − Σ collections`, floored at 0.

The profile's ledger keeps its own running balance as well. This is where the
refinance double-counting bug lived: the ledger re-read the cash that a
refinance injects as a collection, so the hero figure and the ledger disagreed.
The hero figure now comes from the loan's own totals.

### 2.3 Due state — `lib/ui/khata_screen.dart`, 11 tests across two files

| Rule | Value | Tested |
|---|---|---|
| Owing anything keeps the member due | 400 paid of 800 → **still due** | ✅ |
| Due clears only at | `outstanding == 0` | ✅ |
| Every due state is | **red** | ✅ |
| A reminder date in the future is | **blue** | ✅ |
| A reminder set to today is | **red** (due) | ✅ |
| Time of day is irrelevant | only the calendar day is compared | ✅ |

### 2.4 Collected today

Counts `khatabook_collections` where `collection_date` is today. **Pawn
receipts are not included** — a known gap, not an oversight, and it makes the
Home "Collected today" figure lower than the day's real takings.

### 2.5 To Collect — dues, never the balance

`To Collect = Σ remaining over installments/periods with due date ≤ today`,
oldest-first, per loan, summed over due non-promised members. A ₹12,000
outstanding with a ₹1,000 weekly due means ₹1,000; arrears carry forward until
cleared; future dues are invisible until their date arrives. Interest-only
loans sum their billed period rows instead. Reminder-promised members stay
excluded. Tests in `test/khata_schedule_test.dart` (spec Tests 1–5).

### 2.6 Loss Khata

One more Khata row, not a system: moving a customer only rewrites their
`village` (origin kept in `previous_village`). Outstanding displays as-is and
is read as the loss amount. Non-deletable, always visible, distinct color.
Normal collection keeps working there. 8 tests in `test/loss_khata_test.dart`.

---

## 3. Reminder / promise rule

`reminderIsLater(member, today)` → true only when the reminder date is
**strictly after** today. Six tests in `test/reminder_tone_test.dart`.

---

## 4. Customer ID — book scheme

`A01 … A99, B01 … Z99`, then `A001 … Z999` (hyphen-free; legacy `A-01` rows are
normalised on startup, hyphenated input still accepted).

A typed ID seeds the sequence so the next customer continues from it. Freed IDs
return to a pool and are reissued. Legacy numeric IDs were migrated once, tracked
by `customer_id_scheme = 'book'`.

---

## 5. Known disagreements and gaps

| # | Issue | Status |
|---|---|---|
| 1 | ~~Khata outstanding computed in 3 places~~ | **Fixed in v1.0.12** — `lib/util/khata_math.dart` is now the single definition, with 22 tests in `test/khata_math_test.dart` locking the pre-existing behaviour |
| 7 | **Loans attributed to a khata by customer NAME**, so two people sharing a name merged and every village total was wrong | **Fixed in v1.0.13** — uuid first, unique name second, stale loan column last. See §6 |
| 2 | Server recalculates pawn interest from `loan_date`, ignoring `last_interest_date` — mathematically incompatible with §1.1 | **Open — needs a decision when the server is used** |
| 3 | First-term interest is booked at pledge time up to the due date; typing a due date 12 months out books a full year on day one | Open — policy decision |
| 4 | "Collected today" ignores pawn receipts | Open |
| 5 | Pawn "applies from" can be set backwards, re-anchoring the interest chain | Bounded going forward only |
| 6 | ~~Khata refinance exists in two forms; one path hard-codes 20% interest~~ | **Fixed** — one dialog (`lib/ui/refinance_sheet.dart`) + one writer (`AppState.executeRefinance`): old loan frozen REFINANCED, new loan carries previous + fresh + interest, tile shows all three. 5 tests in `test/refinance_test.dart` |

---

## 6. Which khata a loan belongs to

Not a money rule, but it decides which village total a rupee lands in, so it is
documented here. A loan belongs to the khata of **its customer** — the customer's
own record is the source of truth, never the loan's own `village` column, which
goes stale when a customer moves.

| Step | Rule |
|---|---|
| 1 | Match `customer_uuid` (v9) against the customer records |
| 2 | Match the legacy `customer` column, for rows written before v9 |
| 3 | Match `customer_name`, **but only when exactly one customer has that name** |
| 4 | Otherwise fall back to the loan's own `village` column |
| Never | Two customers sharing a name must never be merged |

**Why this exists.** On the shop's own test data there were three separate
customers named "Ravi" in Uppalapadu. The ₹12,000 loan stored the *text* `"ravi"`
rather than a uuid, so it could not say which Ravi owned it and was filed under a
village called `shyam`. The amounts were correct — which is exactly why the
customer profile looked right while the khata list and the Home investment
figure looked wrong.

Schema v9 makes `customer_uuid` the identity on every customer-referencing table,
so this ambiguity can no longer arise. See `lib/data/migration_v9.dart`.

---

## How to use this file

Before changing any rule above: read its row, add or update the test that pins
it, change the code, confirm the test still passes. A rule that changes without
its test changing first is a regression, not a refactor.
