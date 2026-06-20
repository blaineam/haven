import XCTest

/// On-device proof that the hybrid-PQ engine and social feed work, driven through
/// the real (human-friendly) UI. Onboarding is bypassed via an env flag.
final class KithUITests: XCTestCase {
    private func app(tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KITH_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["KITH_TAB"] = tab
        return app
    }

    /// You → Advanced → Run privacy check → all checks pass.
    func testPrivacyCheckPasses() {
        let app = app(tab: "you")
        app.launch()

        let advanced = app.buttons["Advanced"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 15), "Advanced should be reachable")
        advanced.tap()

        let check = app.buttons["privacyCheck"]
        XCTAssertTrue(check.waitForExistence(timeout: 10), "privacy check button should exist")
        check.tap()

        let passed = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "checks passed")
        ).firstMatch
        XCTAssertTrue(passed.waitForExistence(timeout: 10), "all on-device checks should pass")
    }

    /// Posting to the circle feed round-trips through the social engine into the UI.
    func testSocialFeedPostAppears() {
        let app = app(tab: "circle")
        app.launch()

        let seeded = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Golden hour")
        ).firstMatch
        XCTAssertTrue(seeded.waitForExistence(timeout: 15), "seeded feed content should appear")

        let field = app.textFields["composeField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("a sealed post from the UI test")
        app.buttons["composeSend"].tap()

        let posted = app.staticTexts["a sealed post from the UI test"]
        XCTAssertTrue(posted.waitForExistence(timeout: 5), "new post should appear in the feed")
    }

    /// You → Advanced → Networking → Go online: the real iroh node binds and produces
    /// a ticket, proving the async networking FFI runs end-to-end on-device.
    func testNetworkingNodeGoesOnline() {
        let app = app(tab: "you")
        app.launch()

        let advanced = app.buttons["Advanced"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 15))
        advanced.tap()

        let net = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "Networking")
        ).firstMatch
        XCTAssertTrue(net.waitForExistence(timeout: 10), "Networking entry should be reachable")
        net.tap()

        let goOnline = app.buttons["Go online"]
        XCTAssertTrue(goOnline.waitForExistence(timeout: 10))
        goOnline.tap()

        let online = app.staticTexts["Online"]
        XCTAssertTrue(online.waitForExistence(timeout: 25), "node should come online and produce a ticket")
    }
}
