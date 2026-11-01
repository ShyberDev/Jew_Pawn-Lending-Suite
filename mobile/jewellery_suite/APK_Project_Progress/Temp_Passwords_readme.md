# TEMP passwords — development / testing only

**Read this first:** this file exists because the app is still in development. The test phone holds
**no real shop data** — only disposable test rows (Phone QA, Phone QB, Ravi, Test Drag, Edit Test).
Resetting, reinstalling or reconfiguring that phone is safe.

**Before the final release:** change every secret below, then delete this file (together with the
rest of `APK_Project_Progress/`, which moves to `Unnecessary content/` at handover). Do not ship a
release with these values.

- **Package:** `com.shyberdev.jewellery_suite`
- **Test phone:** Redmi Note 8 Pro, `infinity_begonia`, wireless debugging at `10.235.54.186:35879`
- **Branch:** `Apk_Develop_Branch_01_11`
- **Updated:** 2026-11-01 (v1.1.9)

| # | Secret | Current value | Where it is set / reset |
|---|---|---|---|
| 1 | **Screen-lock PIN / MPIN** | `1234` | Password Settings → Biometric & screen lock (Off / Every time / Daily MPIN) |
| 2 | **Shop account identifier** | `9876543210` | Login screen → Gmail or mobile number |
| 3 | **Shop account password** | `Shop@2026` | Login screen → Forgot password? (OTP is shown on the phone when no gateway is set) or Password Settings → Account & login |
| 4 | **Admin password** | `Admin@2026` | Password Settings → Admin password → Forgot …? |
| 5 | **Pawn-move password** | follows the admin password unless changed | Password Settings → pawn move |
| 6 | **One-time-code gateway** | not configured — codes are shown on the phone, 10 minutes, 5 tries | Password Settings → One-time code delivery |

## Notes for the next agent

- Sign in with **#2 + #3**. If either is refused, use **Forgot password?** on that screen: the code
  appears in a dialog labelled **Offline code (valid 10 minutes)** (no SMS/e-mail gateway is set).
- The app may open straight to **Home** in offline mode (`offline_mode=1`). That is the #054 path,
  not a bug. To reach the login form, use **Logout** in Settings.
- **Keep the PIN.** Delete / Release ask the MPIN first (#06E) and fall back to the admin password
  when no MPIN is set; clearing the PIN does not un-gate destructive actions.
- **Do not delete the shop's non-test rows** while testing; the disposable ones are named above.
- This phone's ledger is worthless by design, so a wipe + reinstall is acceptable when a state is
  unrecoverable — but write down in `README.md` that it happened.
