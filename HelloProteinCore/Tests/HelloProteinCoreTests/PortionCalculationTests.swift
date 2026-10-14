import XCTest
@testable import HelloProteinCore

final class PortionCalculationTests: XCTestCase {
    private let day = try! CalendarDay(iso8601: "2026-10-14")
    private let per100g = try! FoodQuantity(value: "100", unit: .gram)

    private struct Fixture: Decodable {
        struct Quantity: Decodable { let value: String; let unit: String }
        struct Case: Decodable {
            let name: String; let proteinGramsText: String; let reference: Quantity; let actual: Quantity
            let expectedCentigrams: Int64; let rounded: Bool
        }
        struct ErrorCase: Decodable {
            let name: String; let proteinGramsText: String; let reference: Quantity; let actual: Quantity; let error: String
        }
        struct Input: Decodable {
            struct Accepted: Decodable { let text: String; let separator: String; let canonical: String }
            struct Rejected: Decodable { let text: String; let separator: String; let error: String }
            let maxIntegerDigits: Int; let maxFractionDigits: Int
            let accepted: [Accepted]; let rejected: [Rejected]
        }
        let cases: [Case]
        let errors: [ErrorCase]
        let quantityInput: Input
    }

    /// `docs/evidence/2026-10-14-quantity-statistics/fixtures/portion-calculation.json`,
    /// the platform-independent contract. The test fails, not skips, when it is gone.
    private func fixture() throws -> Fixture {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/evidence/2026-10-14-quantity-statistics/fixtures/portion-calculation.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "fixture missing at \(url.path)")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func quantity(_ q: Fixture.Quantity) throws -> FoodQuantity {
        try FoodQuantity(value: q.value, unit: try XCTUnwrap(FoodQuantity.Unit(rawValue: q.unit)))
    }

    // MARK: Calculation

    func testFixtureCasesProduceTheExpectedCentigramsWithOneFinalRounding() throws {
        let fixture = try fixture()
        XCTAssertGreaterThanOrEqual(fixture.cases.count, 13)
        for item in fixture.cases {
            let result = try PortionCalculation.centigrams(proteinGramsText: item.proteinGramsText,
                                                           referenceQuantity: quantity(item.reference),
                                                           actualQuantity: quantity(item.actual))
            XCTAssertEqual(result.centigrams, item.expectedCentigrams, item.name)
            XCTAssertEqual(result.rounded, item.rounded, item.name)
        }
    }

    func testFixtureErrorCasesAreRejectedWithTheNamedReason() throws {
        let fixture = try fixture()
        XCTAssertGreaterThanOrEqual(fixture.errors.count, 4)
        for item in fixture.errors {
            XCTAssertThrowsError(try PortionCalculation.centigrams(proteinGramsText: item.proteinGramsText,
                                                                   referenceQuantity: quantity(item.reference),
                                                                   actualQuantity: quantity(item.actual)), item.name) { error in
                XCTAssertEqual(String(describing: error), item.error, item.name)
            }
        }
    }

    func testPlanSamplesAreExactAndNeverChainPreviousResults() throws {
        func grams(_ protein: String, _ reference: String, _ actual: String, unit: FoodQuantity.Unit = .gram) throws -> Int64 {
            try PortionCalculation.centigrams(proteinGramsText: protein,
                                              referenceQuantity: FoodQuantity(value: reference, unit: unit),
                                              actualQuantity: FoodQuantity(value: actual, unit: unit)).centigrams
        }
        XCTAssertEqual(try grams("12.18", "100", "150"), 1_827)
        XCTAssertEqual(try grams("1.005", "100", "200"), 201, "1.01 × 2 = 2.02 would be a pre-rounding")
        XCTAssertEqual(try grams("10", "3", "1"), 333)
        XCTAssertEqual(try grams("10", "3", "2"), 667, "not 333 × 2")
        XCTAssertEqual(try grams("10", "3", "3"), 1_000, "not 667 + 333")
        XCTAssertEqual(try grams("4", "100", "250", unit: .milliliter), 1_000)
        // Repeated edits of the same basis are independent of history.
        let basis = try CalculationBasis.userDefined(proteinGramsText: "10", referenceQuantity: FoodQuantity(value: "3", unit: .gram))
        var record = try FoodRecord(id: "r", day: day, name: "x", quantity: FoodQuantity(value: "1", unit: .gram), basis: basis)
        for (value, expected) in [("2", Int64(667)), ("3", 1_000), ("1", 333), ("3", 1_000)] {
            record = try record.withQuantity(FoodQuantity(value: value, unit: .gram))
            XCTAssertEqual(record.protein.centigrams, expected, value)
            XCTAssertEqual(record.calculationBasis, basis)
        }
    }

