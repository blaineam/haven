import XCTest

/// Proves the hybrid post-quantum pipeline runs end-to-end **on the device**:
/// launches the app, taps the self-test, and asserts every check passes.
final class KithUITests: XCTestCase {
    func testOnDeviceHybridPQSelfTestPasses() {
        let app = XCUIApplication()
        app.launch()

        // The identity (and its QR) is generated on-device at launch.
        XCTAssertTrue(
            app.staticTexts["Your identity"].waitForExistence(timeout: 15),
            "identity screen should appear"
        )

        let runButton = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "self-test")
        ).firstMatch
        XCTAssertTrue(runButton.waitForExistence(timeout: 10), "self-test button should exist")
        runButton.tap()

        let passed = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "checks passed")
        ).firstMatch
        XCTAssertTrue(
            passed.waitForExistence(timeout: 10),
            "all on-device hybrid-PQ checks should pass"
        )
    }

    /// Posts to the social feed and confirms it appears — proving the hybrid-PQ
    /// social engine (seal → open → feed) runs end-to-end on-device.
    func testSocialFeedPostAppears() {
        let app = XCUIApplication()
        app.launchEnvironment["KITH_TAB"] = "feed"
        app.launch()

        // Seeded demo content from the engine should render.
        let seeded = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Our own little corner")
        ).firstMatch
        XCTAssertTrue(seeded.waitForExistence(timeout: 15), "seeded feed content should appear")

        // Compose a new post and confirm it round-trips through the engine into the feed.
        let field = app.textFields["composeField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("a sealed post from the UI test")
        app.buttons["composeSend"].tap()

        let posted = app.staticTexts["a sealed post from the UI test"]
        XCTAssertTrue(posted.waitForExistence(timeout: 5), "new post should appear in the feed")
    }
}
