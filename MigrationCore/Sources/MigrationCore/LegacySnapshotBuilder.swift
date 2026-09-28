import Foundation

/// A UserDefaults value with its runtime type preserved. `integer(forKey:)`
/// would turn a missing key or a wrong type into 0; this never does.
public enum LegacyDefaultsValue: Codable, Equatable {
    case missing
    case string(String)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
    /// Seconds since 1970 with full Double precision plus an ISO string.
    case date(secondsSince1970: Double, iso8601: String)
    case data(base64: String)
    case unsupported(typeName: String)

    private enum CodingKeys: String, CodingKey { case type, value, iso8601 }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .missing:
            try container.encode("missing", forKey: .type)
        case .string(let value):
            try container.encode("string", forKey: .type)
            try container.encode(value, forKey: .value)
        case .integer(let value):
            try container.encode("integer", forKey: .type)
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode("double", forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode("bool", forKey: .type)
            try container.encode(value, forKey: .value)
        case .date(let seconds, let iso):
            try container.encode("date", forKey: .type)
            try container.encode(seconds, forKey: .value)
            try container.encode(iso, forKey: .iso8601)
        case .data(let base64):
            try container.encode("data", forKey: .type)
            try container.encode(base64, forKey: .value)
        case .unsupported(let typeName):
            try container.encode("unsupported", forKey: .type)
            try container.encode(typeName, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "missing": self = .missing
        case "string": self = .string(try container.decode(String.self, forKey: .value))
        case "integer": self = .integer(try container.decode(Int64.self, forKey: .value))
        case "double": self = .double(try container.decode(Double.self, forKey: .value))
        case "bool": self = .bool(try container.decode(Bool.self, forKey: .value))
        case "date":
            self = .date(
                secondsSince1970: try container.decode(Double.self, forKey: .value),
                iso8601: try container.decode(String.self, forKey: .iso8601)
            )
        case "data": self = .data(base64: try container.decode(String.self, forKey: .value))
        case "unsupported": self = .unsupported(typeName: try container.decode(String.self, forKey: .value))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "unknown \(other)")
        }
    }
}

/// The five UserDefaults keys the old app wrote.
public enum LegacyDefaultsKey: String, CaseIterable, Codable {
    case savedDayLabel = "date"
    case savedDate = "Date"
    case totalIntake = "totalIntake"
    case targetProtein = "targetProtein"
    case searchLanguage = "searchLanguage"
}

public struct LegacyDefaultsTypeIssue: Codable, Equatable {
    public let key: String
    public let found: LegacyDefaultsValue

    public init(key: String, found: LegacyDefaultsValue) {
        self.key = key
        self.found = found
    }
}

/// Storage-neutral copies produced by the iOS Realm/UserDefaults reader.
/// Keeping Realm types out of this boundary makes extraction independently testable.
public struct RawLegacyData: Codable, Equatable {
    public struct Food: Codable, Equatable {
        public let id: String
        public let name: String
        public let protein: Int

        public init(id: String, name: String, protein: Int) {
            self.id = id
            self.name = name
            self.protein = protein
        }
    }

    public struct History: Codable, Equatable {
        public let id: String
        public let dayLabel: String
        public let storedDate: Date
        public let total: Int

        public init(id: String, dayLabel: String, storedDate: Date, total: Int) {
            self.id = id
            self.dayLabel = dayLabel
            self.storedDate = storedDate
            self.total = total
        }
    }

    public struct SearchTerm: Codable, Equatable {
        public let id: String
        public let value: String

        public init(id: String, value: String) {
            self.id = id
            self.value = value
        }
    }

    public let savedDayLabel: String?
    public let savedDate: Date?
    public let currentTotal: Int?
    public let foods: [Food]
    public let history: [History]
    public let favorites: [Food]
    public let searchHistory: [SearchTerm]
    public let target: String?
    public let searchLanguage: String?

    public init(
        savedDayLabel: String?, savedDate: Date?, currentTotal: Int?,
        foods: [Food], history: [History], favorites: [Food],
        searchHistory: [SearchTerm], target: String?, searchLanguage: String?
    ) {
        self.savedDayLabel = savedDayLabel
        self.savedDate = savedDate
        self.currentTotal = currentTotal
        self.foods = foods
        self.history = history
        self.favorites = favorites
        self.searchHistory = searchHistory
        self.target = target
        self.searchLanguage = searchLanguage
    }
}

/// Turns typed defaults values into the fields the old app meant, keeping a
/// list of keys whose type does not match what the old app ever wrote.
public enum LegacyDefaultsInterpreter {
    public struct Result: Equatable {
        public var savedDayLabel: String?
        public var savedDate: Date?
        public var currentTotal: Int?
        public var target: String?
        public var searchLanguage: String?
        public var issues: [LegacyDefaultsTypeIssue]
    }

