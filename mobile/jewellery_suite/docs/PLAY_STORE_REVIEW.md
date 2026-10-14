# Play Store readiness — review of the proposed changes

Status: **HELD. Nothing applied.** Written 2026-10-14 against `develop` @ v1.0.24.

Tracked as PLAY-01 … PLAY-07 in [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md).

A "Play Store Ready: All Fixes" document was supplied with 7 replacement files.
Each claim was checked against this repository before applying anything. The
document is a generic template: several of its claims are false for this
codebase, and one of its stated goals (release signing) silently does not work
as written.

---

## What the document gets right

| Item | Verdict |
|---|---|
| `CAMERA` + `READ_MEDIA_IMAGES` permissions | **Real gap.** The manifest declares no camera permission today, yet the app captures customer and pawn-item photos. |
| `res/xml/file_paths.xml` | Harmless and correct, needed if image files are ever shared. |
| Signing config *structure* (load `key.properties`) | Correct idea, broken path (below). |

---

## Blockers — would break features that work today

### 1. `network_security_config.xml` breaks LAN sync

`login_screen.dart:26` prompts for `http://192.168.1.10:8000`. The shopkeeper
types a DHCP-assigned LAN address over plain HTTP at runtime.

The supplied config permits cleartext for **only** `localhost` and `10.0.2.2`;
everything else is HTTPS-only. Every real sync attempt would be refused by the
platform cleartext policy.

Failure mode is quiet and serious: all local features keep working, so the app
looks healthy, but shop data never reaches the server.

A static-IP allowlist cannot fix this — the address is entered by the user and
changes when the router reassigns it.

### 2. The manifest deletes `<queries>`

That block is what lets `url_launcher` resolve **Dial** and **SMS** intents on
Android 11+. Removing it breaks the **Call / SMS / WhatsApp** buttons on the
Customer Profile screen (verified working on the emulator).

### 3. `pubspec.yaml` omits three packages the app uses

| Package | Used by | Consequence if omitted |
|---|---|---|
| `archive` | `data/backup_service.dart` | Backup archive stops working |
| `share_plus` | `ui/backup_screen.dart` | Backup share stops working |
| `package_info_plus` | `util/app_version.dart` | Version-misreporting bug returns |

### 4. ML Kit packages are wrongly described as unused

- `google_mlkit_text_recognition` — the document says "not yet used". It is used
  by `data/slip_ocr_native.dart` (slip OCR).
- `google_mlkit_document_scanner` — omitted from the document entirely, used by
  `data/doc_scanner_native.dart`.

### 5. The signing fix fails silently — the document's main purpose

- Document instructs: create `~/jewellery_suite/key.properties`
- Supplied Gradle reads: `rootProject.file("../key.properties")`, which resolves
  to `mobile/jewellery_suite/key.properties`

Different paths. The `if (keystorePropertiesFile.exists())` guard is false, so
Gradle falls back to `signingConfigs.getByName("debug")`.

The build still succeeds and still produces an APK — still **debug-signed**.
This is precisely the problem the document claims to fix, and it would only be
discovered when Play rejects the upload.

---

## Regressions

| Item | Current | Proposed | Note |
|---|---|---|---|
| `targetSdk` | **36** (delegated) | 35 | Downgrade. Play requires 35+; there is no reason to give up a year of Android behaviour changes. |
| `minSdk` | 24 (delegated) | 23 | Unnecessary; no plugin in use requires it. |
| `proguard-rules.pro` | Exists, with real ML Kit `-dontwarn` rules added to fix an actual R8 failure | "NEW" replacement | The existing file is better. The replacement references `io.flutter.plugins.imagepicker.**`, a package that does not exist. |
| `isMinifyEnabled` / `isShrinkResources` | off | on | R8 has never been enabled here. ML Kit + Flutter + sqflite under shrinking can fail **at runtime**, and the emulator is closed, so this cannot currently be verified. Not acceptable for a money app in this order. |
| `requestLegacyExternalStorage="true"` | absent | added | Ignored at targetSdk 30+, and a Play review flag. `image_picker` manages its own paths. |
| `build-apk.sh` | no `flutter clean` | adds `flutter clean` | Wipes the 4.1 GB build cache deliberately kept for fast rebuilds. |

---

## Corrected plan (when approved)

1. **Signing.** Put `key.properties` at `mobile/jewellery_suite/key.properties`
   and point Gradle at that exact path. Fail the build loudly when it is
   missing rather than falling back to debug. Add `*.jks` and `key.properties`
   to `.gitignore` (currently **not** covered).
   *Status: keystore already exists at `~/jewellery_suite_keystore.jks`. This file
   must be backed up — losing it means the app can never be updated on Play.*
2. **Permissions.** Add `CAMERA`, `READ_MEDIA_IMAGES`, and
   `READ_EXTERNAL_STORAGE` with `maxSdkVersion="32"`. Keep `<queries>`.
3. **Keep** `targetSdk` 36, keep `minSdk` 24, keep the existing proguard rules.
4. **Minify** stays off until the app can be run and exercised after enabling it.
5. **Sync over HTTPS** — see below.

---

## Moving sync to HTTPS (chosen direction)

The shop server is a local Frappe instance on a DHCP LAN address, so a publicly
trusted certificate is not available.

| Approach | Trade-off |
|---|---|
| **Certificate pinning of a self-signed cert** | Recommended. No CA to install on each phone; the app trusts exactly one pinned certificate. Needs a TLS-terminating reverse proxy in front of Frappe. |
| **Local CA installed on each phone** | Works, and `network_security_config` would add `<certificates src="user"/>`. Every phone must have the CA installed and kept. |
| **Free DDNS hostname + Let's Encrypt** | **Not suitable.** Requires exposing the shop LAN to the public internet. Do not do this. |

Whichever is chosen, `network_security_config.xml` then becomes safe to ship,
because cleartext can be genuinely disabled rather than allowlisted.

Note that Play does not reject an app merely for talking HTTP to its own server;
it must be declared in the Data Safety form. The reason to move to HTTPS here is
that the data is customer financial records travelling in the clear on a shared
shop network — not a Play Store formality.

---

## Data Safety declaration (as supplied — accurate)

| Data type | Collected | Shared |
|---|---|---|
| Customer names and phone numbers | yes | no |
| Photos (customer / item) | yes | no |
| Financial records (loans, interest) | yes | no |
| Location | no | — |

Sync to the shop's own server does count as transmission; declare it under
"Data is encrypted in transit" only once HTTPS is in place.