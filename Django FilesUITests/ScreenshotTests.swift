//
//  ScreenshotTests.swift
//  Django FilesUITests
//

import XCTest

final class ScreenshotTests: XCTestCase {

    private var serverURL: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_SERVER_URL"] ?? ""
    }
    private var screenshotUsername: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_USERNAME"] ?? ""
    }
    private var screenshotPassword: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_PASSWORD"] ?? ""
    }
    private var hasCredentials: Bool {
        !serverURL.isEmpty && !screenshotUsername.isEmpty && !screenshotPassword.isEmpty
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 01: Setup / Onboarding

    /// Captures the welcome screen shown on first launch (no sessions configured).
    @MainActor
    func testSetupScreen() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = ["--DeleteAllData", "--DisableFirebase"]
        app.launch()
        XCTAssertTrue(app.textFields["urlTextField"].waitForExistence(timeout: 10))
        snapshot("01_Setup")
    }

    // MARK: - 02: Login

    /// Captures the login form after a server URL is submitted (mock network).
    @MainActor
    func testLoginScreen() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = ["--DeleteAllData", "--DisableFirebase", "--MockNetwork"]
        app.launch()

        let urlField = app.textFields["urlTextField"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 10))
        urlField.tap()
        // The field pre-populates with "https://" on focus; type only the host so the
        // result is "https://localhost" — a valid URL the mock can respond to.
        urlField.typeText("localhost")
        app.buttons["serverSubmitButton"].tap()

        XCTAssertTrue(app.textFields["Username"].waitForExistence(timeout: 10))
        snapshot("02_Login")
    }

    // MARK: - 03: File List (list mode)

    @MainActor
    func testFileListListMode() throws {
        guard hasCredentials else {
            throw XCTSkip("SCREENSHOT_SERVER_URL / USERNAME / PASSWORD not set")
        }
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = ["--DeleteAllData", "--DisableFirebase"]
        app.launch()

        login(app: app)

        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 30))
        snapshot("03_FileList_List")
    }

    // MARK: - 04: File List (gallery mode)

    @MainActor
    func testFileListGalleryMode() throws {
        guard hasCredentials else {
            throw XCTSkip("SCREENSHOT_SERVER_URL / USERNAME / PASSWORD not set")
        }
        let app = XCUIApplication()
        setupSnapshot(app)
        // --FileListGridView sets fileListIsGridView=true in UserDefaults (after --DeleteAllData clears it)
        app.launchArguments = ["--DeleteAllData", "--DisableFirebase", "--FileListGridView"]
        app.launch()

        login(app: app)

        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 30))
        snapshot("04_FileList_Gallery")
    }

    // MARK: - 05: Settings

    @MainActor
    func testSettingsScreen() throws {
        guard hasCredentials else {
            throw XCTSkip("SCREENSHOT_SERVER_URL / USERNAME / PASSWORD not set")
        }
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = ["--DeleteAllData", "--DisableFirebase"]
        app.launch()

        login(app: app)

        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 15))
        settingsTab.tap()
        snapshot("05_Settings")
    }

    // MARK: - Helpers

    private func login(app: XCUIApplication) {
        let urlField = app.textFields["urlTextField"]
        _ = urlField.waitForExistence(timeout: 10)
        urlField.tap()
        // The field pre-populates with "https://" on focus.  Strip the scheme from
        // the env URL so we type only the host+path and avoid "https://https://…".
        let hostAndPath = serverURL.replacingOccurrences(
            of: "^https?://", with: "", options: .regularExpression)
        urlField.typeText(hostAndPath)
        app.buttons["serverSubmitButton"].tap()

        let usernameField = app.textFields["Username"]
        _ = usernameField.waitForExistence(timeout: 20)
        usernameField.tap()
        usernameField.typeText(screenshotUsername)
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText(screenshotPassword)
        app.buttons["Login"].tap()
    }
}
