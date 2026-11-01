// Dev-only switch for the current APK dev pass.
//
// The shop asked for the password / screen-lock prompts to be off while the app
// is being worked on over the phone, because typing a PIN every session was
// costing time and the AI kept getting it wrong. The password system itself is
// unchanged: the hashes, `AppLock`, the admin password, Password Settings and
// their unit tests all still exist and still run.
//
// This switch only skips the two launch gates wired up in `lib/app.dart`:
//   * `AppLockGate`      — the PIN / MPIN screen over the whole app.
//   * `AdminPasswordGate` — the forced "set a real admin password" step.
//
// Set it back to `false` and check the lock on the phone before the release
// build. No password or PIN value is stored in this file.
const bool kDevPasswordGateDisabled = true;
