import Foundation

/// A favorite keeps the old app's value verbatim (signed grams as centigrams)
/// so that migration never drops or clamps it. Validation happens when a
/// favorite is turned into a `FoodRecord`.
public struct FavoriteFood: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let proteinCentigrams: Int64
    public let position: Int
    public let legacySourceID: String?

    public init(id: String, name: String, proteinCentigrams: Int64, position: Int, legacySourceID: String? = nil) throws {
        guard !id.isEmpty else { throw RecordDomainError.emptyID }
        self.id = id
        self.name = name
        self.proteinCentigrams = proteinCentigrams
        self.position = position
        self.legacySourceID = legacySourceID
    }

    private enum CodingKeys: String, CodingKey { case id, name, proteinCentigrams, position, legacySourceID }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            proteinCentigrams: container.decode(Int64.self, forKey: .proteinCentigrams),
            position: container.decode(Int.self, forKey: .position),
            legacySourceID: container.decodeIfPresent(String.self, forKey: .legacySourceID)
        )
    }
}

public struct SearchTerm: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let value: String
    public let position: Int
    public let legacySourceID: String?

    public init(id: String, value: String, position: Int, legacySourceID: String? = nil) throws {
        guard !id.isEmpty else { throw RecordDomainError.emptyID }
        self.id = id
        self.value = value
        self.position = position
        self.legacySourceID = legacySourceID
    }

    private enum CodingKeys: String, CodingKey { case id, value, position, legacySourceID }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            value: container.decode(String.self, forKey: .value),
            position: container.decode(Int.self, forKey: .position),
            legacySourceID: container.decodeIfPresent(String.self, forKey: .legacySourceID)
        )
    }
}

public enum SearchLanguage: String, Codable, Sendable {
    case korean
    case english
}

/// The old app stored `"Korean(한글)"` / `"English(영어)"`. Unknown raw values
/// keep the raw text and fall back explicitly.
public struct SearchLanguageSetting: Codable, Equatable, Sendable {
    public let raw: String?
    public let resolved: SearchLanguage
    public let isFallback: Bool

    public init(raw: String?, resolved: SearchLanguage, isFallback: Bool) {
        self.raw = raw
        self.resolved = resolved
        self.isFallback = isFallback
    }

