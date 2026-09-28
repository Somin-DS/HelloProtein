import Foundation
import HelloProteinCore

public enum MappingError: Error, Equatable {
    /// A legacy food with zero or negative protein cannot become a `FoodRecord`.
    /// Policy for this step: stop and keep the original, never clamp or drop.
    case unrepresentableFood(id: String, protein: Int)
    case unrepresentableHistory(id: String)
    case arithmeticOverflow(String)
    case invalidDay(String)
    case invalidState(String)
}

public enum LegacyIDs {
    public static func daily(_ id: String) -> String { "legacy:daily:\(id)" }
    public static func stat(_ id: String) -> String { "legacy:stat:\(id)" }
    public static func favorite(_ id: String) -> String { "legacy:favorite:\(id)" }
    public static func search(_ id: String) -> String { "legacy:search:\(id)" }
    public static let currentTotalSource = "legacy:defaults:totalIntake"
    public static let goal = "legacy:goal:targetProtein"
}

/// Maps a validated `MigrationPlan` onto the schema 2 `AppState`. IDs are
/// deterministic, so re-running the mapping for the same plan yields the same
/// state and never duplicates rows.
public enum LegacyStateMapper {
    public struct Context {
        public let migratedOn: CalendarDay
        public let completedAt: String
        public let migrationVersion: Int
        public let sourceFingerprint: String

        public init(migratedOn: CalendarDay, completedAt: String, migrationVersion: Int, sourceFingerprint: String) {
            self.migratedOn = migratedOn
            self.completedAt = completedAt
            self.migrationVersion = migrationVersion
            self.sourceFingerprint = sourceFingerprint
        }
    }

    public static func map(_ plan: MigrationPlan, context: Context) throws -> AppState {
        var logs: [DailyLog] = []
        var currentTotalCentigrams: Int64?
        var historyTotalCentigrams: Int64 = 0

        if let dayText = plan.lastSavedDay,
           !(plan.currentFoods.isEmpty && (plan.currentTotal ?? 0) == 0) {
            let day = try calendarDay(dayText)
            var records: [FoodRecord] = []
            for food in plan.currentFoods {
                guard food.protein > 0 else {
                    throw MappingError.unrepresentableFood(id: food.id, protein: food.protein)
                }
                records.append(try FoodRecord(
                    id: LegacyIDs.daily(food.id),
                    day: day,
                    name: food.name,
                    quantity: nil,
                    protein: ProteinAmount(centigrams: centigrams(food.protein, label: "food \(food.id)")),
                    source: .legacy,
                    legacySourceID: food.id
                ))
            }
            guard let total = plan.currentTotal, let adjustment = plan.currentAdjustment else {
                throw MappingError.invalidState("current foods without total")
            }
            let totalCentigrams = try centigrams(total, label: "totalIntake")
            let detailSum = try records.reduce(Int64(0)) { partial, record in
                let (sum, overflow) = partial.addingReportingOverflow(record.protein.centigrams)
                guard !overflow else { throw MappingError.arithmeticOverflow("detail sum") }
                return sum
            }
            let aggregate = try LegacyAggregate(
                sourceID: LegacyIDs.currentTotalSource,
                importedTotalCentigrams: totalCentigrams,
                importedDetailSumCentigrams: detailSum,
                originalLabel: plan.savedDayLabel,
                originalInstant: plan.savedDateInstant
            )
            let log: DailyLog
            do {
                log = try DailyLog(
                    day: day,
                    records: records,
                    legacyAdjustmentCentigrams: centigrams(adjustment, label: "currentAdjustment"),
                    legacyAggregate: aggregate
                )
            } catch let error as RecordDomainError where error == .arithmeticOverflow {
                throw MappingError.arithmeticOverflow("current day total")
            }
            logs.append(log)
            currentTotalCentigrams = totalCentigrams
        }

        for row in plan.historicalTotals {
            let day = try calendarDay(row.day)
            let totalCentigrams = try centigrams(row.total, label: "history \(row.id)")
            let (sum, overflow) = historyTotalCentigrams.addingReportingOverflow(totalCentigrams)
            guard !overflow else { throw MappingError.arithmeticOverflow("history sum") }
            historyTotalCentigrams = sum
            let aggregate = try LegacyAggregate(
                sourceID: LegacyIDs.stat(row.id),
                importedTotalCentigrams: totalCentigrams,
                importedDetailSumCentigrams: 0,
                originalLabel: row.originalLabel,
                originalInstant: row.originalDateInstant
            )
            logs.append(try DailyLog(day: day, records: [], legacyAdjustmentCentigrams: totalCentigrams, legacyAggregate: aggregate))
        }

        let favorites = try plan.favorites.map { food in
            try FavoriteFood(
                id: LegacyIDs.favorite(food.id),
                name: food.name,
                proteinCentigrams: centigrams(food.protein, label: "favorite \(food.id)"),
                position: food.position,
                legacySourceID: food.id
            )
        }
        let searchHistory = try plan.searchHistory.map { term in
            try SearchTerm(id: LegacyIDs.search(term.id), value: term.value, position: term.position, legacySourceID: term.id)
        }

        var goals: [ProteinGoal] = []
        var goalNeedsReview = false
        if let target = plan.target {
            if let amount = try? ProteinInput.parse(target) {
                goals.append(try ProteinGoal(id: LegacyIDs.goal, effectiveFrom: context.migratedOn, amount: amount))
            } else {
                goalNeedsReview = true
            }
        }

        let settings = AppSettings(
            searchLanguage: .interpret(raw: plan.searchLanguage),
            legacyTargetRaw: plan.target,
            goalNeedsReview: goalNeedsReview
        )
        let verification = MigrationVerification(
            legacyFoodCount: plan.currentFoods.count,
            legacyHistoryCount: plan.historicalTotals.count,
            favoriteCount: favorites.count,
            searchTermCount: searchHistory.count,
            legacyDayCount: logs.count,
            legacyCurrentTotalCentigrams: currentTotalCentigrams,
            legacyHistoryTotalCentigrams: historyTotalCentigrams
        )
        let migration = MigrationRecord(
            origin: plan.classification == .freshInstall ? .freshInstall : .legacyImport,
            migrationVersion: context.migrationVersion,
            completedAt: context.completedAt,
            sourceFingerprint: context.sourceFingerprint,
            verification: verification
        )
        do {
            return try AppState(
                logs: logs, favorites: favorites, searchHistory: searchHistory,
                settings: settings, goals: goals, migration: migration
            )
        } catch let error as AppStateError {
            throw MappingError.invalidState(String(describing: error))
        }
    }

