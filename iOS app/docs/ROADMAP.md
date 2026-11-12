# HCG News apps — roadmap

Done in 0.2.0 (on the app side, against fixtures): local offline downloads, local newsroom drafting, configuration import and the capability-gated newsroom client. What remains needs backend work or a founder decision. The app has no placeholder controls for any of it; where something appears, it states that it's unavailable and why.

| Milestone | Scope | Prerequisites |
|---|---|---|
| **Live connection** | Import the approved publication configuration. Adapt `WireFormat.swift` if the real contract differs from the proposal. Run the live items of the acceptance checklist. | Content API ([BACKEND-REQUIREMENTS.md](BACKEND-REQUIREMENTS.md) §A) |
| **HCG Connect live** | Native client registration and the App Access endpoint; account and organisation checks | §C |
| **Newsroom live** | Server drafts, submission, review, scheduling, publishing, corrections, unpublishing | Newsroom API (§B), central permission (§C3) |
| **Notifications** | APNs registration, opt-in prompt, topic delivery (preferences already stored locally) | A notification service; an editorial trigger rule; the Push capability (see PACKAGING.md) |
| **Restricted offline** | Time-limited offline copies of restricted articles | An agreed access and retention policy |
| **Saved-article sync** | Sync across devices | A central per-user storage contract |
| **Native administration** | Sections, authors and media management in the app | Management endpoints (§B5); until then, central management links |
| **Additional platforms** | Mac, widgets, Watch, Android/web parity | A product decision per platform |
| **Release** | App Store metadata, privacy labels, export compliance, TestFlight, App Review | Founder approval. Not to be done without explicit instruction. |
