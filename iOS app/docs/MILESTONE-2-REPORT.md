# HCG News iOS 0.2.0 (2) — milestone report

Date: 11 November 2026 · Branch: `claude/bold-gauss-dp6yro` · Status: **development build. Not released, not uploaded, not connected to live content.**

## 1. Summary

All five stages were implemented on the app side:

- configuration and branding;
- home, search and reader;
- offline downloads and storage migration;
- account and newsroom drafts;
- capability-gated remote editorial and admin actions, with the integration handoff.

Logic lives in the Foundation-only package, which **builds with 0 warnings and passes 135 tests** under Swift 6.1 on Linux. The SwiftUI layer (about 3,000 lines) **has not been compiled**: there is no Xcode or Apple SDK in this environment. It passes a syntax check, and an independent read-through looked for compile errors. Nothing loads live content yet. No supported content API or newsroom API exists (the site inspection confirmed this), and central HCG hasn't registered a native client. Each of those is now one configuration import away, once the backend work in [BACKEND-REQUIREMENTS.md](BACKEND-REQUIREMENTS.md) is done.

## 2. Walkthrough

1. **First launch, no configuration.**
   - The masthead shows the supplied HCG logo on black. Home says "Publication not connected", with **Open Advanced Settings** and a web link.
   - Saved, Search (scope "Downloaded") and the Newsroom still work.
2. **Settings › Advanced › Import Configuration.**
   - Choose Publication or HCG Connect, then pick a JSON file. The preview shows environment and destinations, and any problems.
   - **Apply** stores it and rebuilds the app's services. **Check Connection** reports "Connected" only after the publication's contract check succeeds.
3. **Reading.**
   - Home shows the lead story, Featured (only if editors flag stories), explicit breaking news, the section strip and Latest.
   - Each article has reading controls, notices, audio or read-aloud, photo zoom, and saved position.
   - Save it, then download it. It opens offline, labelled "Stored copy from …".
4. **Account.** Sign in with HCG Connect. Identity, organisation, access and capabilities appear only as HCG returns them. Sign out reports exactly what happened.
5. **Newsroom** (Settings › Newsroom, the iPad sidebar, or ⌘⇧N).
   - Create a local draft: blocks, images with alt text, section and type.
   - Autosave and recovery, versions, preview, and export/import are all available.
   - Remote actions explain why they're unavailable. With a newsroom API and HCG access, they run on explicit taps, with review and conflict sheets.
   - **Administration** separates server audit history from the device's own troubleshooting history.

## 3. Build and test results

| What | Result |
|---|---|
| `swift build` of HCGNewsKit, Swift 6.1.3 Linux, Swift 6 language mode, clean build | **Pass, 0 warnings** |
| `swift test` of HCGNewsKit (fixtures, fake transports, temp folders) | **135 tests, 0 failures**: NewsCore 65, HCGConnect 27, Newsroom 17, NewsAppModel 26 |
| Real defects found by these tests during the work, then fixed | Link markup with parentheses in the URL left a stray `)` in the text; an empty search query could hide the "not connected" state (0.1.0) |
| `swiftc -parse` of every app and UI-test file | Pass (syntax only) |
| `project.pbxproj` with an independent parser (`pbxproj` 4.2.1) | Pass: 37 objects, all references resolve, Newsroom linked to the app target |
| Independent read-only compile review of the SwiftUI layer | See §6 |
| **`xcodebuild`, 14 UI tests, simulator or device runs, screenshots** | **Not run** (no Mac) |
| **Live content, live sign-in, live newsroom** | **Not possible** (no contracts or registrations yet) |

### Failure paths covered by fixture tests

| Path | Test |
|---|---|
| Invalid configuration rollback | `ConfigurationStoreTests.testInvalidImportLeavesPreviousConfigurationActive` |
| Secrets and privileged keys rejected | `testSecretsAnywhereInTheFileAreRejected`, `testCardXRedirectIsRejectedOnImport` |
| Persistence and bundled fallback | `testValidImportPreviewsAppliesAndPersistsAcrossLaunches`, `testRemovalFallsBackToBundled` |
| Public reading without login | `AppContainerTests.testPublicReadingWorksWithoutAnyIdentityConfiguration` |
| No requests without configuration | `testWithoutConfigurationNoNetworkRequestIsEverMade` |
| Missing vs invalid configuration | `testUnconfiguredAndInvalidAreDistinctStates` |
| Pagination deduplication | `testPaginationDeduplicatesAndStopsOnRepeatedCursor` |
| Offline restart | `OfflineLibraryTests.testDownloadThenReadAfterRestartWithoutNetwork`, `SavedAndArticleTests.testDownloadedArticleOpensAfterRestartWhenOfflineAndIsLabelledAsStored` |
| Failed downloads | `testFailedUpdateKeepsPreviousCopy`, `testMissingImageStillDownloadsTextAndCountsIt`, `testStorageLimitRefusesWithoutDeletingOtherDownloads`, `testRestrictedAndSummaryOnlyAreRefused` |
| Interrupted downloads | `testInterruptedDownloadIsRecoverable` |
| Bookmark migration | `BookmarkMigrationTests.testVersion1FileIsMigratedAndBackedUp`, `testNewerFileVersionIsNeverOverwritten` |
| Draft recovery | `DraftStoreTests.testSaveAutosaveAndRecoveryAfterInterruption`, `testDiscardRecoveryKeepsSavedVersion` |
| Revision conflicts | `NewsroomGateAndClientTests.testConflictIsReportedAndNothingOverwritten` |
| Account switching / identity change | `AppContainerTests.testIdentityConfigurationChangeSignsOutAndDetachesDraftLinksButKeepsWork`, `ConfigurationStoreTests.testIdentityChangeIsDetected` |
| Denied editorial actions | `NewsroomModelTests.testActionsUnavailableWithoutCentralAccessAndNothingIsSent`, `testServerDenialIsReportedAndLocalWorkKept`, `NewsroomGateAndClientTests.testDeniedAndSignedOutActions` |
| No automatic submission | `testOfflineFailsImmediatelyWithoutQueueing`, `testUnsyncedChangesBlockActionsUntilSaved` |

