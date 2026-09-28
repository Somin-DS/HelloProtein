import XCTest
@testable import HelloProteinCore

final class RecordDomainTests: XCTestCase {
    private let day = try! CalendarDay(iso8601: "2026-09-28")

    private func record(id: String = "record-1", protein: Int64 = 1_250) throws -> FoodRecord {
        try FoodRecord(
            id: id,
            day: day,
            name: " Egg ",
            quantity: FoodQuantity(value: "100.5", unit: .gram),
            protein: ProteinAmount(centigrams: protein),
            source: .manual
        )
    }

    func testCalendarDayRejectsImpossibleAndNonCanonicalDates() throws {
        XCTAssertThrowsError(try CalendarDay(iso8601: "2026-02-29"))
        XCTAssertThrowsError(try CalendarDay(iso8601: "2026-9-28"))
        XCTAssertEqual(try CalendarDay(iso8601: "2024-02-29").iso8601, "2024-02-29")
    }

    func testAddUpdateDeleteRecalculatesTotalFromRecords() throws {
        var log = try DailyLog(day: day)
        try log.add(record())
        try log.add(record(id: "record-2", protein: 750))
        XCTAssertEqual(try log.totalProteinCentigrams(), 2_000)

        try log.update(record(id: "record-1", protein: 2_000))
        XCTAssertEqual(try log.totalProteinCentigrams(), 2_750)

        let deleted = try log.delete(id: "record-2")
        XCTAssertEqual(deleted.id, "record-2")
        XCTAssertEqual(try log.totalProteinCentigrams(), 2_000)
    }

    func testLegacyAggregateStaysSeparateWhenNewDetailsAreAdded() throws {
        var log = try DailyLog(
            day: day,
            legacyAdjustmentCentigrams: 5_500
        )
        XCTAssertEqual(log.detailState, .legacyTotalOnly)
        try log.add(record(protein: 1_000))
        XCTAssertEqual(log.detailState, .legacyTotalWithNewDetails)
        XCTAssertEqual(try log.totalProteinCentigrams(), 6_500)
    }

    func testRecordCannotMoveToAnotherDayThroughWrongLog() throws {
        let otherDay = try CalendarDay(iso8601: "2026-09-27")
        let wrongRecord = try FoodRecord(
            id: "wrong-day", day: otherDay, name: nil, quantity: nil,
            protein: ProteinAmount(centigrams: 100), source: .manual
        )
        var log = try DailyLog(day: day)
        XCTAssertThrowsError(try log.add(wrongRecord)) {
            XCTAssertEqual($0 as? RecordDomainError, .dayMismatch)
        }
    }

    func testDuplicateAndMissingIDsAreRejected() throws {
        var log = try DailyLog(day: day, records: [record()])
        XCTAssertThrowsError(try log.add(record())) {
            XCTAssertEqual($0 as? RecordDomainError, .duplicateRecordID)
        }
        XCTAssertThrowsError(try log.delete(id: "missing")) {
            XCTAssertEqual($0 as? RecordDomainError, .recordNotFound)
        }
    }

    func testNewRecordRequiresPositiveProteinButNameAndQuantityAreOptional() throws {
        XCTAssertNoThrow(try FoodRecord(
            id: "protein-only", day: day, name: nil, quantity: nil,
            protein: ProteinAmount(centigrams: 1), source: .manual
        ))
        XCTAssertThrowsError(try FoodRecord(
            id: "zero", day: day, name: nil, quantity: nil,
            protein: .zero, source: .manual
        )) {
            XCTAssertEqual($0 as? RecordDomainError, .zeroProtein)
        }
    }

    func testGoalChangesApplyFromTheirDateWithoutRewritingPast() throws {
        let old = try ProteinGoal(
            id: "goal-1", effectiveFrom: CalendarDay(iso8601: "2026-01-01"),
            amount: ProteinAmount(centigrams: 10_000)
        )
        let new = try ProteinGoal(
            id: "goal-2", effectiveFrom: CalendarDay(iso8601: "2026-09-01"),
            amount: ProteinAmount(centigrams: 12_000)
        )
        XCTAssertEqual(
            try GoalHistory.goal(on: try CalendarDay(iso8601: "2026-08-31"), from: [new, old]),
            old
        )
        XCTAssertEqual(try GoalHistory.goal(on: day, from: [old, new]), new)
        XCTAssertNil(try GoalHistory.goal(on: try CalendarDay(iso8601: "2025-12-31"), from: [old, new]))
    }

    func testTotalOverflowDoesNotMutateLog() throws {
        var log = try DailyLog(
            day: day,
            legacyAdjustmentCentigrams: Int64.max
        )
        XCTAssertThrowsError(try log.add(record(protein: 1))) {
            XCTAssertEqual($0 as? RecordDomainError, .arithmeticOverflow)
        }
        XCTAssertTrue(log.records.isEmpty)
        XCTAssertEqual(try log.totalProteinCentigrams(), Int64.max)
    }

    func testPortableJSONRoundTripPreservesState() throws {
        let log = try DailyLog(day: day, records: [record()], legacyAdjustmentCentigrams: 500)
        let data = try JSONEncoder().encode(log)
        XCTAssertEqual(log, try JSONDecoder().decode(DailyLog.self, from: data))
    }

    func testDecodingCannotBypassDomainValidation() throws {
        let invalidDay = Data(#""2026-02-29""#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CalendarDay.self, from: invalidDay))

        let negativeProtein = Data("-1".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ProteinAmount.self, from: negativeProtein))
    }

    func testSignedLegacyAdjustmentPreservesInconsistentOldTotal() throws {
        let log = try DailyLog(
            day: day,
            records: [record(protein: 2_000)],
            legacyAdjustmentCentigrams: -500
        )
        XCTAssertEqual(try log.totalProteinCentigrams(), 1_500)
        XCTAssertEqual(log.detailState, .legacyTotalWithNewDetails)
    }
}
