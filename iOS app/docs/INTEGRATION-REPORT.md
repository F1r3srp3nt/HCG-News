# HCG News iOS/iPadOS — real integration report

Date: 12 November 2026 · Branch: `claude/bold-gauss-dp6yro` · App version: 0.2.0 (2), unchanged. **Development build: not merged, not released, not uploaded.**

## 1. What the app now connects to

These were found by inspecting the publication's own client code, the HCG ONE app and its sister-app integration report (`hcg-one/HCG-CARDX-AUTH-INTEGRATION-REPORT.md`). No endpoint was guessed.

| Need | Real implementation found | How the app uses it |
|---|---|---|
| Publication content | The HCG News website stores articles in the shared HCG project: `news_articles`, `news_categories` and `news_authors`. They're read through PostgREST with row-level security. Article bodies are HTML from the site's rich-text editor. | Reads as the **anonymous** role with the public key the website already ships. It requests only published rows with `published_at <= now`, and only reader columns (never `created_by`, SEO fields or view counts). Every row is re-checked on the device. |
| Sign-in | The shared HCG identity service's password grant: the same HCG account, endpoint and public key as the HCG website and HCG ONE. It's the documented contract for HCG's native sister apps. | HCG-branded native sign-in, tokens in the Keychain, refresh-token rotation (single flight), `logout?scope=local`, and a server check of the session (`/auth/v1/user`). |
| Newsroom roles | The server function `news_has_feature(_user_id, _feature_key)`, which the website calls with these keys: `news.administrator`, `news.editor_in_chief`, `news.editor`, `news.journalist`, `news.contributor`. They're assigned centrally (HCG App Access). | Called with the person's own token for every role. A partial answer counts as a failed check. The roles are re-checked after sign-in, on demand, and when the app returns to the foreground. |
| Newsroom workflow | The website newsroom writes the same tables with the person's token: create, full-row update, a `news_article_versions` snapshot on status change, the `hcg-news-media` storage bucket with signed URLs, `news_media` records and `news_audit`. | The same operations, the same rules (below), and the same storage layout. Saves are **revision-guarded** (`updated_at`), so concurrent edits are detected and never overwritten silently. |
| ERP and Executive tools | The HCG website's mobile routes: `GET /api/public/mobile/workspaces` (the server decides `permitted` / `available`) and `POST /api/public/mobile/handoff` (a one-time link, valid for 60 s). | Account › HCG workspaces lists them as HCG decides. **Open** requests a one-time link and opens it in Safari, where the website starts its own session. The app holds no ERP permissions. |
| Author disclosure | Hard-coded in the website's `disclosures` module and attached to the founder's author id. It isn't in the database. | Mirrored word for word for that author id (`PublicationDisclosures`). It should become database data later (§6). |

