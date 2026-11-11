# HCG News for iPhone and iPad

The iOS app for [news.hakmicapitalgroup.com](https://news.hakmicapitalgroup.com). Everything for it lives in this `iOS app` folder.

**Status: Milestone 1, development build. Not released and not production-ready.** It has not yet been compiled or run on a Mac, simulator or device. See [docs/MILESTONE-1-REPORT.md](docs/MILESTONE-1-REPORT.md).

A native SwiftUI reader for the existing HCG News publication. It has:

- Home (featured, latest, explicit breaking news), Sections, Search and Saved;
- an article reader with native, sanitised formatting, sources, author disclosures, reading size, and sharing of the canonical URL;
- Future (dark navy, cyan, serif) and Classic reading styles;
- iPhone tabs, an iPad sidebar, and Split View / Slide Over support.

The app consumes the publication's content and HCG's central identity. It has no newsroom database, account system, role store or licensing of its own.

**It is not connected yet.** No supported HCG News content API, and none of the HCG Connect contract documents, were available to this milestone. The app ships with **no endpoints, client IDs or secrets**, and shows "Live publication not connected" until an approved configuration is installed. It contains no sample reporting. The only fixtures are DEBUG-only, test-labelled placeholders.

| | |
|---|---|
| Project | [`HCGNews/HCGNews.xcodeproj`](HCGNews/HCGNews.xcodeproj) (Xcode 16+, iOS 17+) |
| Core package | [`HCGNews/HCGNewsKit`](HCGNews/HCGNewsKit). Foundation only; 90 tests, passing on Linux (Swift 6.1). |
| Build and test | [docs/BUILD-AND-TEST.md](docs/BUILD-AND-TEST.md) |
| Architecture | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| What was found, and what's missing | [docs/INTEGRATION-DISCOVERY.md](docs/INTEGRATION-DISCOVERY.md) |
| Proposed content contract | [docs/HCG-NEWS-CONTENT-API-PROPOSAL.md](docs/HCG-NEWS-CONTENT-API-PROPOSAL.md) |
| HCG Connect / ERP handoff | [docs/HCG-MAIN-CONFIGURATION-HANDOFF.md](docs/HCG-MAIN-CONFIGURATION-HANDOFF.md) |
| Milestone report and next steps | [docs/MILESTONE-1-REPORT.md](docs/MILESTONE-1-REPORT.md) |
| Later milestones | [docs/ROADMAP.md](docs/ROADMAP.md) |
