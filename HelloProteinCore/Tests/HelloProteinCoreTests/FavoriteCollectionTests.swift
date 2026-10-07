import XCTest
@testable import HelloProteinCore

final class FavoriteCollectionTests: XCTestCase {
    private let day = try! CalendarDay(iso8601: "2026-10-07")

    private func favorite(_ id: String, _ name: String, _ centigrams: Int64, position: Int,
                          legacy: String? = nil) throws -> FavoriteFood {
        try FavoriteFood(id: id, name: name, proteinCentigrams: centigrams, position: position, legacySourceID: legacy)
    }

    private func migrated() throws -> [FavoriteFood] {
        // Stored out of position order, with a signed and an empty-name entry kept verbatim.
        [try favorite("legacy:favorite:b", "그릭요거트", 900, position: 1, legacy: "b"),
         try favorite("legacy:favorite:a", "닭가슴살", 2_300, position: 0, legacy: "a"),
         try favorite("legacy:favorite:c", "", -500, position: 7, legacy: "c"),
         try favorite("legacy:favorite:d", "zero", 0, position: 3, legacy: "d")]
    }

    func testOrderedSortsByPositionWithoutChangingEntries() throws {
        let ordered = FavoriteCollection.ordered(try migrated())
        XCTAssertEqual(ordered.map(\.id), ["legacy:favorite:a", "legacy:favorite:b", "legacy:favorite:d", "legacy:favorite:c"])
        XCTAssertEqual(ordered.map(\.position), [0, 1, 3, 7])
        XCTAssertEqual(ordered[3].proteinCentigrams, -500)
        XCTAssertEqual(ordered[3].name, "")
        XCTAssertEqual(ordered[0].legacySourceID, "a")
    }

