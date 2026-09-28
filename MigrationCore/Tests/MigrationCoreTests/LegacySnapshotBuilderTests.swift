import XCTest
@testable import MigrationCore

final class LegacySnapshotBuilderTests: XCTestCase {
    func testExtractsNumericDayWithoutDependingOnLocalizedWeekday() throws {
        let raw = RawLegacyData(
            savedDayLabel: "2026-09-28-lun.",
            savedDate: Date(timeIntervalSince1970: 1_759_018_625.125),
            currentTotal: 30,
            foods: [.init(id: "food", name: "Egg", protein: 10)],
            history: [.init(id: "history", dayLabel: "2026-09-27-일",
                            storedDate: Date(timeIntervalSince1970: 1_758_931_200), total: 20)],
            favorites: [.init(id: "favorite", name: "Milk", protein: 8)],
            searchHistory: [.init(id: "search", value: "egg")],
            target: "100",
            searchLanguage: "English(영어)"
        )

        let snapshot = LegacySnapshotBuilder.build(from: raw)
        XCTAssertEqual(snapshot.lastSavedDay, "2026-09-28")
        XCTAssertEqual(snapshot.history[0].day, "2026-09-27")
        XCTAssertEqual(snapshot.foods[0].position, 0)
        XCTAssertEqual(snapshot.searchHistory[0].value, "egg")
        XCTAssertTrue(snapshot.savedDateInstant?.hasSuffix("Z") == true)
    }

    func testInvalidLabelIsCapturedFirstAndRejectedOnlyByValidation() {
        let raw = RawLegacyData(
            savedDayLabel: "28 septembre 2026",
            savedDate: Date(),
            currentTotal: 10,
            foods: [.init(id: "food", name: "Egg", protein: 10)],
            history: [], favorites: [], searchHistory: [],
            target: nil, searchLanguage: nil
        )
        // Capture never fails on content: the original label survives for backup.
        let snapshot = LegacySnapshotBuilder.build(from: raw)
        XCTAssertNil(snapshot.lastSavedDay)
        XCTAssertEqual(snapshot.savedDayLabel, "28 septembre 2026")
        XCTAssertEqual(snapshot.foods.count, 1)
        XCTAssertThrowsError(try LegacyMigration.prepare(snapshot)) {
            XCTAssertEqual($0 as? MigrationError, .missingLastSavedDay)
        }
    }

    func testNonASCIIDigitsInLabelAreNotADay() {
        let raw = RawLegacyData(
            savedDayLabel: "２０２６-09-28-Mon", savedDate: nil, currentTotal: 0,
            foods: [], history: [.init(id: "h", dayLabel: "٢٠٢٦-09-27-Sun", storedDate: Date(), total: 5)],
            favorites: [], searchHistory: [], target: nil, searchLanguage: nil
        )
        let snapshot = LegacySnapshotBuilder.build(from: raw)
        XCTAssertNil(snapshot.lastSavedDay)
        XCTAssertEqual(snapshot.history[0].day, "")
        XCTAssertThrowsError(try LegacyMigration.prepare(snapshot)) {
            XCTAssertEqual($0 as? MigrationError, .invalidDay(""))
        }
    }

    func testPreservesRealmEnumerationOrder() throws {
        let raw = RawLegacyData(
            savedDayLabel: "2026-09-28-Mon", savedDate: nil, currentTotal: 3,
            foods: [
                .init(id: "z", name: "First", protein: 1),
                .init(id: "a", name: "Second", protein: 2)
            ],
            history: [], favorites: [], searchHistory: [],
            target: nil, searchLanguage: nil
        )
        let snapshot = LegacySnapshotBuilder.build(from: raw)
        XCTAssertEqual(snapshot.foods.map(\.id), ["z", "a"])
        XCTAssertEqual(snapshot.foods.map(\.position), [0, 1])
    }
}
