# APNs Server-Side Sending Research (Deno / Edge Functions)

## Scope
Sending push notifications from a Supabase Edge Function (Deno) to Apple Push Notification service via the HTTP/2 provider API with token-based (JWT) authentication.

## Primary Sources
- Apple: Establishing a token-based connection to APNs:
  - https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns
- Apple: Communicating with APNs (archive, HTTP/2 details):
  - https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CommunicatingwithAPNs.html
- Deno fetch API (supports HTTP/2 over HTTPS):
  - https://docs.deno.com/api/deno/fetch

## 1) APNs HTTP/2 Endpoints

| Environment | Host | Port |
|-------------|------|------|
| Production | `api.push.apple.com` | 443 (or 2197) |
| Sandbox/Dev | `api.development.push.apple.com` | 443 (or 2197) |

Protocol: HTTP/2 over TLS 1.2+.
Request path: `/3/device/<device-token>` (hex-encoded device token).

## 2) JWT Structure (Provider Authentication Token)

### Header
```json
{
  "alg": "ES256",
  "kid": "ABC123DEFG"
}
```
- `alg`: Must be `ES256` (ECDSA with P-256 curve and SHA-256)
- `kid`: 10-character Key ID from Apple Developer account

### Claims
```json
{
  "iss": "DEF123GHIJ",
  "iat": 1437179036
}
```
- `iss`: 10-character Team ID from Apple Developer account
- `iat`: UNIX timestamp (seconds since epoch, UTC)

### Token validity
- Valid for **1 hour** from `iat`.
- APNs rejects stale tokens with `ExpiredProviderToken` (403).
- Cache and reuse tokens — do not generate per-request.

## 3) HTTP/2 Request Format

### Required headers
| Header | Value |
|--------|-------|
| `:method` | `POST` |
| `:path` | `/3/device/<hex-device-token>` |
| `authorization` | `bearer <JWT>` |
| `apns-topic` | App bundle ID (e.g., `com.214-pickle`) |

### Optional headers
| Header | Description |
|--------|-------------|
| `apns-push-type` | `alert`, `background`, `voip`, etc. |
| `apns-id` | UUID for deduplication |
| `apns-expiration` | UNIX timestamp; `0` = don't store if undeliverable |
| `apns-priority` | `10` (immediate) or `5` (power-considerate) |
| `apns-collapse-id` | Max 64 bytes; coalesces notifications |

### Request body (JSON payload)
Max 4KB (4096 bytes).

```json
{
  "aps": {
    "alert": {
      "title": "New pickleball booking",
      "body": "Kris added you to a game at Sat, Apr 05 at 10:00 AM."
    },
    "sound": "default",
    "badge": 1
  }
}
```

## 4) Deno HTTP/2 Support

From Deno docs: Deno's `fetch()` automatically negotiates HTTP/2 over HTTPS via ALPN (Application-Layer Protocol Negotiation). No special configuration needed — just use `fetch()` with an HTTPS URL.

This means calling APNs from a Supabase Edge Function works with standard `fetch()`.

## 5) JWT Signing in Deno (ES256 via Web Crypto API)

The APNs `.p8` key is a PEM-encoded PKCS#8 EC private key (P-256). Deno's Web Crypto API supports `ECDSA` with `P-256`.

### Importing the .p8 key
```ts
function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes.buffer
}

async function importApnsKey(pemContents: string): Promise<CryptoKey> {
  const keyData = pemToArrayBuffer(pemContents)
  return await crypto.subtle.importKey(
    'pkcs8',
    keyData,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  )
}
```

