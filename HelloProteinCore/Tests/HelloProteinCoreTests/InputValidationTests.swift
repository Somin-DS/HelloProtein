import XCTest
@testable import HelloProteinCore

final class InputValidationTests: XCTestCase {
    func testCalendarDayRejectsSignsLocalizedDigitsAndYearZero() {
        for text in ["+026-09-28", "２０２६-09-28", "0000-01-01", " 2026-09-28", "2026-09-28 ", "2026/09/28", "٢٠٢٦-09-28"] {
            XCTAssertThrowsError(try CalendarDay(iso8601: text), text)
        }
        XCTAssertThrowsError(try CalendarDay(year: 0, month: 1, day: 1))
        XCTAssertThrowsError(try CalendarDay(year: 10_000, month: 1, day: 1))
        XCTAssertEqual(try CalendarDay(iso8601: "0001-01-01").iso8601, "0001-01-01")
        XCTAssertEqual(try CalendarDay(iso8601: "9999-12-31").iso8601, "9999-12-31")
        XCTAssertEqual(try CalendarDay(iso8601: "2024-02-29").adding(days: 1)?.iso8601, "2024-03-01")
        XCTAssertEqual(try CalendarDay(iso8601: "2026-03-01").adding(days: -1)?.iso8601, "2026-02-28")
    }

    func testTodayUsesInjectedZoneAndGregorianRegardlessOfDeviceCalendar() throws {
        // 2026-09-28T23:30:00Z is already the 29th in Seoul and still the 28th in Los Angeles.
        let instant = Date(timeIntervalSince1970: 1790638200)
        XCTAssertEqual(CalendarDay.today(now: instant, timeZone: TimeZone(identifier: "Asia/Seoul")!)?.iso8601, "2026-09-29")
        XCTAssertEqual(CalendarDay.today(now: instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!)?.iso8601, "2026-09-28")
        XCTAssertEqual(CalendarDay.today(now: instant, timeZone: TimeZone(secondsFromGMT: 0)!)?.iso8601, "2026-09-28")
    }

    func testProteinInputAcceptsWholeStringOnly() throws {
        XCTAssertEqual(try ProteinInput.parse("12").centigrams, 1_200)
        XCTAssertEqual(try ProteinInput.parse("12.5").centigrams, 1_250)
        XCTAssertEqual(try ProteinInput.parse("0.05").centigrams, 5)
        XCTAssertEqual(try ProteinInput.parse(".5").centigrams, 50)
        XCTAssertEqual(try ProteinInput.parse("7.").centigrams, 700)
        XCTAssertEqual(try ProteinInput.parse(" 3 ").centigrams, 300)
        XCTAssertEqual(try ProteinInput.parse("12,5", decimalSeparator: ",").centigrams, 1_250)

        let rejected: [(String, ProteinInputError)] = [
            ("", .empty),
            ("12abc", .notANumber),
            ("1e2", .notANumber),
            ("nan", .notANumber),
            ("inf", .notANumber),
            ("+5", .notANumber),
            ("-5", .notANumber),
            ("1 2", .notANumber),
            ("１２", .notANumber),
            ("1.2.3", .notANumber),
            ("1,234", .groupingSeparatorNotAllowed),
            ("12.345", .tooManyFractionDigits),
            ("0", .notPositive),
            ("0.00", .notPositive),
            ("92233720368547758.08", .overflow),
            ("99999999999999999999", .overflow),
        ]
        for (text, expected) in rejected {
            XCTAssertThrowsError(try ProteinInput.parse(text), text) {
                XCTAssertEqual($0 as? ProteinInputError, expected, text)
            }
        }
        XCTAssertThrowsError(try ProteinInput.parse("1.234", decimalSeparator: ",")) {
            XCTAssertEqual($0 as? ProteinInputError, .groupingSeparatorNotAllowed)
        }
    }

    func testProteinFormatIsCanonicalAndSigned() {
        XCTAssertEqual(ProteinInput.format(centigrams: 1_200), "12")
        XCTAssertEqual(ProteinInput.format(centigrams: 1_250), "12.5")
        XCTAssertEqual(ProteinInput.format(centigrams: 1_205), "12.05")
        XCTAssertEqual(ProteinInput.format(centigrams: -500), "-5")
        XCTAssertEqual(ProteinInput.format(centigrams: -1, decimalSeparator: ","), "-0,01")
    }

    func testQuantityRejectsNonCanonicalDecimals() {
        for text in ["", "0", "0.0", "1e2", "١٢", "1,5", "abc", "-1", ".", "+1"] {
            XCTAssertThrowsError(try FoodQuantity(value: text, unit: .gram), text)
        }
        XCTAssertNoThrow(try FoodQuantity(value: "100.5", unit: .gram))
        XCTAssertNoThrow(try FoodQuantity(value: ".5", unit: .serving))
    }

    func testRecordChangesGoThroughValidationAndKeepIdentity() throws {
        let day = try CalendarDay(iso8601: "2026-09-28")
        let record = try FoodRecord(
            id: "legacy:daily:1", day: day, name: "Egg",
            quantity: FoodQuantity(value: "2", unit: .piece),
            protein: ProteinAmount(centigrams: 1_200), source: .legacy, legacySourceID: "1"
        )
        let changed = try record.withChanges(protein: ProteinAmount(centigrams: 1_500))
        XCTAssertEqual(changed.id, record.id)
        XCTAssertEqual(changed.quantity, record.quantity)
        XCTAssertEqual(changed.source, .legacy)
        XCTAssertEqual(changed.legacySourceID, "1")
        XCTAssertEqual(changed.name, "Egg")
        XCTAssertEqual(try record.withChanges(name: .some(nil)).name, nil)
        XCTAssertThrowsError(try record.withChanges(protein: .zero)) {
            XCTAssertEqual($0 as? RecordDomainError, .zeroProtein)
        }
    }

