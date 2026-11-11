# Google Drive backup — OAuth setup

**Item:** #072 · **Status:** designed, blocked on one input from the shop
**Companion design:** `docs/GOOGLE_DRIVE_SYNC.md`

This guide is the click-by-click version. It has two paths:

- **Path A — Apps Script endpoint (no OAuth).** Fastest way to get an off-phone
  backup into Drive. Works today with the existing `http` dependency. No Cloud
  Console project, no consent screen, no token expiry. It is **backup only**, not
  live multi-device sync.
- **Path B — Drive API + OAuth.** The real thing: the app signs in with the shop's
  Google account and reads/writes its own Drive folder. This is what #072 needs
  for restore-on-a-new-phone and, later, multi-device sync.

Do Path A now if the shop just wants a copy off the phone. Do Path B when the
shop is ready to test sign-in on two phones.

---

## App facts these steps depend on

| Field | Value |
|---|---|
| Package name | `com.shyberdev.jewellery_suite` |
| Release SHA-1 | `C9:27:26:27:AB:0F:66:40:9B:FC:12:C0:50:0E:B5:3A:05:88:13:B6` |
| Release SHA-256 | `54:F9:83:32:23:D1:A8:52:78:A7:49:B8:9F:FA:61:3C:EC:C8:8E:14:7D:CA:25:FA:1C:F6:BA:D5:2A:B6:1C:09` |
| Debug SHA-1 | `CE:85:4B:43:DD:C1:2F:88:CD:04:AB:92:92:E2:D1:1B:FB:A9:3E:49` |
| Keystore | `android/app/upload-keystore.jks`, alias `upload` |
| Current release | `v1.4.26` (versionCode 2078) |
| Scopes | `https://www.googleapis.com/auth/drive.appdata`, `email` |

> The SHA-1 above is the **release** certificate. Google matches the Android
> OAuth client by package name + signing certificate, so a debug build needs the
> debug SHA-1 registered too. Both are listed in the same OAuth client only if
> you create two Android clients (one per certificate).

---

## Path A — Apps Script backup endpoint (no OAuth)

**What the shop gets:** every backup is also copied into a normal Drive folder
called `Jewellery Suite Backups`, visible in the Drive app. The phone keeps its
local copy. Restore still happens from the phone's backup list.

### A1. Create the script

1. Sign in as the shop's Google account at <https://script.google.com>.
2. **New project** → rename it `Jewellery Suite Backup`.
3. Replace `Code.gs` with:

```javascript
const FOLDER_NAME = 'Jewellery Suite Backups';
const SECRET = 'PASTE_A_LONG_RANDOM_SECRET_HERE';
const KEEP = 7;

function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);
    if (body.secret !== SECRET) return out({ ok: false, error: 'unauthorized' });

    const folder = getFolder_();
    const bytes = Utilities.base64Decode(body.data);
    const blob = Utilities.newBlob(bytes, 'application/zip', body.name);
    const file = folder.createFile(blob);

    // Keep the newest KEEP files, trash the rest.
    const files = [];
    const it = folder.getFiles();
    while (it.hasNext()) files.push(it.next());
    files.sort((a, b) => b.getDateCreated() - a.getDateCreated());
    for (let i = KEEP; i < files.length; i++) files[i].setTrashed(true);

    return out({ ok: true, id: file.getId(), name: file.getName() });
  } catch (err) {
    return out({ ok: false, error: String(err) });
  }
}

function getFolder_() {
  const it = DriveApp.getFoldersByName(FOLDER_NAME);
  return it.hasNext() ? it.next() : DriveApp.createFolder(FOLDER_NAME);
}

function out(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
```

4. **Deploy → New deployment → Web app**
   - Description: `backup v1`
   - **Execute as: Me**
   - **Who has access: Anyone** (the app has no Google session; the secret is the
     protection — treat the URL + secret like a password)
5. Copy the **`/exec`** URL (not `/dev`).

### A2. Wire it into the app (code change, not yet written)

`BackupService` already produces the zip. Add one method:

