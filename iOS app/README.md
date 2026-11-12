# HCG News for iPhone and iPad

The iOS app for [news.hakmicapitalgroup.com](https://news.hakmicapitalgroup.com). Everything for it lives in this `iOS app` folder.

**Status: version 0.2.0 (2), development build. Not released and not production-ready.** It has not yet been compiled or run on a Mac, simulator or device. See [docs/INTEGRATION-REPORT.md](docs/INTEGRATION-REPORT.md) and [CHANGELOG.md](CHANGELOG.md).

HCG News is the publication's native reader and newsroom companion:

- **Reader:** Home with a masthead, lead story, editor-flagged Featured stories and explicit breaking news; Sections; Search with stated scope and filters; Saved with offline downloads; and an article reader with corrections, sponsored notices, disclosures, audio, photo zoom and reading controls.
- **Account:** sign-in with the existing HCG account (the same as the HCG website and HCG ONE), with HCG News roles and HCG workspaces (ERP, Executive Control Center) as HCG reports them.
- **Newsroom:** for people HCG gave an HCG News role. Write, edit, review, schedule, publish and archive articles, with media, versions, conflicts and unsaved-edit protection, following the website newsroom's rules. The server authorises every action. Local on-device drafts remain available.
- **Settings › Advanced:** configuration import with preview and rollback, connection checks and diagnostics.

The app consumes the publication's content and HCG's central identity. It has no newsroom database, account system, role store or licensing of its own.

**It is connected to the real publication.** It uses the tables, server function and storage the HCG News website itself uses, through the shared HCG project, and HCG's documented sister-app sign-in. The bundled configuration contains only public values (no secrets). See [docs/INTEGRATION-REPORT.md](docs/INTEGRATION-REPORT.md), including the one access check to run yourself ([tools/verify-hcg-news-access.sh](tools/verify-hcg-news-access.sh)). It contains no sample reporting. The only fixtures are DEBUG-only, labelled and stored separately.

| | |
|---|---|
| Project | [`HCGNews/HCGNews.xcodeproj`](HCGNews/HCGNews.xcodeproj) (Xcode 16+, iOS 17+) |
| Core package | [`HCGNews/HCGNewsKit`](HCGNews/HCGNewsKit). Foundation only; 182 tests, passing on Linux (Swift 6.1). |
| **Real integration: what, how, verification, your steps** | [docs/INTEGRATION-REPORT.md](docs/INTEGRATION-REPORT.md) |
| Access check (run it yourself) · backend handoff if needed | [tools/verify-hcg-news-access.sh](tools/verify-hcg-news-access.sh) · [backend/HCG-NEWS-PUBLIC-READ.md](backend/HCG-NEWS-PUBLIC-READ.md) |
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
