# HCG News (iPhone/iPad) × HCG Connect and ERP — configuration handoff

For: the owner of the main HCG project (ERP / Executive Control Center, HCG Connect/Auth) and the owner of news.hakmicapitalgroup.com.
Status: **preparation only. Nothing has been registered, granted, deployed or changed centrally.** Every value marked PROPOSED needs a decision. The app ships with **no** configuration, so it makes no identity or content request until an approved file is installed.

Labels: **CONFIRMED** = verified in existing HCG source (not live-tested); **PROPOSED** = needs approval; **UNRESOLVED** = needs a value from central HCG.

## 1. What already exists in the app

| Piece | Where | Behaviour |
|---|---|---|
| Configuration loader | `HCGNewsKit/Sources/HCGConnect/ConnectConfiguration.swift` | No defaults. It rejects secrets (`*secret*`, `*password*`, `service_role` keys), non-HTTPS endpoints, endpoints off the issuer or HCG hosts, an App Access endpoint off HCG hosts, a redirect that doesn't use this app's own scheme, and anything without `approvedByFounder: true`. |
| PKCE | `PKCE.swift` | S256, verifier from the system CSPRNG, kept in memory only, sent only to the token endpoint. Tested against the RFC 7636 Appendix B vector. |
| System-browser sign-in | `HCGNews/Platform/SystemBrowserAuthenticator.swift` | `ASWebAuthenticationSession`. Ephemeral session by default, configurable. Never an embedded web view. |
| Callback validation | `AuthorizationFlow.swift` | Exact redirect scheme, host and path. `state` must match. `access_denied` and provider errors are mapped. The code is discarded on any mismatch. |
| Session coordinator | `HCGConnectCoordinator.swift` | Token exchange, single-flight refresh, App Access check, revocation handling and sign-out reporting. |
| Keychain store | `KeychainSessionStore.swift` | One generic-password item, service `com.hakmicapitalgroup.hcgnews.connect`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronisable. |
| Newsroom entry policy | `SessionAndAccess.swift` `NewsroomEntryPolicy` | Shown only when **this run's** App Access decision is `granted`, unexpired, for HCG News' identifier and names the configured permission. Signing in alone never shows it. The newsroom must enforce access itself. |

Tests: `HCGNewsKit/Tests/HCGConnectTests` (27 cases). They cover cancellation, denial, forged state, expiry, rejected refresh, offline refresh, concurrent refresh, 401→refresh→retry, revoked, 403, foreign app/subject decisions, and sign-out with and without an endpoint.

## 2. Proposed native client registration

| Item | Value | Status |
|---|---|---|
| App name | HCG News (iPhone and iPad) | — |
| Bundle identifier | `com.hakmicapitalgroup.hcgnews` | **PROPOSED** (follows `com.hakmicapitalgroup.hcgoneunleashed` and `com.hakmicapitalgroup.lifeos`). Changing it changes the callback scheme. |
| Client type | Public native client, **no client secret** (RFC 8252) | **PROPOSED**. The app refuses a configuration containing a secret. |
| Grant | Authorization Code + PKCE `S256` | CONFIRMED as supported by the HCG identity provider for CardX; **UNRESOLVED** for a new HCG News client |
| Redirect URI | `com.hakmicapitalgroup.hcgnews:/oauth/callback` | **PROPOSED** (RFC 8252 §7.1 private-use scheme = bundle id). The app accepts only this scheme. Registering it with the provider is a central task. |
| Client ID | — | **UNRESOLVED**. Must be a **new** client. CardX's `3eb7b66b-…` must not be reused. |
| Scopes | `openid profile` | **PROPOSED** (what CardX requests). Email is not needed. |
| Browser session | Ephemeral (no shared Safari cookies) | **PROPOSED**. Set `ephemeralBrowserSession: false` if central HCG wants single sign-on with Safari. |
| App Access identifier | `hcg-news-ios` | **PROPOSED**. HCG News' entry in the central App Access registry. |

## 3. Proposed central App Access permissions

The app treats permission names as opaque strings and never derives access from roles, email or display name.

| Permission (PROPOSED name) | Effect in the app | Enforced by |
|---|---|---|
| *(none)* | Public reporting is readable without any account | — |
| `news.newsroom.open` | Shows an "Open the newsroom" link (to `newsroomURL`) in Settings | The newsroom web app, server-side, on every request |
| *(restricted reading)* | The app sends the bearer token only after the content API says an article is restricted | The content API, server-side |

Signing in **never** grants a newsroom role. Granting `news.newsroom.open` is a manual central decision.

## 4. Endpoints