```dart
Future<bool> uploadToGateway(String zipPath) async {
  final bytes = await File(zipPath).readAsBytes();
  final res = await http.post(
    Uri.parse(gatewayUrl),
    headers: const {'Content-Type': 'application/json'},
    body: jsonEncode({
      'secret': gatewaySecret,
      'name': p.basename(zipPath),
      'data': base64Encode(bytes),
    }),
  ).timeout(const Duration(seconds: 60));
  return res.statusCode >= 200 && res.statusCode < 300;
}
```

Settings needed: `drive_backup_url`, `drive_backup_secret`, and a switch
**Also copy backups to Drive**. Reuse the existing `settings` table; no schema
change.

> **#080 is done** (v1.4.16): a backup only carries its database key when
> **Include database key** was switched on, and then the key is wrapped with a
> passphrase (PBKDF2-HMAC-SHA256 + HMAC) and asked for again on restore — never a
> clear `db_key`. Uploading such an archive to Drive is safe. A backup made
> *without* the key can only be restored on the phone that made it, so a Drive
> copy the shop intends to keep must be created with the key and with a
> passphrase the shop has written down.

### A3. Test

```bash
curl -s -X POST '<EXEC_URL>' \
  -H 'Content-Type: application/json' \
  -d '{"secret":"<SECRET>","name":"test.zip","data":"UEsDBAoAAAAAAA=="}'
# -> {"ok":true,...}
```

Then check `Jewellery Suite Backups` in the shop's Drive. Delete the test file.

**Quota:** consumer Gmail Apps Script allows 20,000 URL-fetch/script runs per day
and 50 MB per POST; a shop doing one backup a day is nowhere near it.

---

## Path B — Drive API + OAuth (the #072 design)

### B1. Create the Cloud project

1. <https://console.cloud.google.com> → project selector → **New project**.
2. Name: `Jewellery Suite` → **Create**.
3. **APIs & Services → Library** → search **Google Drive API** → **Enable**.

### B2. OAuth consent screen

1. **APIs & Services → OAuth consent screen** → **Get started**.
2. App name: `Jewellery Suite`; support email: the shop's Gmail.
3. Audience: **External**.
4. Contact email: the shop's Gmail.
5. **Scopes → Add or remove scopes** → add:
   - `https://www.googleapis.com/auth/drive.appdata`
   - `https://www.googleapis.com/auth/userinfo.email`
6. **Test users → Add users** → the shop's Gmail (and any second phone's
   account while testing).
7. Leave publishing status at **Testing** for the first phone pass.

> **Why this is enough:** Google's Drive API docs classify `drive.appdata` as a
> **non-sensitive** scope. It does not need the restricted-scope security
> assessment. For the shop's own accounts, Testing mode needs no verification at
> all. If the app is later handed to other shops, publish it — non-sensitive
> scopes only need basic OAuth verification.

### B3. Create the Android OAuth client

**Credentials → Create credentials → OAuth client ID**

- Application type: **Android**
- Name: `Jewellery Suite Android (release)`
- Package name: `com.shyberdev.jewellery_suite`
- SHA-1: `C9:27:26:27:AB:0F:66:40:9B:FC:12:C0:50:0E:B5:3A:05:88:13:B6`

Repeat once for debug builds:

- Name: `Jewellery Suite Android (debug)`
- SHA-1: `CE:85:4B:43:DD:C1:2F:88:CD:04:AB:92:92:E2:D1:1B:FB:A9:3E:49`

There is **no client secret** for Android clients, and nothing to paste into the
app from these two.

### B4. Create the Web client (for `serverClientId`)

**Credentials → Create credentials → OAuth client ID → Web application**

- Name: `Jewellery Suite Web`
- No redirect URIs needed for the Android app.

Copy the **client ID** — it ends in `.apps.googleusercontent.com`. This is the
value the app needs. It is not a secret.

### B5. What to send back

```text
WEB_CLIENT_ID = 1234567890-abcdefg.apps.googleusercontent.com
TEST_ACCOUNT  = the Gmail added as a test user
```

That is the whole blocker for #072.

---

