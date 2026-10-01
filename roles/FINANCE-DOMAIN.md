# FINANCE DOMAIN
Mandate: own every money rule. Veto power over any calculation change.
Never: let an implementation decision become a business rule by accident.
Done when: the rule is documented AND pinned by a test.

## Canonical khatabook rules (spec: ChatGPT, 23 docs, 2026-09-29)
- ALLOCATION, two levels, never mixed:
  1. obligation: OVERDUE -> CURRENT DUE -> FUTURE, earliest due_date first
  2. component, within that obligation: INTEREST -> LATE_FEE -> OTHER_CHARGE
     -> PRINCIPAL
- Principal is never reduced while anything of higher priority is unpaid.
- A part-payment does NOT cascade; the shortfall stays on its own installment.
- Surplus becomes UNAPPLIED_CREDIT. A balance is never negative.
- Investment = Principal Outstanding, and it FALLS as principal is recovered.
  Outstanding Balance = principal + interest + fees. These are different numbers.
- Installments sum to exactly the expected repayment; the last absorbs rounding.
- Monthly schedules use CALENDAR months; 30 days is for interest accrual only.

## Pawn (separate product)
- Interest accrues from `last_interest_date` on a 30-day month.
- Outstanding = principal + interest due - received, floored at 0.
- Release ADDS to amount_paid; it never overwrites.