    func testAppendingUsesCheckedMaxPlusOneAndKeepsTheRest() throws {
        let result = try FavoriteCollection.appending(id: "new", name: "Egg", proteinCentigrams: 600, to: try migrated())
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result.last?.id, "new")
        XCTAssertEqual(result.last?.position, 8)
        XCTAssertNil(result.last?.legacySourceID)
        XCTAssertEqual(result.map(\.position), [0, 1, 3, 7, 8])
        XCTAssertEqual(try FavoriteCollection.appending(id: "first", name: "x", proteinCentigrams: 1, to: []).first?.position, 0)
        XCTAssertThrowsError(try FavoriteCollection.appending(id: "legacy:favorite:a", name: "x", proteinCentigrams: 1, to: try migrated())) {
            XCTAssertEqual($0 as? FavoriteCollectionError, .duplicateID("legacy:favorite:a"))
        }
    }

    func testAppendingRenumbersOnlyOnPositionOverflowAndKeepsOrderAndIdentity() throws {
        let edge = [try favorite("legacy:favorite:a", "A", 100, position: Int.max - 1, legacy: "a"),
                    try favorite("legacy:favorite:b", "B", 200, position: Int.max, legacy: "b"),
                    try favorite("legacy:favorite:c", "C", 300, position: 5, legacy: "c")]
        let result = try FavoriteCollection.appending(id: "new", name: "N", proteinCentigrams: 1, to: edge)
        XCTAssertEqual(result.map(\.id), ["legacy:favorite:c", "legacy:favorite:a", "legacy:favorite:b", "new"])
        XCTAssertEqual(result.map(\.position), [0, 1, 2, 3])
        XCTAssertEqual(result.map(\.legacySourceID), ["c", "a", "b", nil])
        XCTAssertEqual(result.map(\.proteinCentigrams), [300, 100, 200, 1])
    }

    func testExistingMatchesTrimmedNameAndExactCentigramsLowestPositionFirst() throws {
        let list = [try favorite("x", "Egg ", 600, position: 4),
                    try favorite("y", "Egg", 600, position: 2),
                    try favorite("z", "egg", 600, position: 0),
                    try favorite("w", "Egg", 650, position: 1)]
        XCTAssertEqual(FavoriteCollection.existing(name: " Egg", proteinCentigrams: 600, in: list)?.id, "y")
        XCTAssertNil(FavoriteCollection.existing(name: "Egg", proteinCentigrams: 601, in: list))
        XCTAssertNil(FavoriteCollection.existing(name: "Eggs", proteinCentigrams: 600, in: list))
        XCTAssertEqual(FavoriteCollection.existing(name: "", proteinCentigrams: -500, in: try migrated())?.id, "legacy:favorite:c")
    }

    func testReplacingChangesOnlyNameAndAmountOfThatEntry() throws {
        let result = try FavoriteCollection.replacing(id: "legacy:favorite:c", name: "Fixed", proteinCentigrams: 500, in: try migrated())
        let fixed = try XCTUnwrap(result.first { $0.id == "legacy:favorite:c" })
        XCTAssertEqual(fixed.name, "Fixed")
        XCTAssertEqual(fixed.proteinCentigrams, 500)
        XCTAssertEqual(fixed.position, 7)
        XCTAssertEqual(fixed.legacySourceID, "c")
        XCTAssertEqual(result.map(\.id), try migrated().map(\.id), "order of the array is untouched")
        XCTAssertEqual(result.filter { $0.id != "legacy:favorite:c" }, try migrated().filter { $0.id != "legacy:favorite:c" })
        XCTAssertThrowsError(try FavoriteCollection.replacing(id: "missing", name: "x", proteinCentigrams: 1, in: try migrated())) {
            XCTAssertEqual($0 as? FavoriteCollectionError, .notFound("missing"))
        }
    }

    func testRemovingDropsOneIDAndLeavesDuplicatesAndPositions() throws {
        var list = try migrated()
        list.append(try favorite("dup", "닭가슴살", 2_300, position: 9))
        let result = try FavoriteCollection.removing(id: "legacy:favorite:a", from: list)
        XCTAssertEqual(result.map(\.id), ["legacy:favorite:b", "legacy:favorite:c", "legacy:favorite:d", "dup"])
        XCTAssertEqual(result.map(\.position), [1, 7, 3, 9])
        XCTAssertThrowsError(try FavoriteCollection.removing(id: "legacy:favorite:a", from: result))
    }

    func testRecordAmountIsNilForZeroAndNegativeAndNeverClamps() throws {
        let list = try migrated()
        XCTAssertEqual(FavoriteCollection.recordAmount(of: list[1])?.centigrams, 2_300)
        XCTAssertNil(FavoriteCollection.recordAmount(of: list[2]))
        XCTAssertNil(FavoriteCollection.recordAmount(of: list[3]))
    }

    // MARK: Batch

    private func selection(_ favorite: FavoriteFood, record: String) -> FavoriteSelection {
        FavoriteSelection(favorite: favorite, recordID: record)
    }

    func testBatchBuildsOneFavoriteRecordPerSelectionInOrder() throws {
        let list = try migrated()
        let a = try XCTUnwrap(list.first { $0.id == "legacy:favorite:a" })
        let b = try XCTUnwrap(list.first { $0.id == "legacy:favorite:b" })
        let records = try FavoriteBatch.records(for: [selection(b, record: "r1"), selection(a, record: "r2")], on: day, favorites: list)
        XCTAssertEqual(records.map(\.id), ["r1", "r2"])
        XCTAssertEqual(records.map(\.name), ["그릭요거트", "닭가슴살"])
        XCTAssertEqual(records.map(\.protein.centigrams), [900, 2_300])
        XCTAssertEqual(records.map(\.source), [.favorite, .favorite])
        XCTAssertTrue(records.allSatisfy { $0.quantity == nil && $0.day == day && $0.legacySourceID == nil })
        XCTAssertEqual(try FavoriteBatch.totalCentigrams([selection(b, record: "r1"), selection(a, record: "r2")]), 3_200)
    }

    func testBatchFailsAsAWholeOnEmptyDuplicateChangedOrInvalidSelections() throws {
        let list = try migrated()
        let a = try XCTUnwrap(list.first { $0.id == "legacy:favorite:a" })
        let c = try XCTUnwrap(list.first { $0.id == "legacy:favorite:c" })
        XCTAssertThrowsError(try FavoriteBatch.records(for: [], on: day, favorites: list)) {
            XCTAssertEqual($0 as? FavoriteBatchError, .emptySelection)
        }
        XCTAssertThrowsError(try FavoriteBatch.records(for: [selection(a, record: "r1"), selection(a, record: "r2")], on: day, favorites: list)) {
            XCTAssertEqual($0 as? FavoriteBatchError, .duplicateSelection("legacy:favorite:a"))
        }
        let b = try XCTUnwrap(list.first { $0.id == "legacy:favorite:b" })
        XCTAssertThrowsError(try FavoriteBatch.records(for: [selection(a, record: "r1"), selection(b, record: "r1")], on: day, favorites: list)) {
            XCTAssertEqual($0 as? FavoriteBatchError, .duplicateRecordID("r1"))
        }
        // Edited after selection: the snapshot no longer matches.
        let edited = try FavoriteCollection.replacing(id: "legacy:favorite:a", name: "닭가슴살", proteinCentigrams: 2_400, in: list)
        XCTAssertThrowsError(try FavoriteBatch.records(for: [selection(b, record: "r1"), selection(a, record: "r2")], on: day, favorites: edited)) {
            XCTAssertEqual($0 as? FavoriteBatchError, .selectionChanged("legacy:favorite:a"))
        }
        // Deleted after selection.
        let removed = try FavoriteCollection.removing(id: "legacy:favorite:a", from: list)
        XCTAssertThrowsError(try FavoriteBatch.records(for: [selection(a, record: "r2")], on: day, favorites: removed)) {
            XCTAssertEqual($0 as? FavoriteBatchError, .selectionChanged("legacy:favorite:a"))
        }
        // A negative stored value is never turned into a record.
        XCTAssertThrowsError(try FavoriteBatch.records(for: [selection(a, record: "r1"), selection(c, record: "r2")], on: day, favorites: list)) {
            XCTAssertEqual($0 as? FavoriteBatchError, .invalidAmount("legacy:favorite:c"))
        }
    }

    func testBatchSumOverflowFailsBeforeAnyRecordIsReturned() throws {
        let big1 = try favorite("big1", "Big", Int64.max - 10, position: 0)
        let big2 = try favorite("big2", "Big2", 100, position: 1)
        let selections = [selection(big1, record: "r1"), selection(big2, record: "r2")]
        XCTAssertThrowsError(try FavoriteBatch.totalCentigrams(selections)) {
            XCTAssertEqual($0 as? FavoriteBatchError, .arithmeticOverflow)
        }
        XCTAssertThrowsError(try FavoriteBatch.records(for: selections, on: day, favorites: [big1, big2])) {
            XCTAssertEqual($0 as? FavoriteBatchError, .arithmeticOverflow)
        }
    }

    func testSetFavoritesValidatesAndRollsBack() throws {
        var state = try AppState.freshInstall(completedAt: "2026-10-07T00:00:00Z", migrationVersion: 1)
        try state.setFavorites(try migrated())
        XCTAssertEqual(state.favorites.count, 4)
        let clash = [try favorite("p", "P", 1, position: 0), try favorite("q", "Q", 1, position: 0)]
        XCTAssertThrowsError(try state.setFavorites(clash)) {
            XCTAssertEqual($0 as? AppStateError, .duplicateFavoritePosition(0))
        }
        XCTAssertEqual(state.favorites.count, 4, "rolled back")
    }
}
