import XCTest

final class CopySouLUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let hasOnboarding = app.staticTexts["Set up CopySouL"].exists
        let hasMainWindow = app.staticTexts["CopySouL"].exists
        XCTAssertTrue(hasOnboarding || hasMainWindow)
    }
}
