# HCG News for iPhone and iPad — Milestone 1 report

Date: 3 November 2026 · Branch: `claude/bold-gauss-dp6yro` · Status: **development build. Not released, not production-ready, not connected to live content.**

## 1. Outcome in one paragraph

A complete native reader exists as source: Home with explicit-flag breaking news, Sections, Search, Saved, the article reader, Settings, the Future and Classic styles, and adaptive iPhone/iPad/Split View layouts. Below it sits a Foundation-only core with a sanitising HTML→native converter, visibility rules, bookmarks and a prepared HCG Connect PKCE sign-in. The core compiles and passes **90 tests** under Swift 6.1 on Linux. **The SwiftUI app has not been compiled:** this environment has no Xcode or iOS SDK. **It loads no real articles yet:** no supported HCG News content API, and none of the named HCG Connect contract documents, could be found, and every HCG host was blocked by this environment's network policy. The app therefore ships unconfigured and says so on screen.

## 2. Where things are

| | Path |
|---|---|
| Xcode project (app + UI tests, shared scheme `HCGNews`) | `HCGNews/HCGNews.xcodeproj` |
| SwiftUI app | `HCGNews/HCGNews/` |
| UI tests | `HCGNews/HCGNewsUITests/` |
| Core package + unit tests | `HCGNews/HCGNewsKit/` |
| XcodeGen fallback | `HCGNews/project.yml` |
| Docs | `docs/` |

## 3. Requirement status

| Requirement | Status |
|---|---|
| Load real published articles through the supported backend contract | **Blocked.** No supported contract exists or was found. A client for a *proposed* contract is ready and tested against fixtures. Missing inputs: [INTEGRATION-DISCOVERY.md §5](INTEGRATION-DISCOVERY.md). |
| No guessed endpoints, columns, tokens or client IDs; no scraping | Met. Nothing is hard-coded; there is no scraping code; CardX's client is explicitly rejected. |
| Readable, correctly formatted articles | Implemented: headings, paragraphs, lists (nested, numbered), quotes with attribution, figures with caption and credit, links, sources, embed notices, dividers. Rendering not yet seen on a device. |
| Home, Sections, Search, Saved | Implemented. |
| iPhone / iPad portrait and landscape / multitasking | Implemented (size-class driven, with state carried across). Not yet run. |
| Breaking news only from an explicit flag; one at a time; accessible; Reduce Motion | Implemented and unit-tested (`BreakingNewsRule`, `BreakingCarousel`). |
| Artwork kept separate, proportions preserved, no forced heights | Implemented (`ArticleImageView`). Text-heavy artwork not yet checked with a real image. |
| Untrusted content sanitised; no scripts; constrained navigation | Implemented and unit-tested (16 parser tests, including script, handler, `javascript:` and embed cases). No web view in the app. |
| Disclosures from verified author identity and backend data | Implemented and tested (no name matching). **The FrP/FpU disclosure text must come from the backend.** It is not in the app. |
| Sections from the source of truth (incl. Politics hierarchy) | Implemented (backend-defined hierarchy). Nothing hard-coded. |
| Search via the backend, or labelled loaded-only search | Implemented and tested. |
| Persistent local bookmarks by stable ID; offline limits stated | Implemented and tested (relaunch persistence, corrupt-file preservation, no body stored). |
| HCG Connect: system browser + PKCE, Keychain, no secret, own client | Prepared and tested with fakes. Needs central registration: [handoff](HCG-MAIN-CONFIGURATION-HANDOFF.md). |
| No automatic role grant; newsroom only by central permission | Implemented and tested (`NewsroomEntryPolicy`). |
| No claim of global logout or revocation | Implemented: sign-out messages report exactly what happened. |
| Later milestones documented, no placeholder features | [ROADMAP.md](ROADMAP.md). Settings lists them as "Not in this version" text only. |

## 4. Build and test results

| What | Result |
|---|---|
| `swift build` of HCGNewsKit, Swift 6.1.3 (Linux, `swift:6.1-noble`), Swift 6 language mode | **Pass, 0 warnings** |
| `swift test` of HCGNewsKit (Linux) | **90 tests, 0 failures.** NewsCore 50, HCGConnect 27, NewsAppModel 13. |
| Two real defects found and fixed by those tests during development | Preformatted text lost its significant whitespace; an empty search query could hide the "not connected" state. |
| `swiftc -parse` of every app and UI-test Swift file (Linux) | **Pass** (syntax only, no type checking) |
| `project.pbxproj` parsed with an independent parser (`pbxproj` 4.2.1) | **Pass.** 35 objects, all references resolve, 2 targets. |
| Asset catalog JSON | Valid |
| **iOS app compile (xcodebuild)** | **Not run.** No Xcode or Apple SDK in this environment. |
| **UI tests (11 cases), simulator runs, device runs** | **Not run** |
| **Live article loading, draft exposure against the real backend** | **Not possible.** No contract; hosts blocked. |
| **Auth cancellation / expiry / denial against HCG Connect** | **Not possible.** No registered client or configuration. Covered by fake-transport tests only. |
| Screenshots | **None.** Nothing was executed on iOS, so there are no genuine screenshots. |

### Untested on Apple platforms (do these first on a Mac)

Everything in the [manual checklist](BUILD-AND-TEST.md#manual-verification-checklist): compilation of the SwiftUI layer; iPhone and iPad layouts; rotation and Split View; Dynamic Type at accessibility sizes; VoiceOver; Reduce Motion; Increase Contrast; the Keychain store; `ASWebAuthenticationSession`; image loading and downsampling; the share sheet; CryptoKit's SHA-256 path (the Linux runs used the portable fallback against the same RFC vector).

## 5. Founder-control notes

- Nothing was merged, published, deployed or uploaded. No OAuth client was registered, no role was granted, and no central policy was changed.
- No secrets in source. The only configuration file location is git-ignored. The example contains placeholders and `approvedByFounder: false`.
- Proposed values (bundle id `com.hakmicapitalgroup.hcgnews`, redirect `com.hakmicapitalgroup.hcgnews:/oauth/callback`, App Access id `hcg-news-ios`, permission `news.newsroom.open`, content API path) are labelled PROPOSED wherever they appear.

## 6. Next-step checklist

1. ☐ On a Mac: open the project, build for an iPhone and an iPad simulator, and run the tests ([BUILD-AND-TEST.md](BUILD-AND-TEST.md)). Report any compile errors back.
2. ☐ Go through the manual checklist in both styles, and capture screenshots then.
3. ☐ Publication owner: provide or confirm the content API and the 10 missing inputs ([INTEGRATION-DISCOVERY.md §5](INTEGRATION-DISCOVERY.md)), including the exact FrP/FpU disclosure text and where it must appear.
4. ☐ Central HCG: decisions 1–8 in the [handoff §7](HCG-MAIN-CONFIGURATION-HANDOFF.md). Register a **new** public client; build the App Access endpoint.
5. ☐ Founder: approve the reviewed configuration (`approvedByFounder: true`) and install it locally.
6. ☐ Adapt `WireFormat.swift` if the real contract differs from the proposal; add contract tests using recorded real responses.
7. ☐ Run the HCG Connect acceptance tests (handoff §8) against beta.
8. ☐ Optional: allow HCG hosts in this cloud environment's network settings, or add a macOS CI build (build and test only, no signing or secrets) after approval.
