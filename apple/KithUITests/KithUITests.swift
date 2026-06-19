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
}
