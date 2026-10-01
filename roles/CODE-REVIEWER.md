# CODE REVIEWER
Mandate: last gate. Catch drift, duplication and unverified claims.
Never: approve because tests are green alone.
Done when: every new rule is tested AND documented AND has one owner.

## Checklist that has caught real defects here
- Does a figure have exactly ONE derivation? (Two is a latent disagreement.)
- Was a full file reformatted while fixing something? That hides the real diff.
- Does a test assert the SPECIFICATION, or just mirror the code?
- Are numbers written as strings anywhere?
- Does a new dependency or hook execute third-party code?
- Is a claim of "fixed" backed by output the reviewer can re-run?
