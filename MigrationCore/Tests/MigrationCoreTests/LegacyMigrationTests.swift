import XCTest
@testable import MigrationCore

final class LegacyMigrationTests: XCTestCase {
    private func snapshot() -> LegacySnapshot {
        LegacySnapshot(
            lastSavedDay: "2026-09-23",
            savedDayLabel: "2026-09-23-Tue",
            savedDateInstant: "2026-09-23T01:23:45Z",
            currentTotal: 55,
            foods: [.init(id: "food1", name: "우유", protein: 10)],
            history: [.init(id: "stat1", day: "2026-09-20", total: 70,
                            originalLabel: "2026-09-20-Sun")],
            favorites: [.init(id: "favorite1", name: "Protein", protein: 25)],
            searchHistory: [.init(id: "search1", value: "egg")],
            target: "120", searchLanguage: "English(영어)"
        )
    }

    func testPreservesTotalsDetailsFavoritesAndSettings() throws {
        let source = snapshot()
        let plan = try LegacyMigration.prepare(source)
        XCTAssertEqual(plan.currentFoods, source.foods)
        XCTAssertEqual(plan.currentTotal, 55)
        XCTAssertEqual(plan.currentAdjustment, 45)
        XCTAssertEqual(plan.historicalTotals, source.history)
        XCTAssertEqual(plan.favorites, source.favorites)
        XCTAssertEqual(plan.searchHistory, source.searchHistory)
        XCTAssertEqual(plan.savedDayLabel, source.savedDayLabel)
        XCTAssertEqual(plan.savedDateInstant, source.savedDateInstant)
        XCTAssertEqual(plan.target, "120")
        XCTAssertEqual(plan.searchLanguage, "English(영어)")
    }

    func testRepeatPreparationHasStableIDsAndPortableRoundTrip() throws {
        let source = snapshot()
        let plan = try LegacyMigration.prepare(source)
        XCTAssertEqual(plan, try LegacyMigration.prepare(source))
        let data = try JSONEncoder().encode(plan)
        XCTAssertEqual(plan, try JSONDecoder().decode(MigrationPlan.self, from: data))
    }

    func testFreshInstallDoesNotInventGoalOrDay() throws {
        let source = LegacySnapshot(lastSavedDay: nil, savedDayLabel: nil,
                                    savedDateInstant: nil, currentTotal: nil,
                                    foods: [], history: [], favorites: [],
                                    searchHistory: [],
                                    target: nil, searchLanguage: nil)
        let plan = try LegacyMigration.prepare(source)
        XCTAssertNil(plan.lastSavedDay)
        XCTAssertNil(plan.target)
        XCTAssertNil(plan.currentAdjustment)
    }

    func testMissingDayDoesNotAssignOldFoodToToday() {
        var source = snapshot()
        source.lastSavedDay = nil
        XCTAssertThrowsError(try LegacyMigration.prepare(source)) {
            XCTAssertEqual($0 as? MigrationError, .missingLastSavedDay)
        }
    }

    func testMissingTotalDoesNotSilentlyReplaceWithDetailSum() {
        var source = snapshot()
        source.currentTotal = nil
        XCTAssertThrowsError(try LegacyMigration.prepare(source)) {
            XCTAssertEqual($0 as? MigrationError, .missingCurrentTotal)
        }
    }

    func testAmbiguousDuplicateHistoryStopsImport() {
        var source = snapshot()
        source.history.append(.init(id: "stat2", day: "2026-09-20", total: 80,
                                    originalLabel: "2026-09-20-Sun"))
        XCTAssertThrowsError(try LegacyMigration.prepare(source)) {
            XCTAssertEqual($0 as? MigrationError, .ambiguousHistoricalDay("2026-09-20"))
        }
    }

    func testCurrentAndHistoricalOverlapStopsImport() {
        var source = snapshot()
        source.history[0].day = "2026-09-23"
        XCTAssertThrowsError(try LegacyMigration.prepare(source)) {
            XCTAssertEqual($0 as? MigrationError, .overlappingLastSavedDay("2026-09-23"))
        }
    }

