# Migration v9 — customer identity

**Schema version 8 → 9.** The app's database moved from identifying a customer by
name to identifying them by uuid.

## The bug this fixes

Pawn loans, khata loans, collections, releases, transactions and "You Gave" rows
all stored the customer's **name** to say who they belonged to. Two people may
legitimately share a name — and on the shop's own test data they did:

| Customer | Village | Book ID |
|---|---|---|
| ravi | Uppalapadu | A-5469 |
| Ravi | Uppalapadu | A-5470 |
| Ravi | Uppalapadu | A-5471 |

A ₹12,000 loan (₹10,000 principal + ₹2,000 interest) stored the text `"ravi"`.
With three Ravis, that string cannot say which one owns it, so the app fell back
to the loan's own stale `village` column — which said `shyam`. The loan was filed
under the wrong village, so Uppalapadu appeared to owe nothing while the totals
disagreed with the customer profile.

**The amounts were never wrong.** The identity was. That is why the profile
showed correct figures while the khata list and the Home investment figure did
not — the profile looks a customer up directly, the totals resolved a name.

## What changed in the schema

`customer_uuid TEXT` added to every table that points at a customer:

| Table | Notes |
|---|---|
| `pawn_loans` | |
| `pawn_transactions` | |
| `pawn_releases` | |
| `khatabook_loans` | |
| `khatabook_collections` | |
| `khatabook_given` | |
| `khatabook_refinances` | |

Plus indexes, all of which remove a full table scan from a hot path:

| Index | Replaces |
|---|---|
| `idx_<table>_customer` on each of the 7 | name lookups |
| `idx_customers_name`, `idx_customers_id`, `idx_customers_village` | search and grouping |
| `idx_khata_loans_loan`, `idx_khata_given_loan` | per-loan ledger reads |
| `idx_pawn_loans_status`, `idx_outbox_status` | filters and the sync queue |

A `migration_log` table records what each run did.

## Backfill rules — never a guess

A row is linked to a customer only when the answer is unambiguous:

| Situation | Action |
|---|---|
| The stored reference is already a customer's `client_uuid` | **link** |
| The reference is a name that **exactly one** customer answers to | **link** |
| Several customers share that name | **do not link** — reported for review |
| No customer matches at all | **do not link** — reported for review |
| No reference stored | **do not link** — reported for review |

Name matching ignores case and collapses repeated whitespace, because the same
person is typed "Ravi" and "ravi" from different screens.

**No customer rows are ever merged, updated or deleted.** One customer in, one
customer out. An ambiguous reference is left exactly as it was, so no money can
silently move between two people. The cost is a manual decision on those rows;
the alternative is a wrong balance on someone's account.

### Both legacy columns are tried

`customer` and `customer_name` are both searched, because the app has never been
consistent about which holds the reference — the pawn form writes a uuid into
`customer`, the khata form writes a *name* into `customer`, and the sample seeder
writes a uuid. Trusting one column would silently skip rows written through the
other.

## New writes

Every write path now stores `customer_uuid` alongside the display name:
the pawn loan form, the khata loan form, pawn transactions, pawn releases,
khata collections, "You Gave" rows, refinances, and the sample-member seeder.
New data is therefore correct from the moment it is created, whether or not a
migration ever runs.

## Reproducibility

The migration is a plain Dart module, `lib/data/migration_v9.dart`, with no
generated SQL. It is:

- **Idempotent** — rows already carrying a uuid are skipped, and `addSchema` can
  run any number of times without error. Re-running a backfill links nothing new.
- **Additive** — nothing is dropped, renamed or deleted, so downgrading loses
  nothing and the old columns remain readable.
- **Logged** — every run appends to `migration_log`: how many rows were linked by
  uuid, how many by unique name, and the full list needing review.
- **Tested** — 16 tests in `test/migration_v9_test.dart` cover the schema, both
  fresh-install and upgrade paths, idempotency, and — most importantly — that an
  ambiguous name is reported rather than guessed.

## What was found while building it

The tests caught two real defects in the migration itself:

1. `_addColumn` was passed the whole `'customer_uuid TEXT'` fragment but compared
   it against bare column names, so the "add if missing" guard never matched and
   a second run threw `duplicate column name`. The guard now takes the column and
   type separately.
2. The first version read only `customer`, but the khata form writes the *name*
   there — so loans created through that form would never have been linked. Both
   legacy columns are now tried.