### Creating and signing the JWT
```ts
function base64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}

function base64urlEncode(obj: Record<string, unknown>): string {
  return base64url(new TextEncoder().encode(JSON.stringify(obj)))
}

async function createApnsJwt(
  key: CryptoKey,
  keyId: string,
  teamId: string
): Promise<string> {
  const header = base64urlEncode({ alg: 'ES256', kid: keyId })
  const claims = base64urlEncode({ iss: teamId, iat: Math.floor(Date.now() / 1000) })
  const unsignedToken = `${header}.${claims}`

  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(unsignedToken)
  )

  // Convert DER signature to raw r||s format for JWT
  const sigBytes = new Uint8Array(signature)
  return `${unsignedToken}.${base64url(sigBytes)}`
}
```

Note: Web Crypto ECDSA `.sign()` returns raw r||s concatenation (64 bytes for P-256), which is the correct format for JWT ES256. No DER conversion needed.

### Token caching
```ts
let cachedToken: string | null = null
let tokenCreatedAt = 0
const TOKEN_TTL = 50 * 60 * 1000 // refresh every 50 min (valid for 60)

async function getApnsToken(key: CryptoKey, keyId: string, teamId: string): Promise<string> {
  if (cachedToken && Date.now() - tokenCreatedAt < TOKEN_TTL) {
    return cachedToken
  }
  cachedToken = await createApnsJwt(key, keyId, teamId)
  tokenCreatedAt = Date.now()
  return cachedToken
}
```

## 6) Sending a Push Notification

```ts
async function sendApnsPush(
  deviceToken: string,
  payload: Record<string, unknown>,
  jwt: string,
  bundleId: string,
  sandbox: boolean = false
): Promise<{ success: boolean; status: number; apnsId?: string; error?: string }> {
  const host = sandbox
    ? 'api.development.push.apple.com'
    : 'api.push.apple.com'

  const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: 'POST',
    headers: {
      'authorization': `bearer ${jwt}`,
      'apns-topic': bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    },
    body: JSON.stringify(payload),
  })

  const apnsId = response.headers.get('apns-id') ?? undefined

  if (response.status === 200) {
    return { success: true, status: 200, apnsId }
  }

  const body = await response.json()
  return { success: false, status: response.status, apnsId, error: body.reason }
}
```

## 7) Supabase Edge Function Secrets

Store these as Edge Function secrets:
```bash
supabase secrets set APNS_KEY_ID=ABC123DEFG
supabase secrets set APNS_TEAM_ID=DEF123GHIJ
supabase secrets set APNS_BUNDLE_ID=com.214-pickle
supabase secrets set APNS_P8_KEY="-----BEGIN PRIVATE KEY-----\nMIGH...full key content...\n-----END PRIVATE KEY-----"
supabase secrets set APNS_SANDBOX=true
```

Access in function:
```ts
const keyId = Deno.env.get('APNS_KEY_ID')!
const teamId = Deno.env.get('APNS_TEAM_ID')!
const bundleId = Deno.env.get('APNS_BUNDLE_ID')!
const p8Key = Deno.env.get('APNS_P8_KEY')!
const sandbox = Deno.env.get('APNS_SANDBOX') === 'true'
```

## 8) HTTP Response Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success (empty body) |
| 400 | Bad request (various reason strings) |
| 403 | Auth error: `ExpiredProviderToken`, `InvalidProviderToken`, `MissingProviderToken` |
| 405 | Only POST allowed |
| 410 | `Unregistered` — device token inactive, stop sending |
| 413 | Payload too large (>4KB) |
| 429 | Too many requests to same device |
| 500 | APNs internal error |
| 503 | Service unavailable |

Error response body:
```json
{
  "reason": "ExpiredProviderToken",
  "timestamp": 1234567890
}
```

## 9) Important 410 Handling

When APNs returns `410 Unregistered`, includes a `timestamp` of when the token was last valid. Remove the device token from your database — the user uninstalled the app or disabled notifications.

## Recommendation for This App

1. Store `.p8` key content as `APNS_P8_KEY` secret.
2. Use Web Crypto API for JWT signing (no external libraries needed).
3. Cache JWT tokens for 50 minutes.
4. Use sandbox endpoint during development, production for TestFlight/App Store.
5. Handle 410 by clearing `profiles.apns_device_token`.