    func testHalfUpBoundaryUsesOnlyTheThirdFractionDigit() throws {
        func cg(_ protein: String) throws -> PortionCalculation.Result {
            try PortionCalculation.centigrams(proteinGramsText: protein, referenceQuantity: per100g, actualQuantity: per100g)
        }
        XCTAssertEqual(try cg("1.004999999"), .init(centigrams: 100, rounded: true))
        XCTAssertEqual(try cg("1.005"), .init(centigrams: 101, rounded: true))
        XCTAssertEqual(try cg("1.005000001"), .init(centigrams: 101, rounded: true))
        XCTAssertEqual(try cg("1.01"), .init(centigrams: 101, rounded: false))
        XCTAssertEqual(try cg("1.010"), .init(centigrams: 101, rounded: false))
        XCTAssertThrowsError(try cg("0.004")) { XCTAssertEqual($0 as? PortionCalculationError, .roundsToZero) }
        XCTAssertEqual(try cg("0.005").centigrams, 1)
    }

    func testOverflowIsReportedNotWrapped() throws {
        let reference = try FoodQuantity(value: "1", unit: .gram)
        let huge = try FoodQuantity(value: "999999999.999", unit: .gram)
        XCTAssertEqual(try PortionCalculation.centigrams(proteinGramsText: "92233720368547758.07", referenceQuantity: reference,
                                                         actualQuantity: reference).centigrams, Int64.max)
        XCTAssertThrowsError(try PortionCalculation.centigrams(proteinGramsText: "92233720368547758.08", referenceQuantity: reference,
                                                               actualQuantity: reference)) {
            XCTAssertEqual($0 as? PortionCalculationError, .overflow)
        }
        XCTAssertThrowsError(try PortionCalculation.centigrams(proteinGramsText: "999999999999999999", referenceQuantity: reference,
                                                               actualQuantity: huge)) {
            XCTAssertEqual($0 as? PortionCalculationError, .overflow)
        }
        XCTAssertThrowsError(try PortionCalculation.centigrams(proteinGramsText: "1", referenceQuantity: per100g,
                                                               actualQuantity: FoodQuantity(value: "100", unit: .milliliter))) {
            XCTAssertEqual($0 as? PortionCalculationError, .unitMismatch)
        }
    }

    func testDigitArithmeticIsExact() {
        XCTAssertEqual(DigitArithmetic.multiply([9, 9, 9], [9, 9, 9]), [9, 9, 8, 0, 0, 1])
        XCTAssertEqual(DigitArithmetic.multiply([0, 0, 4], [1, 0, 0]), [4, 0, 0])
        XCTAssertEqual(DigitArithmetic.multiply([], [1]), [])
        let division = DigitArithmetic.divide([1, 0, 0, 0, 0], by: 3)
        XCTAssertEqual(division.quotient, [3, 3, 3, 3])
        XCTAssertEqual(division.remainder, 1)
        XCTAssertEqual(DigitArithmetic.divide([5], by: 10).quotient, [])
        XCTAssertEqual(DigitArithmetic.uint64([1, 8, 4, 4, 6, 7, 4, 4, 0, 7, 3, 7, 0, 9, 5, 5, 1, 6, 1, 5]), UInt64.max)
        XCTAssertNil(DigitArithmetic.uint64([1, 8, 4, 4, 6, 7, 4, 4, 0, 7, 3, 7, 0, 9, 5, 5, 1, 6, 1, 6]))
    }

