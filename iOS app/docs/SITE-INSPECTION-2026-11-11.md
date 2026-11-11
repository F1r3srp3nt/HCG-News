# What news.hakmicapitalgroup.com serves — inspection, 11 November 2026

**Purpose:** gather evidence for the content contract. **Nothing here is an API the app uses.** The app still shows "Live publication not connected" until the publication owner confirms a supported contract (see [INTEGRATION-DISCOVERY.md](INTEGRATION-DISCOVERY.md) §5).

**Method:**
- Anonymous HTTPS GETs from a cloud session, with the user agent `HCGNewsIntegrationCheck/0.1`.
- About 12 requests in total: the home page, `robots.txt`, `sitemap.xml`, three article pages, three JS bundles, and feed and API paths probed for existence.
- No logins, no calls to the site's internal server functions, no database (PostgREST) queries, and no bulk download.

## 1. Platform

| Finding | Evidence |
|---|---|
| Server-rendered React app (TanStack Start / TanStack Router), behind Cloudflare | `server: cloudflare`; bundles `useRouter`, `matchContext`, `createServerFn` |
| Data is fetched through TanStack **server functions** addressed by build hashes (`/_serverFn/<sha256>`), 13 of them | `assets/public.functions-*.js` |
| Media in the Supabase storage bucket `hcg-news-media` on project `qggdyzoydveafkmjgkpq` (the same project as HCG identity), as long-lived signed URLs | image URLs in `og:image` and JSON-LD |

**Consequence:** the server functions are private plumbing between the website's frontend and its server. Their IDs change on every deploy and they have no documented shape. **They are not a supported API, and the app must not call them.** The data appears to live in the shared Supabase project, but table names and columns were not inspected or guessed.

## 2. Public, machine-readable surfaces

| Surface | Status |
|---|---|
| `robots.txt` | Allows `/`; disallows `/admin`, `/auth`, `/reset-password`, `/newsletter/` |
| `sitemap.xml` | 29 URLs: 8 static pages, 10 section pages, 3 author pages, 8 articles, with `lastmod` |
| RSS / Atom / JSON feed (`/rss.xml`, `/feed.xml`, `/feed`, `/rss`) | **None** (404). The only `rel="alternate"` link is the sitemap. |
| `/api/…` routes, including the proposed `/api/public/news/v1/meta` (on both news and beta hosts) | **None** (404) |
| Per-article JSON-LD | `NewsArticle` / `AnalysisNewsArticle`: headline, description, datePublished, dateModified, articleSection, keywords, author (**name only, no id**), image |
| Per-article meta | `article:published_time`, `article:modified_time`, `article:section`, `rel="canonical"` |

## 3. Facts established from the site's own code

These are **observed** in the served bundles (`news-*.js`, `sections-*.js`), not confirmed by the owner.

- **Editorial types:** `news` → News, `analysis` → Analysis, `opinion` → Opinion, `sponsored` → Sponsored, `announcement` → "HCG Announcement". The app now knows all five (`EditorialType`).
- **Statuses:** `draft`, `in_review`, `approved`, `published`, `archived`.
- **Public visibility rule:** `status === "published" && published_at <= now`. This matches the app's `PublicationVisibility` rule.
- **Scheduling:** a future publication date is supported, so the "scheduled" case is real.
- **Sections:** the current public sections are Technology, Artificial Intelligence, Business, Markets, Consulting, Entrepreneurship, Cybersecurity and Innovation. Analysis and Opinion have their own landing pages.
- **Politics:** the code defines `politics` as a parent with `norwegian-politics` and `international-politics`, plus a helper that removes those two from a section list. Politics sections are **not** in the sitemap today. Whether and where they should appear is an editorial decision. The app will show whatever the supported API returns.
- **Article URL:** `/{category.slug ?? "news"}/{slug}`. The canonical URL equals this.
- **Newsroom roles in the publication:** `owner`, `editor_in_chief`, `editor`, `journalist`, `contributor`, with publish rights limited to owner and editor-in-chief. This is a newsroom role model inside the publication. The app does not read or use it. Any newsroom entry point stays behind a central App Access permission, per the handoff.
- **Website sanitiser:** strips `script`, `style`, `object`, `embed`, `form`, event handlers and `javascript:` URLs. It allows iframes only from YouTube and Vimeo. The app is stricter and never loads iframes; it shows a notice instead.

## 4. Article bodies (3 published articles sampled)

| Elements used | Not used |
|---|---|
| `h2`, `h3`, `p`, `ul`/`ol`/`li`, `figure`/`figcaption`, `img`, `a`, `strong`, `em`, `hr` | `blockquote`, `iframe`, `video`, `table`, `pre` |

Every element used is supported by the app's native converter (`HTMLContentParser`). External source links (McKinsey, Gartner, BCG, Deloitte, EY, Prosci) and HCG links appear inline.

## 5. Author disclosure

On the sampled articles authored by Yasin Ludvigsen Hakmi, the site renders exactly:

> Author disclosure: Yasin Ludvigsen Hakmi is a politician affiliated with FrP and FpU.

It does not appear on the article authored by "HCG Publication". The app still renders disclosures only from backend data tied to a verified author id. This text is recorded here so that the supported API can be checked against what readers see today. It is **not** hard-coded in the app. Still open: whether the disclosure must also appear on list cards or author pages, and the author id it is attached to.

## 6. Things for the publication owner to look at

1. **Two published articles still have placeholder slugs:**
   - `/artificial-intelligence/draft-c4983c74-ba1c-44f6-be58-036da187c300` ("Hakmi Capital Group Introduces HCG AI…")
   - `/innovation/draft-3a1a4973-f7fa-42a6-b7f8-a9406b498df9` ("…Expands Its Software Ecosystem…")

   They are genuinely published (they have publication dates and render as `NewsArticle`), so **this is not draft exposure**. It is a URL-hygiene issue. Renaming them changes their canonical URLs, so add redirects first.
2. **JSON-LD authors have no identifier.** The supported API needs a stable author id (for disclosures and author pages).
3. **No feed or API exists.** The lowest-effort supported contract is probably a small, versioned, read-only server route in the same TanStack Start app (for example `/api/public/news/v1/…`, mirroring CardX's `/api/public/cardx/v1/`). It would reuse the existing server-side queries and visibility rule. A documented read-only Supabase view behind RLS would also work. [HCG-NEWS-CONTENT-API-PROPOSAL.md](HCG-NEWS-CONTENT-API-PROPOSAL.md) describes the shape the app expects. Its editorial-type list now matches the five values above.