## App-side implementation plan (Path B)

### Dependencies

```yaml
google_sign_in: ^7.2.0     # 7.x API — the old GoogleSignIn(scopes:) API is gone
googleapis: ^14.0.0        # already in the local pub cache
googleapis_auth: ^2.3.2    # already in the local pub cache
```

`google_sign_in` is **not** in the local pub cache, so the first `flutter pub get`
needs network access.

### Sign-in + Drive client

```dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

const _scopes = <String>[
  'https://www.googleapis.com/auth/drive.appdata',
  'email',
];

Future<drive.DriveApi> connectDrive() async {
  final signIn = GoogleSignIn.instance;
  await signIn.initialize(
    serverClientId: '<WEB_CLIENT_ID>.apps.googleusercontent.com',
  );

  // Must be called from a button press on platforms that require interaction.
  final account = await signIn.authenticate();
  final auth = await account.authorizationClient.authorizeScopes(_scopes);

  final client = authenticatedClient(
    http.Client(),
    AccessToken(
      'Bearer',
      auth.accessToken,
      DateTime.now().add(const Duration(minutes: 55)),
    ),
  );
  return drive.DriveApi(client);
}
```

### Upload / list / download

```dart
// Upload
final file = drive.File()
  ..name = p.basename(zipPath)
  ..parents = ['appDataFolder'];
await api.files.create(
  file,
  uploadMedia: drive.Media(File(zipPath).openRead(), await File(zipPath).length()),
);

// List newest first
final list = await api.files.list(
  spaces: 'appData',
  q: "name contains 'jewellery_suite_' and trashed = false",
  orderBy: 'modifiedTime desc',
  fields: 'files(id,name,size,modifiedTime)',
);

// Download
final media = await api.files.get(
  id,
  downloadOptions: drive.DownloadOptions.fullMedia,
) as drive.Media;
```

Store only the signed-in **email** and a `drive_connected` flag in settings. Do
not store tokens — the plugin owns them. On a 401, call `authorizeScopes` again;
if that throws, show **Reconnect Google Drive**.

### Folder choice

- `appDataFolder` — hidden from the Drive app, deleted only when the app is
  uninstalled *and* the user chooses to delete hidden app data. Good default.
- `drive.file` + a visible `Jewellery Suite Backups` folder — the shop can see the
  files in Drive. Also non-sensitive. Better if the shop wants to verify backups
  by eye.

Pick one before writing the upload code; moving files between them later is a
migration.

---

## Caveats to plan for

1. **Testing mode refresh tokens expire after 7 days.** While the consent screen
   is in Testing, the shop may be asked to approve access again about weekly.
   Publishing the app (basic verification for non-sensitive scopes) removes this.
2. **Unverified-app screen.** In Testing, the consent screen says
   *"Google hasn't verified this app"*; the test user taps **Advanced → Continue**.
   That is expected and disappears after publishing.
3. **Two phones, one account.** Drive access is per Google account, so both
   phones must sign in with the **same** shop account for sync. A second Google
   account sees a different `appDataFolder`.
4. **Archive key.** Fix #080 before any zip leaves the phone: the manifest must
   not carry the SQLCipher key in clear text.
5. **Conflict rules.** Backup is last-write-wins by timestamp. Multi-device sync
   needs the device registry + main-device tie-breaker already described in
   `docs/GOOGLE_DRIVE_SYNC.md`.

---

## Acceptance checklist

- [ ] Cloud project created, Drive API enabled
- [ ] OAuth consent screen: External, Testing, `drive.appdata` + `email`
- [ ] Test user added (shop Gmail)
- [ ] Android client for release SHA-1 (and debug SHA-1)
- [ ] Web client ID copied into the app config
- [ ] Phone: **Connect Google Drive** shows the shop account
- [ ] Upload writes one file into `appDataFolder` / the visible folder
- [ ] List shows it newest-first; download restores it on a second phone
- [ ] Sign-in survives an app restart without a new consent prompt
- [ ] Uploaded manifest carries `db_key_wrapped`, never a clear `db_key` (#080 done)