Configuration: `HCGNews/Resources/HCGNewsConfiguration.json` (`hcgPlatform`) is bundled, so Debug, Release and archive builds are all connected.
- It contains only public values: the project URL, the **anon** key, the website URL and the publication URL.
- The loader refuses service-role and secret keys, other projects (it's pinned to `qggdyzoydveafkmjgkpq`), non-HTTPS URLs, and files not marked `approvedByFounder`.
- An imported configuration still takes precedence.

## 2. Rules implemented (identical to the website's)

| Rule | Source in the website code |
|---|---|
| Public visibility: `status = published` and `published_at <= now` | `news` helper module, function `l` |
| Allowed statuses: Administrator and Editor-in-Chief, all five; Editor, `draft` / `in_review` / `approved`; Journalist and Contributor, `draft` / `in_review` | function `d` |
| Publication needs status `approved`, and the Administrator or Editor-in-Chief role | function `s`, "Approval is required before publication." |
| Publish needs a section, headline, body and slug | "Choose a section before publishing." / "Complete the headline, article body and slug before publishing." |
| Scheduling is `published` plus a future `published_at` | function `u`, "Choose a future publication date." |
| Editing: Editor and above edit any article; others edit only their own, while it's a draft or in review | `canEditAny`, article editor |
| Media: JPEG, PNG, WebP, GIF or AVIF up to 20 MB; MP4, WebM or MOV up to 500 MB; path `articles/<id>/<kind>s/<uuid>.<ext>`; signed for 10 years | media library module |
| Slugs: lowercase, NFKD, hyphens, 90 characters | function `a` |
| Demo content is labelled and never breaking | ArticleCard and Home |
| Canonical URL: `https://news.hakmicapitalgroup.com/<section slug, or "news">/<slug>` | route `/$category/$slug` |

These rules decide **what the app offers**. Authorisation is the server's: every read and write goes to PostgREST or Storage with the person's token, and row-level security accepts or refuses it. A refusal is shown as "Your HCG News role doesn't allow this", with the server's message.

## 3. What was built

**Reader (no sign-in)**
- Home: featured, explicit breaking news, latest, offset pagination, refresh.
- Sections and section feeds.
- Search: headline, subtitle and excerpt, with section and type filters.
- Article: HTML rendered to inert native blocks, author and disclosure, dates, section, label, image with alt text, caption and credit, sources, correction note, and canonical sharing.
- Labels for News, Analysis, Opinion, Sponsored, HCG Announcement and Demo content.
- Existing Saved, offline downloads and caching keep working.
- Distinct states for: missing configuration, offline, server failure, no results, and "the publication returned no published articles".

**HCG account**
- Sign-in with the website's HCG account, and Keychain storage.
- Automatic refresh before expiry; one retry after a 401.
- Revocation detection: the session is cleared and the person is told.
- Sign-out reports exactly whether HCG ended the session.
- Account switching clears roles, workspace data and newsroom lists.

**Newsroom (only for people HCG gave a newsroom role)**
- Hidden from Settings and the sidebar otherwise. The ⌘⇧N shortcut shows "Newsroom access required" instead. The Newsroom closes itself if the role is removed while it's open.
- Desk: All, Mine, Drafts, In review, Approved, Scheduled, Published and Archived, plus search and pull to refresh.
- New drafts are created on HCG, as on the website.
- Editor:
  - headline, subtitle, excerpt and slug ("From Headline");
  - section, type and byline (from verified authors);
  - body blocks, with bold, italic and links;
  - cover and inline images from the media library, or uploaded with required alt text, caption and credit;
  - featured and breaking flags, SEO, tags, sources and a public correction note;
  - a native preview labelled "not published".
- Body editing is **lossless only**. An article whose HTML the app can't reproduce exactly (embeds, styles, nested lists) keeps its body read-only and untouched, and links to the website newsroom.
- Status changes:
  - Submit for review, Approve, Return to draft or Unpublish, and Archive, each behind a confirmation;
  - Publish now or Schedule, in a sheet that lists problems and needs an explicit "I've checked this article" toggle.
- Version history with "Copy into editor"; nothing is saved until Save is tapped.
- Unsaved edits are backed up on the device, per account, and offered after a crash or a failed save.
- Conflicts open a sheet: keep my edits and review, or discard them and load theirs. Nothing is overwritten automatically.
- Administration:
  - sections (add, rename, hide), for Editors-in-Chief and Administrators;
  - the server audit history, for Administrators only.

**Local drafts**
- The earlier on-device drafting workspace is still available inside the Newsroom ("Local Drafts on This Device").

## 4. Verification

| Check | Result |
|---|---|
| `swift build` + `swift test` of HCGNewsKit (Swift 6.1, Linux) | **182 tests, 0 failures.** 47 are new: HCGPlatform 38 and NewsAppModel platform tests 9. |
| Anonymous requests never carry a person's token; only published, due rows and reader columns are requested; Check Connection reports "no articles readable" instead of "connected" | `PublicationContentTests` |
| Drafts and scheduled rows are dropped even if the server sends them | `testDraftsAndScheduledRowsAreDroppedEvenIfTheServerSendsThem` |
| Privileged keys, other projects and unapproved files are refused | `PlatformConfigurationTests` |
| The password is never stored; refresh is single-flight; a revoked refresh token signs out; offline keeps a valid session; logout is local-scope and always clears the Keychain | `HCGAccountSessionTests` |
| Roles come only from the server function; any failed role check fails the whole check; permission rules match the website | `NewsroomRoleTests` |
| Only changed fields are sent, guarded by the loaded revision; a concurrent edit becomes a conflict; an RLS refusal is reported; status changes record a version; scheduling sends the chosen time; failed media records roll back the upload | `NewsroomRepositoryTests` |
| A reader without a role never sees the Newsroom; staff do; sign-out clears account data; a revoked session is detected; conflicts keep local edits; unsaved edits survive a failed save and are offered again; publication needs approval and the right role; an untouched body is never re-sent | `PlatformModelTests` |
| Lossless body round trip; unsupported content stays read-only | `ArticleBodyCodecTests` |
| Workspace directory and handoff (HCG routes only; a 403 becomes "denied") | `WorkspaceServiceTests` |
| SwiftUI layer | Syntax-checked (`swiftc -parse`), plus an independent read-only compile review (§7). **Not compiled**: no Mac or iOS SDK here. |

### Not verified (and why)

- **Live requests against HCG.** The automated anonymous check against the live project was blocked by this environment's safety controls, so nothing in this session read from or wrote to the live publication. Run `tools/verify-hcg-news-access.sh` (§5).
- **Writes with a real staff account.** Not done, by design: test content only, and never real stories. The script's `--write-tests` mode creates one labelled test draft, checks the revision guard, then deletes it.
- **Compiling and running on a simulator or device**, including the 14 UI tests (one was rewritten for the connected build).

## 5. What you need to do

1. **Run the access check** (2 minutes):
   ```bash
   cd "iOS app/tools" && ./verify-hcg-news-access.sh
   ```
   Then optionally, with an ordinary account and with your staff account:
   ```bash
   ./verify-hcg-news-access.sh --account
   ```
   And `--write-tests` with a staff account. It creates one labelled test draft and deletes it.
2. **If "no published articles readable anonymously" fails**, review and apply [`../backend/HCG-NEWS-PUBLIC-READ.md`](../backend/HCG-NEWS-PUBLIC-READ.md) (SQL included, with a rollback). Deployment is manual.
3. **On a Mac:** build and run as in [BUILD-AND-TEST.md](BUILD-AND-TEST.md), then work through the new sections of [ACCEPTANCE-CHECKLIST.md](ACCEPTANCE-CHECKLIST.md) with:
   - an ordinary account;
   - your owner account (its access comes from HCG App Access; nothing is hard-coded);
   - a test draft only.
4. **Signing:** set your team in Xcode when you archive. The bundle id, icon and signing settings are unchanged.

## 6. Open dependencies and decisions

| Item | Owner | Blocking? |
|---|---|---|
| Anonymous read policy and column privileges for published articles | HCG backend | Only if the check fails |
| Author disclosures stored as data (an author field or table) rather than website code | News website | No. The app mirrors the current text. |
| A native OAuth/PKCE client for HCG News (redirect `com.hakmicapitalgroup.hcgnews:/oauth/callback`) | Central HCG | No. The password grant is HCG's documented sister-app contract. The OAuth path stays in the app for when a client is registered. |
| Whether `updated_at` is maintained on every save | HCG backend | The app sets it on each save; `--write-tests` confirms stale saves are refused |
| `news_audit` column names (`actor_id`, `action`, `entity`, `summary`) | — | Taken from the website. The script and app show what's returned. |
| Push notifications, newsletter admin, site settings, analytics | — | Not built (no backend contract for native use) |

## 7. Independent compile review

See the "Compile review" section of [CHANGELOG.md](../CHANGELOG.md) for findings and fixes.
