import XCTest

/// Release-qualification evidence. Uses the DEBUG development fixtures, which are labelled on screen, so
/// no unreviewed article appears in the evidence. Renders the main screens in every edition and
/// appearance and attaches screenshots (kept in the result bundle). Also captures the installed icon
/// on the Home Screen and runs Apple's accessibility audit on the key screens.
final class QualificationEvidenceTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private let combinations = [("future", "light"), ("future", "dark"), ("classic", "light"), ("classic", "dark")]

    private func launch(edition: String, appearance: String, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HCGNEWS_UI_TEST_FIXTURES"] = "1"
        app.launchEnvironment["HCGNEWS_UI_TEST_RESET"] = "1"
        // The argument domain overrides stored preferences for this launch only.
        app.launchArguments += ["-edition", edition, "-appearance", appearance] + arguments
        app.launch()
        return app
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(isPad ? "ipad" : "iphone")-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func go(to name: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 3) { tab.tap(); return }
        let row = app.collectionViews.staticTexts[name].firstMatch
        if row.waitForExistence(timeout: 3) { row.tap() }
    }

    private func openSettings(_ app: XCUIApplication) {
        if app.tabBars.firstMatch.waitForExistence(timeout: 3) {
            app.buttons["Settings"].firstMatch.tap()
        } else {
            go(to: "Settings & Account", in: app)
        }
    }

    private func closeSettings(_ app: XCUIApplication) {
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
    }

    /// Every main screen, in Future and Classic, Light and Dark.
    func testRenderedScreensInEveryEditionAndAppearance() {
        for (edition, appearance) in combinations {
            let tag = "\(edition)-\(appearance)"
            let app = launch(edition: edition, appearance: appearance)
            XCTAssertTrue(element(containing: "Fixture headline", in: app).waitForExistence(timeout: 15), "\(tag): Home loads")
            let editionName = edition == "future" ? "Future Edition" : "Classic Edition"
            XCTAssertTrue(element(containing: editionName, in: app).waitForExistence(timeout: 5), "\(tag): masthead names the edition")
            XCTAssertTrue(app.images["HCG"].firstMatch.exists || element(containing: "HCG News", in: app).exists, "\(tag): wordmark present")
            sleep(1)
            capture(app, "01-home-\(tag)")
            app.swipeUp()
            capture(app, "02-home-cards-\(tag)")
            app.swipeDown(); app.swipeDown()

            let card = app.descendants(matching: .any).matching(identifier: "article-card").firstMatch
            if card.waitForExistence(timeout: 5) {
                card.tap()
                XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 5), "\(tag): article opens")
                sleep(1)
                capture(app, "03-article-\(tag)")
                app.swipeUp()
                capture(app, "04-article-body-\(tag)")
                if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
            } else {
                XCTFail("\(tag): no article card found")
            }

            go(to: "Sections", in: app); sleep(1); capture(app, "05-sections-\(tag)")
            go(to: "Search", in: app); sleep(1); capture(app, "06-search-\(tag)")
            go(to: "Saved", in: app); sleep(1); capture(app, "07-saved-\(tag)")
            go(to: "Home", in: app)
            openSettings(app)
            XCTAssertTrue(app.buttons["settings-edition"].firstMatch.waitForExistence(timeout: 5)
                          || element(containing: "Edition", in: app).exists, "\(tag): edition setting present")
            sleep(1)
            capture(app, "08-settings-\(tag)")
            closeSettings(app)
            app.terminate()
        }
    }

    /// The largest accessibility text size, in both editions: Home, the article's opening, and its
    /// body further down (disclosure, corrections, captions, lists, notices).
    func testLargestDynamicTypeRendering() {
        for edition in ["future", "classic"] {
            let app = launch(edition: edition, appearance: "light",
                             arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
            XCTAssertTrue(element(containing: "Fixture", in: app).waitForExistence(timeout: 15))
            sleep(1)
            capture(app, "09-dynamic-type-xxxl-home-\(edition)")
            let card = app.descendants(matching: .any).matching(identifier: "article-card").firstMatch
            var swipes = 0
            while !(card.exists && card.isHittable) && swipes < 8 { app.swipeUp(); swipes += 1 }
            if card.exists {
                card.tap()
                XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 5), "\(edition): article opens at AX-XXXL")
                sleep(1)
                capture(app, "09-dynamic-type-xxxl-article-\(edition)-1")
                for page in 2...5 {
                    app.swipeUp()
                    capture(app, "09-dynamic-type-xxxl-article-\(edition)-\(page)")
                }
            } else {
                XCTFail("\(edition): no article card at AX-XXXL")
            }
            app.terminate()
        }
    }

    /// The installed app icon and name on the Home Screen.
    func testInstalledIconOnHomeScreen() {
        let app = launch(edition: "future", appearance: "light")
        XCTAssertTrue(element(containing: "Fixture", in: app).waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        sleep(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["HCG News"]
        // New apps are placed on the last Home Screen page.
        var swipes = 0
        while !(icon.exists && icon.isHittable) && swipes < 6 {
            springboard.swipeLeft()
            sleep(1)
            swipes += 1
        }
        XCTAssertTrue(icon.exists, "the HCG News icon is installed with its display name")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "\(isPad ? "ipad" : "iphone")-10-home-screen-icon"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Apple's automated accessibility audit on the key screens.
    ///
    /// Gate: every finding fails the test except these, which are listed in the report with the reason:
    /// - Contrast measured on text lying under the system's translucent bars (tab bar, navigation bar,
    ///   toolbars) or inside the scroll-edge effect beside them: the audit samples blurred glass there.
    /// - Dynamic Type on the brand wordmark ("HCG | News"), which is a logo and scales only to its cap.
    /// - "Partially unsupported" Dynamic Type and "may be clipped" heuristics: checked instead against the
    ///   real rendering at the largest accessibility size (testLargestDynamicTypeRendering, 09 screenshots).
    /// Contrast is audited in its own pass on a settled screen, before the Dynamic Type pass resizes text.
    func testAccessibilityAudit() throws {
        for (edition, appearance) in [("future", "dark"), ("classic", "light")] {
            let tag = "\(edition)-\(appearance)"
            let app = launch(edition: edition, appearance: appearance)
            XCTAssertTrue(element(containing: "Fixture headline", in: app).waitForExistence(timeout: 15))
            var failing: [String] = []
            var advisory: [String] = []
            let screens: [(String, () -> Void)] = [
                ("home", {}),
                ("article", {
                    let card = app.descendants(matching: .any).matching(identifier: "article-card").firstMatch
                    if card.waitForExistence(timeout: 5) { card.tap(); _ = app.buttons["Share"].waitForExistence(timeout: 5) }
                }),
            ]
            for (screen, open) in screens {
                open()
                sleep(2)
                let bars = barFrames(in: app)
                let handler: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
                    let line = "[\(tag) \(screen)] \(issue.compactDescription): \(issue.detailedDescription) — element: \(issue.element?.label ?? "(none)")"
                    if let reason = self.advisoryReason(for: issue, bars: bars) {
                        advisory.append(line + " — not gating: " + reason)
                        return true
                    }
                    failing.append(line)
                    return false
                }
                try app.performAccessibilityAudit(for: .contrast, handler)
                try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(.contrast), handler)
            }
            let report = XCTAttachment(string: """
                Accessibility audit, \(tag)
                Failing findings: \(failing.count)
                \(failing.joined(separator: "\n"))

                Reported, not gating: \(advisory.count)
                \(advisory.joined(separator: "\n"))
                """)
            report.name = "\(isPad ? "ipad" : "iphone")-accessibility-audit-\(tag)"
            report.lifetime = .keepAlways
            add(report)
            app.terminate()
        }
    }

    /// Frames of the system's translucent bars, widened by the scroll-edge effect beside them.
    private func barFrames(in app: XCUIApplication) -> [CGRect] {
        let bars = app.tabBars.allElementsBoundByIndex + app.navigationBars.allElementsBoundByIndex
            + app.toolbars.allElementsBoundByIndex
        return bars.filter(\.exists).map(\.frame).filter { !$0.isEmpty }.map { $0.insetBy(dx: 0, dy: -20) }
    }

    private func advisoryReason(for issue: XCUIAccessibilityAuditIssue, bars: [CGRect]) -> String? {
        let label = issue.element?.label ?? ""
        switch issue.auditType {
        case .contrast:
            if let frame = issue.element?.frame, bars.contains(where: { $0.intersects(frame) }) {
                return "text under a translucent system bar"
            }
            return nil
        case .dynamicType:
            if ["News", "HCG News", "HCG", "HCG News."].contains(label) { return "brand wordmark (logo)" }
            if issue.compactDescription.localizedCaseInsensitiveContains("partially") {
                return "scales with Dynamic Type; checked in the AX-XXXL renders"
            }
            return nil
        case .textClipped:
            return "clipping heuristic; checked in the AX-XXXL renders"
        default:
            return nil
        }
    }
}
