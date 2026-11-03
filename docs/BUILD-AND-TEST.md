# Build and test HCG News

## Requirements

| | |
|---|---|
| Mac | Apple silicon or Intel, with a recent macOS that runs Xcode 16 |
| Xcode | **16.0 or later.** The project uses file-system-synchronised groups (`objectVersion = 77`). |
| iOS deployment target | 17.0 |
| Dependencies | None (only the local `HCGNewsKit` package) |
| Signing | Automatic, no team set. Pick your own team to run on a device. Simulators need no team. |

## Open and run

```bash
git clone https://github.com/F1r3srp3nt/HCG-News.git
```

```bash
cd HCG-News && git checkout claude/bold-gauss-dp6yro
```

```bash
open HCGNews/HCGNews.xcodeproj
```

Choose the **HCGNews** scheme and an iPhone or iPad simulator, then press ⌘R. With no configuration installed the app shows **"Live publication not connected"**. That is expected.

To see the layouts with content, edit the scheme (Run ▸ Arguments ▸ Environment Variables) and add `HCGNEWS_UI_TEST_FIXTURES = 1`. An orange **"TEST FIXTURES — not live reporting"** banner appears on every screen. Fixtures exist only in Debug builds. Optional extras: `HCGNEWS_UI_TEST_OFFLINE=1`, `HCGNEWS_UI_TEST_EMPTY=1`, `HCGNEWS_UI_TEST_RESET=1`.

## Build and test from Terminal

List the simulators you have, and substitute the names below:

```bash
xcrun simctl list devices available
```

Build for the simulator without signing:

```bash
xcodebuild -project HCGNews/HCGNews.xcodeproj -scheme HCGNews -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO build
```

Run every test (package unit tests and UI tests) on an iPhone:

```bash
xcodebuild -project HCGNews/HCGNews.xcodeproj -scheme HCGNews -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Run them again on an iPad:

```bash
xcodebuild -project HCGNews/HCGNews.xcodeproj -scheme HCGNews -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' test
```

Package tests only (fast, on the Mac):

```bash
cd HCGNews/HCGNewsKit && swift test
```

Package tests on Linux, without a Mac (this is how they were run for this milestone):

```bash
docker run --rm -v "$PWD/HCGNews/HCGNewsKit":/pkg -w /pkg swift:6.1-noble swift test
```

Release build (checks that fixtures compile out):

```bash
xcodebuild -project HCGNews/HCGNews.xcodeproj -scheme HCGNews -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

### If Xcode says the project file is damaged

The `.pbxproj` was written by hand, without Xcode, and checked with an independent parser. If your Xcode still rejects it, generate an equivalent project from `HCGNews/project.yml`:

```bash
brew install xcodegen
```

```bash
cd HCGNews && xcodegen generate
```

## Manual verification checklist

Do these on a simulator or device, in **both** reading styles (Settings ▸ Reading).

| # | Check | How |
|---|---|---|
| 1 | Unconfigured honesty | Normal launch: "Live publication not connected", no articles, Settings says sign-in isn't set up. |
| 2 | iPhone navigation | Tabs Home / Sections / Search / Saved; gear opens Settings; back-swipe works. |
| 3 | iPad landscape and portrait | Sidebar with destinations, sections and Settings; rotate while reading an article and confirm you stay on it. |
| 4 | Split View / Slide Over | Put HCG News next to Safari at ⅓ width: the app switches to tabs, nothing clips, no horizontal scrolling. Widen it back: the sidebar returns and the article is still open. |
| 5 | Long headlines | Fixture "long headline" wraps fully in the lead card, rows and article header. |
| 6 | Missing images | Fixture images point at an unreachable host: cards collapse, with no empty boxes. |
| 7 | Text-heavy artwork | **Needs a real image.** Confirm the artwork is shown whole (not cropped) and that no headline is drawn over it. |
| 8 | Article formatting | Fixture article: bold, italic, link, heading, nested list, numbered list, quote with attribution, figure with caption and credit, embed notice, divider, sources. |
| 9 | Source links | Tapping a link opens Safari. |
| 10 | Disclosure | Fixture lead article shows the "Disclosure" box under the byline. |
| 11 | Share | Share sheet offers the canonical `https://news.hakmicapitalgroup.com/…` URL. |
| 12 | Bookmarks after relaunch | Save, force-quit, relaunch: the article is in Saved (also automated). |
| 13 | Dynamic Type | Settings ▸ Accessibility ▸ Larger Text at the largest size: rows stack, nothing truncates mid-word in headlines, the article text-size menu goes larger still. |
| 14 | VoiceOver | Each card reads type, headline, section, byline and date. Breaking banner: "Previous / Next breaking headline" buttons announce the new headline. |
| 15 | Reduce Motion | Breaking headline changes without animation. |
| 16 | Increase Contrast | Future style secondary text and separators get stronger. |
| 17 | Offline | Airplane mode: "You're offline" with Try Again (also automated in fixture mode). |
| 18 | Auth cancellation / expiry / denial | **Needs an approved HCG Connect configuration.** See the handoff, §8. |

## What has and has not been run

See [MILESTONE-1-REPORT.md](MILESTONE-1-REPORT.md).
