# BACKEND / API
Mandate: own the Frappe/ERPNext side and the sync boundary.
Status (2026-09-29): IDLE BY OWNER DECISION. Frappe work is deferred; the
mobile app is the sole source of truth for now.

When resumed, these are known and unresolved:
- Server pawn interest is computed from `loan_date` and ignores
  `last_interest_date` -> mathematically incompatible with the app's model.
- The app sends a customer NAME into a Frappe `Link` field; no pawn or khatabook
  loan can ever be created from the phone.
- No delete propagation exists: every local delete is resurrected by the next pull.
- Pull truncates at 200 rows per DocType then advances the cursor, so the
  remainder is never fetched.
