import XCTest

@MainActor
final class Echo101UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func app(run: String = UUID().uuidString, parent: Bool = true, seeded: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--test-run-id", run]
        if parent { app.launchArguments.append("--test-parent") }
        if seeded { app.launchArguments.append("--seed-samples") }
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }
    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testMomentExpressionPersistsAndCanBeDeleted() throws {
        let run = UUID().uuidString
        let app = app(run: run)
        app.launch()
        XCTAssertTrue(app.buttons["addMoment"].waitForExistence(timeout: 15))
        screenshot("Home-empty", app)
        reveal(app.buttons["addMoment"], in: app)
        app.buttons["addMoment"].tap()
        let note = app.descendants(matching: .any)["momentNote"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap(); note.typeText("A red toy car at home")
        app.buttons["saveMoment"].tap()
        let moment = app.staticTexts["A red toy car at home"].firstMatch
        reveal(moment, in: app)
        XCTAssertTrue(moment.waitForExistence(timeout: 5)); moment.tap()
        reveal(app.buttons["addExpression"], in: app)
        app.buttons["addExpression"].tap()
        let english = app.descendants(matching: .any)["englishText"].firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        english.tap(); english.typeText("A red car.")
        app.buttons["saveExpression"].tap()
        let savedExpression = app.staticTexts["A red car."].firstMatch
        XCTAssertTrue(savedExpression.waitForExistence(timeout: 10))
        reveal(savedExpression, in: app)
        savedExpression.tap()
        XCTAssertTrue(app.buttons["playExpression"].waitForExistence(timeout: 5))
        screenshot("Expression", app)
        // Deliberately do not start microphones or change network/system settings.
        app.terminate(); app.launch()
        reveal(app.staticTexts["A red car."].firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["A red car."].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["A red car."].firstMatch.tap()
        reveal(app.buttons["Delete Expression"], in: app)
        app.buttons["Delete Expression"].tap()
        let confirmDelete = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        // A successful tap is not proof that SwiftUI has finished dismissing.
        let removed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.staticTexts["expressionTitle"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["addMoment"].waitForExistence(timeout: 10))
        screenshot("Expression-deleted", app)
        // Verify durable deletion, not just a transient navigation change.
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["addMoment"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["A red toy car at home"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["A red car."].firstMatch.exists)
        screenshot("Deletion-persists-after-relaunch", app)
        app.terminate()
    }
    func testSettingsDiagnosticsAndCloudOffByDefault() throws {
        let app = app()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let microphone = app.buttons["microphoneSettings"].firstMatch
        reveal(microphone, in: app)
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        microphone.tap()
        reveal(app.buttons["Refresh Voices & Capabilities"], in: app)
        XCTAssertTrue(app.buttons["Refresh Voices & Capabilities"].waitForExistence(timeout: 5))
        screenshot("Voice-diagnostics", app)
        let summary = app.staticTexts.allElementsBoundByIndex.map(\.label)
            .filter { $0.contains("recognition") || $0 == "Supported" || $0 == "Unavailable" }
            .joined(separator: "\n")
        let attachment = XCTAttachment(string: summary)
        attachment.name = "Device-capability-labels"; attachment.lifetime = .keepAlways; add(attachment)
        let enabled = app.switches["cloudGenerationToggle"]
        reveal(enabled, in: app)
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        XCTAssertEqual(enabled.value as? String, "0")
        screenshot("Model-settings", app)
        app.terminate()
    }
    func testCaptureCanBeCancelledWithoutStartingMicrophone() throws {
        let app = app(); app.launch()
        reveal(app.buttons["captureMoment"], in: app)
        app.buttons["captureMoment"].tap()
        XCTAssertTrue(app.buttons["startRecording"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["stopRecording"].exists)
        screenshot("Capture-ready", app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["addMoment"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testChildScreensDoNotExposeDraftsOrParentNotes() throws {
        let app = app(parent: false, seeded: true)
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["Settings"].exists)
        XCTAssertFalse(app.staticTexts["今天一起玩红色小汽车，然后把它收进盒子。"].exists)
        app.tabBars.buttons["Explore"].tap()
        app.staticTexts["Toys"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["A red car."].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Put the car in the box."].exists)
        screenshot("Child-explore-confirmed-only", app)
        app.terminate()
    }
}
