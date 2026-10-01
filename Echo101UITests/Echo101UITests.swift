import XCTest

@MainActor
final class Echo101UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--test-run-id", UUID().uuidString]
        app.launch()
        return app
    }

    func testDefaultTabIsSpeak() {
        let app = launch()
        let speak = app.buttons["说一句"]
        XCTAssertTrue(speak.waitForExistence(timeout: 15))
        XCTAssertTrue(speak.isSelected)
        XCTAssertTrue(app.buttons["按一下，说中文"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["单词"].exists)
        XCTAssertTrue(app.buttons["今天"].exists)
        XCTAssertTrue(app.buttons["爸妈"].exists)
        app.terminate()
    }

    func testTodayTabShowsEmptyDay() {
        let app = launch()
        XCTAssertTrue(app.buttons["今天"].waitForExistence(timeout: 15))
        app.buttons["今天"].tap()
        XCTAssertTrue(app.staticTexts["今天还没有说过"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["按一下，说中文"].exists)
        app.terminate()
    }

    func testParentGateNeedsThreeSecondHoldAndRelocks() {
        let app = launch()
        XCTAssertTrue(app.buttons["爸妈"].waitForExistence(timeout: 15))
        app.buttons["爸妈"].tap()
        XCTAssertTrue(app.staticTexts["这里是爸妈用的"].waitForExistence(timeout: 5))
        let gate = app.buttons["parentGate"]
        XCTAssertTrue(gate.waitForExistence(timeout: 5))
        XCTAssertEqual(gate.label, "按住 3 秒进入")
        XCTAssertFalse(app.staticTexts["晚间回看"].exists)
        gate.press(forDuration: 4)
        XCTAssertTrue(app.staticTexts["晚间回看"].waitForExistence(timeout: 5))
        app.buttons["说一句"].tap()
        app.buttons["爸妈"].tap()
        XCTAssertTrue(app.staticTexts["这里是爸妈用的"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["晚间回看"].exists)
        app.terminate()
    }

    func testWordsTabOpensPinnedCategoryAndWord() {
        let app = launch()
        XCTAssertTrue(app.buttons["单词"].waitForExistence(timeout: 15))
        app.buttons["单词"].tap()
        XCTAssertTrue(app.staticTexts["常用单词"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["category-hangzhou"].exists)
        app.buttons["category-fruit"].tap()
        let apple = app.buttons["word-apple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        apple.tap()
        XCTAssertTrue(app.buttons["playWord"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nextWord"].exists)
        app.terminate()
    }
}