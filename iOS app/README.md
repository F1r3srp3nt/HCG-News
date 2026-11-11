# HCG News for iPhone and iPad

The iOS app for [news.hakmicapitalgroup.com](https://news.hakmicapitalgroup.com). Everything for it lives in this `iOS app` folder.

**Status: version 0.2.0 (2), development build. Not released and not production-ready.** It has not yet been compiled or run on a Mac, simulator or device. See [docs/MILESTONE-2-REPORT.md](docs/MILESTONE-2-REPORT.md) and [CHANGELOG.md](CHANGELOG.md).

HCG News is the publication's native reader and newsroom companion:

- **Reader:** Home with a masthead, lead story, editor-flagged Featured stories and explicit breaking news; Sections; Search with stated scope and filters; Saved with offline downloads; and an article reader with corrections, sponsored notices, disclosures, audio, photo zoom and reading controls.
- **Account:** HCG Connect sign-in (PKCE in the system browser), with identity, organisation, access and capabilities as HCG reports them.
- **Newsroom:** a separate workspace for local drafts with autosave, recovery, versions, preview and export/import. Remote editorial actions are offered only when the newsroom service and HCG support and authorise them.
- **Settings › Advanced:** configuration import with preview and rollback, connection checks and diagnostics.

The app consumes the publication's content and HCG's central identity. It has no newsroom database, account system, role store or licensing of its own.

**It is not connected yet.** The publication has no supported content or newsroom API (see the site inspection), and central HCG hasn't registered a native client. The app ships with **no endpoints, client IDs or secrets** and shows "Publication not connected" until a valid configuration is imported. It contains no sample reporting. The only fixtures are DEBUG-only, labelled and stored separately.

| | |
|---|---|
| Project | [`HCGNews/HCGNews.xcodeproj`](HCGNews/HCGNews.xcodeproj) (Xcode 16+, iOS 17+) |
| Core package | [`HCGNews/HCGNewsKit`](HCGNews/HCGNewsKit). Foundation only; 134 tests, passing on Linux (Swift 6.1). |
| Build and test | [docs/BUILD-AND-TEST.md](docs/BUILD-AND-TEST.md) |
| Architecture | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| What was found, and what's missing | [docs/INTEGRATION-DISCOVERY.md](docs/INTEGRATION-DISCOVERY.md) |
| What the live site serves (11 Nov 2026) | [docs/SITE-INSPECTION-2026-11-11.md](docs/SITE-INSPECTION-2026-11-11.md) |
| Proposed content contract | [docs/HCG-NEWS-CONTENT-API-PROPOSAL.md](docs/HCG-NEWS-CONTENT-API-PROPOSAL.md) |
| HCG Connect / ERP handoff | [docs/HCG-MAIN-CONFIGURATION-HANDOFF.md](docs/HCG-MAIN-CONFIGURATION-HANDOFF.md) |
| Milestone report and next steps | [docs/MILESTONE-1-REPORT.md](docs/MILESTONE-1-REPORT.md) |
| Backend work still needed | [docs/BACKEND-REQUIREMENTS.md](docs/BACKEND-REQUIREMENTS.md) |
| Proposed newsroom API · draft file format | [docs/NEWSROOM-API-PROPOSAL.md](docs/NEWSROOM-API-PROPOSAL.md) · [docs/NEWSROOM-DRAFT-FORMAT.md](docs/NEWSROOM-DRAFT-FORMAT.md) |
| Configuration examples (no secrets) | [docs/config-examples/](docs/config-examples/) |
| Manual acceptance checklist | [docs/ACCEPTANCE-CHECKLIST.md](docs/ACCEPTANCE-CHECKLIST.md) |
| Packaging / HCG Executable Maker | [docs/PACKAGING.md](docs/PACKAGING.md) |
| Later milestones | [docs/ROADMAP.md](docs/ROADMAP.md) |
