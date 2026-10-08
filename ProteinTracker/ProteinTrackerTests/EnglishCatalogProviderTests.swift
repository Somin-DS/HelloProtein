import XCTest
import CryptoKit
import HelloProteinCore

@available(iOS 15.0, *)
final class EnglishCatalogProviderTests: XCTestCase {
    private var catalogURL: URL {
        // The app's resource, compiled into the test host-less bundle set.
        let bundle = Bundle(for: RecordHomeViewModel.self)
        if let url = bundle.url(forResource: "Protein-En", withExtension: "json") { return url }
        // Fallback: the source file next to the project (tests run without a host app).
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ProteinTracker/Assets/Protein-En.json")
        return source
    }

    private func load() throws -> [EnglishCatalogProvider.Row] {
        try EnglishCatalogProvider.load(url: catalogURL).get()
    }

    private func results(_ provider: FoodSearchProvider, _ query: String) -> Result<SearchResultPage, SearchProviderError> {
        let expectation = expectation(description: "search")
        var captured: Result<SearchResultPage, SearchProviderError>!
        provider.search(query: query, page: nil) { captured = $0; expectation.fulfill() }
        waitForExpectations(timeout: 10)
        return captured
    }

    // MARK: Catalog edition pin

    func testBundledCatalogMatchesThePinnedEditionSoRowIDsStayStable() throws {
        let data = try Data(contentsOf: catalogURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "d6a04da54c50f21d9a14d65af4f53f9e0a8048ab24f33fe59b87f9fbdba92d0e",
                       "Protein-En.json changed: bump EnglishCatalogProvider.catalogVersion and re-verify the edition")
        let rows = try load()
        XCTAssertEqual(rows.count, 2_332)
        XCTAssertEqual(EnglishCatalogProvider.catalogVersion, "protein-en.2332.2")
        XCTAssertEqual(rows.first, .init(index: 0, name: "Butter, salted", rawProtein: "0.85", verifiedFDCID: "173410"))
        XCTAssertEqual(rows[5], .init(index: 5, name: "Cheese, brie", rawProtein: "20.75", verifiedFDCID: "172177"))
        XCTAssertEqual(rows.last?.name, "Vitamin D as ingredient")
        XCTAssertEqual(rows.filter { $0.rawProtein == "0" }.count, 144)
        XCTAssertEqual(Set(rows.map(\.name)).count, rows.count, "names are unique in this edition")
    }

    // MARK: Lossless numbers and IDs

    func testNumbersAreKeptAsTextAndConvertedExactly() throws {
        let rows = try load()
        let brick = try XCTUnwrap(rows.first { $0.name == "Cheese, brick" })
        XCTAssertEqual(brick.rawProtein, "23.24")
        let item = EnglishCatalogProvider.item(brick)
        XCTAssertEqual(item.proteinCentigrams, 2_324)
        XCTAssertFalse(item.rounded)
        XCTAssertEqual(item.reference?.quantity, try FoodQuantity(value: "100", unit: .gram))
        XCTAssertEqual(item.id, "usda-sr-legacy-local|protein-en.2332.2|\(brick.index)")
        XCTAssertTrue(item.isSelectable)
        XCTAssertEqual(item.sourceKey, "renewal_search_source_usda")

        // Every row converts without an error; only zero rows are unavailable.
        for row in rows {
            let converted = EnglishCatalogProvider.item(row)
            XCTAssertTrue(converted.unavailability == nil || converted.unavailability == .zeroProtein || converted.unavailability == .unknownReference)
            XCTAssertEqual(converted.isSelectable, row.verifiedFDCID != nil && row.rawProtein != "0", row.name)
        }
    }

    func testRowConversionReportsRoundingZeroAndInvalidValuesWithoutFixingThem() {
        let rounded = EnglishCatalogProvider.item(.init(index: 1, name: "x", rawProtein: "1.005", verifiedFDCID: "fixture"))
        XCTAssertEqual(rounded.proteinCentigrams, 101)
        XCTAssertTrue(rounded.rounded)
        let tiny = EnglishCatalogProvider.item(.init(index: 2, name: "y", rawProtein: "0.004", verifiedFDCID: "fixture"))
        XCTAssertNil(tiny.proteinCentigrams)
        XCTAssertEqual(tiny.unavailability, .zeroProtein)
        XCTAssertFalse(tiny.isSelectable)
        let exponent = EnglishCatalogProvider.item(.init(index: 3, name: "z", rawProtein: "1e2", verifiedFDCID: "fixture"))
        XCTAssertEqual(exponent.unavailability, .invalidProtein)
        XCTAssertEqual(exponent.rawProtein, "1e2", "shown verbatim")
        let negative = EnglishCatalogProvider.item(.init(index: 4, name: "n", rawProtein: "-2", verifiedFDCID: "fixture"))
        XCTAssertEqual(negative.unavailability, .negativeProtein)
        XCTAssertFalse(negative.isSelectable)
        let huge = EnglishCatalogProvider.item(.init(index: 5, name: "h", rawProtein: "99999999999999999999", verifiedFDCID: "fixture"))
        XCTAssertEqual(huge.unavailability, .proteinOutOfRange)
        XCTAssertFalse(huge.isSelectable)
    }

