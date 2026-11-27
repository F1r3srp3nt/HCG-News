# Editorial correction checklist — published articles (review of 27 November 2026)

**Scope:** all 13 articles published on news.hakmicapitalgroup.com on 27 November 2026. They were checked for accuracy, sourcing, labelling and legal risk before any App Store screenshots.

**Rules for this checklist:**
- Nothing here changes the publication by itself. Every item is an editorial decision for the editor-in-chief.
- Published articles are never edited silently, and legitimate journalism is not removed to suit App Review.
- The detailed correction plan for the Nvidia and Coinbase articles, with proposed wording and sources, is kept privately by the founder. It is not in this public repository.

**Corrections to the first version of this review**, made after checking the sources directly:
- It cited a published denial by the subject of one allegation in the Nvidia article. That denial could not be verified, so it has been removed.
- It called one line in the same article a misstatement. That line is accurate.
- It counted 8 articles with the Breaking flag; there are 9.

## 1. Before App Store submission

- [ ] **Nvidia's $1.5 Trillion Roller Coaster** (`e51c9c4a`)
  - Attribute the report of a further relationship to its source and state that it is unconfirmed, or remove that sentence.
  - Align the headline with the standfirst ("An admitted affair").
  - Verify the resignation date, the chairman appointment, the share count and the BuzzFeed attribution.
  - Add source links.
- [ ] **Coinbase Closed His Account…** (`e01faa88`)
  - Remove the internal editor's note from the published text.
  - Request comment from Coinbase and publish the reply or the non-response.
  - Move the founder's conflict-of-interest disclosure to the top.
  - Rephrase the headline as the account holder's claim.
  - Remove the third-party company and the support agent's name.
- [ ] **Breaking flags:** remove from all 9 articles (Nvidia, Beyond Applications, Connected Software Ecosystem, Coinbase, Road Cameras, `/h`, Oslo Sprint, Alphabet, Desktop Applications). In the app, Breaking drives the ticker at the top of Home.

## 2. Accuracy and labelling (any time)

- [ ] **Alphabet** (`45009db2`)
  - Give the market-value loss as a range ($475–500B).
  - Verify or remove the $83.4B ad-revenue expectation and the 2027 capex claim.
  - Note the investment mark behind the net-income drop.
  - Add links.
- [ ] **Road Cameras to Private Messages** (`69120364`)
  - Change the type to analysis.
  - Add the founder's political-affiliation disclosure.
  - Verify the "EEA note of 9 Nov" or remove it.
  - Correct the Council release title.
  - Add URLs.
- [ ] **Oslo Sprint 2026** (`90b0f186`)
  - Delete the leftover "Currently editing image...".
  - Add the Wybe challenge winner.
  - Verify the Kliffi prize, the 14 entries and the jury list with the organisers.
- [ ] **Make Data Smart 2026** (`d23b3a20`)
  - Confirm that DNB's speaker was in Oslo.
  - Name the first-person author.
  - Add sources and an excerpt.
- [ ] **ERP 2026** (`e4670e3a`)
  - Verify or remove the BCG "more than half fail" figure.
  - Clarify "Prosci presented".
  - Add URLs.
- [ ] **HCG Expands Its Software Ecosystem With New Desktop Applications** (`2b6cc742`)
  - Change the type to announcement.
  - Replace the `draft-…` address.
- [ ] **HCG Introduces HCG AI** (`7e347e66`)
  - Confirm the Demo flag.
  - Retitle to match what exists (the website).
  - Check the "Enterprise… Available" claim.
  - Replace the `draft-…` address.
- [ ] **Could AI Give iPhone Jailbreaking a New Purpose?** (`95da8b56`)
  - Disclose that the author's company builds jailbreak tools.
  - Correct the Microsoft study figures (35% overall; study period Nov 2023–Jan 2024).
  - Make the opinion/analysis label consistent.
- [ ] **Beyond Applications** (`4968adfa`), **Connected Software Ecosystem** (`a28d38b9`) and **`/h`** (`0e90410f`)
  - Label HCG's own figures as HCG-reported.
  - Correct "successful launch" to what was actually shown.
  - Give `/h` a proper address.

## 3. App Store screenshots

Screenshots are public marketing, so only articles whose checklist items are done may appear in them. This doesn't affect what the app shows: the app shows the publication as published.

| Status | Articles |
|---|---|
| Cleared today | **None.** Every candidate has at least one open item. |
| Candidates once their items above are done | Make Data Smart (`d23b3a20-a874-42c7-8972-58af1b3329fd`), ERP 2026 (`e4670e3a-65e2-4e84-a33c-2df1feb85f8a`), Alphabet (`45009db2-7677-4df2-aa55-87d69c84e6fb`). Optionally the two HCG announcements (`2b6cc742…`, `7e347e66…`). |
| Not for marketing | Nvidia and Coinbase (allegations involving third parties), and the four jailbreak-related pieces. |

**Before capturing:**
- check the cleared articles' images for identifiable faces and third-party logos;
- then list their ids in `HCGNEWS_SCREENSHOT_ARTICLES`. See [APP-STORE-RELEASE.md](APP-STORE-RELEASE.md) §5.
