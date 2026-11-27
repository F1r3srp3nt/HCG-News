# HCG News design system (app 1.0.0)

The app reuses the identity of news.hakmicapitalgroup.com; it introduces no new visual identity. The sources are the website's own assets and stylesheet, inspected on 27 November 2026.

## 1. Brand

| Element | Website | App |
|---|---|---|
| Logo, Future Edition | `hcg-future-logo.png`: glowing metallic HCG on black | `HCGFutureLogo` image set, transparent. <ul><li>**Dark:** the original colours with the site's `brightness(1.22) contrast(.94)` filter.</li><li>**Light:** an engraved negative; bright lines become graphite ink and cyan edges deep signal blue.</li></ul> |
| Logo, Classic Edition | `hcg-news-logo.png`: classic metallic serif HCG, transparent | `HCGClassicLogo`. <ul><li>**Dark:** silver, with the same filter.</li><li>**Light:** graphite lettering in the same shapes.</li></ul> |
| Wordmark | `[logo] │ News`: a `border-l` hairline, then "News" in italic Newsreader | `NewsWordmark`: logo, 1 pt separator, italic Newsreader "News" |
| Tagline | "The future of information." (hero), "Technology, business, markets and the ideas shaping tomorrow." (header) | Masthead hero and About |
| Publisher line | "A Hakmi Capital Group Publication" | Under the wordmark |

**Logo geometry:**
- The logo geometry is never changed: only transparent margins are trimmed, and colours and transparency remapped. See `tools/design/logos.py`.
- The black rectangles behind the logo, used in 0.2.0, are gone.

## 2. Typography

| Role | Website | App |
|---|---|---|
| Headlines, wordmark, article text | Newsreader (opsz, wght; italic) | Bundled `Newsreader-Variable.ttf` and `Newsreader-Italic-Variable.ttf`, through the named instances `NewsreaderRoman-*` and `NewsreaderItalic-*` |
| Labels, eyebrows, metadata | Manrope | Bundled `Manrope-Variable.ttf` (`Manrope-*`) |

**How fonts behave:**
- Fonts are registered at launch (`BrandFonts.register()`).
- Every style scales with Dynamic Type (`relativeTo:`).
- If a font fails to load, the system serif or sans is used.
- The licences (SIL OFL 1.1) are bundled in `Resources/Fonts`, and acknowledged in About.

## 3. Editions × appearances

**Settings › Edition and appearance** has two independent choices:
- **Edition:** Future (default, as on the website) or Classic.
- **Appearance:** System, Light or Dark.

The website itself is dark-only. Its tokens define the Dark appearance exactly. The Light appearance uses the same hues on an inverted neutral scale.

| Token | Future Light | Future Dark | Classic Light | Classic Dark | Website source (dark) |
|---|---|---|---|---|---|
| background | #F5F7F9 | #050506 | #FFFFFF | #000000 | `--background` 11.5% / classic 0% |
| surface | #E9EBEE | #111213 | #F3F3F5 | #020203 | `--surface` 18% / 9% |
| elevated (cards) | #FFFFFF | #1D1F23 | #FFFFFF | #0A0B0D | `--elevated` 24% / 15% |
| primary text | #0E0F11 | #EDEEF1 | #030304 | #EDEEF1 | `--foreground` 95% |
| secondary text | #505357 | #95989D | #46484B | #95989D | `--muted-foreground` 68% |
| silver / metal | #616368 | #C7CBCE | #5C5E61 | #C7CBCE | `--metal` 84% |
| separator | #DCDEE0 | #1C1C1C | #E0E0E0 | #1F1F1F | `--border` white 9% / 12% |
| accent (signal) | #006678 | #8FCDD8 | #006071 | #8FCDD8 | `--signal` 81% .065 210 |
| breaking bar | #C2181D | #D4302E | #C2181D | #D4302E | `--breaking` 58% .2 27 (57% in the app) |

**Increase Contrast** variants are in `Theme.swift`.

**Checking the palettes:** `tools/design/palette.py` converts the OKLCH values to sRGB and checks every pair:
- primary text against background, surface and card: ≥ 7:1;
- secondary text and accent: ≥ 4.5:1;
- silver: ≥ 3:1;
- text on the accent and on the breaking bar: ≥ 4.5:1.

There are no failures. The website's own breaking red gave 4.47:1 against its text, so the app's is one step darker.

**What differs between editions, besides colour, as on the website:**

| | Future | Classic |
|---|---|---|
| Logo | Futuristic HCG | Classic metallic HCG |
| Masthead hero | Command-centre backdrop (Dark) or signal-tinted surface (Light); "FUTURE EDITION" label | "HCG News." wordmark, with the full stop in signal colour, over a heavy rule |
| Cards | Layered metallic gradient, faint silver border, 4 pt radius | Flat card, hairline border, 2 pt radius |
| Section headings | Signal dot and a hairline rule | 2 pt black or white rule |

## 4. Components

| Website | App |
|---|---|
| Header (date, tagline, edition switch, logo, nav) | `Masthead`, then `SectionStrip` (category navigation) |
| Breaking bar (`bg-breaking`, "BREAKING", headline, `aria-live`) | `BreakingNewsBanner`: red bar with one headline at a time and a 7 s advance. Pause and Next are always offered; it doesn't advance under Reduce Motion or VoiceOver. |
| Story hero | `LeadArticleCard`: 16:10 media, eyebrow, serif headline, excerpt, byline and date |
| Stream card | `StreamCard`. The grid is one column on iPhone and adaptive on iPad. |
| Media placeholder ("HCG News" italic, section eyebrow) | `MediaPlaceholder` |
| Eyebrow, type tag, Demo content tag | `KickerLine`, `EditorialLabel` |
| Dates `27 Nov 2026` (en-GB) | `NewsDate.article` |

**Kept native:**
- the tab bar: a standard `TabView`, which gets Liquid Glass with the iOS 26 SDK;
- navigation stacks and the iPad split view;
- Saved, Search, Account and the Newsroom.

There is no web view.