    func testDuplicateFoodIDStopsImport() {
        var source = snapshot()
        source.foods.append(source.foods[0])
        XCTAssertThrowsError(try LegacyMigration.prepare(source)) {
            XCTAssertEqual($0 as? MigrationError, .duplicateID("food1"))
        }
    }

    func testRejectsImpossibleAndNoncanonicalDates() throws {
        for day in ["2026-02-29", "2026-9-23", "invalid", "2026-13-01"] {
            var source = snapshot()
            source.lastSavedDay = day
            XCTAssertThrowsError(try LegacyMigration.prepare(source), day)
        }
        var source = snapshot()
        source.lastSavedDay = "2024-02-29"
        XCTAssertNoThrow(try LegacyMigration.prepare(source))
    }

    func testNegativeLegacyValuesArePreservedRatherThanClamped() throws {
        var source = snapshot()
        source.currentTotal = -5
        let plan = try LegacyMigration.prepare(source)
        XCTAssertEqual(plan.currentAdjustment, -15)
        XCTAssertEqual(plan.currentTotal, -5)
    }

    func testEmptyCurrentDayResidueIsFreshInstallNotMissingDay() throws {
        // The old home screen writes date/Date/totalIntake=0 even with no food.
        var source = snapshot()
        source.foods = []
        source.history = []
        source.favorites = []
        source.searchHistory = []
        source.target = nil
        source.currentTotal = 0
        source.lastSavedDay = nil
        let plan = try LegacyMigration.prepare(source)
        XCTAssertEqual(plan.classification, .freshInstall)
        XCTAssertEqual(plan.currentAdjustment, 0)

        // A non-zero total without a day is a real record with no date evidence.
        source.currentTotal = 15
        XCTAssertThrowsError(try LegacyMigration.prepare(source)) {
            XCTAssertEqual($0 as? MigrationError, .missingLastSavedDay)
        }
    }

    func testGoalOrFavoritesOnlyStillCountsAsExistingUser() throws {
        var source = snapshot()
        source.foods = []
        source.history = []
        source.searchHistory = []
        source.currentTotal = 0
        source.favorites = []
        XCTAssertEqual(try LegacyMigration.prepare(source).classification, .existingUser, "target only")
        source.target = nil
        XCTAssertEqual(try LegacyMigration.prepare(source).classification, .freshInstall)
        source.favorites = [.init(id: "f", name: "Milk", protein: 8)]
        XCTAssertEqual(try LegacyMigration.prepare(source).classification, .existingUser, "favorites only")
    }

    func testEmptyCurrentDayMayShareDateWithHistory() throws {
        // After a rollover the old app stores yesterday's total in history and
        // resets today to 0; the saved day label can equal the history day.
        var source = snapshot()
        source.foods = []
        source.currentTotal = 0
        source.history[0].day = source.lastSavedDay!
        XCTAssertNoThrow(try LegacyMigration.prepare(source))
    }

    func testOverflowStopsImport() {
        var source = snapshot()
        source.foods = [.init(id: "a", name: "A", protein: Int.max),
                        .init(id: "b", name: "B", protein: 1)]
        XCTAssertThrowsError(try LegacyMigration.prepare(source)) {
            XCTAssertEqual($0 as? MigrationError, .arithmeticOverflow)
        }
    }

    func testPreservesUserVisibleOrderInsteadOfSortingByID() throws {
        var source = snapshot()
        source.foods = [
            .init(id: "z", name: "first", protein: 1, position: 0),
            .init(id: "a", name: "second", protein: 2, position: 1)
        ]
        let plan = try LegacyMigration.prepare(source)
        XCTAssertEqual(plan.currentFoods.map(\.id), ["z", "a"])
        XCTAssertEqual(plan.currentFoods.map(\.position), [0, 1])
    }
}
