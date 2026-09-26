# App Feedback Tracker

Living checklist of pending/queued work from user testing. Everything here is either
built (marked ✅, verified on device) or queued for a later release (marked ⏳).
The app never crashes on unfinished modules — they show **"Coming in a later release"**.

## v1.0.8+ extras (current batch — built)

- ✅ **Release strategy**: GitHub release + APK on ONE repo only (`ShyberDev/Jew_Pawn-Lending-Suite`).
  `ShyberDev/Android_Apps` gets source mirror + a README **download link** to the APK — no
  binary upload (keeps the GitHub repo size small).
- ✅ **Home desk — compact core modules**: Khatabook / Pawn Loans / Cashbook / Jewellery
  tiles show **logo + name only** (no Investment/Outstanding lines). History moved to More.
- ✅ **Home desk — menu (top-left home symbol)**: Logout, Customers, Settings, QR Codes,
  About Phone, Help & Support, Languages, Notifications, Reminders, Theme, Biometric &
  Screen lock, Change password, Appearance. Unconfigured entries → "Coming in a later
  release" (never a crash).
- ✅ **More → Settings**: zoom in/out (smart fit), dark/light appearance, QR codes,
  and the full settings list.
- ✅ **More → Interest Calculator** utility.
- ✅ **Zoom / smart fit**: app font size follows the phone size with an in-app
  Zoom setting (0.8×–1.5×) + auto-fit, so large Display/Font phone settings don't
  overflow the screen.
- ✅ **Pawn save-with-photo bug**: fixed (item photos are saved on the pawn *items*
  rows; the old code wrote to a non-existent `pawn_loans.photo_path` column and aborted
  the whole save).
- ✅ **Pawn New Loan → add customer**: "+" button next to the customer list opens the
  full customer form (name, phone, village, address, photo, ID proof type/number/
  front/back) and re-selects the new customer.
- ✅ **Customer ID — numeric book sequence**: optional start value (e.g. 5102) — next
  customer auto-continues (5103…); blank continues from the previous number; deleted IDs
  reused; ID editable from the customer form; duplicate IDs rejected.
- ✅ **Delete for every entry**: khata ✓ (drag), pawn loans + pawn items ✓ (drag),
  jewellery (module only — pending). Trash bin appears **only while dragging**
  (hidden during normal use).
- ✅ **Pawn labels**: "Active Pawns" → "Pawns". Principal out / Interest due /
  Outstanding kept inside pawn.

## v1.0.8+ extras (batch 2 — built, awaiting on-phone test)

- ✅ **Core module tiles smaller + uniform**: logo + name only, all cells the same
  size (drawn to fit a compact tile).
- ✅ **Home button = profile photo**: shows the user's uploaded photo when set,
  otherwise the home icon. Top-left.
- ✅ **Logout moved into the side dashboard** (top-right logout icon removed) so no
  accidental logout; it only happens from the Home menu.
- ✅ **Home menu = left side dashboard** (opened from the Home button): Payments
  (QR codes) → User Details → Languages → Notifications → Reminders → Dark mode
  (Beta) → Settings → Customers → Sync → Admin → Biometric → Change password →
  About App → Help & Support → Logout.
- ✅ **Admin setting**: toggle "Ask password for delete / release". On = admin
  password (`admin`) required for khata deletes, customer deletes, pawn loan
  deletes and pawn releases; Off = those run on the drag/confirm alone.
- ✅ **Pawn release → confirmation + admin password** (Admin-gated), same as delete.
- ✅ **About phone → About App**: app name + version, **App size (APK)**, **App data
  (your records — DB + photos on this phone)**, and list: Policies, Open Source
  Licences, Privacy & Policy, Feedback & Suggestions, Terms & Conditions.
- ✅ **User Details** (Home menu): your photo upload/remove, name, phone, email —
  photo appears on the Home button.
- ✅ **Dark mode tagged Beta** ("Dark mode (Beta) — some screens may not be fully
  dark yet") in Home menu + Settings.

## Queued (⏳ later releases)

- ⏳ Jewellery module (items delete, entries) once module is built.
- ⏳ QR code UPI payment flow (display+bank details form auto-fill) — QR gallery/swipe done.
- ⏳ Push notifications / reminders engine (per-customer reminder date exists in DB).
- ⏳ Khata "weekly" → frequency-driven ("Fortnightly/Monthly") wording everywhere incl.
  khata list rows.
- ⏳ Server-side Pawn Loan DocType + photo upload (pawn stays local-only today).