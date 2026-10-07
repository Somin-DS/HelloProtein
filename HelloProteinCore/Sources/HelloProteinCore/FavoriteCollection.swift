import Foundation

public enum FavoriteCollectionError: Error, Equatable {
    case notFound(String)
    case duplicateID(String)
    /// Every position is taken up to `Int.max`; the caller renumbers first.
    case positionOverflow
}

/// Pure rules for the favorites list. Display order is the `position` field
/// (`ordered`); the stored array order is not significant and `validate`
/// only requires unique IDs and positions. IDs, names, signed amounts and
/// legacy identities are never touched except where a function says so.
public enum FavoriteCollection {
    /// Display order. Stable: equal positions cannot exist in a valid state.
    public static func ordered(_ favorites: [FavoriteFood]) -> [FavoriteFood] {
        favorites.sorted { $0.position < $1.position }
    }

    /// The exact-match entry a new favorite would duplicate: same trimmed
    /// name and the same centigrams. Case, synonyms and whitespace inside the
    /// name are not normalised; the lowest position wins among several.
    public static func existing(name: String, proteinCentigrams: Int64, in favorites: [FavoriteFood]) -> FavoriteFood? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ordered(favorites).first {
            $0.proteinCentigrams == proteinCentigrams
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == wanted
        }
    }

    /// Appends a favorite at the next position (checked `max + 1`). Only when
    /// that overflows are the existing entries renumbered 0... in their current
    /// order, inside the same returned list. The new entry keeps the caller's
    /// name verbatim (the UI trims before asking).
    public static func appending(id: String, name: String, proteinCentigrams: Int64,
                                 to favorites: [FavoriteFood]) throws -> [FavoriteFood] {
        guard !favorites.contains(where: { $0.id == id }) else { throw FavoriteCollectionError.duplicateID(id) }
        var current = ordered(favorites)
        let next: Int
        if let last = current.last {
            let (candidate, overflow) = last.position.addingReportingOverflow(1)
            if overflow {
                current = try renumbered(current)
                guard let renumberedLast = current.last else { throw FavoriteCollectionError.positionOverflow }
                let (afterRenumber, stillOverflow) = renumberedLast.position.addingReportingOverflow(1)
                guard !stillOverflow else { throw FavoriteCollectionError.positionOverflow }
                next = afterRenumber
            } else {
                next = candidate
            }
        } else {
            next = 0
        }
        current.append(try FavoriteFood(id: id, name: name, proteinCentigrams: proteinCentigrams, position: next))
        return current
    }

    /// Changes only the name and amount of one entry; ID, position and legacy
    /// identity stay. Nothing else in the list moves.
    public static func replacing(id: String, name: String, proteinCentigrams: Int64,
                                 in favorites: [FavoriteFood]) throws -> [FavoriteFood] {
        guard let index = favorites.firstIndex(where: { $0.id == id }) else {
            throw FavoriteCollectionError.notFound(id)
        }
        var result = favorites
        let old = result[index]
        result[index] = try FavoriteFood(id: old.id, name: name, proteinCentigrams: proteinCentigrams,
                                         position: old.position, legacySourceID: old.legacySourceID)
        return result
    }

    /// Removes exactly one entry by ID. Other duplicates and positions stay.
    public static func removing(id: String, from favorites: [FavoriteFood]) throws -> [FavoriteFood] {
        guard favorites.contains(where: { $0.id == id }) else { throw FavoriteCollectionError.notFound(id) }
        return favorites.filter { $0.id != id }
    }

    /// The amount a favorite contributes to a record, or nil when the stored
    /// signed value cannot be a record (zero or negative). Never clamps.
    public static func recordAmount(of favorite: FavoriteFood) -> ProteinAmount? {
        guard favorite.proteinCentigrams > 0 else { return nil }
        return try? ProteinAmount(centigrams: favorite.proteinCentigrams)
    }

    /// Positions 0... in the given order. Only used on overflow.
    static func renumbered(_ favorites: [FavoriteFood]) throws -> [FavoriteFood] {
        try favorites.enumerated().map { offset, favorite in
            try FavoriteFood(id: favorite.id, name: favorite.name, proteinCentigrams: favorite.proteinCentigrams,
                             position: offset, legacySourceID: favorite.legacySourceID)
        }
    }
}

