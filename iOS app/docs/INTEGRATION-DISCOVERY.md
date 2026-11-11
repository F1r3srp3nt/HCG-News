# HCG News app — integration discovery

Status: **Milestone 1 discovery record, 3 November 2026.** Nothing in this document was tested against a live HCG server. This environment's network policy blocked every HCG host (see §1).

## Labels

| Label | Meaning |
|---|---|
| **VERIFIED** | Present in source code of an HCG repository I could read. This does **not** mean it was confirmed working against the live server. |
| **REPORTED** | Stated in an HCG document or code comment, but not visible as working code. |
| **PROPOSED** | Written in this milestone for HCG to accept, change or reject. |
| **MISSING** | Required, but not found anywhere I could inspect. |

## 1. What was inspected

| Source | Result |
|---|---|
| `F1r3srp3nt/HCG-News` (this repo) | Only a README (`news.hakmicapitalgroup.com apps`). No app, website source or API code. |
| `F1r3srp3nt/HCG-One` (`b4f0e29`) | HCG ONE iOS app + main website source. Contains `HCG-CARDX-AUTH-INTEGRATION-REPORT.md` (identity infrastructure) and the official destination list, which includes `https://news.hakmicapitalgroup.com`. **No news content API.** |
| `F1r3srp3nt/HCG-ONE-UNLEASHED` (`c7b657f`) | `docs/INTEGRATIONS.md` records: "News feed API: **None** (in-code list)". |
| `F1r3srp3nt/hcg-cardx` (`e6d5545`) | Working native OAuth 2.0 Authorization Code + PKCE sign-in against the HCG identity provider, with **CardX's own** client (`HCGCardX/Services/HCGAuth.swift`). |
| `F1r3srp3nt/HCG-LifeOS` (`a4994e4`) | `docs/HCG-CONNECT-LIFEOS-HANDOFF.md`: a native-client handoff draft with a proposed App Access response shape. |
| `F1r3srp3nt/hakmi-capital-group-website-test`, `HCG-Mail`, `HCG-Terminal`, `HCG-Executable-Maker`, `HCG-RePrompter` | Nothing about news content or HCG Connect contracts. |
| `docs/hcg-auth-contract.md`, `docs/hcg-authorization-contract.md`, `docs/hcg-connect/handoffs/` | **MISSING.** Not in any repository available to this session (checked by file search in every clone above). |
| `https://news.hakmicapitalgroup.com`, `beta.hakmicapitalgroup.com`, the identity provider host | **Not reachable from this environment.** The cloud environment's network policy refused the connections. No page was fetched or scraped. |

## 2. News content: findings

| Item | Status | Detail |
|---|---|---|
| Article listing endpoint | **MISSING** | No supported API found. UNLEASHED's audit independently reached the same conclusion. |
| Article detail endpoint | **MISSING** | |
| Stable article IDs / slugs / canonical URLs | **MISSING** | The app keys everything on an opaque backend `id`. Slugs are display/URL only. |
| Categories / sections source of truth | **MISSING** | Politics, Norwegian Politics and International Politics are **not hard-coded**. The app shows whatever sections, and hierarchy, the backend returns. |
| Editorial type (News / Analysis / Opinion) | **MISSING** | Supported as a field; shown verbatim. Unknown values are kept. |
| Authors and disclosures | **MISSING** | Disclosures render only from backend data attached to a verified author id. |
| Yasin Ludvigsen Hakmi's FrP/FpU disclosure | **MISSING: exact text and placement rule** | The app does not contain or compose this text. It must come from the backend for the verified author identity (see §5). |
| Body format and content blocks | **MISSING** | The app supports structured blocks or sanitised HTML (proposal §4). |
| Pagination, search | **MISSING** | Cursor pagination proposed. Search falls back to articles loaded on the device, and says so. |
| Images, captions, credits | **MISSING** | Supported fields: url, width, height, alt, caption, credit. |
| Publication visibility rules | **MISSING** | Client-side defence in depth only (see Architecture §4). The backend must enforce them. |
| Breaking news rule | **MISSING** | The app shows breaking items only for an explicit `breaking.active` flag. Recency never makes an item breaking. |

## 3. Identity and authorization: findings

