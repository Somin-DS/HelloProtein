import XCTest

/// Live MFDS smoke test. Requires the real app installed with a locally configured key.
/// Adds one real catalog entry to the simulator only; does not seed or reset data.
final class Smoke: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.devsom.ProteinTracker")
    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-HelloProteinRenewalFlow", "YES", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 15), app.debugDescription)
    }
    func capture(_ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let dir = "/private/tmp/hp-korean-ui-shots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
    }
    func openSearch(_ query: String) {
        app.buttons["renewal.add"].tap()
        let tab = app.buttons["renewal.add.tab.search"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
        let ko = app.buttons["renewal.search.language.korean"]
        XCTAssertTrue(ko.waitForExistence(timeout: 5))
        if !ko.isSelected { ko.tap() }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: ko)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        let field = app.textFields["renewal.search.query"]
        field.tap()
        field.typeText(query)
        app.buttons["renewal.search.run"].tap()
    }
    func reveal(_ element: XCUIElement, limit: Int = 16) {
        for _ in 0..<limit {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    func test1LiveSearchSelectSaveAndPersist() {
        openSearch("닭가슴살")
        let first = app.buttons["renewal.search.result.D102-096060000-0001"]
        if !first.waitForExistence(timeout: 10) { reveal(first) }
        reveal(first)
        XCTAssertTrue(first.label.contains("샌드위치_닭가슴살"), first.label)
        XCTAssertTrue((first.value as? String ?? "").contains("12.18"), first.debugDescription)
        capture("01-live-search-results")
        first.tap()
        let summary = app.staticTexts["renewal.search.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("12.18"), summary.label)
        capture("02-live-search-selected")
        let save = app.buttons["renewal.search.addSelected"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 10), app.debugDescription)
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "샌드위치_닭가슴살")).firstMatch
        reveal(saved)
        XCTAssertTrue(saved.label.contains("12.18"), saved.label)
        XCTAssertTrue(saved.label.contains("100 g"), saved.label)
        capture("03-saved-record")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 15))
        reveal(saved)
        XCTAssertTrue(saved.label.contains("12.18"), saved.label)
        saved.tap()
        XCTAssertTrue(app.staticTexts["renewal.edit.reference"].waitForExistence(timeout: 5), app.debugDescription)
        capture("04-persisted-record-editor")
    }
    func test2LiveSecondPage() {
        openSearch("닭가슴살")
        let first = app.buttons["renewal.search.result.D102-096060000-0001"]
        if !first.waitForExistence(timeout: 10) { reveal(first) }
        let more = app.buttons["renewal.search.more"]
        reveal(more, limit: 35)
        more.tap()
        let second = app.buttons["renewal.search.result.P101-416000400-0095"]
        if !second.waitForExistence(timeout: 10) { reveal(second) }
        reveal(second)
        XCTAssertTrue(second.label.contains("DELISH"), second.label)
        capture("05-live-second-page")
    }
    func test3LiveEmptyResults() {
        openSearch("존재하지않는음식zz987654")
        XCTAssertTrue(app.staticTexts["renewal.search.empty"].waitForExistence(timeout: 30), app.debugDescription)
        capture("06-live-empty-results")
        XCTAssertFalse(app.buttons["renewal.search.addSelected"].exists)
    }
}
