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

    private let baseLaunchArguments = [
        "--DeleteAllData",
        "--DisableFirebase",
        "--ObfuscateForScreenshots",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 01: File List (list mode)

    @MainActor
    func testFileListListMode() throws {
        guard hasCredentials else {
            throw XCTSkip("SCREENSHOT_SERVER_URL / USERNAME / PASSWORD not set")
        }
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = baseLaunchArguments
        app.launch()

        login(app: app)

        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 30))
        snapshot("01_FileList_List")
    }

    // MARK: - 02: File List (gallery mode) with view-options dropdown

    @MainActor
    func testFileListGalleryMode() throws {
        guard hasCredentials else {
            throw XCTSkip("SCREENSHOT_SERVER_URL / USERNAME / PASSWORD not set")
        }
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = baseLaunchArguments + ["--FileListGridView"]
        app.launch()

        login(app: app)

        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 30))
        // Let the grid populate so it's visible behind the open menu.
        _ = app.cells.firstMatch.waitForExistence(timeout: 20)

        let optionsButton = app.buttons["fileListViewOptionsMenu"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: 10))
        optionsButton.tap()
        // The Filters section header confirms the menu is fully expanded.
        _ = app.staticTexts["Filters"].waitForExistence(timeout: 5)
        snapshot("02_FileList_Gallery_Options")
    }

    // MARK: - 03: File List (map mode)

    @MainActor
    func testFileListMapMode() throws {
        guard hasCredentials else {
            throw XCTSkip("SCREENSHOT_SERVER_URL / USERNAME / PASSWORD not set")
        }
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = baseLaunchArguments + ["--FileListMapView"]
        app.launch()

        login(app: app)

        // FileListView sets navigationTitle to "" when showingMap is true, so
        // the usual navigationBars["Files"] check would time out. Wait on the
        // MKMapView (exposed as XCUIElementTypeMap) instead.
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 30))

        // FileMapView shows a large ProgressView overlay while it fetches the
        // GPS-tagged file list. Give the spinner up to 5s to appear (loading
        // in flight), then wait up to 30s for it to disappear (data + cluster
        // annotations ready). If it never appears, the second wait returns
        // immediately — covers the fast / cached path.
        let loadingSpinner = app.activityIndicators.firstMatch
        _ = loadingSpinner.waitForExistence(timeout: 5)
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: loadingSpinner, handler: nil)
        waitForExpectations(timeout: 30)

        // MapKit fetches tiles asynchronously and exposes no accessibility
        // signal for tile completion. A short fixed wait lets tiles + cluster
        // annotations finish rendering before we snap.
        Thread.sleep(forTimeInterval: 4)
        snapshot("03_FileList_Map")
    }

    // MARK: - 04: Albums list

    @MainActor
    func testAlbumsPage() throws {
        guard hasCredentials else {
            throw XCTSkip("SCREENSHOT_SERVER_URL / USERNAME / PASSWORD not set")
        }
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = baseLaunchArguments
        app.launch()

        login(app: app)

        selectTab("Albums", app: app)

        XCTAssertTrue(app.navigationBars["Albums"].waitForExistence(timeout: 15))
        // Wait for at least one cell to load before snapping
        _ = app.cells.firstMatch.waitForExistence(timeout: 20)
        snapshot("04_Albums")
    }

    // MARK: - 05: Album "My Trip" in 3-column grid

    @MainActor
    func testAlbumMyTrip3ColumnGrid() throws {
        guard hasCredentials else {
            throw XCTSkip("SCREENSHOT_SERVER_URL / USERNAME / PASSWORD not set")
        }
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = baseLaunchArguments + ["--FileListGridColumns=3"]
        app.launch()

        login(app: app)

        selectTab("Albums", app: app)

        XCTAssertTrue(app.navigationBars["Albums"].waitForExistence(timeout: 15))

        let myTrip = app.staticTexts["My Trip"]
        XCTAssertTrue(myTrip.waitForExistence(timeout: 20), "Album 'My Trip' not found on Albums tab")
        myTrip.tap()

        // Wait for the album's file grid to load
        XCTAssertTrue(app.navigationBars["My Trip"].waitForExistence(timeout: 15))
        _ = app.cells.firstMatch.waitForExistence(timeout: 20)
        snapshot("05_Album_MyTrip_3Column")
    }

    // MARK: - 06: Shorts list

    @MainActor
    func testShortsPage() throws {
        guard hasCredentials else {
            throw XCTSkip("SCREENSHOT_SERVER_URL / USERNAME / PASSWORD not set")
        }
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = baseLaunchArguments
        app.launch()

        login(app: app)

        selectTab("Shorts", app: app)

        XCTAssertTrue(app.navigationBars["Short URLs"].waitForExistence(timeout: 15))
        _ = app.cells.firstMatch.waitForExistence(timeout: 20)
        snapshot("06_Shorts")
    }

    // MARK: - 07: File Preview

    @MainActor
    func testFilePreview() throws {
        guard hasCredentials else {
            throw XCTSkip("SCREENSHOT_SERVER_URL / USERNAME / PASSWORD not set")
        }
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = baseLaunchArguments
        app.launch()

        login(app: app)

        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 30))
        let firstCell = app.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10))
        firstCell.tap()
        // Share button is always visible in the preview toolbar overlay
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 15))
        snapshot("07_FilePreview")
    }

    // MARK: - 08: File Preview with context menu open

    @MainActor
    func testFilePreviewContextMenu() throws {
        guard hasCredentials else {
            throw XCTSkip("SCREENSHOT_SERVER_URL / USERNAME / PASSWORD not set")
        }
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = baseLaunchArguments
        app.launch()

        login(app: app)

        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 30))
        let firstCell = app.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10))
        firstCell.tap()

        let moreButton = app.buttons["filePreviewMoreMenu"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 15))
        moreButton.tap()
        // Menu items are siblings of the trigger button — wait for any common
        // action to confirm the menu has opened before snapping.
        _ = app.buttons["Copy Share Link"].waitForExistence(timeout: 5)
        snapshot("08_FilePreview_ContextMenu")
    }

    // MARK: - 09: Settings

    @MainActor
    func testSettingsScreen() throws {
        guard hasCredentials else {
            throw XCTSkip("SCREENSHOT_SERVER_URL / USERNAME / PASSWORD not set")
        }
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments = baseLaunchArguments
        app.launch()

        login(app: app)

        selectTab("Settings", app: app)
        snapshot("09_Settings")
    }

    // MARK: - Helpers

    /// Activates the named tab. On iPhone the SwiftUI TabView surfaces tabs
    /// inside an XCUIElementTypeTabBar; on iPad (iOS 18+/26) the same TabView
    /// renders as a top floating tab bar / sidebar where the tab is not
    /// nested in a tabBar element. Try both, with the tab bar path first.
    private func selectTab(_ name: String, app: XCUIApplication) {
        let tabBarButton = app.tabBars.buttons[name]
        if tabBarButton.waitForExistence(timeout: 5) {
            tabBarButton.tap()
            return
        }

        // Fallback for iPad: the tab is a regular button somewhere in the
        // view hierarchy (top tab bar, sidebar, or overflow menu). Multiple
        // matches can exist (Label content vs the tab role) — firstMatch
        // picks whichever is hit-testable first.
        let button = app.buttons[name].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Tab '\(name)' not found in any tab-bar or button container")
        button.tap()
    }

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
        _ = usernameField.waitForExistence(timeout: 30)
        usernameField.tap()
        usernameField.typeText(screenshotUsername)
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText(screenshotPassword)
        app.buttons["Login"].tap()

        // Wait for any navigation bar to appear — auth succeeded once we're
        // out of the login sheet and into the main TabView. We can't wait on
        // navigationBars["Files"] specifically because the Files screen has
        // no title in map mode (--FileListMapView).
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 60)
    }
}