### Platform checks not run

- Compiling the SwiftUI layer, and the 14 UI tests.
- Layouts on iPhone and iPad, rotation, Split View and Stage Manager.
- Dynamic Type at accessibility sizes, VoiceOver, Reduce Motion, Increase Contrast.
- Keychain, the system sign-in browser, PhotosPicker, AVPlayer and speech.
- Image loading from offline files.
- File import and export through Files.
- Hardware-keyboard shortcuts.
- The CryptoKit SHA-256 path.

Use [ACCEPTANCE-CHECKLIST.md](ACCEPTANCE-CHECKLIST.md).

## 4. Remaining backend dependencies

See [BACKEND-REQUIREMENTS.md](BACKEND-REQUIREMENTS.md). In short:

- **News site:** a content API (live reading) and a newsroom API (remote editorial actions).
- **Main HCG:** a native client registration, the App Access endpoint (with optional identity, organisation and entitlement fields), permission names, logout and token semantics, and management links.
- **Not requested now:** notifications, sync and subscriptions are explicitly unavailable, with reasons.

## 5. Founder-control notes

- Nothing was merged, published, deployed or uploaded. No OAuth client was registered, no role granted, and no central policy changed.
- The version change from 0.1.0 (1) to 0.2.0 (2) is recorded in [CHANGELOG.md](../CHANGELOG.md) and [PACKAGING.md](PACKAGING.md).
- Configuration examples contain placeholders and `approvedByFounder: false` only, and no secret-like keys.
- Existing bookmarks are preserved: same file path, v1→v2 migration with a backup. Fixture data uses a separate folder.

## 6. Independent compile review

A separate read-only review checked the SwiftUI layer against the package's public API and the iOS 17 SDK. It found **one certain compile error**, and seven runtime, UX or robustness issues. All eight were fixed:

1. **Compile error.** `ArticleSource` was declared in two imported modules (NewsCore's source-citation struct and NewsAppModel's live/stored enum). The enum was renamed `ArticleOrigin`, and the fixtures now name `NewsCore.ArticleSource` explicitly.
2. **Editor marked itself dirty after newsroom actions.** After a newsroom action, the editor showed "Unsaved changes" and later refused the next action. Added `DraftEditorModel.reload(from:)` and a test for it.
3. **Help text rendered as Markdown.** The editor's markup help showed formatted text instead of the syntax. It now uses `Text(verbatim:)`.
4. **UI test used the wrong element type.** The draft headline is a vertical-axis field, which is exposed as a text view. It now has an accessibility identifier, and the test queries that.
5. **Newsroom might not open from Settings on iPhone.** It could be dropped while the Settings sheet was dismissing. It now opens after the sheet's `onDismiss`.
6. **Sign-in callback assumed the main thread.** The callback no longer assumes it; it hops explicitly with `Task { @MainActor … }`.
7. **Property named `toolbar`.** It overlapped the modifier name and was renamed `toolbarContent`.

The review also confirmed:
- every package API call, label, access level and `await`;
- switch exhaustiveness over every package enum;
- the iOS 17 API usage;
- the Release build's exclusion of fixtures.

## 7. Next steps

1. ☐ On a Mac: build and run all tests on an iPhone and an iPad simulator ([BUILD-AND-TEST.md](BUILD-AND-TEST.md)). Report compile errors back for a quick fix pass.
2. ☐ Work through [ACCEPTANCE-CHECKLIST.md](ACCEPTANCE-CHECKLIST.md) in fixture mode, and capture screenshots.
3. ☐ When the site reopens: implement or confirm the content API (§A), then import the publication configuration.
4. ☐ Central HCG: register the native client and App Access (§C), then import the Connect configuration.
5. ☐ Newsroom API (§B), then add `content.newsroomAPIBaseURL`.
6. ☐ Founder decisions on notifications, restricted offline copies and sync, before any of them is built.
