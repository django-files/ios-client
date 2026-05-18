//
//  Django_FilesUITests.swift
//  Django FilesUITests
//

import XCTest

final class Django_FilesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    // MARK: - Helpers

    private func launchApp(extras: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--DeleteAllData", "--DisableFirebase", "--MockNetwork"] + extras
        app.launch()
        return app
    }

    // MARK: - Tests

    /// Verifies that adding a new server navigates to the login screen showing
    /// the mock site name, without hitting a real network.
    @MainActor
    func testNewServer() throws {
        let app = launchApp()

        let textField = app.textFields["urlTextField"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()
        textField.typeText("localhost")

        let submitButton = app.buttons["serverSubmitButton"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
        submitButton.tap()

        // MockURLProtocol returns {"site_name": "Test Server"} for /api/auth/methods/.
        // LoginView displays that as Text(siteName).
        XCTAssertTrue(app.staticTexts["Test Server"].waitForExistence(timeout: 10))
    }

    /// Verifies that the file list displays mock files when launched with a
    /// pre-authenticated session and mock network responses.
    @MainActor
    func testFileListShowsFiles() throws {
        let app = launchApp(extras: ["--InjectTestSession"])

        // MockURLProtocol returns two files for /api/files/1/.
        // FileRowView renders each file's name as Text(file.name).
        XCTAssertTrue(app.staticTexts["photo.jpg"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["notes.txt"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        #if targetEnvironment(simulator)
        return
        #else
        if #available(iOS 26.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
        #endif
    }
}
