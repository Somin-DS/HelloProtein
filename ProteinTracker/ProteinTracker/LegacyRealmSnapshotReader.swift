import Foundation
import MigrationCore
import RealmSwift

/// Value extraction from an already opened Realm plus typed UserDefaults values.
/// It never writes. Opening the Realm safely is `RealmLegacySourceGateway`'s job.
enum LegacyRealmSnapshotReader {
    static let objectTypes: [ObjectBase.Type] = [
        DailyProtein.self, StatProtein.self, Favorites.self, SearchHistory.self
    ]

    struct Rows {
        var foods: [RawLegacyData.Food] = []
        var history: [RawLegacyData.History] = []
        var favorites: [RawLegacyData.Food] = []
        var searchHistory: [RawLegacyData.SearchTerm] = []
    }

    /// Realm enumeration order is preserved; nothing is sorted or deduplicated.
    static func rows(from realm: Realm) -> Rows {
        var rows = Rows()
        rows.foods = realm.objects(DailyProtein.self).map {
            RawLegacyData.Food(id: $0._id.stringValue, name: $0.proteinName, protein: $0.proteinIntake)
        }
        rows.history = realm.objects(StatProtein.self).map {
            RawLegacyData.History(id: $0._id.stringValue, dayLabel: $0.date, storedDate: $0.originDate, total: $0.totalIntake)
        }
        rows.favorites = realm.objects(Favorites.self).map {
            RawLegacyData.Food(id: $0._id.stringValue, name: $0.proteinName, protein: $0.proteinIntake)
        }
        rows.searchHistory = realm.objects(SearchHistory.self).map {
            RawLegacyData.SearchTerm(id: $0._id.stringValue, value: $0.proteinName)
        }
        return rows
    }

    /// Reads the five keys with their runtime types. Missing, explicit 0 and a
    /// wrong type stay distinguishable.
    static func typedDefaults(_ defaults: UserDefaults) -> [String: LegacyDefaultsValue] {
        var result: [String: LegacyDefaultsValue] = [:]
        for key in LegacyDefaultsKey.allCases {
            result[key.rawValue] = typedValue(defaults.object(forKey: key.rawValue))
        }
        return result
    }

    static func presentDefaultsKeys(_ defaults: UserDefaults) -> [String] {
        LegacyDefaultsKey.allCases.map(\.rawValue).filter { defaults.object(forKey: $0) != nil }
    }

    static func typedValue(_ object: Any?) -> LegacyDefaultsValue {
        guard let object else { return .missing }
        if let string = object as? String { return .string(string) }
        if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            switch String(cString: number.objCType) {
            case "c", "C", "s", "S", "i", "I", "l", "L", "q", "Q":
                return .integer(number.int64Value)
            case "f", "d":
                return .double(number.doubleValue)
            case let other:
                return .unsupported(typeName: "NSNumber(\(other))")
            }
        }
        if let date = object as? Date {
            return .date(secondsSince1970: date.timeIntervalSince1970,
                         iso8601: LegacySnapshotBuilder.instantString(date))
        }
        if let data = object as? Data { return .data(base64: data.base64EncodedString()) }
        return .unsupported(typeName: String(describing: type(of: object)))
    }

    static func capture(rows: Rows, defaults: UserDefaults, realmFilePresent: Bool) -> LegacyCapture {
        LegacyCapture(
            realmFilePresent: realmFilePresent,
            defaults: typedDefaults(defaults),
            foods: rows.foods,
            history: rows.history,
            favorites: rows.favorites,
            searchHistory: rows.searchHistory
        )
    }
}
