# Migration v10 — canonical khatabook allocation

Built from the ChatGPT specification's acceptance criteria (AC-001 … AC-025),
found in `/home/shyam/Documents/Jewellery suite/Khatabook/`.

**Khata only.** Pawn is a different product with a different interest model and
never shares this code.

## Stage v10.1 (done) — `lib/util/khata_alloc.dart`

Pure functions, no database, no UI. Nothing writes to the shop's data yet, so
this stage cannot change a number anyone sees.

### Two levels of priority, kept separate

1. **Obligation priority** — which installment gets the money:
   `OVERDUE → CURRENT DUE → FUTURE SCHEDULED`, earliest `due_date` first.
2. **Component priority** — inside that obligation only:
   `INTEREST → LATE_FEE → OTHER_CHARGE → PRINCIPAL`.

### The rule that matters

Principal is never reduced while anything of higher priority is unpaid. A ₹400
payment against ₹600 of interest recovers **zero** principal, so capital
deployed does not appear to shrink when no capital actually came back.

Money carries to the next obligation only once this one is fully settled. A
part-payment does **not** cascade — the shortfall stays put, so a short week is
never silently forgiven by the next one.

Surplus becomes **unapplied credit**, never a negative balance.

## A real money bug the tests caught

The first implementation allocated in floating-point rupees, applying the money
ceiling to every intermediate step:

```dart
left = Num.money(left - take);   // ceiling of a binary-float subtraction
```

`1234.57 − 33.33` is `1201.2400000000002` in IEEE 754, and the ceiling turns that
into `1201.25`. **Every subtraction leaked paise upward.** A ₹1,234.57 payment
against four dues allocated as ₹1,234.61 — four paise that never existed, and
money the shop had not received.

Fixed by doing all allocation arithmetic in **integer paise**, converting to
rupees only at the end. Integers cannot drift, so `allocated + unapplied` is
always exactly the payment. `Allocation.total` is likewise a plain sum, because
re-applying the ceiling to a sum of exact values inflates it again.

## Tests — 24, in `test/khata_alloc_test.dart`

Written from the specification *before* the implementation, so a disagreement
shows up as a failing test rather than a different number on someone's account.

| Criterion | Covered |
|---|---|
| AC-001 … AC-004 | interest before principal; under, exact and over interest |
| AC-005 / AC-006 | fees after interest; fees cannot preempt interest |
| AC-007 / AC-008 | every rupee allocated or credited, never created or lost |
| AC-009 | negative payment and negative dues rejected |
| AC-010 … AC-012 | principal recovered = principal allocation; interest never reduces principal |
| Obligation priority | overdue → current → future; earliest date first; settled skipped |
| Cascade | carries on only after an obligation clears; part-payment stays put |
| Overpayment | surplus becomes credit, balances never go negative |
| Rounding | awkward amounts, exact-cover payment, the paise-leak regression |

Three of my own test assertions were wrong before the engine was. I had asserted
`allocated == payment` for payments larger than the dues, an ordering that
contradicted the spec, and a cross-obligation interest rule the spec does not
state. The specification was right in each case, so the tests were corrected
rather than the engine.

## Stage v10.2 — schedule and status (`khata_schedule.dart`, 24 tests)

**Monthly uses calendar months, not 30 days.** A 31 January start lands on the
last day of February and returns to the 31st in March, so a schedule never drifts
permanently earlier in the month. A flat 30 remains correct for *interest
accrual*, which is a different concern — the two are deliberately separate.

Generated installments sum to **exactly** the expected repayment, with the final
one absorbing the rounding remainder, and none is ever pre-marked paid.
**Overdue is derived at read time**, never stored, so it cannot freeze in the
past. Status: seven loan states with illegal transitions refused; five
installment states.

## Stage v10.3 — the Investment KPI (`khata_loan_state.dart`, 23 tests)

The defect behind "Khata investment is wrong". Home summed
`SUM(principal_amount)` — the **original** principal — so the figure could only
ever rise and never meant the money still in the street.

* **Investment** = Principal Outstanding. It falls as principal is recovered.
* **Outstanding Balance** = principal outstanding + interest + fees.
* A pre-v10 row has no `principal_outstanding`, so it falls back to its
  principal: an **upper bound, not a guess**. Recovery is never invented where it
  cannot be proven.
* A loan is never marked COMPLETED while a balance remains.

## Stage v10.4 — schema and the allocation ledger (`migration_v10.dart`, 12 tests)

Installments become real rows, the loan carries per-component balances, and
every payment records **exactly where each rupee went**. Without the ledger a
balance is merely correct *today* and cannot be explained afterwards. The
collect flow allocates through the canonical engine and writes the ledger, so
interest outstanding, principal recovered and capital deployed move together.

## Two more paise bugs, both caught by tests not review

1. Summing generated 2-dp installments in floating point and then applying the
   money ceiling inflated the total by a paisa. The invariant is now asserted in
   whole paise, which is where the rows actually live.
2. The component columns were declared `TEXT`, so a balance stored as `'0'`
   rather than `0`. SQLite is dynamically typed, so declaring them `REAL` is
   free and correct.

## Test total

193 passing across 12 files, up from 134. Analyzer: 0 errors, 0 warnings.

## Not yet done

Reports and the refinance-as-new-transaction flow still use the pre-v10 shape.
They should be rebuilt on `KhataLoanState` so the Capital Recovery View is a
pure read of the same balances, never a second calculation.

## Decisions taken

| Question | Decision |
|---|---|
| Overpayment | **Per the specification:** cascade to later installments, then `UNAPPLIED_CREDIT`. This reverses the "clamp at zero" rule locked in v1.0.12. |
| Pawn vs khatabook interest | Different products, **deliberately not unified** (confirmed by the user). |
| Khata interest | Fixed: charged once on the agreed principal for the whole agreed term, not recalculated per installment. |

## Safety

- The database is empty development data, so nothing is at risk.
- A verified backup is one tap away in Settings → Backup & data.
- The allocation module is pure and touches no storage, so v10.1 cannot corrupt
  anything.
