# HCG News iOS — changelog

Version numbers change only on purpose and are recorded here: `MARKETING_VERSION` (`CURRENT_PROJECT_VERSION`). None of these builds has been released, uploaded to TestFlight or submitted.

## Unreleased — real HCG integration (version unchanged: 0.2.0 (2))

Connected to the real publication and HCG identity, using the contracts the HCG News website and HCG ONE already use. Details: [docs/INTEGRATION-REPORT.md](docs/INTEGRATION-REPORT.md).

**Reading**
- Public reading from the publication's own tables, with the public key only: published, due articles, reader columns only, and an on-device visibility re-check.
- Pagination, sections, search with section and type filters, and canonical `/<section>/<slug>` sharing.
- "Demo content" label. The founder's author disclosure is mirrored from the website.

**Account**
- HCG-branded sign-in with the existing HCG account. Keychain storage, refresh, revocation detection, and an exact sign-out report.
- HCG News roles from HCG.
- HCG workspaces (ERP, Executive Control Center) open through one-time links in Safari.

**Newsroom (HCG News staff only)**
- Desk with filters and search.
- Editor with lossless body editing, media library and upload, versions, preview, revision-guarded saves, conflict resolution, and on-device protection of unsaved edits.
- Role-gated status changes with confirmations; publish or schedule.
- Administration: sections, and the audit history for Administrators.

**Configuration**
- `HCGNews/Resources/HCGNewsConfiguration.json` (`hcgPlatform`, public values only) is bundled, so Release and archive builds are connected.
- The loader refuses secret and service-role keys and other projects.

**Tools**
- `tools/verify-hcg-news-access.sh`: an access check to run yourself.
- `backend/`: a public-read SQL handoff, applied only if the check fails.

**Tests**
- 181 package tests (46 new).
- The real-build UI test now expects a connected app.

## Unreleased — app icon (version unchanged: 0.2.0 (2))

- The app icon is now the supplied HCG News icon set (from `HCG-News-Icons.zip`), installed byte-for-byte as `AppIcon.appiconset`. It has 18 slots (8 iPhone, 9 iPad, 1 App Store), using 13 opaque RGB PNGs.
- It replaces the single 1024 px icon generated in 0.2.0. `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` is unchanged (Debug and Release). The bundle id, signing, deployment target, version and build number are unchanged.

## 0.2.0 (2) — 11 November 2026 — development build

**Brand**
- New editorial identity: black, charcoal, silver and white surfaces, with cyan only for actions and status. System, Light and Dark appearance, and Increase Contrast.
- The supplied HCG logo is now the app icon and the masthead. The Hakmi Capital Group mark is used for publisher attribution.

**Configuration and connection**
- Settings › Advanced: separate Publication and HCG Connect configurations.
  - Import from Files, with validation and a preview before applying.
  - A failed import keeps the previous configuration.
  - Configurations persist, and can be exported or removed (removal falls back to the bundled file).
  - A change of sign-in identity clears the session and the account links.
- Distinct states for missing configuration, invalid configuration, offline, empty publication, permission denial and server failure.
- Check Connection distinguishes "configured", "reachable" and "verified".

**Reading**
- Home: lead story, Featured only when editors flag it, explicit breaking news, a section strip, pagination with deduplication, and scroll restoration.
- Labels for News, Analysis, Opinion, Sponsored and HCG Announcement. Unknown types and sections are kept.
- Search: stated scopes (Publication, This session, Downloaded) and filters. Filters the server can't apply are labelled.
- Reader:
  - corrections, sponsored notice, published audio, on-device read-aloud (labelled as local), photo viewer, related stories from metadata;
  - reading controls (size, spacing, width, typeface) and the saved reading position;
  - an unsupported-content notice, and summary-only articles that link to the web.

**Saved and offline**
- Downloads: article text and images, with downloading, downloaded, failed, interrupted and update-available states, the download date and the content revision.
- Readable offline after a force-quit. A failed update keeps the earlier copy. Interrupted downloads can be resumed.
- Storage usage, a size limit and clear controls. Restricted and summary-only articles aren't stored.
- Bookmarks migrate from v1 to v2, with a backup. A file written by a newer app version is never overwritten.

**Account**
- HCG Connect sign-in, with identity and organisation shown as HCG verifies them, organisation selection, access status, capabilities and entitlements, session restore and local sign-out.

**Newsroom (new)**
- A separate workspace for local drafts:
  - structured editor; section and type; verified bylines only;
  - cover and inline images with alt text, caption and credit; media attachments with upload state;
  - autosave and recovery, version snapshots, native preview, versioned export/import, search and filters.
- Remote actions (save to newsroom, submit, approve, schedule, publish, correct, unpublish) through a capability-gated client for a **proposed** newsroom API.
  - Each action is unavailable, with a reason, until HCG and the service support and authorise it.
  - Conflicts are explicit, and nothing is queued or sent automatically.
- Administration: health, access and licence, queue, management links, server audit history (when one exists) and a separate device history.

**Platform**
- iPad: keyboard shortcuts.
- Development fixtures moved to their own storage folder.

**Tests**
- 135 package tests on Linux (Swift 6.1), and 14 UI tests (not yet run).

## 0.1.0 (1) — 3 November 2026 — development build

- First native reader (Milestone 1): unconfigured, with the content API and HCG Connect handoff documented.