| Purpose | Value | Status |
|---|---|---|
| Issuer | Supabase Auth project `qggdyzoydveafkmjgkpq` (exact issuer URL as published by the provider) | CONFIRMED identity provider (HCG ONE, CardX). Exact issuer string **UNRESOLVED** for HCG News. |
| Authorization endpoint | Provider's OAuth authorize URL, as discovered for CardX | **UNRESOLVED**. CardX discovers it at runtime from `…/api/public/cardx/v1/auth-config`. HCG News needs either its own `…/api/public/news/v1/auth-config` or fixed values. |
| Token endpoint (code exchange) | Provider's OAuth token endpoint (form-encoded) | CONFIRMED shape (CardX). Value **UNRESOLVED**. |
| Refresh | `{issuer}/token?grant_type=refresh_token`, JSON body, public `apikey` header → config `refreshFormat: "provider-json"` | CONFIRMED in CardX source ("verified against the live issuer"). Central HCG should confirm this is the approved route for a new client. |
| Sign-out | `{issuer}/logout` with bearer → `signOutFormat: "provider-logout"`; or an RFC 7009 revocation endpoint → `"rfc7009"` | **UNRESOLVED**. Scope semantics needed (§6). |
| Provider public key | The project's **anon** key, if the provider gateway requires it on token/refresh/logout | CONFIRMED required by CardX's provider calls. The app rejects any key whose JWT role is not `anon`. |
| App Access | `GET <endpoint>?app=hcg-news-ios` with bearer → decision JSON (§5) | **UNRESOLVED (does not exist yet)**. PROPOSED: `https://beta.hakmicapitalgroup.com/api/public/mobile/app-access`, next to the existing `/api/public/mobile/workspaces`. |
| Newsroom URL | HCG web route for the newsroom | **UNRESOLVED** |
| Content API | See [HCG-NEWS-CONTENT-API-PROPOSAL.md](HCG-NEWS-CONTENT-API-PROPOSAL.md) | **UNRESOLVED (does not exist yet)** |

### App Access decision (PROPOSED, same shape as the LifeOS handoff)

```json
{
  "appIdentifier": "hcg-news-ios",
  "subject": "<same subject as the access token's sub>",
  "organizationID": null,
  "status": "granted | denied | revoked | unlicensed | suspended",
  "permissions": ["news.newsroom.open"],
  "validUntil": "2026-11-04T12:00:00Z",
  "reason": "<human-readable when not granted>"
}
```

The app rejects a decision for another `appIdentifier` or another `subject`. `revoked` clears the local session. A `403` with no readable decision is shown as "Not granted".

## 5. The configuration file

Install it as `HCGNews/HCGNews/Configuration/HCGNewsConfiguration.json`. Xcode bundles that folder automatically. The path is git-ignored so that unapproved values are never committed. A template with placeholders is in [`HCGNewsConfiguration.example.json`](HCGNewsConfiguration.example.json). Both sections are independent: content can be connected before sign-in, and the other way round.

| Field | Required | Notes |
|---|---|---|
| `content.contractVersion` | yes | `"1"` |
| `content.environment` | yes | e.g. `beta` |
| `content.apiBaseURL` | yes | HTTPS, `*.hakmicapitalgroup.com` |
| `content.publicationURL` | yes | Used to resolve relative links in article HTML |
| `content.approvedByFounder` | yes | must be `true` |
| `connect.contractVersion`, `environment`, `issuer`, `authorizationEndpoint`, `tokenEndpoint`, `appAccessEndpoint`, `clientID`, `redirectURI`, `scopes`, `appIdentifier` | yes | |
| `connect.refreshEndpoint`, `refreshFormat` | no | defaults: token endpoint, `oauth-form` |
| `connect.signOutEndpoint`, `signOutFormat` | no | without them, sign-out is local only and the app says so |
| `connect.providerPublicKey` | no | anon key only; required for `provider-json` |
| `connect.newsroomPermission`, `newsroomURL` | no | both, or neither |
| `connect.ephemeralBrowserSession` | no | default `true` |
| `connect.approvedByFounder` | yes | must be `true` |

## 6. Logout, expiry and revocation behaviour

| Event | What the app does | What it does **not** claim |
|---|---|---|
| Access token near expiry (≤ 60 s) | One refresh (single-flight; concurrent callers share it) | — |
| Refresh rejected (`400`/`401`) | Deletes the Keychain item → state "Your HCG session expired" | — |
| Refresh offline | Keeps the session; an expired access token is not used | — |
| App Access `401` | One forced refresh, then retry; a second `401` → expired | — |
| App Access `status: revoked` | Deletes the Keychain item, signs out, says "HCG revoked this app's access" | That other devices were signed out |
| Sign-out, endpoint configured and acknowledged | Keychain item deleted; "HCG Connect confirmed the sign-out request" | Immediate invalidation of already-issued access tokens. Supabase access tokens are JWTs that stay valid until they expire. |
| Sign-out, endpoint unreachable | Keychain item deleted; "couldn't be reached to confirm, so the session may stay valid elsewhere until it expires" | — |
| Sign-out, no endpoint configured | Keychain item deleted; "Other devices and the HCG website are not affected" | — |
| Different environment in the Keychain | Discarded at launch | — |

