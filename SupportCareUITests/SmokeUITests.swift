import XCTest

/// Launches the app. Without Config.xcconfig it runs in demo mode, so this works in CI.
final class SmokeUITests: XCTestCase {
    func testLaunchShowsAuthOrHome() throws {
        let app = XCUIApplication()
        app.launch()
        let demo = app.buttons["Explore demo with sample data"]
        let signIn = app.buttons["Sign in"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10) || signIn.exists)
        if demo.exists {
            demo.tap()
            XCTAssertTrue(app.tabBars.buttons["Shifts"].waitForExistence(timeout: 10))
            app.tabBars.buttons["Shifts"].tap()
            app.tabBars.buttons["Invoices"].tap()
            app.tabBars.buttons["Profile"].tap()
        }
    }
}
