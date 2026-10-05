import XCTest

final class Smoke: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.devsom.ProteinTracker")

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-HelloProteinRenewalFlow", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + value)
    }

    func testPastEntryAndLegacyTotal() {
        app.launch()
        XCTAssertTrue(app.buttons["Previous week"].waitForExistence(timeout: 10))
        app.buttons["Previous week"].tap()
        let day = app.buttons["September 23, 2026"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        capture("past-before-edit")
        let adjustment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Imported adjustment")).firstMatch
        XCTAssertTrue(adjustment.waitForExistence(timeout: 5), app.debugDescription)
        adjustment.tap()
        capture("legacy-expanded")
        let total = app.buttons["renewal.editTotal"]
        if !total.isHittable { app.swipeUp() }
        XCTAssertTrue(total.waitForExistence(timeout: 5), app.debugDescription)
        total.tap()
        capture("total-editor")
        replace(app.textFields["Daily total (g)"], with: "60")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.otherElements["renewal.dailyTotal"].waitForExistence(timeout: 5) || app.staticTexts["60"].exists)
        capture("legacy-total-saved")
        app.buttons["renewal.add"].tap()
        app.textFields["Food name (optional)"].tap()
        app.textFields["Food name (optional)"].typeText("Phase1 UI verified")
        app.textFields["Protein (g)"].tap()
        app.textFields["Protein (g)"].typeText("18")
        capture("entry-keyboard")
        app.buttons["Save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Phase1 UI verified")).firstMatch
        app.swipeUp()
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.staticTexts["Edit entry"].waitForExistence(timeout: 3), app.debugDescription)
        replace(app.textFields["Protein (g)"], with: "20")
        XCTAssertEqual(app.textFields["Protein (g)"].value as? String, "20")
        capture("entry-edited-before-save")
        app.buttons["Save"].tap()
        let updated = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Phase1 UI verified", "20 g")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 10), app.debugDescription)
        capture("entry-edit-committed")
        app.terminate()
        app.launch()
        app.buttons["Previous week"].tap()
        app.buttons["September 23, 2026"].tap()
        app.swipeUp()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["Edit entry"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(app.textFields["Protein (g)"].value as? String, "20")
        app.buttons["Delete entry"].tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2))
        capture("past-after-delete")
    }

    func testGoalAndAggregateGallery() {
        app.launch()
        app.buttons["renewal.add"].tap()
        app.textFields["Food name (optional)"].tap()
        app.textFields["Food name (optional)"].typeText("Goal UI sample")
        app.textFields["Protein (g)"].tap()
        app.textFields["Protein (g)"].typeText("100.5")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["12 g above your goal"].waitForExistence(timeout: 5), app.debugDescription)
        capture("goal-132-over-120")
        app.buttons["Previous week"].tap()
        app.buttons["Previous week"].tap()
        app.buttons["September 20, 2026"].tap()
        XCTAssertTrue(app.staticTexts["No goal history for this day"].waitForExistence(timeout: 5))
        capture("aggregate-only-70")
    }

    func testUnconfirmedCloseAndReconfirm() {
        app.launchArguments += ["-HelloProteinFailAfterReplaceOnce", "YES"]
        app.launch()
        app.buttons["renewal.add"].tap()
        app.textFields["Food name (optional)"].tap()
        app.textFields["Food name (optional)"].typeText("Pending UI final")
        app.textFields["Protein (g)"].tap()
        app.textFields["Protein (g)"].typeText("31.5")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts["Save result unconfirmed"].waitForExistence(timeout: 5), app.debugDescription)
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.textFields["Protein (g)"].isEnabled)
        capture("pending-sheet")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["renewal.add"].isEnabled)
        capture("pending-home")
        app.buttons["Check save status"].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["renewal.add"].isEnabled)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Pending UI final")).firstMatch
        app.swipeUp()
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        capture("pending-confirmed")
    }
}