    /// Re-checks a committed state against the plan it came from.
    public static func verify(_ state: AppState, against plan: MigrationPlan) -> [String] {
        var problems: [String] = []
        let expectedFoodIDs = plan.currentFoods.map { LegacyIDs.daily($0.id) }
        let legacyRecords = state.logs.flatMap(\.records).filter { $0.source == .legacy }
        if legacyRecords.map(\.id) != expectedFoodIDs { problems.append("legacy food ids/order") }
        for (record, food) in zip(legacyRecords, plan.currentFoods) {
            let expectedName = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if record.protein.centigrams != checkedCentigrams(food.protein) || record.name != (expectedName.isEmpty ? nil : expectedName) {
                problems.append("legacy food \(food.id) values")
            }
        }
        if let total = plan.currentTotal, let dayText = plan.lastSavedDay, let day = try? CalendarDay(iso8601: dayText),
           !(plan.currentFoods.isEmpty && total == 0) {
            if (try? state.log(for: day)?.totalProteinCentigrams()) != checkedCentigrams(total) { problems.append("current day total") }
        }
        for row in plan.historicalTotals {
            guard let day = try? CalendarDay(iso8601: row.day), let log = state.log(for: day) else {
                problems.append("history day \(row.day) missing"); continue
            }
            if (try? log.totalProteinCentigrams()) != checkedCentigrams(row.total) || log.legacyAggregate?.sourceID != LegacyIDs.stat(row.id) {
                problems.append("history \(row.id) total")
            }
        }
        if state.favorites.map(\.id) != plan.favorites.map({ LegacyIDs.favorite($0.id) }) { problems.append("favorite ids/order") }
        for (favorite, food) in zip(state.favorites, plan.favorites) where favorite.proteinCentigrams != checkedCentigrams(food.protein) || favorite.name != food.name {
            problems.append("favorite \(food.id) values")
        }
        if state.searchHistory.map(\.value) != plan.searchHistory.map(\.value) { problems.append("search history values/order") }
        if state.settings.legacyTargetRaw != plan.target { problems.append("target raw text") }
        if state.settings.searchLanguage.raw != plan.searchLanguage { problems.append("search language raw text") }
        return problems
    }

    private static func calendarDay(_ text: String) throws -> CalendarDay {
        do { return try CalendarDay(iso8601: text) }
        catch { throw MappingError.invalidDay(text) }
    }

    /// `verify` counterpart of `centigrams`: nil on overflow instead of trapping.
    private static func checkedCentigrams(_ grams: Int) -> Int64? {
        let (result, overflow) = Int64(grams).multipliedReportingOverflow(by: 100)
        return overflow ? nil : result
    }

    /// Whole grams → centigrams through Int64 with overflow checks. Never via Double.
    static func centigrams(_ grams: Int, label: String) throws -> Int64 {
        let (result, overflow) = Int64(grams).multipliedReportingOverflow(by: 100)
        guard !overflow else { throw MappingError.arithmeticOverflow(label) }
        return result
    }
}
