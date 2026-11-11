# HCG News apps — later milestones

None of these are in Milestone 1. The app has no placeholder screens or controls for them. Each needs a founder decision and, where noted, a verified central contract first.

| Milestone | Scope | Prerequisites |
|---|---|---|
| **M1.1 Live connection** | Install the approved content configuration; adapt the decoder if the real contract differs from the proposal; device testing; real text-heavy artwork checks | Content API (or confirmed existing contract) from the publication owner; HCG host access for testing |
| **M1.2 HCG Connect live** | Register the HCG News native client centrally; App Access endpoint; run the acceptance tests in the handoff (§8) | Central HCG decisions in [HCG-MAIN-CONFIGURATION-HANDOFF.md](HCG-MAIN-CONFIGURATION-HANDOFF.md) §7 |
| **M2 Notifications** | Opt-in push notifications; topic preferences (e.g. per section, breaking only); no prompt at first launch | A push service owned by HCG; an editorial rule for what triggers a notification; APNs key held server-side only; privacy review |
| **M3 Offline reading** | Explicit "Download for offline" per article or section, with storage limits and expiry; honours later corrections and unpublishing | Content API support for conditional fetches; editorial policy on corrected or unpublished articles stored on devices |
| **M4 Bookmark sync** | Account-based sync of saved articles across devices | A verified central contract, owned by HCG, for per-user data; account-linking and conflict rules; local bookmarks stay usable when signed out |
| **M5 Native newsroom** | Native editing and publishing for authorised staff | Newsroom write API with server-side permission checks, audit log, draft/review/publish workflow; App Access permissions; security review. Until then, staff use the existing web newsroom through the permission-gated link. |
| **M6 Additional platforms** | Mac (native or Catalyst), Apple Watch headlines, widgets, Android/web parity | Product decision per platform; shared core package already Foundation-only |
| **Release** | App Store metadata, privacy nutrition labels, export compliance answers, TestFlight, App Review | Founder approval. Not to be done without explicit instruction. |