| Item | Status | Source |
|---|---|---|
| Shared identity = Supabase Auth project behind the main site (`qggdyzoydveafkmjgkpq`) | VERIFIED | HCG ONE report §2, CardX `HCGAuth.swift` (anon key JWT `ref`) |
| Native OAuth 2.0 Authorization Code + PKCE (S256) via `ASWebAuthenticationSession` | VERIFIED (for CardX) | CardX `HCGAuth.swift` `signIn()` |
| Endpoints are discovered from a **product-specific** `GET …/api/public/cardx/v1/auth-config` (issuer, authorization, token, userinfo, scopes) | VERIFIED (CardX only) | CardX `HCGAuth.swift` header and `ensureDiscovery()` |
| Consent surface `https://beta.hakmicapitalgroup.com/.lovable/oauth/consent` | VERIFIED (CardX config) | CardX `HCGAuthConfig.consentURL` |
| Code exchange: form-encoded POST to the discovered OAuth `token_endpoint` (`grant_type`, `code`, `code_verifier`, `client_id`, `redirect_uri`) | VERIFIED | CardX `exchangeCode` / `tokenRequest` |
| Refresh is **not** served by the OAuth token endpoint; CardX refreshes at the provider's native `{issuer}/token?grant_type=refresh_token` with a JSON body and the public `apikey` header | VERIFIED (CardX code + comment: "verified against the live issuer") | CardX `HCGAuth.swift` lines ~484–520, ~780 |
| Sign-out: `POST {issuer}/logout` with bearer token (CardX sends `scope: global`) | VERIFIED (CardX) | CardX `signOut()` |
| Authorization is decided server-side by the website mobile API (`GET /api/public/mobile/workspaces`, `POST /api/public/mobile/handoff`) | VERIFIED (HCG ONE) | HCG ONE report §4, §8 |
| An **App Access** endpoint for a specific app | **MISSING** | LifeOS handoff §5 proposes a shape (PENDING). HCG News uses the same shape (PROPOSED). |
| HCG News native OAuth client (client id, redirect, scopes) | **MISSING** | It must be registered by central HCG. CardX's client (`3eb7b66b-…`) must not be reused, and the app rejects CardX's redirect scheme. |
| Exact logout / revocation semantics (per app or global; access-token validity after logout) | **MISSING** | See handoff §6. The app never claims global logout. |
| Role semantics | Known risk | HCG ONE maps roles by substring (UNLEASHED `SECURITY_BOUNDARIES.md` S-02). HCG News reads **no roles**. It only uses centrally issued permission names from App Access. |

## 4. Logo assets

`HCGLogo.png` (1024×1024, silver on black) is byte-identical in HCG ONE (`ios-hcg/HCGONE/Assets.xcassets/HCGLogo.imageset`), the main website (`public/hcg-logo.png`), CardX and UNLEASHED. HCG News uses that file unchanged, and HCG ONE's `AppIcon` `icon.png` as its app icon. `HCGLogoTrimmed.png` is the same artwork with its empty black margins cropped (606×447) so it stays legible at navigation-bar size. Nothing was redrawn.

## 5. Exact missing inputs (blocking live content)

From the owner of news.hakmicapitalgroup.com:

1. The supported, versioned **read API** for published articles: base URL per environment, authentication (if any for public reads), rate limits. Alternatively, confirmation of which existing mechanism is the supported contract (for example a Supabase table or view behind RLS, or an edge function). If an existing endpoint is chosen, its exact path and response schema.
2. The **article schema**: id type, slug, canonical URL rule, status values, access/visibility values, `publishedAt`/`updatedAt` semantics, scheduled-publication handling.
3. The **body format** (HTML, Markdown, editor JSON…) and the block types actually used in published articles.
4. **Sections**: the source table/list, hierarchy (for example Norwegian Politics under Politics), ordering and slugs.
5. **Editorial type** field and its allowed values.
6. **Authors**: verified author ids, how disclosures are stored, the **exact current FrP/FpU disclosure text** for Yasin Ludvigsen Hakmi, and the editorial rule for where it must appear (article page only, or also cards, bylines or share text).
7. **Breaking** and **featured** flags (field names, expiry semantics, who may set them).
8. **Pagination** (cursor or page) and whether full-text **search** exists.
9. **Images**: hosting domain, intrinsic dimensions, alt text, caption and credit fields.
10. Whether any content is **restricted**, and how restricted reads are authorized.

From central HCG (ERP / Executive Control Center): see [HCG-MAIN-CONFIGURATION-HANDOFF.md](HCG-MAIN-CONFIGURATION-HANDOFF.md) §7.

From the environment owner (to test from a cloud session): allow `news.hakmicapitalgroup.com`, `beta.hakmicapitalgroup.com` and the identity provider host in the cloud environment's network settings. Alternatively, run the tests on a Mac.
