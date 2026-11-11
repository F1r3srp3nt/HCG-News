import XCTest

/// UI tests. Most run against the DEBUG fixture service (HCGNEWS_UI_TEST_FIXTURES=1),
/// which shows a "TEST FIXTURES — not live reporting" banner. One test launches the
/// real, unconfigured app and checks that it shows no content and the honest
/// "not connected" state.
///
/// Run on both an iPhone and an iPad simulator (see docs/BUILD-AND-TEST.md).
final class HCGNewsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(fixtures: Bool = true, reset: Bool = true, extra: [String: String] = [:],
                        arguments: [String] = []) -> XCUIApplication {
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

    /// Selects a top-level destination on either layout (tab bar or iPad sidebar).
    private func go(to name: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 2) {
            tab.tap()
            return
        }
        let sidebarItem = app.collectionViews.staticTexts[name].firstMatch
        if !sidebarItem.exists {
            // Sidebar may be collapsed in portrait.
            let toggle = app.navigationBars.buttons["Show Sidebar"]
            if toggle.exists { toggle.tap() }
        }
        XCTAssertTrue(sidebarItem.waitForExistence(timeout: 5), "No navigation item named \(name)")
        sidebarItem.tap()
    }

    private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    // MARK: Real configuration (none installed)

    func testUnconfiguredBuildShowsNotConnectedAndNoArticles() {
        let app = launch(fixtures: false)
        XCTAssertTrue(app.staticTexts["Live publication not connected"].waitForExistence(timeout: 10))
        XCTAssertFalse(element(containing: "Fixture", in: app).exists)
        XCTAssertTrue(app.links["Read HCG News on the web"].exists || app.buttons["Read HCG News on the web"].exists)
    }

    // MARK: Fixture-driven

    func testFixtureBannerAndNavigationDestinationsExist() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["TEST FIXTURES — not live reporting"].waitForExistence(timeout: 10))
        for name in ["Sections", "Search", "Saved", "Home"] {
            go(to: name, in: app)
        }
    }

    func testBreakingHeadlineNavigation() {
        let app = launch()
        let first = element(containing: "Breaking: Fixture headline 2", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let next = app.buttons["Next breaking headline"]
        XCTAssertTrue(next.exists)
        next.tap()
        XCTAssertTrue(element(containing: "Breaking: Fixture breaking headline two", in: app).waitForExistence(timeout: 3))
        app.buttons["Previous breaking headline"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 3))
    }

    func testArticleShowsDisclosureSourcesAndEmbedNotice() {
        let app = launch()
        let lead = element(containing: "Fixture long headline", in: app)
        XCTAssertTrue(lead.waitForExistence(timeout: 10))
        lead.tap()
        XCTAssertTrue(element(containing: "Fixture disclosure.", in: app).waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(element(containing: "Embedded content not shown", in: app).waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(element(containing: "Fixture source document", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share"].exists)
    }

    func testBookmarkPersistsAfterRelaunch() {
        var app = launch(reset: true)
        let row = element(containing: "Fixture headline 5", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.buttons["Remove from Saved"].waitForExistence(timeout: 3))
        app.terminate()

        app = launch(reset: false)
        go(to: "Saved", in: app)
        XCTAssertTrue(element(containing: "Fixture headline 5", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Article text isn't downloaded", in: app).exists)
    }

    func testRestrictedArticleExplainsSignIn() {
        let app = launch()
        let restricted = element(containing: "Fixture headline 7", in: app)
        XCTAssertTrue(restricted.waitForExistence(timeout: 10))
        restricted.tap()
        XCTAssertTrue(app.staticTexts["Sign-in required"].waitForExistence(timeout: 5))
    }

    func testOfflineShowsOfflineState() {
        let app = launch(extra: ["HCGNEWS_UI_TEST_OFFLINE": "1"])
        XCTAssertTrue(app.staticTexts["You're offline"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Try Again"].exists)
    }

    func testEmptyHomeAndEmptySection() {
        let app = launch(extra: ["HCGNEWS_UI_TEST_EMPTY": "1"])
        XCTAssertTrue(app.staticTexts["No articles yet"].waitForExistence(timeout: 10))
        go(to: "Sections", in: app)
        let empty = element(containing: "Empty Section (fixture)", in: app)
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        empty.tap()
        XCTAssertTrue(element(containing: "Nothing in Empty Section (fixture) yet", in: app).waitForExistence(timeout: 5))
    }

    func testSearchIsLabelledAsLoadedArticlesOnly() {
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

    func testLargestAccessibilityTextSizeStillReadable() {
        let app = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(element(containing: "Fixture long headline", in: app).waitForExistence(timeout: 10))
        element(containing: "Fixture long headline", in: app).tap()
        XCTAssertTrue(element(containing: "Fixture disclosure.", in: app).waitForExistence(timeout: 5))
    }

    func testSettingsShowsHonestAccountState() {
        let app = launch()
        if app.tabBars.firstMatch.waitForExistence(timeout: 5) {
            app.buttons["Settings"].firstMatch.tap()
        } else {
            go(to: "Settings", in: app)
        }
        XCTAssertTrue(element(containing: "isn't set up for HCG News yet", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "Development build. Not released.", in: app).exists)
    }
}
