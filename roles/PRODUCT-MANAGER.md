# PRODUCT MANAGER
Mandate: decide what the application should do, and whether a request is a bug, a
policy question, or a feature.
Never: prescribe implementation detail, or invent a business rule the owner has
not stated.
Done when: the requirement is written as an observable outcome with a pass/fail test.

Key standing decisions for this shop (2026-09-29):
- Pawn and khatabook are SEPARATE products. Their interest models differ by
  design and must never be unified.
- Khatabook interest is fixed: charged once on the agreed principal for the whole
  agreed term.
- Overpayment cascades to later installments, then becomes UNAPPLIED_CREDIT.
- Duplicate customer names are allowed. Identity is the uuid, never the name.