**Central HCG must state:** whether `/logout` for this client should use `scope=local` (this session) or `global` (every session of the user, including the website). Note that CardX sends `global`. Also state the access-token lifetime, refresh-token rotation and reuse detection, and whether revocation is visible to App Access immediately. A scope can be put in the sign-out URL query, for example `…/logout?scope=local`.

## 7. Decisions and values needed from central HCG

1. Approve or change the bundle id, redirect URI, scopes, App Access identifier and permission names (§2–3).
2. Register a **new public native client** for HCG News, with no secret and with PKCE required, and provide the `clientID`. Do not reuse CardX's client.
3. Provide the issuer, authorization, token, refresh and sign-out endpoint values for each environment (§4). Alternatively, publish `…/api/public/news/v1/auth-config` like CardX's.
4. Build or approve the **App Access read endpoint** (§4). It does not exist today.
5. Logout scope, token lifetimes, rotation and revocation semantics (§6).
6. Newsroom URL, and confirmation that the newsroom enforces permissions server-side.
7. Content API (separate owner), per [INTEGRATION-DISCOVERY.md](INTEGRATION-DISCOVERY.md) §5.
8. Founder approval, recorded by setting `approvedByFounder: true` in the reviewed file.

Not requested, and not done by this project: changing central security policy, RLS, roles or auth settings; registering clients; granting roles; deploying.

## 8. Acceptance tests once configured (on a device or simulator)

1. No file installed: Home shows "Live publication not connected", Settings shows "isn't set up", and a network monitor shows **zero** HCG requests. (This is automated as a model test and a UI test.)
2. A file with a secret, an `http://` endpoint, or CardX's redirect: shown as invalid, and nothing is attempted. (Automated.)
3. Approved file: *Sign In* opens the system browser at the HCG page. Cancel → "Sign-in was cancelled", with no token request.
4. Successful sign-in → Keychain item created (device-only) → App Access fetched → status shown. The newsroom link appears **only** with `news.newsroom.open`.
5. Denied or unlicensed account → "Not granted" with the central reason. Public articles still readable.
6. Central revocation → next access check signs out locally.
7. Expiry: set a short token lifetime in beta → silent refresh. Revoke the refresh token centrally → "session expired".
8. Sign-out with the endpoint reachable, and with it unreachable → messages match §6.
9. Offline at launch with a stored session → reading works; Settings shows the access check failure with *Check Access Again*.
10. Restricted article while signed out → "Sign-in required". Signed in without permission → "No access". With permission → readable.

## 9. Paste-ready request for the main-site session

> You are working on the HCG main site, which owns HCG identity, App Access, roles and the ERP / Executive Control Center. Prepare, **but do not deploy, enable or grant**, the central side of native sign-in for **HCG News for iPhone and iPad** (proposed bundle id `com.hakmicapitalgroup.hcgnews`). Do not change existing RLS, roles, auth settings or security policy automatically. Write each proposed change as a reviewable diff plus a summary for founder approval. Do not reuse the CardX OAuth client.
>
> Please produce:
> 1. A proposed **public native OAuth client** (PKCE required, no secret) with redirect `com.hakmicapitalgroup.hcgnews:/oauth/callback` and scopes `openid profile`. Give the issuer, authorization, token, refresh and logout endpoint values per environment, and state whether refresh must use the provider's native `/token?grant_type=refresh_token` route (as CardX does).
> 2. A proposed **App Access read endpoint**: `GET …?app=hcg-news-ios` with a bearer token. It returns `{appIdentifier, subject, organizationID, status (granted|denied|revoked|unlicensed|suspended), permissions[], validUntil, reason}`, enforced server-side, with no inference from email or display name.
> 3. Permission names for HCG News, including one that allows showing a newsroom entry point (proposed `news.newsroom.open`), plus the newsroom URL. Confirm that the newsroom enforces access itself.
> 4. Logout semantics (local or global scope), access-token lifetime, refresh rotation and reuse detection, and how revocation surfaces.
> 5. Filled-in values, or "TBD", for every `connect.*` field in HCG News' `docs/HCGNewsConfiguration.example.json`, kept pending until the founder sets `approvedByFounder`.
