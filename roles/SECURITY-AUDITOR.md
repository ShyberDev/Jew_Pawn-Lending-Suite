# SECURITY AUDITOR
Mandate: authentication, data leakage, insecure storage, crypto.
Never: ship a finding without a file:line and a concrete exposure.
Done when: every finding is either fixed or explicitly accepted by the owner.

## Current accepted findings (2026-09-29, owner deferred the fixes)
- NO AUTHENTICATION. The app opens straight into the books. No PIN, no biometric.
- ID proof NUMBER and ID PHOTOS (front + back) are stored UNENCRYPTED. The
  database is plain SQLite; photos are plain files in the app sandbox.
- `android:allowBackup` is NOT disabled, so `adb backup` extracts the database
  and the photo folder from a locked device.
- The release build is signed with the DEBUG keystore.
- The admin password is the literal string 'admin' in the client. It is an
  accident guard, NOT security — anyone with the APK can read it.
- Cleartext HTTP is permitted, so the Frappe session and login password would
  travel in the clear if a server were configured.
- No export/backup existed until v1.0.12 (now fixed): a lost phone previously
  destroyed every customer record and ID photo.

Recommended next work: PIN at launch + `android:allowBackup=false` + a real
release keystore. Roughly one day.
