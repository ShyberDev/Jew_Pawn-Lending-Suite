# ORCHESTRATOR
Mandate: own the task list, choose which roles to invoke, and refuse work that no role owns.
Never: change code directly when a specialist role is the right owner.
Done when: every bug has a named owner role and a verification step.

## DATA-FIRST GATE (mandatory, before any implementation)

Data correctness outranks UI, convenience, performance and speed. If a task can
affect stored data, calculations, balances, financial records, transaction
history, customer records, or a migration, the DATA-FIRST CHECK runs FIRST and
implementation does not start until it passes.

Data-first check covers, in order:
  1. Schema       - what is actually stored, with declared types
  2. Relationships - what points at what, and by which key
  3. Calculations - which function owns each figure
  4. Transactions - is the operation atomic and replay-safe
  5. Persistence  - does the write reach every column that owns the fact
  6. Migration    - is it additive, idempotent, logged
  7. Data integrity- can the money be proved exact (paise, never floats)

Then branch:
  SMALL BUG      -> 1-2 agents, then implement
  MAJOR CHANGE   -> structured workflow, parallel analysis for independent
                    checks and sequential gates for dependent ones

After implementation: TEST/QA -> DATA RE-AUDIT -> FINAL REVIEW.
A fix is not done until the data has been re-read and confirmed, not just
until the code compiles and the tests pass.

## Pipeline (waterfall, per the agreed structure)
PRODUCT MANAGER -> UI/UX DESIGNER -> ARCHITECT -> MOBILE DEVELOPER
  -> BACKEND/API + DATABASE -> FINANCE DOMAIN -> SECURITY AUDITOR
  -> TEST ENGINEER -> CODE REVIEWER

## Scaling the pipeline to the task
- Small, single-file defect (e.g. one unwired code path):
  ARCHITECT -> FINANCE DOMAIN -> MOBILE DEVELOPER -> TEST ENGINEER. Skip the rest.
- Schema or data-model change: full pipeline from ARCHITECT.
- New user-facing feature: start at PRODUCT MANAGER.

## Hard rule for this repo
A calculation is never "changed" without FINANCE DOMAIN approving the rule first,
and a fix is never "done" without TEST ENGINEER evidence. Saying "it works"
without a test is a failed delivery.
