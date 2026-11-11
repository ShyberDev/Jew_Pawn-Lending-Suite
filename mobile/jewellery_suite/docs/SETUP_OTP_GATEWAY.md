# OTP delivery gateway — setup and test

**Item:** #065 · **Status:** app side done, blocked on the shop's real gateway URL
**App code:** `lib/util/otp_gateway.dart`, `lib/ui/password_settings_screen.dart`,
`lib/ui/otp_flow.dart`, `lib/features/authentication/screens/login_screen.dart`

The app never sends SMS or e-mail itself. It POSTs one JSON document to a URL the
shop configures in **Password Settings → One-time code delivery**. Any 2xx reply
means "sent"; a timeout or non-2xx means "not sent" and the app falls back to
showing the code on the phone, so a forgotten password can never lock the shop out.

---

## The exact contract

```http
POST <gateway URL>
Content-Type: application/json
X-Gateway-Secret: <shared secret>   # only when one is configured

{
  "to": "benwolf449@gmail.com",
  "channel": "email",
  "purpose": "admin_reset",
  "code": "123456",
  "message": "Jewellery Suite code 123456 — valid 10 minutes. If you did not ask for it, ignore this message.",
  "secret": "<shared secret, only when one is configured>"
}
```

| Field | Meaning |
|---|---|
| `to` | The account's e-mail address or mobile number, as stored |
| `channel` | `"email"` or `"sms"` — the toggle in Password Settings |
| `purpose` | `admin_reset`, `login`, … (free text from the caller) |
| `code` | The 6-digit code; hashing, expiry and the attempt cap already live in `LocalAccount` |
| `message` | Ready-to-send text, so a dumb gateway can forward it verbatim |
| `secret` | The same shared secret as the `X-Gateway-Secret` header. Present only when one is configured; the Apps Script and Worker examples below check this field |

- Timeout: **12 seconds** (`OtpGateway.send`).
- Success: **any 2xx**.
- Failure: non-2xx, timeout, DNS/TLS error → on-screen fallback.
- **Auth:** when a shared secret is saved (*Password Settings → One-time code
  delivery → Shared secret*) it is sent both as `X-Gateway-Secret` and as
  `secret` in the body. The gateways below reject a call without it. A gateway
  URL saved with no secret is protected by nothing but the URL itself — see
  *Security gaps* below.

---

## Option 1 — Apps Script + Gmail (e-mail only, no server)

Best for the shop's own Gmail account. Free, no card, no SMS provider.

1. <https://script.google.com> → **New project** → name it `Jewellery Suite OTP`.
2. Replace `Code.gs` with:

```javascript
const SECRET = 'PASTE_A_LONG_RANDOM_SECRET_HERE';
const ALLOWED = ['benwolf449@gmail.com', '+919121376318'];

function doPost(e) {
  try {
    const b = JSON.parse(e.postData.contents);

    if (b.secret !== SECRET) return out({ ok: false, error: 'unauthorized' });

    if (!ALLOWED.includes(b.to)) return out({ ok: false, error: 'recipient' });
    if (b.channel !== 'email') return out({ ok: false, error: 'email only' });

    MailApp.sendEmail({
      to: b.to,
      subject: 'Jewellery Suite one-time code',
      body: b.message,
      name: 'Jewellery Suite',
    });
    return out({ ok: true });
  } catch (err) {
    return out({ ok: false, error: String(err) });
  }
}

function out(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
```

3. **Deploy → New deployment → Web app**
   - Execute as: **Me**
   - Who has access: **Anyone** (the app has no Google session)
4. Copy the **`/exec`** URL.
5. In the app: **Password Settings → One-time code delivery** → paste the `/exec`
   URL → choose **E-mail** → **Save gateway**.
6. Test: **Forgot password? → Send code**. The Gmail inbox should receive it.

**Quota:** consumer Gmail allows ~100 recipients/day via `MailApp`; a shop resetting
a password a few times a month is far below it. Apps Script web apps allow 20,000
requests/day.

> Apps Script answers a POST with a 302 to `script.googleusercontent.com`. The
> `doPost` runs on the first request; Dart's `http` follows the redirect and still
> sees the JSON. Use the `/exec` URL, not `/dev` (the dev URL requires a Google
> login and will fail from the phone).

---

## Option 2 — Cloudflare Worker + SMS provider

Apps Script cannot send SMS. Put a Worker in front of Twilio / MSG91 / Fast2SMS.
The Worker keeps the provider key off the phone.

