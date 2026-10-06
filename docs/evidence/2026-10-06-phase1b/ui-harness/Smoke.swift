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
        XCTAssertFalse(app.scrollViews["renewal.dayScroll"].exists, "Standard 375+ pt layout must not scroll", file: file, line: line)
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
        // Existence does not prove visibility. Scroll the strip itself and
        // actually select both ends, returning to today between selections
        // because the visible range recenters on each selected date.
        for offset in [-3, 3] {
            let target = dayButton(calendar.date(byAdding: .day, value: offset, to: today)!)
            let strip = app.scrollViews["renewal.dayScroll"]
            XCTAssertTrue(strip.waitForExistence(timeout: 3))
            for _ in 0..<4 {
                if target.isHittable && target.frame.minX >= strip.frame.minX && target.frame.maxX <= strip.frame.maxX { break }
                if offset < 0 { strip.swipeRight() } else { strip.swipeLeft() }
            }
            XCTAssertTrue(target.isHittable)
            XCTAssertGreaterThanOrEqual(target.frame.minX, strip.frame.minX - 0.5)
            XCTAssertLessThanOrEqual(target.frame.maxX, strip.frame.maxX + 0.5)
            target.tap()
            XCTAssertTrue(target.isSelected, "Tapping the end date must change selection")
            app.buttons["오늘"].tap()
            XCTAssertTrue(dayButton(today).isSelected)
        }
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

    // MARK: Phase 1B helpers

    /// Pulls the presented sheet down by dragging its navigation bar, which is
    /// what a user does to dismiss it interactively.
    func swipeSheetDown() {
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 3), app.debugDescription)
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.15, thenDragTo: end)
    }

    func alert(_ title: String) -> XCUIElement { app.alerts[title] }

    var L: [String: String] {
        ko ? [
            "add": "renewal.add", "name": "음식 이름 (선택)", "protein": "단백질량 (g)", "total": "하루 총량 (g)",
            "cancel": "취소", "save": "저장", "delete": "기록 삭제", "edit": "기록 수정",
            "discardTitle": "변경 내용을 버릴까요?", "keep": "계속 입력", "discard": "버리고 닫기",
            "deleteTitle": "이 기록을 삭제할까요?", "deleteConfirm": "기록 삭제",
            "pendingTitle": "저장 결과를 확인하기 전에 닫을까요?", "stay": "화면에 머무르기", "close": "닫기",
            "unconfirmed": "저장 결과 미확인", "ok": "확인", "reconfirm": "저장 결과 확인", "notSaved": "저장되지 않음",
            "storage": "저장하지 못했어요",
        ] : [
            "add": "renewal.add", "name": "Food name (optional)", "protein": "Protein (g)", "total": "Daily total (g)",
            "cancel": "Cancel", "save": "Save", "delete": "Delete entry", "edit": "Edit entry",
            "discardTitle": "Discard changes?", "keep": "Keep editing", "discard": "Discard changes",
            "deleteTitle": "Delete this entry?", "deleteConfirm": "Delete entry",
            "pendingTitle": "Close before checking the save status?", "stay": "Stay here", "close": "Close",
            "unconfirmed": "Save result unconfirmed", "ok": "OK", "reconfirm": "Check save status", "notSaved": "Not saved",
            "storage": "Couldn't save",
        ]
    }

    func openAddSheet() {
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["renewal.add"].tap()
        XCTAssertTrue(app.textFields[L["name"]!].waitForExistence(timeout: 5), app.debugDescription)
    }

    func typeEntry(name: String, protein: String) {
        app.textFields[L["name"]!].tap()
        app.textFields[L["name"]!].typeText(name)
        app.textFields[L["protein"]!].tap()
        app.textFields[L["protein"]!].typeText(protein)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }

    func row(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    func rowCount(_ name: String) -> Int {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).count
    }

    // MARK: Phase 1B scenarios

    /// Cancel and pull-down on a dirty entry sheet both ask; "Keep editing"
    /// keeps the input; "Discard changes" closes; a clean sheet closes silently
    /// and can be reopened after an interactive close.
    func test7DiscardEntry() {
        configure()
        app.launch()
        let suffix = String(Int(Date().timeIntervalSince1970) % 100000)
        let name = "Discard me \(suffix)"
        openAddSheet()
        // Clean: the Cancel button closes without asking.
        app.buttons[L["cancel"]!].tap()
        XCTAssertFalse(alert(L["discardTitle"]!).waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 3))
        // Clean: the pull-down closes without asking, and the sheet reopens afterwards.
        openAddSheet()
        swipeSheetDown()
        XCTAssertFalse(alert(L["discardTitle"]!).waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields[L["name"]!].exists, "sheet must be gone")
        openAddSheet()
        // Dirty: Cancel asks (keyboard still up).
        typeEntry(name: name, protein: "9")
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(alert(L["discardTitle"]!).waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(alert(L["discardTitle"]!).buttons[L["keep"]!].isHittable)
        XCTAssertTrue(alert(L["discardTitle"]!).buttons[L["discard"]!].isHittable)
        capture("discard-entry")
        alert(L["discardTitle"]!).buttons[L["keep"]!].tap()
        XCTAssertFalse(alert(L["discardTitle"]!).waitForExistence(timeout: 1))
        XCTAssertEqual(app.textFields[L["name"]!].value as? String, name, "input kept")
        XCTAssertEqual(app.textFields[L["protein"]!].value as? String, "9")
        // Dirty: pull-down asks too, with the same wording.
        swipeSheetDown()
        XCTAssertTrue(alert(L["discardTitle"]!).waitForExistence(timeout: 3), app.debugDescription)
        capture("discard-entry-swipe")
        alert(L["discardTitle"]!).buttons[L["keep"]!].tap()
        XCTAssertEqual(app.textFields[L["name"]!].value as? String, name, "input kept after refused swipe")
        swipeSheetDown()
        XCTAssertTrue(alert(L["discardTitle"]!).waitForExistence(timeout: 3))
        alert(L["discardTitle"]!).buttons[L["discard"]!].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields[L["name"]!].exists)
        XCTAssertEqual(rowCount(name), 0, "discard wrote nothing")
        // The sheet opens again, empty: no draft survives.
        openAddSheet()
        XCTAssertEqual(app.textFields[L["name"]!].value as? String ?? "", L["name"]!, "placeholder, no draft")
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 3))
        capture("discard-entry-home")
    }

    /// The legacy total editor follows the same policy; returning to the original string is clean again.
    func test8DiscardTotal() {
        configure()
        app.launch()
        navigate(to: utcDay("2026-09-23"))
        let adjustment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ko ? "이전 기록 보정" : "Imported adjustment")).firstMatch
        XCTAssertTrue(adjustment.waitForExistence(timeout: 5), app.debugDescription)
        adjustment.tap()
        let total = app.buttons["renewal.editTotal"]
        if !total.isHittable { app.swipeUp() }
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        total.tap()
        let field = app.textFields[L["total"]!]
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        let original = field.value as? String ?? ""
        XCTAssertFalse(original.isEmpty)
        // Clean close.
        app.buttons[L["cancel"]!].tap()
        XCTAssertFalse(alert(L["discardTitle"]!).waitForExistence(timeout: 1))
        if !total.isHittable { app.swipeUp() }
        total.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Typed and reverted: clean again.
        field.tap()
        field.typeText("1")
        XCTAssertEqual(field.value as? String, original + "1")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String, original)
        swipeSheetDown()
        XCTAssertFalse(alert(L["discardTitle"]!).waitForExistence(timeout: 1), "reverted input is clean")
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 3))
        // Dirty: ask on Cancel, keep, then ask on pull-down and discard.
        if !total.isHittable { app.swipeUp() }
        total.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("7")
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(alert(L["discardTitle"]!).waitForExistence(timeout: 3), app.debugDescription)
        capture("discard-total")
        alert(L["discardTitle"]!).buttons[L["keep"]!].tap()
        XCTAssertEqual(field.value as? String, original + "7")
        swipeSheetDown()
        XCTAssertTrue(alert(L["discardTitle"]!).waitForExistence(timeout: 3))
        alert(L["discardTitle"]!).buttons[L["discard"]!].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 3))
        if !total.isHittable { app.swipeUp() }
        total.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, original, "nothing was written")
        app.buttons[L["cancel"]!].tap()
    }

    /// Delete asks with the stored name, date and amount; Cancel writes nothing;
    /// confirming deletes exactly one row.
    func test9DeleteConfirm() {
        configure()
        app.launch()
        let suffix = String(Int(Date().timeIntervalSince1970) % 100000)
        let name = "Delete me \(suffix)"
        openAddSheet()
        typeEntry(name: name, protein: "12.5")
        app.buttons[L["save"]!].tap()
        let r = row(name)
        scrollRowIntoView(r)
        XCTAssertTrue(r.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(rowCount(name), 1)
        r.tap()
        XCTAssertTrue(app.staticTexts[L["edit"]!].waitForExistence(timeout: 3))
        // Change the field first: the prompt must describe the stored record, not the field.
        replace(app.textFields[L["protein"]!], with: "99")
        app.buttons[L["delete"]!].tap()
        let prompt = alert(L["deleteTitle"]!)
        XCTAssertTrue(prompt.waitForExistence(timeout: 3), app.debugDescription)
        let expected = "\(name) · \(longDate(todayLocal)) · 12.5 g"
        XCTAssertTrue(prompt.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch.exists,
                      "expected '\(expected)' in \(prompt.debugDescription)")
        XCTAssertTrue(prompt.buttons[L["cancel"]!].isHittable)
        XCTAssertTrue(prompt.buttons[L["deleteConfirm"]!].isHittable)
        capture("delete-confirm")
        prompt.buttons[L["cancel"]!].tap()
        XCTAssertFalse(prompt.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons[L["delete"]!].exists, "sheet stays open after cancelling the delete")
        XCTAssertEqual(app.textFields[L["protein"]!].value as? String, "99", "input kept")
        // Leave without saving: the dirty prompt, then discard.
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(alert(L["discardTitle"]!).waitForExistence(timeout: 3))
        alert(L["discardTitle"]!).buttons[L["discard"]!].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 3))
        scrollRowIntoView(r)
        XCTAssertEqual(rowCount(name), 1, "cancelled delete wrote nothing")
        XCTAssertTrue(row(name).label.contains("12.5 g"), row(name).label)
        // Confirm: one row gone, sheet closed without any further prompt.
        r.tap()
        XCTAssertTrue(app.buttons[L["delete"]!].waitForExistence(timeout: 3))
        app.buttons[L["delete"]!].tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        prompt.buttons[L["deleteConfirm"]!].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(alert(L["discardTitle"]!).exists)
        XCTAssertFalse(app.buttons[L["delete"]!].exists)
        XCTAssertEqual(rowCount(name), 0)
        capture("delete-done")
    }

    /// Real afterReplace failure: the sheet is pending; closing asks with the
    /// pending wording (not the discard one); "Stay here" keeps everything;
    /// closing shows the home banner, and the home re-check finds the row once.
    func test10PendingClose() {
        configure()
        app.launchArguments += ["-HelloProteinFailAfterReplaceOnce", "YES"]
        app.launch()
        let suffix = String(Int(Date().timeIntervalSince1970) % 100000)
        let name = "Pending close \(suffix)"
        openAddSheet()
        typeEntry(name: name, protein: "31.5")
        app.buttons[L["save"]!].tap()
        XCTAssertTrue(alert(L["unconfirmed"]!).waitForExistence(timeout: 5), app.debugDescription)
        alert(L["unconfirmed"]!).buttons[L["ok"]!].tap()
        XCTAssertFalse(app.textFields[L["protein"]!].isEnabled)
        XCTAssertFalse(app.buttons[L["save"]!].isEnabled)
        XCTAssertTrue(app.buttons["renewal.reconfirm.sheet"].exists)
        app.buttons[L["cancel"]!].tap()
        let prompt = alert(L["pendingTitle"]!)
        XCTAssertTrue(prompt.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertFalse(alert(L["discardTitle"]!).exists, "pending wins over dirty")
        XCTAssertTrue(prompt.buttons[L["stay"]!].isHittable)
        XCTAssertTrue(prompt.buttons[L["close"]!].isHittable)
        capture("pending-close")
        prompt.buttons[L["stay"]!].tap()
        XCTAssertFalse(prompt.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["renewal.reconfirm.sheet"].exists, "still on the sheet, still pending")
        XCTAssertEqual(app.textFields[L["name"]!].value as? String, name)
        swipeSheetDown()
        XCTAssertTrue(prompt.waitForExistence(timeout: 3), app.debugDescription)
        capture("pending-close-swipe")
        prompt.buttons[L["close"]!].tap()
        XCTAssertTrue(app.buttons["renewal.reconfirm.home"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields[L["name"]!].exists)
        XCTAssertFalse(app.buttons["renewal.add"].isEnabled, "writes stay blocked on the home screen")
        capture("pending-home")
        app.buttons["renewal.reconfirm.home"].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["renewal.add"].isEnabled)
        let r = row(name)
        scrollRowIntoView(r)
        XCTAssertTrue(r.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(rowCount(name), 1)
        capture("pending-confirmed")
    }

    /// DEBUG double: the write never landed. Re-checking from the sheet unlocks
    /// the input and keeps it; saving again stores the row once.
    func test11NotAppliedSheet() {
        configure()
        app.launchArguments += ["-HelloProteinSaveOutcomeOnce", "notApplied"]
        app.launch()
        let suffix = String(Int(Date().timeIntervalSince1970) % 100000)
        let name = "Not applied \(suffix)"
        openAddSheet()
        typeEntry(name: name, protein: "7.5")
        app.buttons[L["save"]!].tap()
        XCTAssertTrue(alert(L["unconfirmed"]!).waitForExistence(timeout: 5), app.debugDescription)
        alert(L["unconfirmed"]!).buttons[L["ok"]!].tap()
        XCTAssertTrue(app.buttons["renewal.reconfirm.sheet"].waitForExistence(timeout: 3))
        app.buttons["renewal.reconfirm.sheet"].tap()
        XCTAssertTrue(alert(L["notSaved"]!).waitForExistence(timeout: 5), app.debugDescription)
        capture("not-applied-sheet")
        alert(L["notSaved"]!).buttons[L["ok"]!].tap()
        XCTAssertTrue(app.textFields[L["protein"]!].isEnabled, "unlocked")
        XCTAssertTrue(app.buttons[L["save"]!].isEnabled)
        XCTAssertFalse(app.buttons["renewal.reconfirm.sheet"].exists)
        XCTAssertEqual(app.textFields[L["name"]!].value as? String, name, "input kept")
        XCTAssertEqual(app.textFields[L["protein"]!].value as? String, "7.5")
        // Now dirty and idle: closing would ask with the discard wording.
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(alert(L["discardTitle"]!).waitForExistence(timeout: 3))
        alert(L["discardTitle"]!).buttons[L["keep"]!].tap()
        app.buttons[L["save"]!].tap()
        let r = row(name)
        scrollRowIntoView(r)
        XCTAssertTrue(r.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(rowCount(name), 1, "same session, same record ID: one row")
        capture("not-applied-saved")
    }

    /// DEBUG double, checked from the home screen after closing: neutral "not
    /// saved" message, writes unlocked, no row, no restored draft.
    func test12NotAppliedHome() {
        configure()
        app.launchArguments += ["-HelloProteinSaveOutcomeOnce", "notApplied"]
        app.launch()
        let suffix = String(Int(Date().timeIntervalSince1970) % 100000)
        let name = "Not applied home \(suffix)"
        openAddSheet()
        typeEntry(name: name, protein: "5")
        app.buttons[L["save"]!].tap()
        XCTAssertTrue(alert(L["unconfirmed"]!).waitForExistence(timeout: 5))
        alert(L["unconfirmed"]!).buttons[L["ok"]!].tap()
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(alert(L["pendingTitle"]!).waitForExistence(timeout: 3))
        alert(L["pendingTitle"]!).buttons[L["close"]!].tap()
        XCTAssertTrue(app.buttons["renewal.reconfirm.home"].waitForExistence(timeout: 5))
        app.buttons["renewal.reconfirm.home"].tap()
        XCTAssertTrue(alert(L["notSaved"]!).waitForExistence(timeout: 5), app.debugDescription)
        capture("not-applied-home")
        alert(L["notSaved"]!).buttons[L["ok"]!].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["renewal.add"].isEnabled)
        XCTAssertFalse(app.buttons["renewal.reconfirm.home"].exists)
        XCTAssertEqual(rowCount(name), 0)
        openAddSheet()
        XCTAssertEqual(app.textFields[L["name"]!].value as? String ?? "", L["name"]!, "no draft restored")
        app.buttons[L["cancel"]!].tap()
    }

    /// DEBUG double: the write landed but the first re-read fails. The sheet
    /// stays pending and locked; the second re-read confirms the row once.
    func test13ReconfirmReadFailed() {
        configure()
        app.launchArguments += ["-HelloProteinSaveOutcomeOnce", "readFailure"]
        app.launch()
        let suffix = String(Int(Date().timeIntervalSince1970) % 100000)
        let name = "Read failed \(suffix)"
        openAddSheet()
        typeEntry(name: name, protein: "4.5")
        app.buttons[L["save"]!].tap()
        XCTAssertTrue(alert(L["unconfirmed"]!).waitForExistence(timeout: 5))
        alert(L["unconfirmed"]!).buttons[L["ok"]!].tap()
        app.buttons["renewal.reconfirm.sheet"].tap()
        XCTAssertTrue(alert(L["storage"]!).waitForExistence(timeout: 5), app.debugDescription)
        capture("reconfirm-read-failed")
        alert(L["storage"]!).buttons[L["ok"]!].tap()
        XCTAssertTrue(app.buttons["renewal.reconfirm.sheet"].exists, "still pending")
        XCTAssertFalse(app.textFields[L["protein"]!].isEnabled, "still locked")
        XCTAssertFalse(app.buttons[L["save"]!].isEnabled)
        XCTAssertEqual(app.textFields[L["name"]!].value as? String, name)
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(alert(L["pendingTitle"]!).waitForExistence(timeout: 3), "closing still asks with the pending wording")
        alert(L["pendingTitle"]!).buttons[L["stay"]!].tap()
        app.buttons["renewal.reconfirm.sheet"].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5), "applied: the sheet closed by itself")
        XCTAssertFalse(app.textFields[L["name"]!].exists)
        let r = row(name)
        scrollRowIntoView(r)
        XCTAssertTrue(r.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(rowCount(name), 1)
        capture("reconfirm-read-recovered")
    }

    /// Run after the shell corrupted app-state.json: retry is offered, a tap
    /// re-runs the gate and (file still corrupt) lands on a fresh recovery screen.
    func test14RecoveryRetry() {
        configure()
        app.launch()
        let retry = app.buttons["recovery.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["recovery.retryHint"].exists)
        XCTAssertTrue(app.staticTexts["recovery.title"].exists)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        XCTAssertFalse(app.buttons["renewal.add"].exists)
        capture(ko ? "recovery-retry-ko-ax3" : "recovery-retry")
        retry.tap()
        // A fresh recovery screen: still no home, retry available again.
        XCTAssertTrue(app.buttons["recovery.retry"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["renewal.add"].exists)
        XCTAssertTrue(app.buttons["recovery.retry"].isEnabled)
        try? "retried".write(toFile: outputDir + "/recovery-retry-tapped.txt", atomically: true, encoding: .utf8)
    }

    /// Run after the shell wrote an unsupported-schema app-state.json: no retry, no hint.
    func test15RecoveryNoRetry() {
        configure()
        app.launch()
        XCTAssertTrue(app.staticTexts["recovery.title"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["recovery.retry"].exists)
        XCTAssertFalse(app.staticTexts["recovery.retryHint"].exists)
        XCTAssertFalse(app.buttons["renewal.add"].exists)
        capture(ko ? "recovery-no-retry-ko-ax3" : "recovery-no-retry")
    }

    /// Run after the shell restored the file: the home screen opens normally.
    func test16RecoveredHome() {
        configure()
        app.launch()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["recovery.title"].exists)
        capture("recovery-restored-home")
    }

    func test17KoreanLargeTextPrompts() {
        ko = true
        contentSize = "UICTContentSizeCategoryAccessibilityXL" // AX3
        configure()
        app.launch()
        let suffix = String(Int(Date().timeIntervalSince1970) % 100000)
        let name = "큰글씨 \(suffix)"
        openAddSheet()
        typeEntry(name: name, protein: "3")
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(alert(L["discardTitle"]!).waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(alert(L["discardTitle"]!).buttons[L["keep"]!].isHittable)
        XCTAssertTrue(alert(L["discardTitle"]!).buttons[L["discard"]!].isHittable)
        capture("discard-entry-ko-ax3")
        alert(L["discardTitle"]!).buttons[L["keep"]!].tap()
        XCTAssertEqual(app.textFields[L["name"]!].value as? String, name)
        app.buttons[L["save"]!].tap()
        let r = row(name)
        scrollRowIntoView(r)
        XCTAssertTrue(r.waitForExistence(timeout: 5), app.debugDescription)
        r.tap()
        XCTAssertTrue(app.buttons[L["delete"]!].waitForExistence(timeout: 3))
        if !app.buttons[L["delete"]!].isHittable { app.swipeUp() }
        app.buttons[L["delete"]!].tap()
        let prompt = alert(L["deleteTitle"]!)
        XCTAssertTrue(prompt.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(prompt.buttons[L["deleteConfirm"]!].isHittable)
        capture("delete-confirm-ko-ax3")
        prompt.buttons[L["deleteConfirm"]!].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5))
        XCTAssertEqual(rowCount(name), 0)
    }

    func test18KoreanPendingClose() {
        ko = true
        configure()
        app.launchArguments += ["-HelloProteinFailAfterReplaceOnce", "YES"]
        app.launch()
        let suffix = String(Int(Date().timeIntervalSince1970) % 100000)
        let name = "미확정 \(suffix)"
        openAddSheet()
        typeEntry(name: name, protein: "2.5")
        app.buttons[L["save"]!].tap()
        XCTAssertTrue(alert(L["unconfirmed"]!).waitForExistence(timeout: 5), app.debugDescription)
        alert(L["unconfirmed"]!).buttons[L["ok"]!].tap()
        app.buttons[L["cancel"]!].tap()
        let prompt = alert(L["pendingTitle"]!)
        XCTAssertTrue(prompt.waitForExistence(timeout: 3), app.debugDescription)
        capture("pending-close-ko")
        prompt.buttons[L["close"]!].tap()
        XCTAssertTrue(app.buttons["renewal.reconfirm.home"].waitForExistence(timeout: 5))
        capture("pending-home-ko")
        app.buttons["renewal.reconfirm.home"].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5))
        let r = row(name)
        scrollRowIntoView(r)
        XCTAssertTrue(r.waitForExistence(timeout: 5))
        XCTAssertEqual(rowCount(name), 1)
    }

    func test19RecoveryRetryKoreanLargeText() {
        ko = true
        contentSize = "UICTContentSizeCategoryAccessibilityXL"
        test14RecoveryRetry()
    }

    func test20RecoveryNoRetryKoreanLargeText() {
        ko = true
        contentSize = "UICTContentSizeCategoryAccessibilityXL"
        test15RecoveryNoRetry()
    }
}