    public static func interpret(raw: String?, fallback: SearchLanguage = .english) -> SearchLanguageSetting {
        switch raw {
        case "Korean(한글)": return .init(raw: raw, resolved: .korean, isFallback: false)
        case "English(영어)": return .init(raw: raw, resolved: .english, isFallback: false)
        default: return .init(raw: raw, resolved: fallback, isFallback: true)
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var searchLanguage: SearchLanguageSetting
    /// The old `targetProtein` text exactly as stored, for recovery and review.
    public var legacyTargetRaw: String?
    /// True when the old target could not be converted into a goal.
    public var goalNeedsReview: Bool

    public init(searchLanguage: SearchLanguageSetting, legacyTargetRaw: String?, goalNeedsReview: Bool) {
        self.searchLanguage = searchLanguage
        self.legacyTargetRaw = legacyTargetRaw
        self.goalNeedsReview = goalNeedsReview
    }

    public static let freshInstall = AppSettings(
        searchLanguage: .interpret(raw: nil),
        legacyTargetRaw: nil,
        goalNeedsReview: false
    )
}

/// Counts and sums recorded at migration time so a later reader can re-check
/// the store against the backup without re-running the migration.
public struct MigrationVerification: Codable, Equatable, Sendable {
    public let legacyFoodCount: Int
    public let legacyHistoryCount: Int
    public let favoriteCount: Int
    public let searchTermCount: Int
    public let legacyDayCount: Int
    public let legacyCurrentTotalCentigrams: Int64?
    public let legacyHistoryTotalCentigrams: Int64

    public init(
        legacyFoodCount: Int,
        legacyHistoryCount: Int,
        favoriteCount: Int,
        searchTermCount: Int,
        legacyDayCount: Int,
        legacyCurrentTotalCentigrams: Int64?,
        legacyHistoryTotalCentigrams: Int64
    ) {
        self.legacyFoodCount = legacyFoodCount
        self.legacyHistoryCount = legacyHistoryCount
        self.favoriteCount = favoriteCount
        self.searchTermCount = searchTermCount
        self.legacyDayCount = legacyDayCount
        self.legacyCurrentTotalCentigrams = legacyCurrentTotalCentigrams
        self.legacyHistoryTotalCentigrams = legacyHistoryTotalCentigrams
    }
}

public struct MigrationRecord: Codable, Equatable, Sendable {
    public enum Origin: String, Codable, Sendable {
        case freshInstall
        case legacyImport
        case schema1Upgrade
    }

    public let origin: Origin
    public let migrationVersion: Int
    /// ISO 8601 UTC instant of the commit that created this store.
    public let completedAt: String
    /// SHA-256 hex of the canonical legacy capture; nil for fresh installs.
    public let sourceFingerprint: String?
    public let verification: MigrationVerification?

    public init(
        origin: Origin,
        migrationVersion: Int,
        completedAt: String,
        sourceFingerprint: String?,
        verification: MigrationVerification?
    ) {
        self.origin = origin
        self.migrationVersion = migrationVersion
        self.completedAt = completedAt
        self.sourceFingerprint = sourceFingerprint
        self.verification = verification
    }
}

public enum AppStateError: Error, Equatable {
    case unsupportedSchema(Int)
    case duplicateDay(CalendarDay)
    case unsortedLogs
    case duplicateFavoriteID(String)
    case duplicateSearchTermID(String)
    case duplicateFavoritePosition(Int)
    case duplicateSearchTermPosition(Int)
    case incompleteMigrationMetadata(String)
    case goalHistory(RecordDomainError)
}

/// Schema 2: everything the app persists, committed as one document.
public struct AppState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public private(set) var logs: [DailyLog]
    public var favorites: [FavoriteFood]
    public var searchHistory: [SearchTerm]
    public var settings: AppSettings
    public private(set) var goals: [ProteinGoal]
    public let migration: MigrationRecord
    /// ID of the user operation that produced this document, or nil for
    /// migration/fresh-install documents and files written before this field
    /// existed. A retry after an unconfirmed commit compares this value to
    /// decide whether its operation already landed. Only the latest value is
    /// kept, so the field never grows.
    public var lastOperationID: String?

    public init(
        logs: [DailyLog],
        favorites: [FavoriteFood],
        searchHistory: [SearchTerm],
        settings: AppSettings,
        goals: [ProteinGoal],
        migration: MigrationRecord,
        lastOperationID: String? = nil
    ) throws {
        self.schemaVersion = Self.currentSchemaVersion
        self.logs = logs.sorted { $0.day < $1.day }
        self.favorites = favorites
        self.searchHistory = searchHistory
        self.settings = settings
        self.goals = goals.sorted { $0.effectiveFrom < $1.effectiveFrom }
        self.migration = migration
        self.lastOperationID = lastOperationID
        try validate()
    }

    public static func freshInstall(completedAt: String, migrationVersion: Int, settings: AppSettings = .freshInstall) throws -> AppState {
        try AppState(
            logs: [],
            favorites: [],
            searchHistory: [],
            settings: settings,
            goals: [],
            migration: MigrationRecord(
                origin: .freshInstall,
                migrationVersion: migrationVersion,
                completedAt: completedAt,
                sourceFingerprint: nil,
                verification: nil
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, logs, favorites, searchHistory, settings, goals, migration, lastOperationID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw AppStateError.unsupportedSchema(version)
        }
        self.schemaVersion = version
        self.logs = try container.decode([DailyLog].self, forKey: .logs)
        self.favorites = try container.decode([FavoriteFood].self, forKey: .favorites)
        self.searchHistory = try container.decode([SearchTerm].self, forKey: .searchHistory)
        self.settings = try container.decode(AppSettings.self, forKey: .settings)
        self.goals = try container.decode([ProteinGoal].self, forKey: .goals)
        self.migration = try container.decode(MigrationRecord.self, forKey: .migration)
        // Absent in files written before operation IDs existed; nil must not change any record.
        self.lastOperationID = try container.decodeIfPresent(String.self, forKey: .lastOperationID)
        try validate()
    }

    /// Full invariant check. Decoding is not trusted on its own.
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw AppStateError.unsupportedSchema(schemaVersion)
        }
        var days = Set<CalendarDay>()
        var previous: CalendarDay?
        for log in logs {
            guard days.insert(log.day).inserted else { throw AppStateError.duplicateDay(log.day) }
            if let previous, !(previous < log.day) { throw AppStateError.unsortedLogs }
            previous = log.day
            _ = try log.totalProteinCentigrams()
        }
        var favoriteIDs = Set<String>()
        var favoritePositions = Set<Int>()
        for favorite in favorites {
            guard favoriteIDs.insert(favorite.id).inserted else {
                throw AppStateError.duplicateFavoriteID(favorite.id)
            }
            guard favoritePositions.insert(favorite.position).inserted else {
                throw AppStateError.duplicateFavoritePosition(favorite.position)
            }
        }
        var termIDs = Set<String>()
        var termPositions = Set<Int>()
        for term in searchHistory {
            guard termIDs.insert(term.id).inserted else {
                throw AppStateError.duplicateSearchTermID(term.id)
            }
            guard termPositions.insert(term.position).inserted else {
                throw AppStateError.duplicateSearchTermPosition(term.position)
            }
        }
        do { try GoalHistory.validate(goals) }
        catch let error as RecordDomainError { throw AppStateError.goalHistory(error) }
        guard migration.migrationVersion > 0 else {
            throw AppStateError.incompleteMigrationMetadata("migrationVersion")
        }
        guard !migration.completedAt.isEmpty else {
            throw AppStateError.incompleteMigrationMetadata("completedAt")
        }
        if migration.origin == .legacyImport {
            guard let fingerprint = migration.sourceFingerprint, !fingerprint.isEmpty else {
                throw AppStateError.incompleteMigrationMetadata("sourceFingerprint")
            }
            guard migration.verification != nil else {
                throw AppStateError.incompleteMigrationMetadata("verification")
            }
        }
    }

    public func log(for day: CalendarDay) -> DailyLog? {
        logs.first { $0.day == day }
    }

    /// Inserts or replaces the log for its day, keeping logs sorted and unique.
    /// An empty log without legacy data removes the day instead of storing it.
    public mutating func upsert(_ log: DailyLog) throws {
        var updated = logs.filter { $0.day != log.day }
        if log.detailState != .empty {
            updated.append(log)
            updated.sort { $0.day < $1.day }
        }
        let previous = logs
        logs = updated
        do { try validate() }
        catch {
            logs = previous
            throw error
        }
    }

    public func goal(on day: CalendarDay) throws -> ProteinGoal? {
        try GoalHistory.goal(on: day, from: goals)
    }

    public mutating func replaceGoal(on day: CalendarDay, with goal: ProteinGoal) throws {
        goals = try GoalHistory.replacingGoal(on: day, with: goal, in: goals)
    }
}