```javascript
export default {
  async fetch(req, env) {
    if (req.method !== 'POST') return json({ ok: false }, 405);

    const b = await req.json();
    if (b.secret !== env.SHARED_SECRET) return json({ ok: false }, 403);
    if (b.channel !== 'sms') return json({ ok: false, error: 'sms only' }, 400);

    const res = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${env.TWILIO_SID}/Messages.json`,
      {
        method: 'POST',
        headers: {
          Authorization:
            'Basic ' + btoa(`${env.TWILIO_SID}:${env.TWILIO_TOKEN}`),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          To: b.to,
          From: env.TWILIO_FROM,
          Body: b.message,
        }),
      },
    );
    return json({ ok: res.ok }, res.ok ? 200 : 502);
  },
};

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
```

Secrets (`TWILIO_SID`, `TWILIO_TOKEN`, `TWILIO_FROM`, `SHARED_SECRET`) go in
**Worker → Settings → Variables and Secrets**, never in the repo. The same shape
works for MSG91/Fast2SMS — only the provider URL and body change.

**Cost:** Twilio charges per SMS (India ~₹0.25–₹0.50 + carrier fees); MSG91 and
Fast2SMS have cheaper India rates. This is the only paid part of #065.

---

## Option 3 — Local mock (what we test with now)

Use this to prove the phone sends the right payload without spending an SMS.

```bash
# On the laptop, same Wi-Fi as the phone
cat > /tmp/opencode/otp_mock.py <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import datetime

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(n).decode('utf-8', 'replace')
        with open('/tmp/opencode/otp_requests.log', 'a') as f:
            f.write(f"{datetime.datetime.now().isoformat()} {self.path} {body}\n")
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"ok":true}')
    def log_message(self, *args):
        pass

HTTPServer(('0.0.0.0', 8765), H).serve_forever()
PY

: > /tmp/opencode/otp_requests.log
nohup python3 /tmp/opencode/otp_mock.py > /tmp/opencode/otp_mock.out 2>&1 &
hostname -I    # note the laptop's LAN IP, e.g. 10.52.61.21
```

Phone steps:

1. **Password Settings → One-time code delivery**
2. URL: `http://<laptop-ip>:8765/otp`
3. Channel: **E-mail** → **Save gateway**
4. Log out (or **Forgot password?**) → **Send code**
5. Check the laptop:

```bash
tail -1 /tmp/opencode/otp_requests.log
# 2026-11-05T... /otp {"to":"benwolf449@gmail.com","channel":"email",
#   "purpose":"admin_reset","code":"123456","message":"Jewellery Suite code ..."}
```

6. The app must show **Code sent**. Enter the code from the log → password reset.
7. **Remove gateway** afterwards, then repeat **Send code** and confirm the code
   is shown on the phone (offline fallback still works).

> The laptop IP changed with the Wi-Fi: it was `10.235.54.21`, it is
> `10.52.61.21` on the current network. Always re-run `hostname -I` before the test.
> Android 9+ blocks cleartext HTTP by default; the app's manifest must allow it
> for this test (or use `https://`). If the POST never arrives, check
> `adb logcat | grep -i cleartext`.

---

## Security gaps (must close before a real gateway)

1. ~~No shared secret in the app.~~ **Closed 2026-11-08:** `OtpGateway` stores
   `otp_gateway_secret` and sends it as `X-Gateway-Secret` **and** as `secret`
   in the JSON body, which is the field the Apps Script and Worker examples
   above check. Set the same value in the gateway's own secrets. A gateway URL
   saved with an empty secret still accepts calls from anyone who learns it, so
   do not leave the field blank on a real gateway.
2. **HTTP is allowed by the URL field.** Production must be `https://` only
   (#042). Cleartext puts the OTP on the Wi-Fi.
3. **The URL and secret sit in the encrypted DB.** That is acceptable, but rotate
   the secret if the phone is lost; it is a bearer credential.
4. **Do not log the code** in the gateway's production logs. The mock does; that
   is fine for a test.
5. **Rate-limit the gateway** (one code per recipient per minute) so a stolen URL
   cannot burn the SMS balance.
6. **Recipient allow-list.** The Apps Script example only sends to the shop's own
   address/number; keep that list tight.

---

## Acceptance checklist

- [ ] Gateway URL saved with the **E-mail** channel
- [ ] **Send code** produces a POST with `to`, `channel`, `purpose`, `code`, `message`
- [ ] Gateway replies 2xx and the app shows **Code sent**
- [ ] The code from the request resets the admin password
- [ ] **Remove gateway** clears the field and restores the on-screen fallback
- [ ] Airplane mode → **Send code** falls back on-screen without an error dialog
- [ ] Real gateway: HTTPS URL + shared secret (both the app field and the
      gateway's own secret) + rate limit
