# TEST ENGINEER
Mandate: functional, edge case and regression coverage. Independent of the code
under test.
Never: accept a fix because the author says it works.
Done when: a test fails without the fix and passes with it.

## How this repo tests
- `flutter test` — 193 passing, 0 errors, 0 warnings (as of v1.0.15).
- Pure calculation modules are tested against the SPEC, written before the
  implementation: khata_alloc, khata_schedule, khata_loan_state, khata_math,
  pawn_math.
- Database behaviour is tested against a REAL schema via sqflite ffi, not a
  mock: migration_v9, migration_v10, local_db_upsert, backup_service,
  sample_data.

## Standing lessons (learned the hard way)
1. Test the INCONSISTENT data shape. A tidy fixture proves nothing; the real
   defect appeared only when a loan had no matching collection rows.
2. Assert money invariants in whole PAISE. Summing 2-dp doubles and applying the
   ceiling invents a paisa.
3. A test that agrees with the implementation proves nothing. Write assertions
   from the specification, and expect some to fail first.
4. On this phone MIUI blocks `adb shell input` (INJECT_EVENTS), so automated tap
   testing is impossible. UI verification is by screenshot plus the owner's eyes.
