import XCTest
@testable import HelloProteinCore

final class SearchRecordBatchTests: XCTestCase {
    private let day = try! CalendarDay(iso8601: "2026-10-07")
    private let per100g = try! FoodQuantity(value: "100", unit: .gram)

    private func selection(_ key: String, record: String, name: String = "Food", centigrams: Int64 = 2_300,
                           quantity: FoodQuantity? = nil) -> SearchSelection {
        SearchSelection(itemKey: key, recordID: record, name: name, proteinCentigrams: centigrams, quantity: quantity ?? per100g)
    }

    // MARK: Gram text conversion

    func testGramTextConvertsExactlyWithHalfUpRoundingOnTheThirdDigit() throws {
        XCTAssertEqual(try ProteinGramsText.centigrams("0.85"), .init(centigrams: 85, rounded: false))
        XCTAssertEqual(try ProteinGramsText.centigrams("23"), .init(centigrams: 2_300, rounded: false))
        XCTAssertEqual(try ProteinGramsText.centigrams("23.5"), .init(centigrams: 2_350, rounded: false))
        XCTAssertEqual(try ProteinGramsText.centigrams("21.4"), .init(centigrams: 2_140, rounded: false))
        XCTAssertEqual(try ProteinGramsText.centigrams("1.005"), .init(centigrams: 101, rounded: true), "half up")
        XCTAssertEqual(try ProteinGramsText.centigrams("1.004"), .init(centigrams: 100, rounded: true))
        XCTAssertEqual(try ProteinGramsText.centigrams("0.004"), .init(centigrams: 0, rounded: true), "not selectable")
        XCTAssertEqual(try ProteinGramsText.centigrams("0.005"), .init(centigrams: 1, rounded: true))
        XCTAssertEqual(try ProteinGramsText.centigrams("2.9999"), .init(centigrams: 300, rounded: true))
        XCTAssertEqual(try ProteinGramsText.centigrams("1.2300"), .init(centigrams: 123, rounded: false), "trailing zeros are not a rounding")
        XCTAssertEqual(try ProteinGramsText.centigrams(".5"), .init(centigrams: 50, rounded: false))
        XCTAssertEqual(try ProteinGramsText.centigrams("5."), .init(centigrams: 500, rounded: false))
        XCTAssertEqual(try ProteinGramsText.centigrams("0"), .init(centigrams: 0, rounded: false))
        XCTAssertEqual(try ProteinGramsText.centigrams("-0"), .init(centigrams: 0, rounded: false))
    }

    func testGramTextRejectsWhatIsNotAPlainDecimal() {
        for text in ["", "-", ".", "1e3", "1E3", "NaN", "inf", "Infinity", "1,5", " 1", "1 ", "+1", "1.2.3", "１２", "abc", "1-"] {
            XCTAssertThrowsError(try ProteinGramsText.centigrams(text), text) {
                XCTAssertEqual($0 as? ProteinGramsTextError, .notANumber, text)
            }
        }
        XCTAssertThrowsError(try ProteinGramsText.centigrams("-5")) { XCTAssertEqual($0 as? ProteinGramsTextError, .negative) }
        XCTAssertThrowsError(try ProteinGramsText.centigrams("-0.004")) { XCTAssertEqual($0 as? ProteinGramsTextError, .negative) }
        XCTAssertEqual(try ProteinGramsText.centigrams("92233720368547758.07").centigrams, Int64.max)
        XCTAssertThrowsError(try ProteinGramsText.centigrams("92233720368547758.08")) { XCTAssertEqual($0 as? ProteinGramsTextError, .overflow) }
        XCTAssertThrowsError(try ProteinGramsText.centigrams("92233720368547758.075")) { XCTAssertEqual($0 as? ProteinGramsTextError, .overflow) }
        XCTAssertThrowsError(try ProteinGramsText.centigrams("99999999999999999999")) { XCTAssertEqual($0 as? ProteinGramsTextError, .overflow) }
    }

    // MARK: Batch

    func testRecordsKeepSelectionOrderSourceAndQuantity() throws {
        let serving = try FoodQuantity(value: "1", unit: .serving)
        let records = try SearchRecordBatch.records(for: [selection("k2", record: "r2", name: "Milk", centigrams: 340, quantity: serving),
                                                          selection("k1", record: "r1", name: "Egg")], on: day)
        XCTAssertEqual(records.map(\.id), ["r2", "r1"])
        XCTAssertEqual(records.map(\.name), ["Milk", "Egg"])
        XCTAssertEqual(records.map(\.source), [.search, .search])
        XCTAssertEqual(records.map(\.quantity), [serving, per100g])
        XCTAssertEqual(records.map(\.protein.centigrams), [340, 2_300])
        XCTAssertEqual(records.map(\.day), [day, day])
        XCTAssertTrue(records.allSatisfy { $0.legacySourceID == nil })
        XCTAssertEqual(try SearchRecordBatch.totalCentigrams([selection("a", record: "1", centigrams: 1), selection("b", record: "2", centigrams: 2)]), 3)
    }

    func testBatchFailsAsAWholeOnEmptyDuplicateInvalidOrOverflow() throws {
        XCTAssertThrowsError(try SearchRecordBatch.records(for: [], on: day)) { XCTAssertEqual($0 as? SearchBatchError, .emptySelection) }
        XCTAssertThrowsError(try SearchRecordBatch.records(for: [selection("k", record: "r1"), selection("k", record: "r2")], on: day)) {
            XCTAssertEqual($0 as? SearchBatchError, .duplicateSelection("k"))
        }
        XCTAssertThrowsError(try SearchRecordBatch.records(for: [selection("a", record: "r"), selection("b", record: "r")], on: day)) {
            XCTAssertEqual($0 as? SearchBatchError, .duplicateRecordID("r"))
        }
        XCTAssertThrowsError(try SearchRecordBatch.records(for: [selection("a", record: "r1"), selection("b", record: "r2", centigrams: 0)], on: day)) {
            XCTAssertEqual($0 as? SearchBatchError, .invalidAmount("b"))
        }
        XCTAssertThrowsError(try SearchRecordBatch.records(for: [selection("a", record: "r1", centigrams: -1)], on: day)) {
            XCTAssertEqual($0 as? SearchBatchError, .invalidAmount("a"))
        }
        XCTAssertThrowsError(try SearchRecordBatch.records(for: [selection("a", record: "r1", centigrams: .max), selection("b", record: "r2", centigrams: 1)], on: day)) {
            XCTAssertEqual($0 as? SearchBatchError, .arithmeticOverflow)
        }
        XCTAssertThrowsError(try SearchRecordBatch.totalCentigrams([selection("a", record: "r1", centigrams: .max), selection("b", record: "r2", centigrams: 1)]))
    }
}
