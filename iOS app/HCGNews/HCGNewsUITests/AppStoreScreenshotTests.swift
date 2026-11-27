import XCTest

/// Captures App Store screenshots from the real app and the live publication, limited to
/// articles cleared by editorial review (docs/EDITORIAL-REVIEW-2026-11-27.md).
///
/// Not part of the normal test run: it does nothing unless HCGNEWS_SCREENSHOT_ARTICLES is
/// set (comma-separated article ids) in the scheme's test environment. Run on the required
/// devices (e.g. iPhone 17 Pro Max and iPad Pro 13-inch), then export the attachments from
/// the test report. Nothing is uploaded anywhere.
final class AppStoreScreenshotTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private var articleIDs: String? {
        let value = ProcessInfo.processInfo.environment["HCGNEWS_SCREENSHOT_ARTICLES"]
        return (value?.isEmpty ?? true) ? nil : value
    }

    private func launch(edition: String, appearance: String, ids: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HCGNEWS_SCREENSHOT_ARTICLES"] = ids
        app.launchArguments += ["-edition", edition, "-appearance", appearance]
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func go(_ app: XCUIApplication, _ tab: String) {
        let button = app.tabBars.buttons[tab]
        if button.waitForExistence(timeout: 3) { button.tap() }
        else { app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", tab)).firstMatch.tap() }
    }

    func testCaptureScreenshots() throws {
        guard let ids = articleIDs else { throw XCTSkip("Set HCGNEWS_SCREENSHOT_ARTICLES to cleared article ids.") }
        for edition in ["future", "classic"] {
            for appearance in ["light", "dark"] {
                let app = launch(edition: edition, appearance: appearance, ids: ids)
                let tag = "\(edition)-\(appearance)"
                XCTAssertTrue(app.staticTexts["Latest"].waitForExistence(timeout: 20) || app.staticTexts["LATEST"].waitForExistence(timeout: 5))
                sleep(2) // let images load
                capture(app, "01-home-\(tag)")
                app.swipeUp()
                capture(app, "02-home-cards-\(tag)")
                app.swipeDown(); app.swipeDown()
                let card = app.descendants(matching: .any).matching(identifier: "article-card").firstMatch
                if card.waitForExistence(timeout: 5) {
                    card.tap()
                    sleep(2)
                    capture(app, "03-article-\(tag)")
                    app.navigationBars.buttons.firstMatch.tap()
                }
                go(app, "Sections"); sleep(1); capture(app, "04-sections-\(tag)")
                go(app, "Search"); sleep(1); capture(app, "05-search-\(tag)")
                go(app, "Saved"); sleep(1); capture(app, "06-saved-\(tag)")
                app.terminate()
            }
        }
    }
}
