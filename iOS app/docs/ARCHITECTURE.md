# HCG News for iPhone and iPad — architecture

App version 0.2.0 (2). Development build, **not released**.

## 1. Layout

Everything below is inside the repository's `iOS app/` folder.

```
HCGNews/
  HCGNews.xcodeproj              app + UI-test targets, shared scheme "HCGNews"
  project.yml                    XcodeGen fallback
  HCGNews/                       SwiftUI app (file-system-synchronised group)
    App/                         entry point, AppContainer injection, adaptive root, Router, keyboard commands
    Design/Theme.swift           palette (black/charcoal/silver/white + cyan for actions), typography, reader settings
    Components/                  masthead/brand, cards, labels, images + photo viewer, audio + read-aloud, states
    Features/Home|Sections|Search|Saved|Article     reader
    Features/Settings            Settings, Advanced (configuration import, checks, diagnostics), About
    Features/Account             HCG Connect account
    Features/Newsroom            workspace, draft editor, administration
    Platform/                    ASWebAuthenticationSession adapter
    Preview Content/             DEBUG-only development fixtures (separate storage folder)
    Resources/Assets.xcassets    HCGNewsMark (supplied HCG logo), AppIcon, HCGLogo/HCGLogoTrimmed (publisher)
  HCGNewsUITests/                14 XCUITests (fixtures + real unconfigured app)
  HCGNewsKit/                    Swift package, Foundation only; builds and tests on Linux
    HCGTransport                 HTTP seam, JSON dates, secret guard, HCG host policy
    NewsCore                     models, HTML→blocks, visibility/breaking rules, content API client,
                                 OfflineLibrary, BookmarkStore (v2 + migration), ReadingPositionStore
    HCGConnect                   configuration, PKCE, coordinator (sign-in, refresh, App Access,
                                 organisation, reachability, sign-out), Keychain store
    HCGPlatform                  THE REAL INTEGRATION: PlatformClient (PostgREST/Auth/Storage + website
                                 mobile routes), PublicationContentService (public reading),
                                 HCGAccountSession (HCG account sign-in), NewsroomRoleResolver
                                 (news_has_feature), NewsroomRepository (articles, versions, media,
                                 sections, authors, audit), ArticleBodyCodec, HCGWorkspaceService (ERP)
    Newsroom                     drafts, DraftStore (autosave, snapshots, media, export/import),
                                 NewsroomService (proposed API client), NewsroomGate
    NewsAppModel                 ConfigurationStore, AppContainer/NewsAppEnvironment, screen models,
                                 Account/Connection models, Newsroom/Editor/Admin models, event log, diagnostics
    Tests/                       187 XCTest cases
```

## 2. Composition and configuration

```
LocalStores (survive configuration changes)
  ConfigurationStore  publication.json / connect.json   (imported; else bundled; else none)
  BookmarkStore       bookmarks.json (v2)
  OfflineLibrary      Offline/manifest.json + articles/<key>/{article.json, images/*}
  ReadingPositionStore, DraftStore (Newsroom/Drafts/<id>/…), LocalEventLog

AppContainer ── build() ──► NewsAppEnvironment (generation n)
   │                        ├─ NewsService: PublicationContentService (hcgPlatform, bundled)
   │                        │              | NewsAPIClient (proposed API) | UnconfiguredNewsService(missing|invalid)
   │                        ├─ PlatformAccountModel + NewsroomDeskModel (hcgPlatform only)
   │                        ├─ HCGConnectCoordinator (configured or unavailable)
   │                        ├─ NewsroomService: NewsroomAPIClient (if newsroomAPIBaseURL) | Unavailable
   │                        └─ Home/Sections/Search/Saved/Article/Account/Connection/Newsroom/Admin models
   └─ apply(preview) / remove(kind) → rebuild (generation n+1); on identity change:
        coordinator.forgetLocalSession() + drafts.detachAllServerLinks() + log
```

Imports are two-step: `preview` (validate, no side effects), then `apply` (atomic write, previous file kept). The UI resets navigation when the generation changes.

## 3. Reading and offline

