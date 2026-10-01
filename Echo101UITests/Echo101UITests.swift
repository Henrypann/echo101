import XCTest

@MainActor
final class Echo101UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func app(run: String = UUID().uuidString, parent: Bool = false, pending: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--test-run-id", run]
        if parent { app.launchArguments.append("--test-parent") }
        if pending { app.launchArguments.append("--seed-pending") }
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testGrandparentPageIsOneScreenWithoutTabs() throws {
        let app = app()
        app.launch()
        let record = app.buttons["recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 15))
        XCTAssertTrue(record.label.contains("按一下，说中文"))
        XCTAssertTrue(app.descendants(matching: .any)["parentEntry"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertFalse(app.buttons["addMoment"].exists)
        XCTAssertFalse(app.tabBars.buttons["Today"].exists)
        XCTAssertFalse(app.tabBars.buttons["Settings"].exists)
        screenshot("Grandparent-waiting", app)
        app.terminate()
    }

    func testLongPressOpensParentAndLeaveReturns() throws {
        let app = app()
        app.launch()
        let entry = app.descendants(matching: .any)["parentEntry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        XCTAssertTrue(entry.isHittable)
        entry.press(forDuration: 4)
        XCTAssertTrue(app.descendants(matching: .any)["parentTitle"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.tabBars.count, 0)
        screenshot("Parent-after-long-press", app)
        app.descendants(matching: .any)["leaveParent"].tap()
        XCTAssertTrue(app.buttons["recordButton"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["parentTitle"].exists)
        app.terminate()
    }

    func testSettingsStayOffAndExportReminderShows() throws {
        let app = app(parent: true)
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["parentTitle"].waitForExistence(timeout: 15))
        let consent = app.switches["consentToggle"]
        reveal(consent, in: app)
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        XCTAssertEqual(consent.value as? String, "0")
        let cellular = app.switches["cellularToggle"]
        reveal(cellular, in: app)
        XCTAssertTrue(cellular.waitForExistence(timeout: 5))
        XCTAssertEqual(cellular.value as? String, "0")
        let reminder = app.staticTexts["exportReminder"]
        reveal(reminder, in: app)
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        XCTAssertTrue(reminder.label.contains("还没有导出过"))
        screenshot("Parent-settings", app)
        app.terminate()
    }

    func testPendingSentenceJoinsLibraryOnlyAfterConfirm() throws {
        let app = app(parent: true, pending: true)
        app.launch()
        let pending = app.descendants(matching: .any)["pendingRow"]
        XCTAssertTrue(pending.waitForExistence(timeout: 15))
        pending.tap()
        let confirm = app.buttons["confirmPending"]
        reveal(confirm, in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        XCTAssertTrue(confirm.isHittable)
        XCTAssertTrue(app.staticTexts["宝宝要喝水"].waitForExistence(timeout: 5))
        confirm.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["confirmPending"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["pendingRow"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["parentTitle"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["pendingRow"].exists)
        screenshot("Pending-confirmed", app)
        app.terminate()
    }
}