/// One favorite picked for a batch add, as it looked when the user picked it.
/// `recordID` is fixed for the editing session so a retry never adds twice.
public struct FavoriteSelection: Equatable, Sendable {
    public let favoriteID: String
    public let recordID: String
    public let name: String
    public let proteinCentigrams: Int64

    public init(favoriteID: String, recordID: String, name: String, proteinCentigrams: Int64) {
        self.favoriteID = favoriteID
        self.recordID = recordID
        self.name = name
        self.proteinCentigrams = proteinCentigrams
    }

    public init(favorite: FavoriteFood, recordID: String) {
        self.init(favoriteID: favorite.id, recordID: recordID, name: favorite.name,
                  proteinCentigrams: favorite.proteinCentigrams)
    }
}

public enum FavoriteBatchError: Error, Equatable {
    case emptySelection
    case duplicateSelection(String)
    case duplicateRecordID(String)
    /// The favorite was removed or edited after it was selected.
    case selectionChanged(String)
    /// The stored amount is not a positive protein amount.
    case invalidAmount(String)
    case arithmeticOverflow
}

/// Builds the records for a multi-favorite add. Either every selection still
/// matches the latest favorites and becomes a record, or nothing does.
public enum FavoriteBatch {
    /// Checked sum of the selected amounts, for the summary and the write.
    public static func totalCentigrams(_ selections: [FavoriteSelection]) throws -> Int64 {
        var sum: Int64 = 0
        for selection in selections {
            let (next, overflow) = sum.addingReportingOverflow(selection.proteinCentigrams)
            guard !overflow else { throw FavoriteBatchError.arithmeticOverflow }
            sum = next
        }
        return sum
    }

    /// Records for `day`, one per selection, in selection order. Fails on an
    /// empty or duplicated selection, a favorite that changed since it was
    /// picked, a non-positive amount, or a sum that overflows.
    public static func records(for selections: [FavoriteSelection], on day: CalendarDay,
                               favorites: [FavoriteFood]) throws -> [FoodRecord] {
        guard !selections.isEmpty else { throw FavoriteBatchError.emptySelection }
        var favoriteIDs = Set<String>()
        var recordIDs = Set<String>()
        var records: [FoodRecord] = []
        for selection in selections {
            guard favoriteIDs.insert(selection.favoriteID).inserted else {
                throw FavoriteBatchError.duplicateSelection(selection.favoriteID)
            }
            guard recordIDs.insert(selection.recordID).inserted else {
                throw FavoriteBatchError.duplicateRecordID(selection.recordID)
            }
            guard let latest = favorites.first(where: { $0.id == selection.favoriteID }),
                  latest.name == selection.name, latest.proteinCentigrams == selection.proteinCentigrams else {
                throw FavoriteBatchError.selectionChanged(selection.favoriteID)
            }
            guard let amount = FavoriteCollection.recordAmount(of: latest) else {
                throw FavoriteBatchError.invalidAmount(selection.favoriteID)
            }
            records.append(try FoodRecord(id: selection.recordID, day: day, name: latest.name, quantity: nil,
                                          protein: amount, source: .favorite))
        }
        _ = try totalCentigrams(selections)
        return records
    }
}

extension AppState {
    /// Replaces the favorites list and re-validates the whole document,
    /// rolling back on failure.
    public mutating func setFavorites(_ favorites: [FavoriteFood]) throws {
        let previous = self.favorites
        self.favorites = favorites
        do { try validate() }
        catch {
            self.favorites = previous
            throw error
        }
    }
}
