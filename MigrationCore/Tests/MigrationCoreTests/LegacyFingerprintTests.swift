import XCTest
@testable import MigrationCore

final class LegacyFingerprintTests: XCTestCase {
    private func capture(total: Int64 = 55, keys: [(String, LegacyDefaultsValue)]) -> LegacyCapture {
        var defaults: [String: LegacyDefaultsValue] = [:]
        for (key, value) in keys { defaults[key] = value }
        defaults["totalIntake"] = .integer(total)
        return LegacyCapture(
            realmFilePresent: true, defaults: defaults,
            foods: [.init(id: "a", name: "우유", protein: 10)],
            history: [.init(id: "h", dayLabel: "2026-09-20-Sun", storedDate: Date(timeIntervalSince1970: 1_758_326_400.5), total: 70)],
            favorites: [], searchHistory: [.init(id: "s", value: "egg")]
        )
    }

    func testSameValuesGiveSameHexRegardlessOfDictionaryOrder() throws {
        let a = capture(keys: [("date", .string("2026-09-23-Tue")), ("targetProtein", .string("120"))])
        let b = capture(keys: [("targetProtein", .string("120")), ("date", .string("2026-09-23-Tue"))])
        let hex = try LegacyFingerprint.sha256Hex(of: a)
        XCTAssertEqual(hex, try LegacyFingerprint.sha256Hex(of: b))
        XCTAssertEqual(hex.count, 64)
        XCTAssertTrue(hex.allSatisfy { "0123456789abcdef".contains($0) })
    }

    func testValueOrTypeChangeChangesFingerprint() throws {
        let base = try LegacyFingerprint.sha256Hex(of: capture(keys: [("date", .string("2026-09-23-Tue"))]))
        XCTAssertNotEqual(base, try LegacyFingerprint.sha256Hex(of: capture(total: 56, keys: [("date", .string("2026-09-23-Tue"))])))
        XCTAssertNotEqual(base, try LegacyFingerprint.sha256Hex(of: capture(keys: [("date", .string("2026-09-23-Wed"))])))
        XCTAssertNotEqual(base, try LegacyFingerprint.sha256Hex(of: capture(keys: [("date", .integer(0))])))
    }

    func testKnownVectorForEmptyData() {
        XCTAssertEqual(LegacyFingerprint.sha256Hex(of: Data()),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}
