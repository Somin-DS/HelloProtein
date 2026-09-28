import Foundation

/// Value copies only. The native reader must capture these before any rollover
/// deletes DailyProtein rows. This module never opens or mutates a Realm file.
public struct LegacySnapshot: Codable, Equatable {
    /// The day last stored by the old app. It must never be replaced with the
    /// day on which migration happens.
    public var lastSavedDay: String?
    public var savedDayLabel: String?
    public var savedDateInstant: String?
    public var currentTotal: Int?
    public var foods: [Food]
    public var history: [HistoricalTotal]
    public var favorites: [Food]
    public var searchHistory: [SearchTerm]
    public var target: String?
    public var searchLanguage: String?

    public init(lastSavedDay: String?, savedDayLabel: String?, savedDateInstant: String?,
                currentTotal: Int?, foods: [Food],
                history: [HistoricalTotal], favorites: [Food], searchHistory: [SearchTerm],
                target: String?, searchLanguage: String?) {
        self.lastSavedDay = lastSavedDay
        self.savedDayLabel = savedDayLabel
        self.savedDateInstant = savedDateInstant
        self.currentTotal = currentTotal
        self.foods = foods
        self.history = history
        self.favorites = favorites
        self.searchHistory = searchHistory
        self.target = target
        self.searchLanguage = searchLanguage
    }

    public struct Food: Codable, Equatable {
        public var id: String
        public var name: String
        public var protein: Int
        public var position: Int

        public init(id: String, name: String, protein: Int, position: Int = 0) {
            self.id = id
            self.name = name
            self.protein = protein
            self.position = position
        }
    }

    public struct HistoricalTotal: Codable, Equatable {
        public var id: String
        /// Gregorian yyyy-MM-dd, normalized by the native reader.
        public var day: String
        public var total: Int
        /// Preserve the original localized date label for diagnostics.
        public var originalLabel: String
        public var originalDateInstant: String?
        public var position: Int

        public init(id: String, day: String, total: Int, originalLabel: String,
                    originalDateInstant: String? = nil, position: Int = 0) {
            self.id = id
            self.day = day
            self.total = total
            self.originalLabel = originalLabel
            self.originalDateInstant = originalDateInstant
            self.position = position
        }
    }

    public struct SearchTerm: Codable, Equatable {
        public var id: String
        public var value: String
        public var position: Int

        public init(id: String, value: String, position: Int = 0) {
            self.id = id
            self.value = value
            self.position = position
        }
    }

    /// Whether the old app ever held user data. A `date`/`Date`/`totalIntake == 0`
    /// residue from merely opening the old home screen does not make a user.
    public var classification: LegacySourceClassification {
        if !foods.isEmpty || !history.isEmpty || !favorites.isEmpty || !searchHistory.isEmpty {
            return .existingUser
        }
        if target != nil { return .existingUser }
        if let total = currentTotal, total != 0 { return .existingUser }
        return .freshInstall
    }

    /// True when the current-day part carries nothing worth a log entry.
    public var currentDayIsEmpty: Bool {
        foods.isEmpty && (currentTotal ?? 0) == 0
    }
}

public enum LegacySourceClassification: String, Codable, Equatable {
    case freshInstall
    case existingUser
}

/// Portable handoff format for the future iOS/Android store.
/// Re-import by stable ID (upsert), never by appending rows.
public struct MigrationPlan: Codable, Equatable {
    public let schemaVersion: Int
    public let lastSavedDay: String?
    public let savedDayLabel: String?
    public let savedDateInstant: String?
    public let currentFoods: [LegacySnapshot.Food]
    public let currentTotal: Int?
    /// Keeps UserDefaults' total intact when it differs from surviving details.
    /// Future total = sum(currentFoods) + this adjustment. It is not a food.
    public let currentAdjustment: Int?
    /// Do not synthesize food entries from aggregate-only historical records.
    public let historicalTotals: [LegacySnapshot.HistoricalTotal]
    public let favorites: [LegacySnapshot.Food]
    public let searchHistory: [LegacySnapshot.SearchTerm]
    public let target: String?
    public let searchLanguage: String?
    public let classification: LegacySourceClassification
}

public enum MigrationError: Error, Equatable {
    case missingLastSavedDay
    case missingCurrentTotal
    case invalidDay(String)
    case invalidID
    case duplicateID(String)
    case ambiguousHistoricalDay(String)
    case overlappingLastSavedDay(String)
    case arithmeticOverflow
}

public enum LegacyMigration {
    public static func prepare(_ snapshot: LegacySnapshot) throws -> MigrationPlan {
        if snapshot.lastSavedDay == nil, !snapshot.currentDayIsEmpty {
            // Foods or a non-zero total without a day are real records with no
            // date evidence. They must not move to the migration day.
            throw MigrationError.missingLastSavedDay
        }
        if !snapshot.foods.isEmpty && snapshot.currentTotal == nil {
            throw MigrationError.missingCurrentTotal
        }
        if let day = snapshot.lastSavedDay { try validateDay(day) }
        try validateIDs(snapshot.foods.map(\.id))
        try validateIDs(snapshot.favorites.map(\.id))
        try validateIDs(snapshot.history.map(\.id))
        try validateIDs(snapshot.searchHistory.map(\.id))

        var days = Set<String>()
        for row in snapshot.history {
            try validateDay(row.day)
            guard days.insert(row.day).inserted else {
                // No evidence whether duplicate legacy sums are additive or
                // retries. Stop instead of silently losing/doubling intake.
                throw MigrationError.ambiguousHistoricalDay(row.day)
            }
            if row.day == snapshot.lastSavedDay, !snapshot.currentDayIsEmpty {
                throw MigrationError.overlappingLastSavedDay(row.day)
            }
        }

        var sum = 0
        for food in snapshot.foods {
            let result = sum.addingReportingOverflow(food.protein)
            guard !result.overflow else { throw MigrationError.arithmeticOverflow }
            sum = result.partialValue
        }
        var adjustment: Int?
        if let total = snapshot.currentTotal {
            let result = total.subtractingReportingOverflow(sum)
            guard !result.overflow else { throw MigrationError.arithmeticOverflow }
            adjustment = result.partialValue
        }

        return MigrationPlan(
            schemaVersion: 1,
            lastSavedDay: snapshot.lastSavedDay,
            savedDayLabel: snapshot.savedDayLabel,
            savedDateInstant: snapshot.savedDateInstant,
            currentFoods: snapshot.foods,
            currentTotal: snapshot.currentTotal,
            currentAdjustment: adjustment,
            historicalTotals: snapshot.history,
            favorites: snapshot.favorites,
            searchHistory: snapshot.searchHistory,
            target: snapshot.target,
            searchLanguage: snapshot.searchLanguage,
            classification: snapshot.classification
        )
    }

    private static func validateIDs(_ ids: [String]) throws {
        var seen = Set<String>()
        for id in ids {
            guard !id.isEmpty else { throw MigrationError.invalidID }
            guard seen.insert(id).inserted else { throw MigrationError.duplicateID(id) }
        }
    }

    private static func validateDay(_ day: String) throws {
        let scalars = Array(day.unicodeScalars)
        guard scalars.count == 10, scalars[4] == "-", scalars[7] == "-" else {
            throw MigrationError.invalidDay(day)
        }
        for (index, scalar) in scalars.enumerated() where index != 4 && index != 7 {
            guard scalar.isASCII, ("0"..."9").contains(scalar) else { throw MigrationError.invalidDay(day) }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: day),
              formatter.string(from: date) == day,
              day.prefix(4) != "0000" else {
            throw MigrationError.invalidDay(day)
        }
    }
}
