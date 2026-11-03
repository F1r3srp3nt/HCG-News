# HCG News for iPhone and iPad — architecture

Milestone 1 (development build, **not released**).

## 1. Layout

```
HCGNews/
  HCGNews.xcodeproj           iOS app project: app target + UI-test target, shared scheme "HCGNews"
  project.yml                 XcodeGen fallback that generates an equivalent project
  HCGNews/                    SwiftUI app (file-system-synchronised group)
    App/                      entry point, composition, adaptive root (tabs / sidebar), Router
    Design/Theme.swift        Future and Classic styles, palette, typography, reading size
    Components/               cards, breaking banner, image pipeline, state views, brand mark, inline text
    Features/                 Home, Article, Sections, Search, Saved, Settings
    Platform/                 ASWebAuthenticationSession adapter
    Preview Content/          DEBUG-only fixtures for previews and UI tests (compiled out of Release)
    Resources/Assets.xcassets supplied HCG logo, trimmed logo, app icon, accent colour
    Configuration/            (absent) approved HCGNewsConfiguration.json goes here; git-ignored
  HCGNewsUITests/             XCUITests (fixture mode + real unconfigured mode)
  HCGNewsKit/                 Swift package, Foundation only, builds and tests on Linux too
    Sources/HCGTransport      HTTP transport seam, JSON dates, secret guard, HCG host policy
    Sources/NewsCore          models, HTML→native blocks, visibility, breaking rule, bookmarks, API client
    Sources/HCGConnect        config validation, PKCE, callback validation, coordinator, Keychain store
    Sources/NewsAppModel      @Observable @MainActor screen models + composition root
    Tests/                    90 XCTest cases
```

## 2. Data flow

```
HCGNewsConfiguration.json (bundle, optional)
        │
        ├── NewsConfigurationLoader ──► .ready ──► NewsAPIClient (proposed contract) ──┐
        │                          └─► otherwise ► UnconfiguredNewsService (no network)  ├─► NewsService
        │                                                                                 │
        └── ConnectConfigurationLoader ─► HCGConnectCoordinator (actor)                   │
                                            │  browser: SystemBrowserAuthenticator         │
                                            │  store:   KeychainSessionStore               │
                                            └─ validAccessToken() ─────────────────────────┘ (restricted articles only)

NewsAppEnvironment (@Observable)
  ├─ HomeModel / SectionsModel / ArticleListModel (per section) / SearchModel / ArticleModel
  ├─ SavedModel ── BookmarkStore (actor, JSON in Application Support)
  ├─ AccountModel ── HCGConnectCoordinator
  └─ LoadedArticleIndex (articles seen this session; used for labelled local search)
```

There is no code path that scrapes rendered web pages. With no configuration the app shows "Live publication not connected" plus a plain link to the website in Safari.

## 3. Layouts

- **Compact width** (iPhone in any orientation; iPad Slide Over and narrow Split View): `TabView` with Home, Sections, Search and Saved. Each tab has its own `NavigationStack`. Settings is a sheet behind the gear button. The tab bar is at the bottom for one-handed reach.
- **Regular width** (iPad full screen, wide Split View or Stage Manager): `NavigationSplitView`. The sidebar holds the destinations, the backend's sections (with their hierarchy) and Settings. The detail column has its own stack.
- `Router` keeps the stacks. When the size class changes (rotation or Split View resize), `adoptCompact()` and `adoptRegular()` move the current stack across, so the reader keeps their place.
- Content columns use readable maximum widths (articles 720 pt, feeds 760–1000 pt) and flexible layouts. Nothing uses fixed widths that could overflow a 320 pt column. At accessibility text sizes, rows and the lead card switch from side-by-side to stacked.

## 4. Content safety

- **Untrusted HTML** (`HTMLContentParser`) becomes inert `ContentBlock` values, using an allow-list of output structures. There is no `WKWebView` anywhere in the app. Scripts, styles, forms, SVG and templates are dropped with their content. Event handlers and all other attributes are ignored. Embeds (iframe, video, audio, object, embed) become a notice with a link to the web article. Links survive only for `https`, `http` and `mailto`, including obfuscated `java\tscript:` forms. Images must be HTTPS. Input size and block count are capped.
- **Link taps** go through an `OpenURLAction` that hands only web and mail links to the system. Anything else is discarded.
- **Visibility** (`PublicationVisibility`) is defence in depth: items with a non-`published` status, no publication date, a publication date more than 5 minutes in the future, a blank headline or an unknown access value are hidden. `restricted` items are listed with a lock and require a server-authorised fetch. The backend remains the authority.
- **Breaking** (`BreakingNewsRule`): only `breaking.active == true`, not expired, newest first, at most 5.
- **Sharing** uses the canonical URL only when it is HTTPS on `hakmicapitalgroup.com`. Otherwise the Share button is hidden.
- **Disclosures** come only from `authors[].disclosures` attached to verified author ids. They are shown verbatim in a "Disclosure" box under the byline. The app never matches display names and contains no disclosure text of its own.

## 5. Identity and authorization

See [HCG-MAIN-CONFIGURATION-HANDOFF.md](HCG-MAIN-CONFIGURATION-HANDOFF.md). In short:

- Public client with PKCE S256 in the system browser. No client secret can be configured.
- Tokens are stored only in the Keychain (device-only, not synchronised), never logged, never put in URLs, and sent only in `Authorization` headers to configured endpoints.
- Authorization comes from the App Access decision fetched in the current run. No roles are read, and nothing is inferred from email or name. The newsroom link needs an explicit central permission, and the newsroom enforces access itself.
- Sign-out always clears the device and reports the central result honestly.

## 6. Bookmarks

- `BookmarkStore` (actor) writes `Application Support/HCGNews/bookmarks.json` atomically, with complete-until-first-unlock file protection on iOS.
- Bookmarks are keyed by the stable `ArticleID`. Each holds a display snapshot (headline, section, type, byline, date, canonical URL) and **no article body**. The snapshot is refreshed when a saved article is opened.
- A corrupt file is moved aside (`*.corrupt-<timestamp>.json`) rather than overwritten.
- No cloud sync (no verified central contract).

## 7. Design

- **Future** (default): #05080F background, #0B1220 surfaces, #ECF1F7 text, #A2B0C3 secondary text, restrained cyan #3FD0E0 accent, serif (New York) headlines, sans body. Always dark. Under Increase Contrast, secondary text, separators and accent get stronger.
- **Classic**: system backgrounds and labels (follows Light and Dark Mode), deep-navy / light-blue accent, serif headlines and serif body.
- All text uses Dynamic Type text styles. The article's text-size control offsets the system size (−2…+3 steps, clamped to the accessibility sizes).
- Images are never cropped and never carry an overlaid headline. Thumbnails fit inside a bounded box at their real proportions. A failed or missing image collapses instead of leaving an empty box. There are no fixed card heights.
- Reduce Motion: breaking-headline changes are instant. There is no marquee or auto-advance in any mode.
- VoiceOver: cards are single elements with type, headline, section, byline, date and restriction. Breaking controls have labels and announce the new headline. Headings carry the header trait. Decorative images without alt text are hidden.
