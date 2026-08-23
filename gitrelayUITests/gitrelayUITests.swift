import AppKit
import XCTest

final class gitrelayUITests: XCTestCase {
    private var baseURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-ui-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let baseURL {
            try? FileManager.default.removeItem(at: baseURL)
        }
    }

    @MainActor
    func testEmptyWorkspaceOpensUnifiedAddMirror() throws {
        let app = launch(fixture: "empty")

        XCTAssertTrue(element("smart-view.all-mirrors", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("mirror-list.add", in: app).exists)

        element("mirror-list.add", in: app).click()
        XCTAssertTrue(element("add-mirror.source-selection", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose a Connected Service"].exists)

        element("add-mirror.source-mode.gitURL", in: app).click()
        XCTAssertTrue(element("add-mirror.mirror-path", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("add-mirror.primary-action", in: app).exists)

        let addWindow = app.windows["Add Mirror"]
        XCTAssertGreaterThanOrEqual(addWindow.frame.height, 750)
        XCTAssertEqual(addWindow.scrollBars.count, 0)
    }

    @MainActor
    func testConnectedServiceAddUsesNativeWindowClose() throws {
        let app = launch(fixture: "empty")

        let addButton = element("mirror-list.add", in: app)
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.click()

        let addWindow = app.windows["Add Mirror"]
        XCTAssertTrue(addWindow.waitForExistence(timeout: 3))
        XCTAssertFalse(
            addWindow.descendants(matching: .any)["add-mirror.cancel"].exists
        )

        let closeButton = addWindow.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.exists)
        closeButton.click()

        XCTAssertFalse(
            element("add-mirror.source-selection", in: app).waitForExistence(timeout: 1)
        )
    }

    @MainActor
    func testAttentionMirrorRoutesToRepairAction() throws {
        let app = launch(fixture: "attention")
        let row = element("mirror-row.11111111-1111-1111-1111-111111111111", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        let primary = element("mirror-detail.primary-action", in: app)
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        XCTAssertEqual(primary.label, "Retry")
        XCTAssertTrue(app.staticTexts["The destination could not be reached."].exists)
    }

    @MainActor
    func testSettingsUsesSixNativeCategories() throws {
        let app = launch(fixture: "empty")
        openSettings(in: app)

        XCTAssertTrue(element("settings-pane.general", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("settings-pane.connections", in: app).exists)
        XCTAssertTrue(element("settings-pane.defaultPolicies", in: app).exists)
        XCTAssertTrue(element("settings-pane.notifications", in: app).exists)
        XCTAssertTrue(element("settings-pane.integrations", in: app).exists)
        XCTAssertTrue(element("settings-pane.storageMaintenance", in: app).exists)
    }

    @MainActor
    func testGeneralSettingsStayCompactAndUncluttered() throws {
        let app = launch(fixture: "empty")
        openSettings(in: app)

        let generalPane = element("settings-pane.general", in: app)
        XCTAssertTrue(generalPane.waitForExistence(timeout: 5))

        let languageLabels = app.staticTexts.matching(NSPredicate(format: "label == %@", "Language"))
        XCTAssertEqual(languageLabels.count, 1)
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label == %@",
                    "When enabled, closing the main window leaves GitRelay in the menu bar (Dock icon may hide). Turn off to quit when the last window closes."
                )
            ).firstMatch.exists
        )
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label == %@",
                    "When enabled, viewing tokens in plaintext, deleting mirrors, and changing a mirror target to a different host require authentication. Canceling or failing authentication aborts the action."
                )
            ).firstMatch.exists
        )
    }

    @MainActor
    func testSettingsSidebarToggleAlignsWithNativeColumn() throws {
        let app = launch(fixture: "empty")
        openSettings(in: app)

        let generalRow = element("settings-pane.general", in: app)
        XCTAssertTrue(generalRow.waitForExistence(timeout: 5))
        let settingsSidebar = element("settings.sidebar", in: app)
        XCTAssertTrue(settingsSidebar.exists)

        let settingsWindow = app.windows
            .containing(.any, identifier: "settings-pane.general")
            .firstMatch
        XCTAssertTrue(settingsWindow.exists)

        let sidebarToggle = settingsWindow.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "sidebar")
        ).firstMatch
        XCTAssertTrue(sidebarToggle.exists)

        let sidebarTrailingEdge = settingsSidebar.frame.maxX - settingsWindow.frame.minX
        XCTAssertLessThanOrEqual(
            sidebarTrailingEdge,
            225,
            "The Settings sidebar must keep the compact KeyChord-style native column width."
        )

        let toggleTrailingOffset = abs(settingsSidebar.frame.maxX - sidebarToggle.frame.maxX)
        XCTAssertLessThan(
            toggleTrailingOffset,
            24,
            "The system sidebar toggle must stay aligned with the trailing edge of the Settings sidebar."
        )

        let overflow = settingsWindow.popUpButtons.matching(
            NSPredicate(format: "label ==[c] %@", "more toolbar items")
        ).firstMatch
        XCTAssertFalse(
            overflow.exists,
            "Settings must not register toolbar actions beside the system sidebar control."
        )

        sidebarToggle.click()
        XCTAssertFalse(
            overflow.waitForExistence(timeout: 0.5),
            "Collapsing Settings must not leave AppKit's toolbar overflow chevron visible."
        )
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        app.activate()

        let appMenu = app.menuBars.menuBarItems["GitRelay"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 3))
        appMenu.click()

        let settingsItem = app.menuItems["Settings…"]
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 3))
        settingsItem.click()
    }

    @MainActor
    func testAboutShowsProjectLicenseAndUpdateInformation() throws {
        let app = launch(fixture: "empty")
        app.activate()

        let appMenu = app.menuBars.menuBarItems["GitRelay"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 3))
        appMenu.click()

        let aboutItem = appMenu.descendants(matching: .menuItem)["About GitRelay"]
        XCTAssertTrue(aboutItem.waitForExistence(timeout: 3))
        aboutItem.click()

        let aboutWindow = app.windows["About GitRelay"]
        XCTAssertTrue(aboutWindow.waitForExistence(timeout: 3))
        XCTAssertTrue(element("about.license", in: app).exists)
        XCTAssertTrue(element("about.github", in: app).exists)
        XCTAssertTrue(element("about.check-for-updates", in: app).exists)
    }

    @MainActor
    func testMinimumWindowKeepsPrimaryWorkspaceUsable() throws {
        let app = launch(fixture: "attention", width: 860, height: 600)

        XCTAssertTrue(element("mirror-list.add", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(
            element("mirror-row.11111111-1111-1111-1111-111111111111", in: app).exists
        )
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.width, 850)
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.height, 590)
    }

    @MainActor
    func testTwoHundredMirrorSearchRemainsResponsive() throws {
        let app = launch(fixture: "many")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("199")

        XCTAssertTrue(
            element("mirror-row.00000000-0000-0000-0000-000000000200", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(
            element("mirror-row.00000000-0000-0000-0000-000000000001", in: app).exists
        )
    }

    @MainActor
    func testConnectedServiceBatchCreatesOneMirrorPerSource() throws {
        let app = launch(fixture: "batch")

        XCTAssertTrue(element("mirror-list.add", in: app).waitForExistence(timeout: 5))
        element("mirror-list.add", in: app).click()
        let selectAll = element("add-mirror.connected.select-all", in: app)
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        selectAll.click()
        element("add-mirror.connected.next", in: app).click()

        let targetTemplate = element("add-mirror.connected.target-template", in: app)
        XCTAssertTrue(targetTemplate.waitForExistence(timeout: 5))
        XCTAssertEqual(
            targetTemplate.value as? String,
            "git@gitlab.com:backup/{name}.git"
        )
        let submit = element("add-mirror.connected.submit", in: app)
        XCTAssertTrue(submit.isEnabled)
        submit.click()

        XCTAssertTrue(
            element("add-mirror.connected.result-summary", in: app).waitForExistence(timeout: 5)
        )
        element("add-mirror.connected.finish", in: app).click()
        let allMirrors = element("smart-view.all-mirrors", in: app)
        expectation(
            for: NSPredicate(format: "value CONTAINS %@", "2"),
            evaluatedWith: allMirrors
        )
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testMirrorDeepLinkLeavesAttentionScopeAndSelectsIdentity() throws {
        let app = launch(fixture: "deep-link")
        XCTAssertTrue(
            element("mirror-row.11111111-1111-1111-1111-111111111111", in: app)
                .waitForExistence(timeout: 5)
        )

        let url = URL(string: "gitrelay://repo/33333333-3333-3333-3333-333333333333")!
        XCTAssertTrue(NSWorkspace.shared.open(url))

        let detailTitle = element("mirror-detail.title", in: app)
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(detailTitle.value as? String, "Healthy Destination")
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(
            element("mirror-row.33333333-3333-3333-3333-333333333333", in: app).exists
        )
        XCTAssertTrue(
            element("mirror-row.11111111-1111-1111-1111-111111111111", in: app).exists
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            launch(fixture: "many").terminate()
        }
    }

    @MainActor
    private func launch(
        fixture: String,
        width: Int? = nil,
        height: Int? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["GITRELAY_UI_TEST_MODE"] = "1"
        app.launchEnvironment["GITRELAY_UI_TEST_BASE"] = baseURL.path
        app.launchEnvironment["GITRELAY_UI_TEST_RESET_DEFAULTS"] = "1"
        app.launchEnvironment["GITRELAY_UI_TEST_FIXTURE"] = fixture
        if let width, let height {
            app.launchEnvironment["GITRELAY_UI_TEST_WINDOW_WIDTH"] = String(width)
            app.launchEnvironment["GITRELAY_UI_TEST_WINDOW_HEIGHT"] = String(height)
        }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
