import XCTest
import HelloProteinCore
@testable import MigrationCore

final class LegacyStateMapperTests: XCTestCase {
    private let migratedOn = try! CalendarDay(iso8601: "2026-09-28")
    private var context: LegacyStateMapper.Context {
        .init(migratedOn: migratedOn, completedAt: "2026-09-28T10:00:00.000Z", migrationVersion: 1, sourceFingerprint: "fp")
    }

    private func snapshot() -> LegacySnapshot {
        LegacySnapshot(
            lastSavedDay: "2026-09-23", savedDayLabel: "2026-09-23-Tue", savedDateInstant: "2026-09-23T01:23:45.000Z",
            currentTotal: 55,
            foods: [.init(id: "f1", name: "우유", protein: 10, position: 0), .init(id: "f2", name: " 계란 ", protein: 35, position: 1)],
            history: [.init(id: "s1", day: "2026-09-20", total: 70, originalLabel: "2026-09-20-Sun", originalDateInstant: "2026-09-20T12:00:00.000Z", position: 0)],
            favorites: [.init(id: "v1", name: "Protein", protein: 25, position: 0), .init(id: "v0", name: "Zero", protein: 0, position: 1)],
            searchHistory: [.init(id: "q1", value: "egg", position: 0), .init(id: "q2", value: "egg", position: 1)],
            target: "120", searchLanguage: "Korean(한글)"
        )
    }

    private func map(_ snapshot: LegacySnapshot) throws -> AppState {
        try LegacyStateMapper.map(try LegacyMigration.prepare(snapshot), context: context)
    }

    func testFullMappingPreservesIDsOrderValuesAndTotals() throws {
        let state = try map(snapshot())
        XCTAssertEqual(state.logs.map(\.day.iso8601), ["2026-09-20", "2026-09-23"])

        let current = try XCTUnwrap(state.log(for: CalendarDay(iso8601: "2026-09-23")))
        XCTAssertEqual(current.records.map(\.id), ["legacy:daily:f1", "legacy:daily:f2"])
        XCTAssertEqual(current.records.map(\.legacySourceID), ["f1", "f2"])
        XCTAssertEqual(current.records.map(\.name), ["우유", "계란"])
        XCTAssertEqual(current.records.map(\.source), [.legacy, .legacy])
        XCTAssertEqual(current.legacyAdjustmentCentigrams, 1_000)
        XCTAssertEqual(try current.totalProteinCentigrams(), 5_500)
        XCTAssertEqual(current.legacyAggregate?.sourceID, "legacy:defaults:totalIntake")
        XCTAssertEqual(current.legacyAggregate?.importedTotalCentigrams, 5_500)
        XCTAssertEqual(current.legacyAggregate?.importedDetailSumCentigrams, 4_500)
        XCTAssertEqual(current.legacyAggregate?.originalLabel, "2026-09-23-Tue")
        XCTAssertEqual(current.detailState, .legacyTotalWithNewDetails)

        let history = try XCTUnwrap(state.log(for: CalendarDay(iso8601: "2026-09-20")))
        XCTAssertEqual(history.detailState, .legacyTotalOnly)
        XCTAssertTrue(history.records.isEmpty, "no food details are invented")
        XCTAssertEqual(try history.totalProteinCentigrams(), 7_000)
        XCTAssertEqual(history.legacyAggregate?.sourceID, "legacy:stat:s1")
        XCTAssertEqual(history.legacyAggregate?.originalInstant, "2026-09-20T12:00:00.000Z")

        XCTAssertEqual(state.favorites.map(\.id), ["legacy:favorite:v1", "legacy:favorite:v0"])
        XCTAssertEqual(state.favorites.map(\.proteinCentigrams), [2_500, 0], "favorites are kept verbatim")
        XCTAssertEqual(state.searchHistory.map(\.value), ["egg", "egg"], "no dedupe")
        XCTAssertEqual(state.searchHistory.map(\.position), [0, 1])
        XCTAssertEqual(state.settings.legacyTargetRaw, "120")
        XCTAssertEqual(state.settings.searchLanguage.resolved, .korean)
        XCTAssertFalse(state.settings.searchLanguage.isFallback)
        XCTAssertEqual(state.goals.count, 1)
        XCTAssertEqual(state.goals[0].effectiveFrom, migratedOn)
        XCTAssertEqual(state.goals[0].amount.centigrams, 12_000)
        XCTAssertNil(try state.goal(on: CalendarDay(iso8601: "2026-09-23")), "no goal history before migration day")
        XCTAssertEqual(state.migration.origin, .legacyImport)
        XCTAssertEqual(state.migration.sourceFingerprint, "fp")
        XCTAssertEqual(state.migration.verification?.legacyFoodCount, 2)
        XCTAssertEqual(state.migration.verification?.legacyCurrentTotalCentigrams, 5_500)
        XCTAssertEqual(state.migration.verification?.legacyHistoryTotalCentigrams, 7_000)
        XCTAssertTrue(LegacyStateMapper.verify(state, against: try LegacyMigration.prepare(snapshot())).isEmpty)
    }

