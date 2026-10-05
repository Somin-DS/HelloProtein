import XCTest

/// One-off UI harness for the regular-iPhone correction pass. Attaches to the
/// already-installed app (bundle id below) and writes PNGs to
/// /private/tmp/hp-iphone-ui/out/<run>/<device>/<name>.png, where <run> is the
/// first line of /private/tmp/hp-iphone-ui/run.txt (default "run").
final class Smoke: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.devsom.ProteinTracker")
    var ko = false
    var contentSize: String?

    override func setUp() {
        continueAfterFailure = false
        ko = false
        contentSize = nil
    }

    func configure() {
        var args = ["-HelloProteinRenewalFlow", "YES"]
        args += ko ? ["-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
                   : ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let size = contentSize { args += ["-UIPreferredContentSizeCategoryName", size] }
        app.launchArguments = args
    }

    // MARK: Helpers

    var outputDir: String {
        let run = (try? String(contentsOfFile: "/private/tmp/hp-iphone-ui/run.txt"))?
            .split(separator: "\n").first.map(String.init) ?? "run"
        let device = UIDevice.current.name.replacingOccurrences(of: " ", with: "-")
        return "/private/tmp/hp-iphone-ui/out/\(run)/\(device)"
    }

    func capture(_ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: outputDir + "/\(name).png"))
    }

    func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + value)
    }

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    /// Mirrors RecordHomeView.longDate: gregorian, UTC, long style, app locale.
    func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: ko ? "ko_KR" : "en_US")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateStyle = .long
        return f.string(from: date)
    }

    func utcDay(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)!
    }

    /// Today as the app computes it (local time zone), then normalised to a UTC day.
    var todayLocal: Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        let comps = c.dateComponents([.year, .month, .day], from: Date())
        return utcDay(String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!))
    }

    func dayButton(_ date: Date) -> XCUIElement { app.buttons[longDate(date)] }

    /// Taps "Previous week" until `target` is inside the ±3 day strip, then taps it.
    func navigate(to target: Date) {
        var center = todayLocal
        var taps = 0
        while abs(calendar.dateComponents([.day], from: center, to: target).day!) > 3 {
            center = calendar.date(byAdding: .day, value: target < center ? -7 : 7, to: center)!
            taps += 1
            XCTAssertLessThan(taps, 60)
        }
        let direction = target < todayLocal ? "Previous week" : "Next week"
        let koDirection = target < todayLocal ? "일주일 전" : "일주일 후"
        let button = app.buttons[ko ? koDirection : direction]
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<taps { button.tap() }
        let day = dayButton(target)
        XCTAssertTrue(day.waitForExistence(timeout: 5), app.debugDescription)
        day.tap()
    }

    /// The seven strip buttons around `center` must all be hittable without scrolling.
    func assertSevenDaysVisible(around center: Date, file: StaticString = #filePath, line: UInt = #line) {
        // A day button whose frame crosses the page inset is clipped by the
        // horizontal scroller (frames come back unclipped from XCUITest).
        // RenewalTheme.pageInset is 20 pt; the strip's scroller is clipped there.
        let left: CGFloat = 20
        let right = app.windows.firstMatch.frame.maxX - 20
        var frames: [String] = []
        for offset in -3...3 {
            let date = calendar.date(byAdding: .day, value: offset, to: center)!
            let b = dayButton(date)
            XCTAssertTrue(b.exists, "missing day \(longDate(date))", file: file, line: line)
            frames.append("\(longDate(date)) \(b.frame)")
            XCTAssertTrue(b.isHittable, "not hittable: \(longDate(date)) frame=\(b.frame)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(b.frame.minX, left - 0.5, "clipped left of content edge \(left): \(longDate(date)) \(b.frame)", file: file, line: line)
            XCTAssertLessThanOrEqual(b.frame.maxX, right + 0.5, "clipped right of content edge \(right): \(longDate(date)) \(b.frame)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(b.frame.width, 43.5, "touch target < 44pt: \(longDate(date)) \(b.frame)", file: file, line: line)
        }
        let attachment = XCTAttachment(string: "content \(left)...\(right)\n" + frames.joined(separator: "\n"))
        attachment.name = "day-strip-frames"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? (("content \(left)...\(right)\n" + frames.joined(separator: "\n")) as String)
            .write(toFile: outputDir + "/day-strip-frames-\(ko ? "ko" : "en").txt", atomically: true, encoding: .utf8)
    }

    func scrollRowIntoView(_ row: XCUIElement) {
        var attempts = 0
        let add = app.buttons["renewal.add"]
        while attempts < 6 {
            if row.exists, row.isHittable, row.frame.maxY <= add.frame.minY { return }
            app.swipeUp()
            attempts += 1
        }
    }

    // MARK: Scenarios

    func test1HomeEnglish() {
        configure()
        app.launch()
        let today = todayLocal
        XCTAssertTrue(dayButton(today).waitForExistence(timeout: 10), app.debugDescription)
        capture("home-en")
        assertSevenDaysVisible(around: today)
        XCTAssertTrue(app.buttons["renewal.add"].isHittable)
        XCTAssertFalse(app.buttons["Today"].isEnabled) // today selected → disabled
        app.buttons["Pick a date"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        capture("date-picker")
        app.buttons["Cancel"].tap()

        navigate(to: utcDay("2026-09-23"))
        XCTAssertTrue(app.staticTexts["No goal history for this day"].waitForExistence(timeout: 5), app.debugDescription)
        assertSevenDaysVisible(around: utcDay("2026-09-23"))
        capture("past-records")
        let adjustment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Imported adjustment")).firstMatch
        XCTAssertTrue(adjustment.waitForExistence(timeout: 5), app.debugDescription)
        adjustment.tap()
        XCTAssertTrue(app.staticTexts["Original imported total, 55 g"].waitForExistence(timeout: 5)
                      || app.otherElements["Original imported total, 55 g"].exists, app.debugDescription)
        capture("legacy-expanded")
        let total = app.buttons["renewal.editTotal"]
        if !total.isHittable { app.swipeUp() }
        XCTAssertTrue(total.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(total.isHittable)
        total.tap()
        XCTAssertTrue(app.textFields["Daily total (g)"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.textFields["Daily total (g)"].value as? String, "55")
        app.textFields["Daily total (g)"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save"].isHittable)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        capture("total-editor")
        app.buttons["Cancel"].tap()

        let aggregateDay = dayButton(utcDay("2026-09-20"))
        XCTAssertTrue(aggregateDay.waitForExistence(timeout: 5))
        aggregateDay.tap()
        XCTAssertTrue(app.staticTexts["No goal history for this day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Original imported daily total")).firstMatch.exists, app.debugDescription)
        capture("aggregate-only")

        app.buttons["Today"].tap()
        XCTAssertTrue(dayButton(today).waitForExistence(timeout: 5))
        XCTAssertTrue(dayButton(today).isSelected)
    }

    func test2EntryLifecycle() {
        configure()
        app.launch()
        let name = "Grilled chicken breast with a deliberately long name"
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 10))
        app.buttons["renewal.add"].tap()
        XCTAssertTrue(app.textFields["Food name (optional)"].waitForExistence(timeout: 5))
        app.textFields["Food name (optional)"].tap()
        app.textFields["Food name (optional)"].typeText(name)
        app.textFields["Protein (g)"].tap()
        app.textFields["Protein (g)"].typeText("120.5")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save"].isHittable)
        XCTAssertTrue(app.buttons["Cancel"].isHittable)
        capture("add-keyboard")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["0.5 g above your goal"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Goal reached"].exists)
        capture("goal-reached")

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        scrollRowIntoView(row)
        XCTAssertTrue(row.isHittable, app.debugDescription)
        XCTAssertLessThanOrEqual(row.frame.maxY, app.buttons["renewal.add"].frame.minY, "last row hidden under add button")
        capture("last-row-above-add")
        row.tap()
        XCTAssertTrue(app.staticTexts["Edit entry"].waitForExistence(timeout: 3), app.debugDescription)
        replace(app.textFields["Protein (g)"], with: "60")
        XCTAssertEqual(app.textFields["Protein (g)"].value as? String, "60")
        XCTAssertTrue(app.buttons["Delete entry"].exists)
        capture("edit-keyboard")
        app.buttons["Save"].tap()
        let updated = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", name, "60 g")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).count, 1, "edit duplicated the row")

        app.terminate()
        app.launch()
        scrollRowIntoView(updated)
        XCTAssertTrue(updated.waitForExistence(timeout: 5), app.debugDescription)
        updated.tap()
        XCTAssertTrue(app.staticTexts["Edit entry"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["Protein (g)"].value as? String, "60")
        app.buttons["Delete entry"].tap()
        XCTAssertFalse(updated.waitForExistence(timeout: 2))
        capture("after-delete")
    }

    func test4UnconfirmedCloseAndReconfirm() {
        configure()
        app.launchArguments += ["-HelloProteinFailAfterReplaceOnce", "YES"]
        app.launch()
        let name = "Pending save with a deliberately long food name"
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 10))
        app.buttons["renewal.add"].tap()
        app.textFields["Food name (optional)"].tap()
        app.textFields["Food name (optional)"].typeText(name)
        app.textFields["Protein (g)"].tap()
        app.textFields["Protein (g)"].typeText("31.5")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts["Save result unconfirmed"].waitForExistence(timeout: 5), app.debugDescription)
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.textFields["Protein (g)"].isEnabled)
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        XCTAssertTrue(app.buttons["Check save status"].exists)
        capture("pending-sheet")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Check save status"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["renewal.add"].isEnabled)
        capture("pending-home")
        app.buttons["Check save status"].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["renewal.add"].isEnabled)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        scrollRowIntoView(row)
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).count, 1)
        capture("pending-confirmed")
    }

    func test3KoreanHome() {
        ko = true
        configure()
        app.launch()
        let today = todayLocal
        XCTAssertTrue(dayButton(today).waitForExistence(timeout: 10), app.debugDescription)
        capture("home-ko")
        assertSevenDaysVisible(around: today)
        XCTAssertTrue(app.buttons["renewal.add"].isHittable)
        XCTAssertTrue(app.buttons["날짜 선택"].exists)
        navigate(to: utcDay("2026-09-23"))
        XCTAssertTrue(app.staticTexts["이 날짜에는 목표 이력이 없어요"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "이전 기록 보정")).firstMatch.tap()
        capture("past-records-ko")
    }

    func test5LargeTextKorean() {
        ko = true
        contentSize = "UICTContentSizeCategoryAccessibilityXL" // AX3 (accessibilityExtraLarge)
        configure()
        app.launch()
        let today = todayLocal
        XCTAssertTrue(dayButton(today).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(dayButton(today).isHittable)
        XCTAssertTrue(app.buttons["renewal.add"].isHittable)
        capture("large-text")
        // Strip must still reach every day of the week by scrolling.
        let last = dayButton(calendar.date(byAdding: .day, value: 3, to: today)!)
        if !last.isHittable { app.swipeLeft() }
        XCTAssertTrue(last.waitForExistence(timeout: 3))
        app.swipeUp()
        capture("large-text-scrolled")
        app.buttons["renewal.add"].tap()
        XCTAssertTrue(app.textFields["단백질량 (g)"].waitForExistence(timeout: 5), app.debugDescription)
        app.textFields["단백질량 (g)"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        capture("large-text-add")
        app.buttons["취소"].tap()
    }

    /// Run after `simctl ui <udid> appearance dark`.
    func test6SystemDark() {
        configure()
        app.launch()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 10))
        capture("dark-home")
        app.buttons["Pick a date"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        capture("dark-calendar")
        app.buttons["Cancel"].tap()
        app.buttons["renewal.add"].tap()
        XCTAssertTrue(app.textFields["Protein (g)"].waitForExistence(timeout: 5))
        capture("dark-sheet")
        app.buttons["Cancel"].tap()
    }
}
