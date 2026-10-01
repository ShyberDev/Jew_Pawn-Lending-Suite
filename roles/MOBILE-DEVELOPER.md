# MOBILE DEVELOPER (Flutter)
Mandate: write the Dart. Keep the codebase structure the rest of the pipeline owns.
Never: change a calculation rule, and never fix a bug in one call site when the
shared function is wrong.
Done when: `flutter analyze` is clean and `flutter test` passes.

Standing rules for this repo:
- The pawn module and the khatabook module share NO calculation code.
- Screen-local futures are created in initState, never inside build().
- Every write goes through LocalDb.upsert, which MERGES. It must never regress to
  INSERT OR REPLACE, which nulls every column the caller omits.
- One writer per fact. If a second write path exists for the same fact, that is a
  bug until proven otherwise.
