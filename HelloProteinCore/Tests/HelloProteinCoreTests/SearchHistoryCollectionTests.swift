import XCTest
@testable import HelloProteinCore

final class SearchHistoryCollectionTests: XCTestCase {
    private func term(_ id: String, _ value: String, position: Int, legacy: String? = nil) throws -> SearchTerm {
        try SearchTerm(id: id, value: value, position: position, legacySourceID: legacy)
    }

    /// Stored out of position order, with an untrimmed and an empty legacy value kept verbatim.
    private func migrated() throws -> [SearchTerm] {
        [try term("legacy:search:b", "milk", position: 1, legacy: "b"),
         try term("legacy:search:a", "egg", position: 0, legacy: "a"),
         try term("legacy:search:c", " Egg ", position: 5, legacy: "c"),
         try term("legacy:search:d", "", position: 3, legacy: "d")]
    }

    func testOrderedSortsByPositionAndKeepsValuesVerbatim() throws {
        let ordered = SearchHistoryCollection.ordered(try migrated())
        XCTAssertEqual(ordered.map(\.id), ["legacy:search:a", "legacy:search:b", "legacy:search:d", "legacy:search:c"])
        XCTAssertEqual(ordered.map(\.value), ["egg", "milk", "", " Egg "])
        XCTAssertEqual(ordered.map(\.position), [0, 1, 3, 5])
        XCTAssertEqual(ordered[0].legacySourceID, "a")
    }

    func testBlankQueriesAreRefusedAndTrimmedQueriesMatchExactly() throws {
        XCTAssertNil(SearchHistoryCollection.normalizedQuery("   \n"))
        XCTAssertEqual(SearchHistoryCollection.normalizedQuery("  tofu "), "tofu")
        XCTAssertThrowsError(try SearchHistoryCollection.recording(query: "  ", newID: "n", in: try migrated())) {
            XCTAssertEqual($0 as? SearchHistoryError, .blankQuery)
        }
        // Trimmed equality, no case folding: "Egg" matches the untrimmed legacy value, not "egg".
        XCTAssertEqual(SearchHistoryCollection.existing(query: "Egg", in: try migrated())?.id, "legacy:search:c")
        XCTAssertEqual(SearchHistoryCollection.existing(query: " egg", in: try migrated())?.id, "legacy:search:a")
        XCTAssertNil(SearchHistoryCollection.existing(query: "EGG", in: try migrated()))
    }

    func testRecordingAnExistingQueryMovesTheFirstMatchToTheFrontAndKeepsItsIdentity() throws {
        let result = SearchHistoryCollection.ordered(try SearchHistoryCollection.recording(query: " milk ", newID: "unused", in: try migrated()))
        XCTAssertEqual(result.map(\.id), ["legacy:search:b", "legacy:search:a", "legacy:search:d", "legacy:search:c"])
        XCTAssertEqual(result.map(\.position), [0, 1, 2, 3], "contiguous after the move")
        XCTAssertEqual(result[0].value, "milk")
        XCTAssertEqual(result[0].legacySourceID, "b")
        XCTAssertEqual(result.count, 4, "nothing else is dropped or merged")
        XCTAssertEqual(result[3].value, " Egg ", "other values stay verbatim")
    }

    func testRecordingANewQueryInsertsTheTrimmedValueAtTheFront() throws {
        let result = SearchHistoryCollection.ordered(try SearchHistoryCollection.recording(query: "  tofu ", newID: "new", in: try migrated()))
        XCTAssertEqual(result.map(\.id), ["new", "legacy:search:a", "legacy:search:b", "legacy:search:d", "legacy:search:c"])
        XCTAssertEqual(result.map(\.position), [0, 1, 2, 3, 4])
        XCTAssertEqual(result[0].value, "tofu")
        XCTAssertNil(result[0].legacySourceID)
        XCTAssertEqual(try SearchHistoryCollection.recording(query: "x", newID: "first", in: []).first?.position, 0)
        XCTAssertThrowsError(try SearchHistoryCollection.recording(query: "tofu", newID: "legacy:search:a", in: try migrated())) {
            XCTAssertEqual($0 as? SearchHistoryError, .duplicateID("legacy:search:a"))
        }
    }

    func testRecordingWhenTwoEntriesMatchMovesOnlyTheLowestPosition() throws {
        let twice = try migrated() + [try term("legacy:search:e", "egg", position: 9, legacy: "e")]
        let result = SearchHistoryCollection.ordered(try SearchHistoryCollection.recording(query: "egg", newID: "n", in: twice))
        XCTAssertEqual(result.map(\.id), ["legacy:search:a", "legacy:search:b", "legacy:search:d", "legacy:search:c", "legacy:search:e"])
        XCTAssertEqual(result.filter { $0.value == "egg" }.count, 2, "duplicates are not merged")
    }

    func testRemovingDeletesExactlyThatIDWithoutRenumbering() throws {
        let result = try SearchHistoryCollection.removing(id: "legacy:search:b", from: try migrated())
        XCTAssertEqual(SearchHistoryCollection.ordered(result).map(\.id), ["legacy:search:a", "legacy:search:d", "legacy:search:c"])
        XCTAssertEqual(SearchHistoryCollection.ordered(result).map(\.position), [0, 3, 5])
        XCTAssertThrowsError(try SearchHistoryCollection.removing(id: "missing", from: try migrated())) {
            XCTAssertEqual($0 as? SearchHistoryError, .notFound("missing"))
        }
    }

    func testExtremePositionsAreMadeContiguousByARecordingWrite() throws {
        let extreme = [try term("x", "a", position: Int.max), try term("y", "b", position: Int.min)]
        let result = SearchHistoryCollection.ordered(try SearchHistoryCollection.recording(query: "a", newID: "n", in: extreme))
        XCTAssertEqual(result.map(\.id), ["x", "y"])
        XCTAssertEqual(result.map(\.position), [0, 1])
    }

    func testSettingTheHistoryValidatesAndRollsBack() throws {
        var state = try AppState.freshInstall(completedAt: "2026-10-07T00:00:00Z", migrationVersion: 1)
        try state.setSearchHistory([try term("a", "egg", position: 0)])
        XCTAssertEqual(state.searchHistory.count, 1)
        XCTAssertThrowsError(try state.setSearchHistory([try term("a", "egg", position: 0), try term("b", "milk", position: 0)]))
        XCTAssertEqual(state.searchHistory.map(\.id), ["a"], "rolled back")
    }

    func testLanguageRawValuesRoundTripThroughInterpret() {
        XCTAssertEqual(SearchLanguageSetting.confirmed(.korean), SearchLanguageSetting(raw: "Korean(한글)", resolved: .korean, isFallback: false))
        XCTAssertEqual(SearchLanguageSetting.confirmed(.english), SearchLanguageSetting(raw: "English(영어)", resolved: .english, isFallback: false))
        XCTAssertTrue(SearchLanguageSetting.interpret(raw: "english").isFallback)
    }
}
