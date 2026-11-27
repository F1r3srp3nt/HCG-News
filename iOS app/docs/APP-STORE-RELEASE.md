# HCG News 1.0.0 (3) — App Store release preparation

**Status:** prepared, not submitted. Nothing has been uploaded to TestFlight or App Store Connect, and nothing was published to the HCG Store. You do the upload, the submission and the release.

## 1. Before you submit (blocking)

| # | Item | Why | Owner |
|---|---|---|---|
| 1 | Resolve the urgent articles in [EDITORIAL-REVIEW-2026-11-27.md](EDITORIAL-REVIEW-2026-11-27.md) (Nvidia, Coinbase), and remove the Breaking flag from routine items | The app shows the live publication's top stories to App Review and every user | Editorial |
| 2 | Add an app section to the website's privacy policy ([APP-PRIVACY-POLICY-ADDENDUM.md](APP-PRIVACY-POLICY-ADDENDUM.md)) | App Store Connect requires a privacy policy URL that covers the app; the current policy covers only the website | You (website) |
| 3 | Build, test and archive on a Mac with **Xcode 26** (iOS 26 SDK) | Gives the Liquid Glass tab bar; App Store uploads must use the current SDK. This app has not yet been compiled. | You (Mac) |
| 4 | Join the Apple Developer Program as Hakmi Capital Group, register the App ID `com.hakmicapitalgroup.hcgnews`, and set **Signing & Capabilities → Team** | `DEVELOPMENT_TEAM` is empty in the project | You |
| 5 | Capture screenshots from cleared articles only (§5) | Screenshots are public marketing | You |

## 2. Project settings (done in this change)