    // MARK: Input

    func testQuantityInputFixtureAcceptsAndRejectsAsSpecified() throws {
        let input = try fixture().quantityInput
        XCTAssertEqual(input.maxIntegerDigits, PortionInput.maxIntegerDigits)
        XCTAssertEqual(input.maxFractionDigits, PortionInput.maxFractionDigits)
        for item in input.accepted {
            XCTAssertEqual(try PortionInput.parseQuantity(item.text, decimalSeparator: item.separator).canonical, item.canonical, item.text)
        }
        for item in input.rejected {
            XCTAssertThrowsError(try PortionInput.parseQuantity(item.text, decimalSeparator: item.separator), item.text) { error in
                XCTAssertEqual(String(describing: error), item.error, item.text)
            }
        }
    }

    func testOneAllowedSeparatorIsAlwaysTheDecimalPoint() throws {
        XCTAssertEqual(try PortionInput.parseQuantity("1.234", decimalSeparator: ",").canonical, "1.234", "not 1234")
        XCTAssertEqual(try PortionInput.parseQuantity("1,234", decimalSeparator: ",").canonical, "1.234")
        XCTAssertEqual(try PortionInput.parseQuantity("150,5", decimalSeparator: ",").canonical, "150.5")
        XCTAssertThrowsError(try PortionInput.parseQuantity("1,5", decimalSeparator: ".")) {
            XCTAssertEqual($0 as? PortionInputError, .groupingNotAllowed)
        }
        XCTAssertThrowsError(try PortionInput.parseQuantity("1.5,0", decimalSeparator: ",")) {
            XCTAssertEqual($0 as? PortionInputError, .mixedSeparators)
        }
        XCTAssertThrowsError(try PortionInput.parseQuantity("1\u{00A0}000", decimalSeparator: ",")) {
            XCTAssertEqual($0 as? PortionInputError, .groupingNotAllowed)
        }
    }

    func testEditableQuantityValueFollowsTheInputRange() {
        XCTAssertTrue(PortionInput.isEditableQuantityValue("100"))
        XCTAssertTrue(PortionInput.isEditableQuantityValue("999999999.999"))
        XCTAssertTrue(PortionInput.isEditableQuantityValue("0.001"))
        XCTAssertFalse(PortionInput.isEditableQuantityValue("0.0001"))
        XCTAssertFalse(PortionInput.isEditableQuantityValue("1234567890"))
        XCTAssertFalse(PortionInput.isEditableQuantityValue("0"))
        XCTAssertFalse(PortionInput.isEditableQuantityValue("abc"))
    }

    func testPortionDecimalCanonicalizesAndCountsDigits() throws {
        XCTAssertEqual(try PortionDecimal(canonical: "007.250").canonical, "7.25")
        XCTAssertEqual(try PortionDecimal(canonical: ".5").canonical, "0.5")
        XCTAssertEqual(try PortionDecimal(canonical: "5.").canonical, "5")
        XCTAssertEqual(try PortionDecimal(canonical: "0.0012").significantDigitCount, 2)
        XCTAssertEqual(try PortionDecimal(canonical: "120.5").significantDigitCount, 4)
        XCTAssertEqual(try PortionDecimal(canonical: "1000").significantDigitCount, 4)
        XCTAssertEqual(try PortionDecimal(canonical: "1.005").fractionDigitCount, 3)
        XCTAssertThrowsError(try PortionDecimal(canonical: "0.000")) { XCTAssertEqual($0 as? PortionInputError, .zero) }
        XCTAssertThrowsError(try PortionDecimal(canonical: "-1")) { XCTAssertEqual($0 as? PortionInputError, .notANumber) }
        XCTAssertThrowsError(try PortionDecimal(canonical: "1,5")) { XCTAssertEqual($0 as? PortionInputError, .notANumber) }
    }