    public static func interpret(_ values: [String: LegacyDefaultsValue]) -> Result {
        var result = Result(issues: [])
        func value(_ key: LegacyDefaultsKey) -> LegacyDefaultsValue { values[key.rawValue] ?? .missing }
        func issue(_ key: LegacyDefaultsKey, _ found: LegacyDefaultsValue) {
            result.issues.append(.init(key: key.rawValue, found: found))
        }

        switch value(.savedDayLabel) {
        case .missing: break
        case .string(let label): result.savedDayLabel = label
        case let other: issue(.savedDayLabel, other)
        }
        switch value(.savedDate) {
        case .missing: break
        case .date(let seconds, _): result.savedDate = Date(timeIntervalSince1970: seconds)
        case let other: issue(.savedDate, other)
        }
        switch value(.totalIntake) {
        case .missing: break
        case .integer(let total) where Int64(Int.min) <= total && total <= Int64(Int.max):
            result.currentTotal = Int(total)
        case let other: issue(.totalIntake, other)
        }
        switch value(.targetProtein) {
        case .missing: break
        case .string(let text): result.target = text
        case .integer(let number): result.target = String(number)
        case .double(let number): result.target = String(number)
        case let other: issue(.targetProtein, other)
        }
        switch value(.searchLanguage) {
        case .missing: break
        case .string(let text): result.searchLanguage = text
        case let other: issue(.searchLanguage, other)
        }
        return result
    }
}

/// Everything captured from the old store before any validation. This is what
/// gets backed up, fingerprinted and, if needed, re-run from.
public struct LegacyCapture: Codable, Equatable {
    public static let captureFormatVersion = 1

    public let captureFormatVersion: Int
    public let realmFilePresent: Bool
    public let defaults: [String: LegacyDefaultsValue]
    public let raw: RawLegacyData
    public let typeIssues: [LegacyDefaultsTypeIssue]

    public init(realmFilePresent: Bool, defaults: [String: LegacyDefaultsValue], raw: RawLegacyData, typeIssues: [LegacyDefaultsTypeIssue]) {
        self.captureFormatVersion = Self.captureFormatVersion
        self.realmFilePresent = realmFilePresent
        self.defaults = defaults
        self.raw = raw
        self.typeIssues = typeIssues
    }

    /// Convenience for readers: interpret defaults and combine with Realm rows.
    public init(
        realmFilePresent: Bool,
        defaults: [String: LegacyDefaultsValue],
        foods: [RawLegacyData.Food],
        history: [RawLegacyData.History],
        favorites: [RawLegacyData.Food],
        searchHistory: [RawLegacyData.SearchTerm]
    ) {
        let interpreted = LegacyDefaultsInterpreter.interpret(defaults)
        self.init(
            realmFilePresent: realmFilePresent,
            defaults: defaults,
            raw: RawLegacyData(
                savedDayLabel: interpreted.savedDayLabel,
                savedDate: interpreted.savedDate,
                currentTotal: interpreted.currentTotal,
                foods: foods,
                history: history,
                favorites: favorites,
                searchHistory: searchHistory,
                target: interpreted.target,
                searchLanguage: interpreted.searchLanguage
            ),
            typeIssues: interpreted.issues
        )
    }
}

/// Normalizes raw values into a `LegacySnapshot`. It never validates; the
/// capture must already be backed up and `LegacyMigration.prepare` decides.
public enum LegacySnapshotBuilder {
    public static func build(from raw: RawLegacyData) -> LegacySnapshot {
        LegacySnapshot(
            lastSavedDay: raw.savedDayLabel.flatMap(numericDayPrefix),
            savedDayLabel: raw.savedDayLabel,
            savedDateInstant: raw.savedDate.map(instantString),
            currentTotal: raw.currentTotal,
            foods: raw.foods.enumerated().map { position, food in
                .init(id: food.id, name: food.name, protein: food.protein,
                      position: position)
            },
            history: raw.history.enumerated().map { position, row in
                .init(id: row.id,
                      day: numericDayPrefix(row.dayLabel) ?? "",
                      total: row.total,
                      originalLabel: row.dayLabel,
                      originalDateInstant: instantString(row.storedDate),
                      position: position)
            },
            favorites: raw.favorites.enumerated().map { position, food in
                .init(id: food.id, name: food.name, protein: food.protein,
                      position: position)
            },
            searchHistory: raw.searchHistory.enumerated().map { position, term in
                .init(id: term.id, value: term.value, position: position)
            },
            target: raw.target,
            searchLanguage: raw.searchLanguage
        )
    }

    /// The old app wrote `yyyy-MM-dd-EEE`. Only the ASCII numeric prefix is a
    /// date; the localized weekday is ignored.
    static func numericDayPrefix(_ label: String) -> String? {
        let scalars = Array(label.unicodeScalars)
        guard scalars.count >= 10, scalars[4] == "-", scalars[7] == "-" else { return nil }
        for (index, scalar) in scalars.prefix(10).enumerated() where index != 4 && index != 7 {
            guard scalar.isASCII, ("0"..."9").contains(scalar) else { return nil }
        }
        return String(String.UnicodeScalarView(scalars.prefix(10)))
    }

    private static let instantFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    public static func instantString(_ date: Date) -> String {
        instantFormatter.string(from: date)
    }

    public static func instant(from text: String) -> Date? {
        instantFormatter.date(from: text)
    }
}