- **Public reading never needs a token.** A bearer token is sent only after the content API marks an article restricted and the reader is signed in.
- **Article sources.** `ArticleModel` loads the live article. If that fails as offline, unavailable or not configured, and a stored copy exists, it shows the copy labelled **"Stored copy from …"**. If the publication returns not-found (unpublished), the stored copy is *not* shown.
- **Downloads.** Downloads are written to `tmp/` and swapped in only when complete, so a failed update never destroys the previous copy. `downloading` is persisted, and becomes `interrupted` at the next launch.
- **Update detection.** Each copy stores a content marker (revision, else update time, else publication time). Newer markers seen in lists or the live article set "update available".
- **What is refused.** Restricted and summary-only articles are refused. The storage limit is enforced without deleting other downloads.
- **Bookmarks are separate from downloads.** Removing a download keeps the bookmark. There is no sync.

## 4. Content safety

Unchanged from 0.1.0, with one addition:
- No web view; untrusted HTML becomes inert blocks.
- Links are limited to http(s) and mailto, and link taps go through an `OpenURLAction`.
- Embeds and **unknown block types** become explicit notices.
- Share uses only the canonical HTTPS HCG URL.
- Disclosures, corrections, sponsor details and related stories are displayed only as supplied, never generated.

## 5. Identity and authorisation

**With the HCG platform (the bundled configuration):**
- Sign-in is HCG's documented sister-app contract: the shared identity service's password grant, the same HCG account as the website and HCG ONE. The session is kept in the Keychain (`com.hakmicapitalgroup.hcgnews.account`, this device only).
- Newsroom roles come from `news_has_feature` with the person's token. The Newsroom is shown only to staff. Roles are re-checked on foreground (at most once a minute) and after every refusal.
- `NewsroomPermissions` mirrors the website's rules to decide what to *offer*. Row-level security on every request is the authority.
- ERP and executive tools: the website's workspace directory, plus a one-time handoff link opened in Safari.
- Sign-out or an account change clears roles, the workspace directory and newsroom lists. Unsaved newsroom edits stay on the device, per account.

**With an OAuth (HCG Connect) configuration, when a native client is registered:**

- Public native client with PKCE in the system browser; sessions in the Keychain.
- Organisation selection only when HCG lists several organisations. Capabilities and entitlements are displayed as issued.
- **Configured, reachable and verified are separate states.** "Verified" for HCG Connect means a sign-in plus an App Access decision in this session.
- **The newsroom gate requires all of:**
  - a configured newsroom service;
  - a signed-in reader;
  - HCG App Access granted in this session (naming `newsroomPermission` if configured);
  - the action in the service's `supportedActions`;
  - the action in its `allowedActions`.

  The service checks again on every request. The app has no role logic.

## 6. Newsroom drafts

- **Local first.** Drafts are always labelled "Local draft". Save is local, autosave (every 2 s of inactivity, and when the app is backgrounded) protects against crashes, and recovery is offered at the next launch.
- **Snapshots** are taken automatically every five minutes or more while saving, and on demand. Restoring snapshots the current version first.
- **Export and import.** The export format is documented ([NEWSROOM-DRAFT-FORMAT.md](NEWSROOM-DRAFT-FORMAT.md)). Import always creates a new draft.
- **Remote actions.** Each runs only on an explicit tap; nothing is queued. Updates carry `baseRevision`, and a `409` opens an explicit conflict sheet. Destructive actions show the affected article and need confirmation.

## 7. Design

| Token | Light | Dark |
|---|---|---|
| Background | #FAFAF8 | #0B0B0C |
| Surface (charcoal) | #F0F0EE | #17181A |
| Primary text | #121212 | #F2F2F2 |
| Secondary text | #4A4B50 | #A9ABB0 |
| Silver (rules, quiet labels) | #8A8C91 | #8E9096 |
| Accent (actions, status only) | #007C99 | #3FD0E0 |

- Increase Contrast variants exist for text, silver, separators and accent.
- Headlines use the serif face (New York); article body text is serif or sans, by preference.
- All text uses Dynamic Type. The reader's text size can be offset further, up to the accessibility sizes.
- Reduce Motion removes transitions. There is no auto-advance or marquee anywhere.
