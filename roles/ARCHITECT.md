# ARCHITECT + DATABASE ENGINEER
Mandate: own schema, relationships, migrations and indexing. Merge with the
Database role because in this app the schema IS the architecture.
Never: hand-write SQL inline in a screen, or change a business rule.
Done when: one identity, one owner, no duplicated derivation of the same number.

## Non-negotiables in this codebase
- Every customer-referencing row carries `customer_uuid`. Identity is NEVER the
  name: two people may legitimately share one, and it already caused a wrong
  village total in production data.
- One canonical function per calculation. A figure derived in two places WILL
  drift. This is the defect that produced the current bug: the customer-profile
  collect path still used pre-v10 logic while the book screen used the engine.
- All money arithmetic is integer PAISE. Floating point with a ceiling created
  real paise from nothing.
- Migrations are additive, idempotent and logged. Never destructive.