    func testMappingIsDeterministicAcrossRuns() throws {
        XCTAssertEqual(try map(snapshot()), try map(snapshot()))
    }

    func testNegativeAndZeroAdjustmentsAreKeptWithoutClamping() throws {
        var source = snapshot()
        source.currentTotal = 15  // details sum to 45
        let negative = try map(source)
        let day = try CalendarDay(iso8601: "2026-09-23")
        XCTAssertEqual(negative.log(for: day)?.legacyAdjustmentCentigrams, -3_000)
        XCTAssertEqual(try negative.log(for: day)?.totalProteinCentigrams(), 1_500)

        source.currentTotal = 45
        let zero = try map(source)
        XCTAssertEqual(zero.log(for: day)?.legacyAdjustmentCentigrams, 0)
        XCTAssertEqual(zero.log(for: day)?.detailState, .legacyTotalWithNewDetails)
    }

    func testLegacyTotalEditAfterImportRecalculatesAdjustment() throws {
        // Past day with 70 g only; add 10 g, then set the total to 75 g.
        let state = try map(snapshot())
        let day = try CalendarDay(iso8601: "2026-09-20")
        var log = try XCTUnwrap(state.log(for: day))
        try log.add(FoodRecord(id: "new", day: day, name: nil, quantity: nil, protein: ProteinAmount(centigrams: 1_000), source: .manual))
        XCTAssertEqual(try log.totalProteinCentigrams(), 8_000)
        try log.setLegacyDailyTotal(7_500)
        XCTAssertEqual(log.legacyAdjustmentCentigrams, 6_500)
        XCTAssertEqual(log.legacyAggregate?.importedTotalCentigrams, 7_000)
        XCTAssertEqual(log.legacyAggregate?.userEditedTotalCentigrams, 7_500)
    }

    func testZeroOrNegativeFoodStopsMappingInsteadOfDroppingOrClamping() throws {
        for protein in [0, -3] {
            var source = snapshot()
            source.foods[1].protein = protein
            XCTAssertThrowsError(try map(source)) {
                XCTAssertEqual($0 as? MappingError, .unrepresentableFood(id: "f2", protein: protein))
            }
        }
    }

    func testCentigramConversionChecksOverflowWithoutDouble() throws {
        var source = snapshot()
        source.history[0].total = Int(Int64.max / 100) + 1
        XCTAssertThrowsError(try map(source)) {
            if case .arithmeticOverflow? = $0 as? MappingError {} else { XCTFail("\($0)") }
        }
        source.history[0].total = Int(Int64.max / 100)
        XCTAssertNoThrow(try map(source))
    }

    func testInvalidTargetKeepsRawTextAndFlagsReview() throws {
        for target in ["1e2", "-5", "12.345", "abc", "1,234", "0"] {
            var source = snapshot()
            source.target = target
            let state = try map(source)
            XCTAssertTrue(state.goals.isEmpty, target)
            XCTAssertTrue(state.settings.goalNeedsReview, target)
            XCTAssertEqual(state.settings.legacyTargetRaw, target)
            XCTAssertEqual(state.logs.count, 2, "records are never hidden because of the goal")
        }
        var source = snapshot()
        source.target = "120.5"
        XCTAssertEqual(try map(source).goals.first?.amount.centigrams, 12_050)
    }

    func testUnsupportedSearchLanguageKeepsRawWithExplicitFallback() throws {
        var source = snapshot()
        source.searchLanguage = "Deutsch"
        let setting = try map(source).settings.searchLanguage
        XCTAssertEqual(setting.raw, "Deutsch")
        XCTAssertEqual(setting.resolved, .english)
        XCTAssertTrue(setting.isFallback)
    }

    func testEmptyCurrentDayDoesNotCreateAZeroLog() throws {
        var source = snapshot()
        source.foods = []
        source.currentTotal = 0
        let state = try map(source)
        XCTAssertEqual(state.logs.map(\.day.iso8601), ["2026-09-20"])
        XCTAssertEqual(state.migration.verification?.legacyCurrentTotalCentigrams, nil)
    }

    func testFreshInstallClassificationProducesFreshOrigin() throws {
        let source = LegacySnapshot(lastSavedDay: nil, savedDayLabel: nil, savedDateInstant: nil, currentTotal: 0,
                                    foods: [], history: [], favorites: [], searchHistory: [], target: nil, searchLanguage: "English(영어)")
        let state = try map(source)
        XCTAssertEqual(state.migration.origin, .freshInstall)
        XCTAssertTrue(state.logs.isEmpty)
        XCTAssertEqual(state.settings.searchLanguage.raw, "English(영어)")
    }

    func testVerifyDetectsTamperedStore() throws {
        let plan = try LegacyMigration.prepare(snapshot())
        var state = try LegacyStateMapper.map(plan, context: context)
        let day = try CalendarDay(iso8601: "2026-09-20")
        var log = try XCTUnwrap(state.log(for: day))
        try log.setLegacyDailyTotal(100)
        try state.upsert(log)
        XCTAssertEqual(LegacyStateMapper.verify(state, against: plan), ["history s1 total"])
    }
}