    func testLegacyDailyTotalEditRecomputesAdjustmentFromDetails() throws {
        let day = try CalendarDay(iso8601: "2026-09-20")
        let aggregate = try LegacyAggregate(
            sourceID: "legacy:stat:abc", importedTotalCentigrams: 7_000,
            importedDetailSumCentigrams: 0, originalLabel: "2026-09-20-Sun", originalInstant: nil
        )
        var log = try DailyLog(day: day, legacyAdjustmentCentigrams: 7_000, legacyAggregate: aggregate)
        try log.add(FoodRecord(id: "new", day: day, name: nil, quantity: nil,
                               protein: ProteinAmount(centigrams: 1_000), source: .manual))
        XCTAssertEqual(try log.totalProteinCentigrams(), 8_000)

        try log.setLegacyDailyTotal(7_500)
        XCTAssertEqual(log.legacyAdjustmentCentigrams, 6_500)
        XCTAssertEqual(try log.totalProteinCentigrams(), 7_500)
        XCTAssertEqual(log.legacyAggregate?.importedTotalCentigrams, 7_000)
        XCTAssertEqual(log.legacyAggregate?.userEditedTotalCentigrams, 7_500)

        try log.setLegacyDailyTotal(500)
        XCTAssertEqual(log.legacyAdjustmentCentigrams, -500)
        XCTAssertEqual(try log.totalProteinCentigrams(), 500)

        var plain = try DailyLog(day: day)
        XCTAssertThrowsError(try plain.setLegacyDailyTotal(100)) {
            XCTAssertEqual($0 as? RecordDomainError, .noLegacyTotal)
        }
        XCTAssertThrowsError(try DailyLog(day: day, legacyAggregate: aggregate)) {
            XCTAssertEqual($0 as? RecordDomainError, .legacyAggregateWithoutAdjustment)
        }
    }

    func testTotalEditOverflowLeavesLogUnchanged() throws {
        let day = try CalendarDay(iso8601: "2026-09-20")
        var log = try DailyLog(day: day, records: [
            FoodRecord(id: "a", day: day, name: nil, quantity: nil,
                       protein: ProteinAmount(centigrams: 10), source: .manual)
        ], legacyAdjustmentCentigrams: 5)
        XCTAssertThrowsError(try log.setLegacyDailyTotal(Int64.min)) {
            XCTAssertEqual($0 as? RecordDomainError, .arithmeticOverflow)
        }
        XCTAssertEqual(log.legacyAdjustmentCentigrams, 5)
    }

    func testDuplicateGoalDatesAreRejectedAndUserChangeReplaces() throws {
        let day = try CalendarDay(iso8601: "2026-09-01")
        let a = try ProteinGoal(id: "a", effectiveFrom: day, amount: ProteinAmount(centigrams: 10_000))
        let b = try ProteinGoal(id: "b", effectiveFrom: day, amount: ProteinAmount(centigrams: 12_000))
        XCTAssertThrowsError(try GoalHistory.goal(on: day, from: [a, b])) {
            XCTAssertEqual($0 as? RecordDomainError, .duplicateGoalEffectiveDate(day))
        }
        let replaced = try GoalHistory.replacingGoal(on: day, with: b, in: [a])
        XCTAssertEqual(replaced, [b])
    }


    func testSignedTotalAcceptsZeroAndNegativeButStaysStrict() throws {
        XCTAssertEqual(try ProteinInput.parseSignedTotal("0"), 0)
        XCTAssertEqual(try ProteinInput.parseSignedTotal("-5.5"), -550)
        XCTAssertEqual(try ProteinInput.parseSignedTotal("75"), 7_500)
        XCTAssertEqual(try ProteinInput.parseSignedTotal("-0,5", decimalSeparator: ","), -50)
        XCTAssertThrowsError(try ProteinInput.parseSignedTotal("")) { XCTAssertEqual($0 as? ProteinInputError, .empty) }
        XCTAssertThrowsError(try ProteinInput.parseSignedTotal("-")) { XCTAssertEqual($0 as? ProteinInputError, .notANumber) }
        XCTAssertThrowsError(try ProteinInput.parseSignedTotal("--1")) { XCTAssertEqual($0 as? ProteinInputError, .notANumber) }
        XCTAssertThrowsError(try ProteinInput.parseSignedTotal("+1")) { XCTAssertEqual($0 as? ProteinInputError, .notANumber) }
        XCTAssertThrowsError(try ProteinInput.parseSignedTotal("1.234")) { XCTAssertEqual($0 as? ProteinInputError, .tooManyFractionDigits) }
        // Food entries stay strictly positive.
        XCTAssertThrowsError(try ProteinInput.parse("0")) { XCTAssertEqual($0 as? ProteinInputError, .notPositive) }
        XCTAssertThrowsError(try ProteinInput.parse("-1")) { XCTAssertEqual($0 as? ProteinInputError, .notANumber) }
    }
}
