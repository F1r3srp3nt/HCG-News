import XCTest

/// UI tests. Most run against DEBUG development fixtures (HCGNEWS_UI_TEST_FIXTURES=1),
/// which show a "DEVELOPMENT FIXTURES — not live reporting" banner and use a separate
/// storage folder. One test launches the real, unconfigured app.
///
/// These are fixture tests, not live verification. Run on an iPhone and an iPad
/// simulator (see docs/BUILD-AND-TEST.md).
final class HCGNewsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(fixtures: Bool = true, reset: Bool = true, extra: [String: String] = [:], arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        if fixtures {
            app.launchEnvironment["HCGNEWS_UI_TEST_FIXTURES"] = "1"
            if reset { app.launchEnvironment["HCGNEWS_UI_TEST_RESET"] = "1" }
        }
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func go(to name: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 2) { tab.tap(); return }
        let item = app.collectionViews.staticTexts[name].firstMatch
        if !item.exists, app.navigationBars.buttons["Show Sidebar"].exists { app.navigationBars.buttons["Show Sidebar"].tap() }
        XCTAssertTrue(item.waitForExistence(timeout: 5), "No navigation item named \(name)")
        item.tap()
    }

    private func openSettings(_ app: XCUIApplication) {
        if app.tabBars.firstMatch.waitForExistence(timeout: 3) {
            app.buttons["Settings"].firstMatch.tap()
        } else {
            go(to: "Settings & Account", in: app)
        }
    }

    private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    // MARK: Real build, no configuration

    func testUnconfiguredBuildShowsNotConnectedWithRouteToAdvancedSettings() {
        let app = launch(fixtures: false)
        XCTAssertTrue(app.staticTexts["Publication not connected"].waitForExistence(timeout: 10))
        XCTAssertFalse(element(containing: "Fixture", in: app).exists, "no sample content outside fixtures")
        let advanced = app.buttons["Open Advanced Settings"]
        XCTAssertTrue(advanced.exists)
        advanced.tap()
        XCTAssertTrue(element(containing: "Import Configuration", in: app).waitForExistence(timeout: 5))
    }

    // MARK: Fixtures

    func testFixtureBannerMastheadAndNavigation() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["DEVELOPMENT FIXTURES — not live reporting"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(containing: "HCG News,", in: app).exists, "masthead")
        for name in ["Sections", "Search", "Saved", "Home"] { go(to: name, in: app) }
    }

    func testEditorialLabelsIncludingSponsoredAndAnnouncement() {
        let app = launch()
        XCTAssertTrue(element(containing: "Fixture headline", in: app).waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(element(containing: "Sponsored content", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "HCG Announcement", in: app).exists)
    }

    func testBreakingHeadlineNavigation() {
        let app = launch()
        let first = element(containing: "Breaking: Fixture headline 2", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        app.buttons["Next breaking headline"].tap()
        XCTAssertTrue(element(containing: "Breaking: Fixture breaking headline two", in: app).waitForExistence(timeout: 3))
        app.buttons["Previous breaking headline"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 3))
    }

    func testArticleShowsDisclosureCorrectionUnsupportedNoticeAndSources() {
        let app = launch()
        let lead = element(containing: "Fixture long headline", in: app)
        XCTAssertTrue(lead.waitForExistence(timeout: 10))
        lead.tap()
        XCTAssertTrue(element(containing: "Fixture disclosure.", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Fixture correction", in: app).exists)
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertTrue(element(containing: "can't be shown in the app", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Fixture source document", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share"].exists)
    }

    func testSummaryOnlyArticleLinksToWeb() {
        let app = launch()
        let row = element(containing: "Fixture headline 11", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(element(containing: "Only a summary is available", in: app).waitForExistence(timeout: 5))
    }

    func testBookmarkPersistsAfterRelaunch() {
        var app = launch(reset: true)
        let row = element(containing: "Fixture headline 5", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Remove from Saved"].waitForExistence(timeout: 3))
        app.terminate()
        app = launch(reset: false)
        go(to: "Saved", in: app)
        XCTAssertTrue(element(containing: "Fixture headline 5", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Not downloaded", in: app).exists)
    }

    func testDownloadedArticleOpensAfterRelaunchOffline() {
        var app = launch(reset: true)
        let row = element(containing: "Fixture headline 6", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        app.buttons["More"].firstMatch.tap()
        app.buttons["Download for Offline"].tap()
        app.terminate()

        app = launch(reset: false, extra: ["HCGNEWS_UI_TEST_OFFLINE": "1"])
        XCTAssertTrue(app.staticTexts["You're offline"].waitForExistence(timeout: 10))
        go(to: "Saved", in: app)
        let saved = element(containing: "Fixture headline 6", in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Downloaded", in: app).exists)
        saved.tap()
        XCTAssertTrue(element(containing: "Stored copy from", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Fixture paragraph with", in: app).waitForExistence(timeout: 5), "the stored body renders offline")
    }

    func testRestrictedArticleExplainsSignIn() {
        let app = launch()
        let restricted = element(containing: "Fixture headline 7", in: app)
        XCTAssertTrue(restricted.waitForExistence(timeout: 10))
        restricted.tap()
        XCTAssertTrue(app.staticTexts["Sign-in required"].waitForExistence(timeout: 5))
    }

    func testOfflineAndEmptyStatesAreDistinct() {
        let offline = launch(extra: ["HCGNEWS_UI_TEST_OFFLINE": "1"])
        XCTAssertTrue(offline.staticTexts["You're offline"].waitForExistence(timeout: 10))
        XCTAssertTrue(offline.buttons["Try Again"].exists)
        offline.terminate()
        let empty = launch(extra: ["HCGNEWS_UI_TEST_EMPTY": "1"])
        XCTAssertTrue(empty.staticTexts["No articles yet"].waitForExistence(timeout: 10))
        go(to: "Sections", in: empty)
        let section = element(containing: "Empty Section (fixture)", in: empty)
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        section.tap()
        XCTAssertTrue(element(containing: "Nothing in Empty Section (fixture) yet", in: empty).waitForExistence(timeout: 5))
    }

    func testSearchScopeIsStated() {
        let app = launch()
        XCTAssertTrue(element(containing: "Fixture headline", in: app).waitForExistence(timeout: 10))
        go(to: "Search", in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("headline 9")
        XCTAssertTrue(element(containing: "loaded on this device during this session", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Fixture headline 9", in: app).waitForExistence(timeout: 5))
    }

    func testLocalDraftSurvivesRelaunchAndIsLabelledLocal() {
        var app = launch(reset: true)
        XCTAssertTrue(element(containing: "Fixture headline", in: app).waitForExistence(timeout: 10))
        openSettings(app)
        app.buttons["Open Newsroom"].tap()
        XCTAssertTrue(element(containing: "Local drafting only", in: app).waitForExistence(timeout: 5))
        app.buttons["New Draft"].firstMatch.tap()
        // A vertical-axis TextField is exposed as a text view.
        let headline = app.descendants(matching: .any).matching(identifier: "draftHeadline").firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        headline.tap()
        headline.typeText("UI test local draft")
        app.buttons["Save Locally"].tap()
        XCTAssertTrue(element(containing: "It is not submitted or published", in: app).exists)
        app.terminate()

        app = launch(reset: false)
        XCTAssertTrue(element(containing: "Fixture headline", in: app).waitForExistence(timeout: 10))
        openSettings(app)
        app.buttons["Open Newsroom"].tap()
        XCTAssertTrue(element(containing: "UI test local draft", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Local draft", in: app).exists)
    }

    func testLargestAccessibilityTextSizeStillReadable() {
        let app = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let lead = element(containing: "Fixture long headline", in: app)
        XCTAssertTrue(lead.waitForExistence(timeout: 10))
        lead.tap()
        XCTAssertTrue(element(containing: "Fixture disclosure.", in: app).waitForExistence(timeout: 5))
    }

    func testAccountExplainsUnavailableSignInAndTechnicalSettingsAreUnderAdvanced() {
        let app = launch()
        XCTAssertTrue(element(containing: "Fixture headline", in: app).waitForExistence(timeout: 10))
        openSettings(app)
        XCTAssertTrue(element(containing: "Sign-in isn't set up", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element(containing: "Content API", in: app).exists, "technical details live under Advanced")
        app.buttons["Advanced"].firstMatch.tap()
        XCTAssertTrue(element(containing: "On this device", in: app).waitForExistence(timeout: 5))
    }
}
