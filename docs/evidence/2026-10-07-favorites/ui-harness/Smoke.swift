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

    var runSuffix: String { String(Int(Date().timeIntervalSince1970) % 100000) }

    func test2EntryLifecycle() {
        configure()
        app.launch()
        // Unique per run: rows from earlier (aborted) runs on the same day would
        // otherwise match the CONTAINS predicates below.
        let name = "Grilled chicken breast with a deliberately long name \(runSuffix)"
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
        // The day's total accumulates across runs, so the goal copy is not
        // asserted here (test21+ cover goals); the new row is.
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5), app.debugDescription)
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
        // Since Phase 1B, deleting asks for confirmation first.
        let deletePrompt = alert(L["deleteTitle"]!)
        XCTAssertTrue(deletePrompt.waitForExistence(timeout: 3), app.debugDescription)
        deletePrompt.buttons[L["deleteConfirm"]!].tap()
        XCTAssertFalse(updated.waitForExistence(timeout: 2))
        capture("after-delete")
    }

    func test4UnconfirmedCloseAndReconfirm() {
        configure()
        app.launchArguments += ["-HelloProteinFailAfterReplaceOnce", "YES"]
        app.launch()
        let name = "Pending save with a deliberately long food name \(runSuffix)"
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
        // Since Phase 1B, closing with an unconfirmed save asks first.
        app.buttons["Cancel"].tap()
        XCTAssertTrue(alert(L["pendingTitle"]!).waitForExistence(timeout: 3), app.debugDescription)
        alert(L["pendingTitle"]!).buttons[L["close"]!].tap()
        XCTAssertTrue(app.buttons["renewal.reconfirm.home"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["renewal.reconfirm.sheet"].exists, "the sheet is closed")
        XCTAssertFalse(app.buttons["renewal.add"].isEnabled)
        capture("pending-home")
        app.buttons["renewal.reconfirm.home"].tap()
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
            "storage": "저장하지 못했어요", "reconfirmFailed": "저장 결과 미확인",
            "tabFavorites": "즐겨찾기", "tabManual": "직접 입력", "switchTitle": "입력/선택을 버리고 이동할까요?", "switchStay": "머무르기", "switchConfirm": "버리고 이동", "favDeleteTitle": "즐겨찾기에서 삭제할까요?", "favDeleteConfirm": "삭제", "favExistsTitle": "이미 즐겨찾기에 있어요", "unnamed": "이름 없음", "checkValue": "저장된 단백질량을 확인해야 기록에 추가할 수 있어요.", "discardSelTitle": "선택을 버릴까요?", "discardSelConfirm": "버리기",
            "goalSet": "목표 설정", "goalChange": "목표 변경", "goal": "하루 목표 (g)", "goalTitle": "하루 단백질 목표", "history": "목표 이력", "dateChanged": "적용 날짜가 바뀌었어요", "updateDate": "적용일을 오늘로 변경", "current": "현재 적용 중",
        ] : [
            "add": "renewal.add", "name": "Food name (optional)", "protein": "Protein (g)", "total": "Daily total (g)",
            "cancel": "Cancel", "save": "Save", "delete": "Delete entry", "edit": "Edit entry",
            "discardTitle": "Discard changes?", "keep": "Keep editing", "discard": "Discard changes",
            "deleteTitle": "Delete this entry?", "deleteConfirm": "Delete entry",
            "pendingTitle": "Close before checking the save status?", "stay": "Stay here", "close": "Close",
            "unconfirmed": "Save result unconfirmed", "ok": "OK", "reconfirm": "Check save status", "notSaved": "Not saved",
            "storage": "Couldn't save", "reconfirmFailed": "Save result unconfirmed",
            "tabFavorites": "Favorites", "tabManual": "Manual", "switchTitle": "Discard your input or selection and switch tabs?", "switchStay": "Stay here", "switchConfirm": "Discard and switch", "favDeleteTitle": "Remove from favorites?", "favDeleteConfirm": "Remove", "favExistsTitle": "Already in favorites", "unnamed": "Unnamed", "checkValue": "Check the saved protein amount before adding this item.", "discardSelTitle": "Discard the selection?", "discardSelConfirm": "Discard",
            "goalSet": "Set goal", "goalChange": "Change goal", "goal": "Daily goal (g)", "goalTitle": "Daily protein goal", "history": "Goal history", "dateChanged": "The start date has changed", "updateDate": "Update start date to today", "current": "Currently active",
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
        XCTAssertTrue(alert(L["reconfirmFailed"]!).waitForExistence(timeout: 5), app.debugDescription)
        capture("reconfirm-read-failed")
        alert(L["reconfirmFailed"]!).buttons[L["ok"]!].tap()
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

    // MARK: Goal settings

    func goalEntry() -> XCUIElement { app.buttons["renewal.goal.entry"] }
    func goalField() -> XCUIElement { app.textFields[L["goal"]!] }
    func goalSave() -> XCUIElement { app.buttons["renewal.goal.save"] }
    /// Rows are combined accessibility elements; their type varies, so match by identifier only.
    func historyRows(_ iso: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "renewal.goal.history.\(iso)"))
    }
    func historyRow(_ iso: String) -> XCUIElement { historyRows(iso).firstMatch }

    func openGoalSheet() {
        XCTAssertTrue(goalEntry().waitForExistence(timeout: 10), app.debugDescription)
        // The bottom add button is a safe-area inset drawn over the scroll
        // content; a tap on an entry behind it would open the add sheet.
        let addButton = app.buttons["renewal.add"]
        var attempts = 0
        while attempts < 4, !goalEntry().isHittable || (addButton.exists && goalEntry().frame.maxY > addButton.frame.minY - 8) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
            attempts += 1
        }
        goalEntry().tap()
        XCTAssertTrue(goalField().waitForExistence(timeout: 5), app.debugDescription)
    }

    func homeGoalText() -> String {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", ko ? "목표 " : "Goal ")).firstMatch.label
    }

    /// Existing migrated goal: prefilled, unchanged value cannot be saved,
    /// changed value is saved from today, yesterday keeps the earlier goal,
    /// a second save today replaces today's entry, history is read-only.
    func test21GoalChangeAndHistory() {
        configure()
        app.launch()
        let today = todayLocal
        XCTAssertTrue(dayButton(today).waitForExistence(timeout: 10))
        let before = homeGoalText()
        // Yesterday's own goal is the baseline for the "earlier days unchanged" check
        // (today may already differ from it after earlier runs).
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        dayButton(yesterday).tap()
        XCTAssertTrue(dayButton(yesterday).isSelected)
        let yesterdayBefore = homeGoalText()
        XCTAssertFalse(goalEntry().exists, "no goal editing from a past day")
        dayButton(today).tap()
        XCTAssertTrue(goalEntry().waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(goalEntry().label, L["goalChange"]!)
        openGoalSheet()
        let prefilled = goalField().value as? String ?? ""
        XCTAssertFalse(prefilled.isEmpty && prefilled != L["goal"]!, "prefill expected")
        XCTAssertTrue(app.staticTexts["renewal.goal.current"].exists)
        XCTAssertFalse(goalSave().isEnabled, "unchanged value must not create a history entry")
        capture("goal-existing")
        app.staticTexts[L["history"]!].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "renewal.goal.history.")).firstMatch.waitForExistence(timeout: 3)
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", L["current"]!)).firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        capture("goal-history")
        // Change: 131.5 from today.
        replace(goalField(), with: "131.5")
        XCTAssertTrue(goalSave().isEnabled)
        capture("goal-keyboard")
        goalSave().tap()
        XCTAssertTrue(goalEntry().waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[ko ? "목표 131.5g" : "Goal 131.5g"].waitForExistence(timeout: 5), app.debugDescription + before)
        capture("goal-changed-home")
        // Yesterday keeps the earlier goal.
        dayButton(yesterday).tap()
        XCTAssertTrue(dayButton(yesterday).isSelected)
        XCTAssertFalse(goalEntry().exists, "no goal editing from a past day")
        XCTAssertEqual(homeGoalText(), yesterdayBefore, "yesterday's goal unchanged")
        XCTAssertNotEqual(homeGoalText(), ko ? "목표 131.5g" : "Goal 131.5g", "new goal must not reach yesterday")
        capture("past-goal-preserved")
        app.buttons[ko ? "오늘" : "Today"].tap()
        // Same day again: today's entry is replaced, not duplicated.
        openGoalSheet()
        XCTAssertEqual(goalField().value as? String, "131.5")
        replace(goalField(), with: "125")
        goalSave().tap()
        XCTAssertTrue(app.staticTexts[ko ? "목표 125g" : "Goal 125g"].waitForExistence(timeout: 5), app.debugDescription)
        openGoalSheet()
        app.staticTexts[L["history"]!].tap()
        let todayRow = historyRow(isoDay(today))
        XCTAssertTrue(todayRow.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(historyRows(isoDay(today)).count, 1, "one entry per day")
        XCTAssertTrue(todayRow.label.contains("125"))
        XCTAssertTrue(todayRow.label.contains(L["current"]!), todayRow.label)
        capture("goal-history-replaced")
        app.buttons[L["cancel"]!].tap()
        XCTAssertFalse(alert(L["discardTitle"]!).waitForExistence(timeout: 1), "clean close")
    }

    func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Dirty cancel and swipe ask; keep editing keeps the value; input errors keep the sheet.
    func test22GoalDiscardAndInputError() {
        configure()
        app.launch()
        openGoalSheet()
        replace(goalField(), with: "abc")
        goalSave().tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        capture("goal-input-error")
        app.alerts.firstMatch.buttons[L["ok"]!].tap()
        XCTAssertEqual(goalField().value as? String, "abc", "input kept after an input error")
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(alert(L["discardTitle"]!).waitForExistence(timeout: 3), app.debugDescription)
        capture("goal-discard")
        alert(L["discardTitle"]!).buttons[L["keep"]!].tap()
        XCTAssertEqual(goalField().value as? String, "abc")
        swipeSheetDown()
        XCTAssertTrue(alert(L["discardTitle"]!).waitForExistence(timeout: 3))
        alert(L["discardTitle"]!).buttons[L["discard"]!].tap()
        XCTAssertTrue(goalEntry().waitForExistence(timeout: 5))
        XCTAssertFalse(goalField().exists)
    }

    /// Run after the shell removed the goals from the fixture: "Set goal", empty field, empty history.
    func test23GoalEmpty() {
        configure()
        app.launch()
        XCTAssertTrue(goalEntry().waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(goalEntry().label, L["goalSet"]!)
        XCTAssertTrue(app.staticTexts[ko ? "목표가 설정되지 않았어요" : "No goal set"].exists)
        openGoalSheet()
        XCTAssertEqual(goalField().value as? String ?? "", L["goal"]!, "placeholder only, no invented number")
        app.staticTexts[L["history"]!].tap()
        XCTAssertTrue(app.staticTexts[ko ? "아직 목표 이력이 없어요." : "No goal history yet."].waitForExistence(timeout: 3), app.debugDescription)
        capture("goal-empty")
        replace(goalField(), with: "100")
        goalSave().tap()
        XCTAssertTrue(app.staticTexts[ko ? "목표 100g" : "Goal 100g"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(goalEntry().label, L["goalChange"]!)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayLocal)!
        dayButton(yesterday).tap()
        XCTAssertTrue(app.staticTexts[ko ? "이 날짜에는 목표 이력이 없어요" : "No goal history for this day"].waitForExistence(timeout: 3), app.debugDescription)
        capture("goal-empty-yesterday-no-history")
    }

    /// Run after the shell set goalNeedsReview with an unusable raw value.
    func test24GoalNeedsReview() {
        configure()
        app.launch()
        XCTAssertTrue(goalEntry().waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(goalEntry().label, L["goalSet"]!)
        openGoalSheet()
        XCTAssertEqual(goalField().value as? String ?? "", L["goal"]!, "no prefill from an unusable value")
        let notice = app.staticTexts["renewal.goal.review"]
        XCTAssertTrue(notice.exists, app.debugDescription)
        XCTAssertTrue(notice.label.contains("120 grams"), notice.label)
        capture("goal-needs-review")
        replace(goalField(), with: "90")
        goalSave().tap()
        XCTAssertTrue(app.staticTexts[ko ? "목표 90g" : "Goal 90g"].waitForExistence(timeout: 5), app.debugDescription)
        openGoalSheet()
        XCTAssertFalse(app.staticTexts["renewal.goal.review"].exists, "review flag cleared by the save")
        XCTAssertEqual(goalField().value as? String, "90")
        app.buttons[L["cancel"]!].tap()
        capture("goal-review-cleared")
    }

    /// DEBUG clock: the day advances 30 s after launch while the sheet is open.
    func test25GoalDateChanged() {
        configure()
        app.launchArguments += ["-HelloProteinAdvanceDayAfterSeconds", "30"]
        app.launch()
        let today = todayLocal
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let previousGoal = homeGoalText()
        openGoalSheet()
        XCTAssertTrue(app.staticTexts["renewal.goal.appliesFrom"].label.contains(longDate(today)), app.staticTexts["renewal.goal.appliesFrom"].label)
        replace(goalField(), with: "142")
        sleep(31)
        goalSave().tap()
        XCTAssertTrue(alert(L["dateChanged"]!).waitForExistence(timeout: 5), app.debugDescription)
        capture("goal-date-changed")
        alert(L["dateChanged"]!).buttons[L["ok"]!].tap()
        XCTAssertEqual(goalField().value as? String, "142", "input kept")
        let update = app.buttons["renewal.goal.updateDate"]
        XCTAssertTrue(update.waitForExistence(timeout: 3), app.debugDescription)
        capture("goal-date-stale")
        update.tap()
        XCTAssertTrue(app.staticTexts["renewal.goal.appliesFrom"].label.contains(longDate(tomorrow)), app.staticTexts["renewal.goal.appliesFrom"].label)
        XCTAssertFalse(update.exists)
        XCTAssertEqual(goalField().value as? String, "142")
        goalSave().tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5), "sheet closed")
        // Selection remains on the old day, so there must be no goal entry.
        XCTAssertFalse(goalEntry().exists)
        XCTAssertEqual(homeGoalText(), previousGoal, "the old day's goal is preserved")
        capture("goal-date-changed-home")
        app.buttons[ko ? "오늘" : "Today"].tap()
        XCTAssertTrue(goalEntry().waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[ko ? "목표 142g" : "Goal 142g"].waitForExistence(timeout: 5))
        openGoalSheet()
        XCTAssertEqual(goalField().value as? String, "142")
        XCTAssertTrue(app.staticTexts["renewal.goal.appliesFrom"].label.contains(longDate(tomorrow)))
        capture("goal-date-updated-confirmed")
        app.buttons[L["cancel"]!].tap()
    }

    /// Real afterReplace failure on the goal sheet, then home re-check.
    func test26GoalPending() {
        configure()
        app.launchArguments += ["-HelloProteinFailAfterReplaceOnce", "YES"]
        app.launch()
        openGoalSheet()
        replace(goalField(), with: "133")
        goalSave().tap()
        XCTAssertTrue(alert(L["unconfirmed"]!).waitForExistence(timeout: 5), app.debugDescription)
        alert(L["unconfirmed"]!).buttons[L["ok"]!].tap()
        XCTAssertFalse(goalField().isEnabled)
        XCTAssertTrue(app.buttons["renewal.reconfirm.sheet"].exists)
        capture("goal-pending")
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(alert(L["pendingTitle"]!).waitForExistence(timeout: 3))
        alert(L["pendingTitle"]!).buttons[L["close"]!].tap()
        XCTAssertTrue(app.buttons["renewal.reconfirm.home"].waitForExistence(timeout: 5))
        XCTAssertFalse(goalEntry().isEnabled, "goal entry blocked while pending")
        app.buttons["renewal.reconfirm.home"].tap()
        XCTAssertTrue(app.staticTexts[ko ? "목표 133g" : "Goal 133g"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(goalEntry().isEnabled)
        capture("goal-pending-confirmed")
    }

    /// DEBUG doubles: not applied (sheet) then read failure (sheet).
    func test27GoalNotApplied() {
        configure()
        app.launchArguments += ["-HelloProteinSaveOutcomeOnce", "notApplied"]
        app.launch()
        openGoalSheet()
        replace(goalField(), with: "134")
        goalSave().tap()
        XCTAssertTrue(alert(L["unconfirmed"]!).waitForExistence(timeout: 5))
        alert(L["unconfirmed"]!).buttons[L["ok"]!].tap()
        app.buttons["renewal.reconfirm.sheet"].tap()
        XCTAssertTrue(alert(L["notSaved"]!).waitForExistence(timeout: 5), app.debugDescription)
        capture("goal-not-applied")
        alert(L["notSaved"]!).buttons[L["ok"]!].tap()
        XCTAssertTrue(goalField().isEnabled)
        XCTAssertEqual(goalField().value as? String, "134")
        goalSave().tap()
        XCTAssertTrue(app.staticTexts[ko ? "목표 134g" : "Goal 134g"].waitForExistence(timeout: 5), app.debugDescription)
    }

    func test28GoalReadFailure() {
        configure()
        app.launchArguments += ["-HelloProteinSaveOutcomeOnce", "readFailure"]
        app.launch()
        openGoalSheet()
        replace(goalField(), with: "135")
        goalSave().tap()
        XCTAssertTrue(alert(L["unconfirmed"]!).waitForExistence(timeout: 5))
        alert(L["unconfirmed"]!).buttons[L["ok"]!].tap()
        app.buttons["renewal.reconfirm.sheet"].tap()
        XCTAssertTrue(alert(L["reconfirmFailed"]!).waitForExistence(timeout: 5), app.debugDescription)
        capture("goal-read-failure")
        alert(L["reconfirmFailed"]!).buttons[L["ok"]!].tap()
        XCTAssertFalse(goalField().isEnabled, "still pending and locked")
        app.buttons["renewal.reconfirm.sheet"].tap()
        XCTAssertTrue(goalEntry().waitForExistence(timeout: 5), "applied: closed by itself")
        XCTAssertTrue(app.staticTexts[ko ? "목표 135g" : "Goal 135g"].waitForExistence(timeout: 5), app.debugDescription)
    }

    /// DEBUG delay: every write sleeps 4 s so the busy state is observable.
    func test29GoalBusy() {
        configure()
        app.launchArguments += ["-HelloProteinSaveDelaySeconds", "8"]
        app.launch()
        openGoalSheet()
        replace(goalField(), with: "136")
        goalSave().tap()
        XCTAssertTrue(app.buttons[L["cancel"]!].waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons[L["cancel"]!].isEnabled, "cancel blocked while busy")
        XCTAssertFalse(goalSave().isEnabled)
        XCTAssertFalse(goalField().isEnabled)
        capture("goal-busy")
        swipeSheetDown()
        XCTAssertTrue(goalField().exists, "swipe blocked while busy")
        XCTAssertFalse(app.alerts.firstMatch.exists, "no prompt while busy")
        XCTAssertTrue(app.staticTexts[ko ? "목표 136g" : "Goal 136g"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(goalField().exists, "closed after the save landed")
    }

    func test30GoalKoreanLargeText() {
        ko = true
        contentSize = "UICTContentSizeCategoryAccessibilityXL"
        configure()
        app.launch()
        openGoalSheet()
        capture("goal-ko-ax3")
        app.swipeUp()
        if app.staticTexts[L["history"]!].isHittable { app.staticTexts[L["history"]!].tap() }
        capture("goal-ko-ax3-history")
        replace(goalField(), with: "137")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        capture("goal-ko-ax3-keyboard")
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(alert(L["discardTitle"]!).waitForExistence(timeout: 3), app.debugDescription)
        capture("goal-ko-ax3-discard")
        alert(L["discardTitle"]!).buttons[L["discard"]!].tap()
        XCTAssertTrue(goalEntry().waitForExistence(timeout: 5))
    }

    // MARK: Favorites (Phase A)

    func favoritesTab() {
        app.buttons["renewal.add.tab.favorites"].tap()
        XCTAssertTrue(app.buttons["renewal.favorite.addSelected"].waitForExistence(timeout: 5), app.debugDescription)
    }
    func favoriteRow(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "renewal.favorite.row.", name)).firstMatch
    }
    func favoriteRowCount(_ name: String) -> Int {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "renewal.favorite.row.", name)).count
    }
    func favoriteEditButton(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "renewal.favorite.edit.", name)).firstMatch
    }
    func favoriteDeleteButton(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "renewal.favorite.delete.", name)).firstMatch
    }
    func favoriteToggle() -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "renewal.add.favoriteToggle").firstMatch
    }
    func addSelected() -> XCUIElement { app.buttons["renewal.favorite.addSelected"] }

    /// Home rows live in a LazyVStack: rows below the fold do not exist until
    /// scrolled into view, so scroll to the end before counting, then back.
    func homeRowCount(_ name: String) -> Int {
        // No early exit: a swipe that reveals no new matching row may still
        // be followed by rows that do match further down a long day.
        var count = rowCount(name)
        for _ in 0..<10 {
            app.swipeUp()
            count = max(count, rowCount(name))
        }
        for _ in 0..<10 { app.swipeDown() }
        return count
    }
    func summary() -> XCUIElement { app.staticTexts["renewal.favorite.summary"] }

    /// Manual entry with "also save as favorite" on; the sheet closes on success.
    func addManualFavorite(name: String, protein: String) {
        openAddSheet()
        // Toggle first: the keyboard would cover it afterwards on the SE.
        favoriteToggle().tap()
        typeEntry(name: name, protein: protein)
        app.buttons["renewal.add.save"].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5), app.debugDescription)
    }

    /// Migrated favorites are listed in position order, two are picked (deselect
    /// and re-select included), and one tap adds both to the day as one commit.
    func test31FavoritesBatchAdd() {
        configure()
        app.launch()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 10))
        let chickenBefore = homeRowCount("닭가슴살")
        let yogurtBefore = homeRowCount("그릭요거트")
        openAddSheet()
        favoritesTab()
        let chicken = favoriteRow("닭가슴살")
        let yogurt = favoriteRow("그릭요거트")
        XCTAssertTrue(chicken.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(yogurt.exists)
        XCTAssertLessThan(chicken.frame.minY, yogurt.frame.minY, "position order")
        XCTAssertFalse(addSelected().isEnabled, "nothing selected")
        capture("favorites-list")
        chicken.tap()
        yogurt.tap()
        XCTAssertTrue(summary().label.contains("2"), summary().label)
        XCTAssertTrue(summary().label.contains("32"), summary().label)
        XCTAssertTrue(chicken.isSelected)
        XCTAssertTrue(addSelected().isEnabled)
        capture("favorites-selected")
        yogurt.tap()
        XCTAssertTrue(summary().label.contains("23"), summary().label)
        yogurt.tap()
        XCTAssertTrue(summary().label.contains("32"), summary().label)
        addSelected().tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(homeRowCount("닭가슴살"), chickenBefore + 1)
        XCTAssertEqual(homeRowCount("그릭요거트"), yogurtBefore + 1)
        capture("favorites-added-home")
    }

    /// "Also save as favorite" creates the favorite in the same save; an exact
    /// duplicate later is reused (record saved, notice shown, no second favorite).
    func test32ManualAlsoSaveFavorite() {
        configure()
        app.launch()
        let name = "Tofu \(Int(Date().timeIntervalSince1970) % 100000)"
        addManualFavorite(name: name, protein: "8")
        XCTAssertEqual(homeRowCount(name), 1)
        openAddSheet()
        favoritesTab()
        XCTAssertTrue(favoriteRow(name).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(favoriteRow(name).isEnabled)
        capture("favorite-created")
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5))
        openAddSheet()
        favoriteToggle().tap()
        typeEntry(name: name, protein: "8")
        app.buttons["renewal.add.save"].tap()
        XCTAssertTrue(alert(L["favExistsTitle"]!).waitForExistence(timeout: 5), app.debugDescription)
        capture("favorite-exists")
        alert(L["favExistsTitle"]!).buttons[L["ok"]!].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5))
        XCTAssertEqual(homeRowCount(name), 2, "the record was saved")
        openAddSheet()
        favoritesTab()
        XCTAssertTrue(favoriteRow(name).waitForExistence(timeout: 5))
        XCTAssertEqual(favoriteRowCount(name), 1, "no duplicate favorite")
        app.buttons[L["cancel"]!].tap()
    }

    /// A dirty tab asks before switching; "Stay" keeps the input, "Discard and
    /// switch" drops only that tab's draft. Deleting a favorite confirms with the
    /// stored values, keeps the sheet open and keeps the logged record.
    func test33TabSwitchAndDeleteFavorite() {
        configure()
        app.launch()
        let name = "Del \(Int(Date().timeIntervalSince1970) % 100000)"
        addManualFavorite(name: name, protein: "3")
        openAddSheet()
        replace(app.textFields[L["protein"]!], with: "5")
        app.buttons["renewal.add.tab.favorites"].tap()
        XCTAssertTrue(alert(L["switchTitle"]!).waitForExistence(timeout: 3), app.debugDescription)
        capture("tab-switch-prompt")
        alert(L["switchTitle"]!).buttons[L["switchStay"]!].tap()
        XCTAssertEqual(app.textFields[L["protein"]!].value as? String, "5", "stay keeps the input")
        app.buttons["renewal.add.tab.favorites"].tap()
        alert(L["switchTitle"]!).buttons[L["switchConfirm"]!].tap()
        XCTAssertTrue(addSelected().waitForExistence(timeout: 5))
        favoriteRow("닭가슴살").tap()
        XCTAssertTrue(favoriteRow("닭가슴살").isSelected)
        app.buttons["renewal.add.tab.manual"].tap()
        XCTAssertTrue(alert(L["switchTitle"]!).waitForExistence(timeout: 3))
        alert(L["switchTitle"]!).buttons[L["switchConfirm"]!].tap()
        XCTAssertTrue(app.textFields[L["name"]!].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields[L["protein"]!].value as? String, L["protein"]!, "manual draft was dropped earlier")
        favoritesTab()
        XCTAssertFalse(favoriteRow("닭가슴살").isSelected, "selection was dropped with the switch")
        favoriteDeleteButton(name).tap()
        XCTAssertTrue(alert(L["favDeleteTitle"]!).waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(alert(L["favDeleteTitle"]!).staticTexts.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.exists)
        XCTAssertTrue(alert(L["favDeleteTitle"]!).staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3 g")).firstMatch.exists)
        capture("favorite-delete-prompt")
        alert(L["favDeleteTitle"]!).buttons[L["favDeleteConfirm"]!].tap()
        XCTAssertTrue(waitUntil(timeout: 5) { self.favoriteRowCount(name) == 0 }, "row removed")
        XCTAssertTrue(addSelected().exists, "the sheet stays open after a delete")
        capture("favorite-deleted")
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5))
        XCTAssertEqual(homeRowCount(name), 1, "the logged record stays")
    }

    func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }

    /// Fixture variant with a signed, an empty-named and a zero favorite: they
    /// are listed verbatim, cannot be selected, and the edit path fixes one in
    /// place. Editing with a selection asks first.
    func test34InvalidFavoritesAndEdit() {
        configure()
        app.launch()
        openAddSheet()
        favoritesTab()
        let unnamed = favoriteRow(L["unnamed"]!)
        XCTAssertTrue(unnamed.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(unnamed.isEnabled, "negative value cannot be selected")
        XCTAssertFalse(favoriteRow("zero").isEnabled)
        XCTAssertTrue(app.staticTexts[L["checkValue"]!].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["-5 g"].exists, "signed value shown verbatim")
        capture("favorite-invalid")
        favoriteEditButton(L["unnamed"]!).tap()
        let editName = app.textFields["renewal.favorite.editName"]
        let editProtein = app.textFields["renewal.favorite.editProtein"]
        XCTAssertTrue(editName.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(editProtein.value as? String, "-5")
        replace(editName, with: "Fixed")
        replace(editProtein, with: "5")
        capture("favorite-edit")
        app.buttons["renewal.favorite.editSave"].tap()
        XCTAssertTrue(favoriteRow("Fixed").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(favoriteRow("Fixed").isEnabled)
        XCTAssertFalse(app.textFields["renewal.favorite.editName"].exists, "back to the list")
        capture("favorite-edited")
        favoriteRow("Fixed").tap()
        favoriteEditButton("Edit me").tap()
        XCTAssertTrue(alert(L["discardSelTitle"]!).waitForExistence(timeout: 3), app.debugDescription)
        alert(L["discardSelTitle"]!).buttons[L["discardSelConfirm"]!].tap()
        XCTAssertTrue(editName.waitForExistence(timeout: 5))
        XCTAssertEqual(editName.value as? String, "Edit me")
        app.buttons["renewal.favorite.editCancel"].tap()
        XCTAssertTrue(addSelected().waitForExistence(timeout: 5))
        XCTAssertFalse(favoriteRow("Fixed").isSelected, "selection was discarded for editing")
        app.buttons[L["cancel"]!].tap()
    }

    /// Real afterReplace failure on a batch add: unconfirmed, tabs and inputs
    /// locked, and the reconfirm closes the sheet because the batch landed.
    func test35FavoritesBatchPendingReal() {
        configure()
        app.launchArguments += ["-HelloProteinFailAfterReplaceOnce", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 10))
        let before = homeRowCount("닭가슴살")
        openAddSheet()
        favoritesTab()
        favoriteRow("닭가슴살").tap()
        addSelected().tap()
        XCTAssertTrue(alert(L["unconfirmed"]!).waitForExistence(timeout: 5), app.debugDescription)
        alert(L["unconfirmed"]!).buttons[L["ok"]!].tap()
        XCTAssertTrue(app.buttons["renewal.reconfirm.sheet"].waitForExistence(timeout: 3))
        XCTAssertFalse(addSelected().isEnabled)
        XCTAssertFalse(app.buttons["renewal.add.tab.manual"].isEnabled, "tabs locked while pending")
        capture("favorites-pending")
        app.buttons["renewal.reconfirm.sheet"].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5), "batch confirmed: the sheet closes")
        XCTAssertEqual(homeRowCount("닭가슴살"), before + 1)
        capture("favorites-pending-confirmed")
    }

    /// DEBUG read-failure double on a favorite edit: the reconfirm failure keeps
    /// the pending state; the next reconfirm succeeds and returns to the list
    /// without closing the add sheet.
    func test36FavoriteEditPendingReadFailure() {
        configure()
        app.launchArguments += ["-HelloProteinSaveOutcomeOnce", "readFailure"]
        app.launch()
        openAddSheet()
        favoritesTab()
        favoriteEditButton("그릭요거트").tap()
        let editProtein = app.textFields["renewal.favorite.editProtein"]
        XCTAssertTrue(editProtein.waitForExistence(timeout: 5))
        XCTAssertEqual(editProtein.value as? String, "9")
        app.buttons["renewal.favorite.editSave"].tap()
        XCTAssertTrue(alert(L["unconfirmed"]!).waitForExistence(timeout: 5), app.debugDescription)
        alert(L["unconfirmed"]!).buttons[L["ok"]!].tap()
        XCTAssertTrue(app.buttons["renewal.reconfirm.sheet"].waitForExistence(timeout: 3))
        app.buttons["renewal.reconfirm.sheet"].tap()
        XCTAssertTrue(alert(L["reconfirmFailed"]!).waitForExistence(timeout: 5), app.debugDescription)
        capture("favorite-edit-read-failed")
        alert(L["reconfirmFailed"]!).buttons[L["ok"]!].tap()
        XCTAssertTrue(app.buttons["renewal.reconfirm.sheet"].waitForExistence(timeout: 3), "still pending")
        app.buttons["renewal.reconfirm.sheet"].tap()
        XCTAssertTrue(addSelected().waitForExistence(timeout: 5), "edit confirmed: back to the list, sheet still open")
        XCTAssertFalse(app.textFields["renewal.favorite.editProtein"].exists)
        XCTAssertTrue(favoriteRow("그릭요거트").exists)
        capture("favorite-edit-pending-confirmed")
        app.buttons[L["cancel"]!].tap()
    }

    /// DEBUG not-applied double on a favorite delete: the row stays, the sheet
    /// stays open, and the delete can be repeated.
    func test37FavoriteDeleteNotApplied() {
        configure()
        app.launch()
        let name = "Tmp \(Int(Date().timeIntervalSince1970) % 100000)"
        addManualFavorite(name: name, protein: "2")
        app.terminate()
        configure()
        app.launchArguments += ["-HelloProteinSaveOutcomeOnce", "notApplied"]
        app.launch()
        openAddSheet()
        favoritesTab()
        XCTAssertTrue(favoriteRow(name).waitForExistence(timeout: 5), app.debugDescription)
        favoriteDeleteButton(name).tap()
        XCTAssertTrue(alert(L["favDeleteTitle"]!).waitForExistence(timeout: 3))
        alert(L["favDeleteTitle"]!).buttons[L["favDeleteConfirm"]!].tap()
        XCTAssertTrue(alert(L["unconfirmed"]!).waitForExistence(timeout: 5), app.debugDescription)
        alert(L["unconfirmed"]!).buttons[L["ok"]!].tap()
        XCTAssertTrue(app.buttons["renewal.reconfirm.sheet"].waitForExistence(timeout: 3))
        app.buttons["renewal.reconfirm.sheet"].tap()
        XCTAssertTrue(alert(L["notSaved"]!).waitForExistence(timeout: 5), app.debugDescription)
        capture("favorite-delete-not-applied")
        alert(L["notSaved"]!).buttons[L["ok"]!].tap()
        XCTAssertTrue(favoriteRow(name).exists, "row kept: nothing was removed")
        XCTAssertTrue(addSelected().exists)
        favoriteDeleteButton(name).tap()
        alert(L["favDeleteTitle"]!).buttons[L["favDeleteConfirm"]!].tap()
        XCTAssertTrue(waitUntil(timeout: 5) { self.favoriteRowCount(name) == 0 })
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5))
        XCTAssertEqual(homeRowCount(name), 1, "the record stays")
    }

    func test38FavoritesKoreanLargeText() {
        ko = true
        contentSize = "UICTContentSizeCategoryAccessibilityXL"
        configure()
        app.launch()
        openAddSheet()
        XCTAssertTrue(app.buttons["renewal.add.tab.favorites"].isHittable)
        favoritesTab()
        XCTAssertTrue(favoriteRow("닭가슴살").waitForExistence(timeout: 5), app.debugDescription)
        capture("favorites-ko-ax3")
        favoriteRow("닭가슴살").tap()
        XCTAssertTrue(addSelected().isEnabled)
        capture("favorites-ko-ax3-selected")
        app.buttons[L["cancel"]!].tap()
        XCTAssertTrue(alert(L["discardTitle"]!).waitForExistence(timeout: 3), app.debugDescription)
        capture("favorites-ko-ax3-discard")
        alert(L["discardTitle"]!).buttons[L["discard"]!].tap()
        XCTAssertTrue(app.buttons["renewal.add"].waitForExistence(timeout: 5))
    }
}
