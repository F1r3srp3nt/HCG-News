# HCG News Content API v1 — PROPOSAL

Status: **PROPOSED. Not implemented by any HCG server, and not confirmed.** No supported content API for news.hakmicapitalgroup.com was available to inspect (see [INTEGRATION-DISCOVERY.md](INTEGRATION-DISCOVERY.md) §2).

The iPhone/iPad app decodes exactly this shape (`HCGNewsKit/Sources/NewsCore/WireFormat.swift`, `Models.swift`). The publication owner should do one of the following:

- **(a)** implement it as a thin read-only layer over the existing newsroom data; or
- **(b)** return the existing supported contract, so the app's decoder can be changed to match it.

Either way, nothing here creates a second newsroom database. It is a read view of the publication's existing source of truth.

The app only calls this API after an approved configuration names its base URL (see [HCG-MAIN-CONFIGURATION-HANDOFF.md](HCG-MAIN-CONFIGURATION-HANDOFF.md) §5). The app refuses non-HTTPS URLs and hosts outside `hakmicapitalgroup.com`.

## 1. General

- Base URL (PROPOSED): `https://news.hakmicapitalgroup.com/api/public/news/v1/`. This mirrors the existing CardX canonical-gateway pattern `…/api/public/cardx/v1/`.
- `GET` only, JSON, UTF-8, timestamps in ISO 8601 with a zone.
- Public reads are anonymous: no token, no cookies.
- **The server returns only published, public or explicitly restricted content.** Drafts, scheduled, private, internal and deleted items must never appear. The app also filters them as a safeguard.
- Errors: `404`/`410` not found, `401` or `403` with `{"error":"restricted"}` for restricted content, `429` rate limited, `503` unavailable. The body is `{"error": "<code>", "message": "<text>"}`.
- Caching: `Cache-Control` and `ETag` are welcome. The app does not rely on them in v1.

## 2. Endpoints

| Method & path | Purpose | Response |
|---|---|---|
| `GET meta` | Contract version and capabilities. Called first. | `{"contractVersion":"1","capabilities":{"search":true}}` |
| `GET home` | Home screen as decided by editors | `{"featured":[Summary],"breaking":[Summary],"latest":{"items":[Summary],"nextCursor":"…"\|null}}` |
| `GET sections` | Section source of truth, including hierarchy | `{"sections":[Section]}` |
| `GET articles?section=<slug>&cursor=<c>` | Latest published, optionally in one section | `{"items":[Summary],"nextCursor":"…"\|null}` |
| `GET articles/{id}` | Full article by stable id | `Article` |
| `GET search?q=<text>&cursor=<c>` | Full-text search (only if `capabilities.search`) | `{"items":[Summary],"nextCursor":…}` |

If `contractVersion` differs from the version the app was configured for, the app stops and shows "This version can't read the publication". It does not guess.

## 3. Objects

```jsonc
// Section
{ "id": "…", "slug": "norwegian-politics", "name": "Norwegian Politics",
  "description": null, "parentSlug": "politics", "position": 2 }

// Summary
{
  "id": "…",                      // stable, never reused; bookmarks key on this
  "slug": "…",
  "canonicalUrl": "https://news.hakmicapitalgroup.com/…",   // used for sharing
  "headline": "…",
  "standfirst": "…",              // optional
  "section": { "id": "…", "slug": "…", "name": "…" },
  "editorialType": "news" | "analysis" | "opinion",          // other values shown verbatim
  "authors": [ Author ],
  "publishedAt": "2026-11-03T10:15:00Z",
  "updatedAt": "2026-11-03T11:00:00Z",                       // optional
  "image": { "url": "https://…", "width": 1600, "height": 900,
             "alt": "…", "caption": "…", "credit": "…" },     // optional
  "isFeatured": false,
  "breaking": { "active": true, "expiresAt": "…", "label": "Breaking" },  // optional; explicit editorial flag
  "access": "public" | "restricted",                          // absent = public
  "status": "published"                                       // optional; anything else is hidden
}

// Author — `id` is the verified author identity, not a display name
{ "id": "…", "name": "…", "title": "…",
  "disclosures": [ { "id": "…", "authorID": "…", "text": "…", "kind": "political-affiliation" } ] }

// Article = Summary fields + body + sources
{ …Summary…,
  "body": { "format": "blocks", "blocks": [Block] }    // preferred
       // or { "format": "html", "html": "<p>…</p>" }  // sanitised natively by the app
  "sources": [ { "title": "…", "url": "https://…", "publisher": "…" } ] }
```

### Blocks

| `type` | Fields | Notes |
|---|---|---|
| `heading` | `level` (2–4), `text` or `html` | |
| `paragraph` | `text` (plain, taken literally) or `html` (inline: `a`, `strong`/`b`, `em`/`i`, `code`, `br`) | |
| `list` | `ordered`, `items` (inline HTML strings) | |
| `quote` | `text` or `html`, `attribution` | |
| `image` | `image` (object as above) | HTTPS only |
| `divider` | — | |
| `embed` | `url` | **Not loaded.** The app shows "Embedded content not shown" and links to the web article. |

Unknown block types are skipped, not rendered as raw text.

### HTML bodies

If the newsroom stores HTML, `format: "html"` is acceptable. The app never renders HTML in a web view. It converts an allow-list of structures (`p`, `h1`–`h6`, `ul`/`ol`/`li`, `blockquote` + `cite`/`footer`, `figure`/`img`/`figcaption`, `hr`, `pre`, `br`, `a`, `strong`/`b`, `em`/`i`, `code`) into native text. It drops `script`, `style`, `form`, `svg`, `template`, event handlers and every other attribute, and it replaces `iframe`/`video`/`audio`/`object`/`embed` with a notice. Links are kept only for `https`, `http` and `mailto`.

## 4. Editorial rules the server owns

- **Breaking:** only items an editor explicitly flags. Optional `expiresAt` ends the flag. The app never infers breaking from recency.
- **Featured:** only items flagged `isFeatured` (or curated in `home.featured`). If none, Home shows Latest only.
- **Disclosures:** attached to the verified author record and returned with every article by that author. The app renders the text verbatim in a "Disclosure" box under the byline. It never matches on author names. Where else a disclosure must appear (for example list cards) is an editorial decision still to be confirmed.
- **Restricted content:** listed with `access: "restricted"`. The detail endpoint returns `401` or `403` (`{"error":"restricted"}`) without a valid bearer token, and authorizes server-side when a token is present.

## 5. Not part of v1

Write endpoints, comments, analytics or tracking parameters, personalisation, push, and offline bundles.