    func testUnverifiedRowsNeverReceiveAReferenceOrUSDAAttribution() throws {
        let rows = try load()
        XCTAssertEqual(rows.filter { $0.verifiedFDCID != nil }.count, 2196)
        XCTAssertEqual(rows.filter { $0.verifiedFDCID == nil }.count, 136)
        for row in rows where row.verifiedFDCID == nil {
            let item = EnglishCatalogProvider.item(row)
            XCTAssertFalse(item.isSelectable)
            XCTAssertNil(item.reference)
            XCTAssertEqual(item.unavailability, .unknownReference)
            XCTAssertEqual(item.sourceKey, "renewal_search_source_unverified")
        }
        // A known value mismatch and a missing name must not silently become 100 g records.
        XCTAssertNil(EnglishCatalogProvider.item(rows[7]).reference)
        XCTAssertNil(EnglishCatalogProvider.item(rows[318]).reference)
        let missingMetadata = try EnglishCatalogProvider.parse(Data(#"[{"Food":"Unknown","Protein":23}]"#.utf8))
        XCTAssertFalse(EnglishCatalogProvider.item(missingMetadata[0]).isSelectable)
    }

    // MARK: Filtering

    func testFilterIsTrimmedCaseAndDiacriticInsensitiveInCatalogOrder() throws {
        let rows = try load()
        let plain = EnglishCatalogProvider.matches(for: "cheese, bri", in: rows).map(\.name)
        XCTAssertEqual(plain.first, "Cheese, brick")
        XCTAssertEqual(plain.prefix(2).map { $0 }, ["Cheese, brick", "Cheese, brie"], "file order, not alphabetical")
        XCTAssertEqual(EnglishCatalogProvider.matches(for: "  CHEESE, BRI ", in: rows).map(\.name), plain)
        XCTAssertEqual(EnglishCatalogProvider.matches(for: "chéese, bri", in: rows).map(\.name), plain)
        XCTAssertTrue(EnglishCatalogProvider.matches(for: "", in: rows).isEmpty)
        XCTAssertTrue(EnglishCatalogProvider.matches(for: "   ", in: rows).isEmpty)
        XCTAssertTrue(EnglishCatalogProvider.matches(for: "zzzz-no-such-food", in: rows).isEmpty)
        let indexes = EnglishCatalogProvider.matches(for: "egg", in: rows).map(\.index)
        XCTAssertEqual(indexes, indexes.sorted(), "catalog order is kept")
        XCTAssertGreaterThan(indexes.count, 1)
    }

    func testProviderAnswersOnePageAndReportsMissingOrInvalidFiles() throws {
        let provider = EnglishCatalogProvider(url: catalogURL)
        let page = try results(provider, "butter").get()
        XCTAssertNil(page.nextPage)
        XCTAssertEqual(page.items.first?.name, "Butter, salted")
        XCTAssertEqual(page.items.first?.proteinCentigrams, 85)
        XCTAssertTrue(try results(provider, "   ").get().items.isEmpty)

        let missing = EnglishCatalogProvider(url: nil)
        guard case .failure(.localData) = results(missing, "egg") else { return XCTFail("missing resource is a local data failure") }
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID().uuidString).json")
        try Data("[{\"Food\": \"x\", \"Protein\": 1.0".utf8).write(to: broken)
        defer { try? FileManager.default.removeItem(at: broken) }
        guard case .failure(.localData) = results(EnglishCatalogProvider(url: broken), "x") else { return XCTFail("invalid JSON is a local data failure") }
        let wrongShape = FileManager.default.temporaryDirectory.appendingPathComponent("shape-\(UUID().uuidString).json")
        try Data("[{\"Food\": \"x\", \"Protein\": \"1.0\"}]".utf8).write(to: wrongShape)
        defer { try? FileManager.default.removeItem(at: wrongShape) }
        guard case .failure(.localData) = results(EnglishCatalogProvider(url: wrongShape), "x") else { return XCTFail("a string protein is not the documented shape") }
    }

    func testCancelledRequestDoesNotDeliverResults() throws {
        let provider = EnglishCatalogProvider(url: catalogURL)
        let expectation = expectation(description: "cancelled")
        let handle = provider.search(query: "egg", page: nil) { result in
            if case .failure(.cancelled) = result { expectation.fulfill() } else { XCTFail("\(result)") }
        }
        handle.cancel()
        waitForExpectations(timeout: 10)
    }

    // MARK: JSON reader

    func testCatalogJSONKeepsNumberTextAndDecodesEscapes() throws {
        let data = Data(#"[{"Food":"Caf\u00e9 \"au\" lait\n\ud83e\udd5b","Protein":0.850,"n":null,"t":true,"e":1e2,"neg":-0.5,"big":123456789012345678901234567890}]"#.utf8)
        let value = try CatalogJSON.parse(data)
        let row = try XCTUnwrap(value.arrayValue?.first)
        XCTAssertEqual(row["Food"]?.stringValue, "Café \"au\" lait\n🥛")
        XCTAssertEqual(row["Protein"], .number("0.850"))
        XCTAssertEqual(row["n"], .null)
        XCTAssertEqual(row["t"], .bool(true))
        XCTAssertEqual(row["e"], .number("1e2"))
        XCTAssertEqual(row["neg"], .number("-0.5"))
        XCTAssertEqual(row["big"]?.numberText, "123456789012345678901234567890")
        for bad in ["[1,]", "{\"a\":}", "[01]", "[1.]", "\"unterminated", "[1] x", "[\"\\x\"]", "[\"\u{01}\"]", "", "[\"\\ud83e\"]"] {
            XCTAssertThrowsError(try CatalogJSON.parse(Data(bad.utf8)), bad)
        }
    }

    // MARK: Korean language

    func testKoreanProviderIsReportedAsNotConfiguredWithoutAnyRequest() {
        let provider = SearchProviderFactory.make(for: .korean)
        XCTAssertEqual(provider.providerID, SearchProviderFactory.koreanProviderID)
        guard case .failure(.notConfigured) = results(provider, "계란") else { return XCTFail("the Korean service has no verified contract") }
        XCTAssertTrue(SearchProviderFactory.make(for: .english) is EnglishCatalogProvider)
    }
}