| Setting | Value |
|---|---|
| Version / build | `MARKETING_VERSION` **1.0.0**, `CURRENT_PROJECT_VERSION` **3** (from 0.2.0 (2); recorded in the CHANGELOG) |
| Bundle id | `com.hakmicapitalgroup.hcgnews` (unchanged) |
| Display name | HCG News |
| Category (Info.plist) | `public.app-category.news` |
| Copyright | © 2026 Hakmi Capital Group |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO`. The app uses only Apple's HTTPS/TLS and Keychain; set in `Supporting/HCGNews-Info.plist`, which is merged with the generated Info.plist. |
| Privacy manifest | `HCGNews/Resources/PrivacyInfo.xcprivacy` (§4) |
| Devices | iPhone and iPad, iOS 17.0+. No Mac Catalyst or visionOS. |
| Capabilities and entitlements | None (no push, no iCloud, no App Groups, no Associated Domains) |
| App icon | The supplied `AppIcon.appiconset` (18 slots, opaque, including the 1024 px App Store icon), unchanged |
| Fonts | Newsreader and Manrope (SIL OFL 1.1), bundled with their licences |
| Signing | Automatic. Team still to be set (§1, item 4). |

## 3. App Store Connect metadata (draft)

| Field | Draft |
|---|---|
| Name | HCG News |
| Subtitle (≤30) | The future of information. |
| Primary / secondary category | News / Business |
| Promotional text (≤170) | Technology, business, markets and the ideas shaping tomorrow — from HCG News, a Hakmi Capital Group publication. Read in the Classic or Future Edition. |
| Keywords (≤100) | `news,technology,business,markets,AI,analysis,Norway,innovation,cybersecurity,startups,ERP,opinion` |
| Support URL | https://news.hakmicapitalgroup.com/contact |
| Marketing URL | https://news.hakmicapitalgroup.com |
| Privacy policy URL | https://news.hakmicapitalgroup.com/privacy (once the app section is added) |
| Copyright | 2026 Hakmi Capital Group |

**Description (draft):**

> HCG News brings the publication from news.hakmicapitalgroup.com to iPhone and iPad as a native app.
>
> • The day's featured story, breaking news and the latest reporting on technology, business, markets, artificial intelligence, cybersecurity and innovation
> • Sections, search, and articles saved for offline reading
> • Two editions from the website: the Future Edition and the black-and-white Classic Edition, each in Light and Dark
> • Comfortable reading: text size, line spacing, width and typeface; Dynamic Type and VoiceOver support
> • Corrections, sources and author disclosures shown with each article
>
> No account is needed to read. HCG News staff can sign in with their HCG account to use the newsroom.
>
> HCG News is a Hakmi Capital Group publication. Its founder is a politician affiliated with Fremskrittspartiet (FrP) and Fremskrittspartiets Ungdom (FpU); articles are not party statements.

**Age rating:** answer the questionnaire honestly for news content. Expect at least 12+ if coverage includes mature themes; the current front page includes an affair and espionage story. Unrestricted web access: **No**, because links open in Safari, not in an in-app browser.

**App Review notes (draft):**

> Reading requires no account. The Newsroom (Settings › Newsroom) appears only for HCG accounts with a newsroom role assigned by Hakmi Capital Group; ordinary accounts never see it. Sign-in uses the same HCG account as hakmicapitalgroup.com. Demo account (no newsroom role): [provide]. Accounts are created on the website, not in the app.

Provide a demo account without a newsroom role, so App Review can test sign-in without access to real editorial tools. If you want App Review to see the newsroom, give it a Contributor account that has only test content.

## 4. App Privacy ("nutrition label") answers

These match `PrivacyInfo.xcprivacy`:

| Data type | Collected? | Linked to identity | Tracking | Purpose | When |
|---|---|---|---|---|---|
| Email address | Yes | Yes | No | App functionality | Only when someone signs in with an HCG account (optional) |
| User ID | Yes | Yes | No | App functionality | Same |
| Photos or videos | Yes | Yes | No | App functionality | Newsroom staff uploading article media |
| Other user content | Yes | Yes | No | App functionality | Newsroom staff writing articles |
| Everything else (location, contacts, browsing, usage data, diagnostics, identifiers for advertising, purchases) | **No** | — | — | — | No analytics or crash-reporting SDKs; nothing is collected for reading |

**Required-reason APIs** declared in the manifest:
- UserDefaults, reason `CA92.1`: the app's own preferences.
- File timestamp, reason `C617.1`: the modification date of an imported configuration file inside the app container.

No third-party SDKs.

## 5. Screenshots

- **Required sizes:**
  - iPhone 6.9" (1320 × 2868 or 1290 × 2796);
  - iPad 13" (2064 × 2752), because the app supports iPad.
  Up to 10 each.
- **Content:** only articles cleared in [EDITORIAL-REVIEW-2026-11-27.md](EDITORIAL-REVIEW-2026-11-27.md). No identifiable faces or third-party logos in the images.
- **Capture:** in Xcode, open Edit Scheme › Test › Arguments, set the environment variable `HCGNEWS_SCREENSHOT_ARTICLES` to the cleared ids (comma-separated), and run `AppStoreScreenshotTests` on an iPhone 17 Pro Max and an iPad Pro 13-inch simulator.
  - The DEBUG app then shows only those articles.
  - The test captures Home, cards, an article, Sections, Search and Saved, in Future and Classic, Light and Dark.
  - Export the images from the test report's attachments.
  - It does nothing unless the variable is set.
- **Suggested order:**
  1. Home (Future, Dark) with the masthead and featured story;
  2. an article;
  3. Home (Classic, Light);
  4. Sections;
  5. Saved / offline;
  6. Search;
  7. Settings › Edition and appearance.
- **Rules:** don't add device frames with unreleased features, and don't add text promising things the app doesn't do: no push notifications, no subscriptions, no AI features.

## 6. Signing and distribution (manual)

1. Enrol in the Apple Developer Program as an organisation. This needs a D-U-N-S number for Hakmi Capital Group.
2. In Certificates, Identifiers & Profiles, register the App ID `com.hakmicapitalgroup.hcgnews`. No capabilities are needed.
3. In App Store Connect, create the app record with the same bundle id. Fill in the metadata (§3), App Privacy (§4) and the age rating.
4. In Xcode 26, open the HCGNews target › Signing & Capabilities and select your Team, keeping "Automatically manage signing". Build and run the tests ([BUILD-AND-TEST.md](BUILD-AND-TEST.md)).
5. Run Product › Archive (Any iOS Device), then Organizer › Validate App. Fix anything it reports.
6. **When you decide:** Distribute App › App Store Connect › Upload, then TestFlight, then submit for review. Not done by this change.

## 7. Verification

**Legend:**
- **Done here:** verified in this environment.
- **Mac:** requires Xcode, a simulator or a device, none of which is available here.

| Area | What was verified | Status |
|---|---|---|
| Light and Dark, both editions | <ul><li>Palettes generated from the website's tokens; every text and background pair checked for WCAG contrast (AA; AAA for body text), including Increase Contrast. Script: `docs/DESIGN-SYSTEM.md` §3.</li><li>Logo variants inspected on light and dark grounds.</li></ul> | Done here (colours, assets). **Mac** (on screen). |
| Official application icon | The supplied `AppIcon.appiconset` is unchanged; 18 slots, opaque, 1024 px marketing icon | Done here (files). **Mac** (on device). |
| Native iPhone layouts | <ul><li>Layouts are written for compact and regular width.</li><li>Swift syntax checked.</li><li>Independent compile review (see CHANGELOG).</li></ul> | **Mac** |
| Dynamic Type and accessibility | <ul><li>All brand fonts use `relativeTo:` text styles.</li><li>Accessibility sizes stack layouts.</li><li>Cards have combined labels.</li><li>The ticker can be paused and doesn't move under Reduce Motion or VoiceOver.</li><li>44 pt targets.</li></ul> | Code review. **Mac** (VoiceOver, sizes). |
| Article loading and navigation | <ul><li>Live publication queries verified (list, detail, search, sections).</li><li>188 package tests.</li></ul> | Done here (data). **Mac** (UI). |
| Search and saved articles | Package tests: search, offline library, bookmarks | Done here. **Mac** (UI). |
| Account functionality | <ul><li>Package tests: sign-in, refresh, revocation, sign-out, roles.</li><li>The signed-in live check needs your password (`tools/verify-hcg-news-access.sh --account`).</li></ul> | Partly. **You.** |
| Privacy disclosures | <ul><li>Privacy manifest added.</li><li>App Privacy answers drafted.</li><li>The privacy policy still needs an app section.</li></ul> | Prepared; **website update needed**. |
| External links | <ul><li>About links (editorial policy, corrections, advertising disclosure, privacy, terms, about, contact) and the HCG password reset all return HTTP 200.</li><li>Links open in Safari; only https, http and mailto are allowed.</li></ul> | Done here. |
| Error and offline states | Package tests for offline, timeout, server, empty, not-configured and unreadable publication; offline downloads | Done here (logic). **Mac** (UI). |
| App Store metadata and screenshots | <ul><li>Metadata drafted.</li><li>Screenshot test written; allowlist from the editorial review.</li></ul> | Prepared. **Mac** (capture). |
| Signing and distribution | <ul><li>Export compliance and privacy manifest set.</li><li>Version 1.0.0 (3).</li><li>The team is not set.</li></ul> | Prepared. **You** (§6). |