    // MARK: Basis

    private func providerBasis(protein: String = "12.18", reference: FoodQuantity? = nil) throws -> CalculationBasis {
        try CalculationBasis.providerSnapshot(proteinGramsText: protein, referenceQuantity: reference ?? per100g,
                                              providerID: "mfds", dataVersion: "2026-10", itemID: "D000001")
    }

    func testBasisKeepsRawPrecisionAndEnforcesItsLimits() throws {
        let basis = try providerBasis(protein: "1.005")
        XCTAssertEqual(basis.proteinGramsText, "1.005")
        XCTAssertEqual(try providerBasis(protein: "01.2300").proteinGramsText, "1.23", "canonical text")
        XCTAssertEqual(try providerBasis(protein: "123456789.123456789").proteinGramsText, "123456789.123456789", "18 significant, 9 fraction")
        XCTAssertThrowsError(try providerBasis(protein: "1234567890.123456789")) {
            guard case .invalidBasis(let reason)? = $0 as? RecordDomainError else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("significant"), reason)
        }
        XCTAssertThrowsError(try providerBasis(protein: "0.0000000001")) {
            guard case .invalidBasis(let reason)? = $0 as? RecordDomainError else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("fraction"), reason)
        }
        XCTAssertThrowsError(try providerBasis(protein: "0"))
        XCTAssertThrowsError(try providerBasis(protein: "-1"))
        XCTAssertThrowsError(try providerBasis(reference: FoodQuantity(value: "0.0000000001", unit: .gram)))
        XCTAssertThrowsError(try CalculationBasis.providerSnapshot(proteinGramsText: "1", referenceQuantity: per100g,
                                                                   providerID: "", dataVersion: "v", itemID: "i"))
        XCTAssertThrowsError(try CalculationBasis(proteinGramsText: "1", referenceQuantity: per100g, origin: .providerSnapshot, provider: nil))
        XCTAssertThrowsError(try CalculationBasis(proteinGramsText: "1", referenceQuantity: per100g, origin: .userDefined,
                                                  provider: CalculationBasis.ProviderReference(providerID: "a", dataVersion: "b", itemID: "c")))
        XCTAssertTrue(basis.isReferenceEditable)
        XCTAssertFalse(try providerBasis(reference: FoodQuantity(value: "1234567890", unit: .gram)).isReferenceEditable)
        XCTAssertFalse(try providerBasis(reference: FoodQuantity(value: "0.0001", unit: .gram)).isReferenceEditable)
    }

    func testRecordWithBasisDerivesProteinAndRejectsEveryMismatch() throws {
        let basis = try providerBasis()
        let eaten = try FoodQuantity(value: "150", unit: .gram)
        let record = try FoodRecord(id: "r1", day: day, name: "샌드위치_닭가슴살", quantity: eaten, basis: basis)
        XCTAssertEqual(record.protein.centigrams, 1_827)
        XCTAssertEqual(record.quantity, eaten)
        XCTAssertEqual(record.source, .search)
        XCTAssertEqual(record.calculationBasis, basis)

        func make(quantity: FoodQuantity?, protein: Int64, source: FoodRecord.Source = .search) throws -> FoodRecord {
            try FoodRecord(id: "r", day: day, name: nil, quantity: quantity, protein: ProteinAmount(centigrams: protein),
                           source: source, legacySourceID: nil, calculationBasis: basis)
        }
        XCTAssertNoThrow(try make(quantity: eaten, protein: 1_827))
        XCTAssertThrowsError(try make(quantity: eaten, protein: 1_828)) { XCTAssertTrue("\($0)".contains("differs from computed"), "\($0)") }
        XCTAssertThrowsError(try make(quantity: nil, protein: 1_827)) { XCTAssertTrue("\($0)".contains("without quantity"), "\($0)") }
        XCTAssertThrowsError(try make(quantity: eaten, protein: 1_827, source: .manual)) { XCTAssertTrue("\($0)".contains("cannot carry"), "\($0)") }
        XCTAssertThrowsError(try make(quantity: FoodQuantity(value: "150", unit: .milliliter), protein: 1_827)) {
            XCTAssertTrue("\($0)".contains("unit"), "\($0)")
        }
        XCTAssertThrowsError(try make(quantity: FoodQuantity(value: "1234567890", unit: .gram), protein: 1)) {
            XCTAssertTrue("\($0)".contains("input range"), "\($0)")
        }
        XCTAssertThrowsError(try FoodRecord(id: "r", day: day, name: nil, quantity: FoodQuantity(value: "0.01", unit: .gram), basis: basis)) {
            XCTAssertEqual($0 as? RecordDomainError, .portion(.roundsToZero))
        }
    }

    func testEditsKeepIdentityAndBasisSemantics() throws {
        let basis = try providerBasis()
        let record = try FoodRecord(id: "r1", day: day, name: "Chicken", quantity: FoodQuantity(value: "150", unit: .gram), basis: basis)

        // Name only: basis, quantity and protein untouched.
        let renamed = try record.withChanges(name: .some("Chicken sandwich"))
        XCTAssertEqual(renamed.name, "Chicken sandwich")
        XCTAssertEqual(renamed.calculationBasis, basis)
        XCTAssertEqual(renamed.protein, record.protein)
        XCTAssertEqual(renamed.quantity, record.quantity)
        // Same protein through the generic edit: still the provider basis.
        XCTAssertEqual(try record.withChanges(protein: record.protein).calculationBasis, basis)

        // Quantity: recomputed from the original basis, ID/day/source kept.
        let more = try record.withQuantity(FoodQuantity(value: "200", unit: .gram))
        XCTAssertEqual(more.protein.centigrams, 2_436)
        XCTAssertEqual(more.id, "r1")
        XCTAssertEqual(more.day, day)
        XCTAssertEqual(more.source, .search)
        XCTAssertEqual(more.calculationBasis, basis)
        XCTAssertEqual(try more.withQuantity(FoodQuantity(value: "150", unit: .gram)), record, "back to the original amount is the original record")
        XCTAssertThrowsError(try record.withQuantity(FoodQuantity(value: "200", unit: .milliliter))) {
            XCTAssertEqual($0 as? RecordDomainError, .portion(.unitMismatch))
        }
        XCTAssertThrowsError(try record.withQuantity(FoodQuantity(value: "1234567890", unit: .gram))) {
            XCTAssertEqual($0 as? RecordDomainError, .invalidQuantity)
        }

        // Direct protein: a new user-defined basis of (current quantity, entered protein); provider IDs dropped.
        let direct = try record.withDirectProtein(ProteinAmount(centigrams: 2_000))
        XCTAssertEqual(direct.protein.centigrams, 2_000)
        XCTAssertEqual(direct.quantity, record.quantity)
        XCTAssertEqual(direct.calculationBasis?.origin, .userDefined)
        XCTAssertNil(direct.calculationBasis?.provider)
        XCTAssertEqual(direct.calculationBasis?.proteinGramsText, "20")
        XCTAssertEqual(direct.calculationBasis?.referenceQuantity, record.quantity)
        XCTAssertEqual(try direct.withQuantity(FoodQuantity(value: "300", unit: .gram)).protein.centigrams, 4_000, "later amount edits use the new basis")
        XCTAssertEqual(try record.withChanges(protein: ProteinAmount(centigrams: 2_000)), direct, "the generic edit routes a changed protein the same way")
        XCTAssertThrowsError(try record.withDirectProtein(ProteinAmount(centigrams: Int64.max))) {
            guard case .invalidBasis(let reason)? = $0 as? RecordDomainError else { return XCTFail("\($0)") }
            XCTAssertTrue(reason.contains("significant"), reason)
        }

        // Records without a basis: unchanged behaviour, no quantity editing.
        let old = try FoodRecord(id: "old", day: day, name: "Milk", quantity: per100g, protein: ProteinAmount(centigrams: 340), source: .search)
        XCTAssertNil(old.calculationBasis)
        let oldEdited = try old.withChanges(name: .some("Milk 2"), protein: ProteinAmount(centigrams: 500))
        XCTAssertNil(oldEdited.calculationBasis)
        XCTAssertEqual(oldEdited.quantity, per100g)
        XCTAssertEqual(oldEdited.source, .search)
        XCTAssertThrowsError(try old.withQuantity(FoodQuantity(value: "200", unit: .gram))) {
            XCTAssertEqual($0 as? RecordDomainError, .quantityNotEditable)
        }
        XCTAssertNil(try old.withDirectProtein(ProteinAmount(centigrams: 700)).calculationBasis)
    }

    // MARK: Persistence

    func testBasisRoundTripsThroughJSONAndOldFilesStillDecodeWithoutIt() throws {
        let basis = try providerBasis(protein: "1.005")
        let record = try FoodRecord(id: "r1", day: day, name: "x", quantity: FoodQuantity(value: "200", unit: .gram), basis: basis)
        let data = try JSONEncoder().encode(record)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""proteinGramsText":"1.005""#), json)
        XCTAssertTrue(json.contains(#""origin":"providerSnapshot""#), json)
        XCTAssertFalse(json.contains("http"), "no URLs")
        XCTAssertEqual(try JSONDecoder().decode(FoodRecord.self, from: data), record)

        let old = #"{"id":"a","day":"2026-10-14","name":"Milk","quantity":{"value":"100","unit":"gram"},"protein":340,"source":"search"}"#
        let decoded = try JSONDecoder().decode(FoodRecord.self, from: Data(old.utf8))
        XCTAssertNil(decoded.calculationBasis)
        XCTAssertEqual(decoded.quantity?.value, "100")
        // A stored quantity longer than the new limits still decodes (limits apply to a basis only).
        let long = #"{"id":"a","day":"2026-10-14","quantity":{"value":"12345678901234567890.123456789012","unit":"gram"},"protein":340,"source":"search"}"#
        XCTAssertEqual(try JSONDecoder().decode(FoodRecord.self, from: Data(long.utf8)).quantity?.value, "12345678901234567890.123456789012")
        XCTAssertFalse(json.contains("legacySourceID"), "nil fields are omitted as before")
    }

    func testCorruptBasisInJSONIsAnErrorNotNil() throws {
        func json(protein: Int = 1_827, source: String = "search", origin: String = "providerSnapshot",
                  itemID: String = "i", referenceUnit: String = "gram", proteinText: String = "12.18") -> Data {
            Data("""
            {"id":"a","day":"2026-10-14","quantity":{"value":"150","unit":"gram"},"protein":\(protein),"source":"\(source)",
             "calculationBasis":{"proteinGramsText":"\(proteinText)","referenceQuantity":{"value":"100","unit":"\(referenceUnit)"},
             "origin":"\(origin)","provider":{"providerID":"p","dataVersion":"v","itemID":"\(itemID)"}}}
            """.utf8)
        }
        XCTAssertNoThrow(try JSONDecoder().decode(FoodRecord.self, from: json()))
        XCTAssertThrowsError(try JSONDecoder().decode(FoodRecord.self, from: json(protein: 1_828))) {
            XCTAssertTrue("\($0)".contains("differs from computed"), "\($0)")
        }
        XCTAssertThrowsError(try JSONDecoder().decode(FoodRecord.self, from: json(source: "manual")))
        XCTAssertThrowsError(try JSONDecoder().decode(FoodRecord.self, from: json(origin: "userDefined")), "userDefined with provider IDs")
        XCTAssertThrowsError(try JSONDecoder().decode(FoodRecord.self, from: json(itemID: "")))
        XCTAssertThrowsError(try JSONDecoder().decode(FoodRecord.self, from: json(referenceUnit: "milliliter")))
        XCTAssertThrowsError(try JSONDecoder().decode(FoodRecord.self, from: json(proteinText: "abc")))
        XCTAssertThrowsError(try JSONDecoder().decode(FoodRecord.self, from: json(proteinText: "1e1")))
    }

    func testSchema2ReaderRejectsABasisAndSchema3DocumentsRejectOldReaders() throws {
        let day = self.day
        func document(version: Int, record: String) -> Data {
            Data("""
            {"schemaVersion":\(version),"logs":[{"day":"\(day.iso8601)","records":[\(record)]}],"favorites":[],"searchHistory":[],
             "settings":{"searchLanguage":{"raw":null,"resolved":"english","isFallback":true},"legacyTargetRaw":null,"goalNeedsReview":false},
             "goals":[],"migration":{"origin":"freshInstall","migrationVersion":1,"completedAt":"2026-10-14T00:00:00Z","sourceFingerprint":null,"verification":null}}
            """.utf8)
        }
        let plain = #"{"id":"a","day":"2026-10-14","protein":340,"source":"manual"}"#
        let withBasis = #"{"id":"b","day":"2026-10-14","quantity":{"value":"150","unit":"gram"},"protein":1827,"source":"search","calculationBasis":{"proteinGramsText":"12.18","referenceQuantity":{"value":"100","unit":"gram"},"origin":"providerSnapshot","provider":{"providerID":"p","dataVersion":"v","itemID":"i"}}}"#

        let promoted = try AppState.decodeSchema2(document(version: 2, record: plain))
        XCTAssertEqual(promoted.schemaVersion, 3)
        XCTAssertNil(promoted.logs.first?.records.first?.calculationBasis)
        XCTAssertThrowsError(try AppState.decodeSchema2(document(version: 2, record: withBasis))) {
            XCTAssertTrue("\($0)".contains("not part of schema 2"), "\($0)")
        }
        XCTAssertThrowsError(try AppState.decodeSchema2(document(version: 3, record: plain))) {
            XCTAssertEqual($0 as? AppStateError, .unsupportedSchema(3), "a schema 2 writer never accepts schema 3")
        }
        XCTAssertThrowsError(try JSONDecoder().decode(AppState.self, from: document(version: 2, record: plain))) {
            XCTAssertEqual($0 as? AppStateError, .unsupportedSchema(2), "the current reader does not open schema 2 directly")
        }
        XCTAssertNoThrow(try JSONDecoder().decode(AppState.self, from: document(version: 3, record: withBasis)))
    }

    // MARK: Batch

    func testBatchWritesBasisRecordsAndRechecksTheSnapshot() throws {
        let basis = try providerBasis()
        let eaten = try FoodQuantity(value: "150", unit: .gram)
        let withBasis = SearchSelection(itemKey: "k1", recordID: "r1", name: "A", proteinCentigrams: 1_827, quantity: eaten, basis: basis)
        let plain = SearchSelection(itemKey: "k2", recordID: "r2", name: "B", proteinCentigrams: 500, quantity: per100g)
        let records = try SearchRecordBatch.records(for: [withBasis, plain], on: day)
        XCTAssertEqual(records.map(\.calculationBasis), [basis, nil])
        XCTAssertEqual(records.map(\.protein.centigrams), [1_827, 500])
        XCTAssertEqual(records.map(\.quantity), [eaten, per100g])
        XCTAssertEqual(try SearchRecordBatch.totalCentigrams([withBasis, plain]), 2_327)

        let stale = SearchSelection(itemKey: "k1", recordID: "r1", name: "A", proteinCentigrams: 1_218, quantity: eaten, basis: basis)
        XCTAssertThrowsError(try SearchRecordBatch.records(for: [stale], on: day)) {
            guard case .basisMismatch(let detail)? = $0 as? SearchBatchError else { return XCTFail("\($0)") }
            XCTAssertTrue(detail.hasPrefix("k1:"), detail)
        }
    }
}
