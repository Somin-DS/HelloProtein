import XCTest
@testable import MigrationCore

final class LegacyDefaultsInterpreterTests: XCTestCase {
    func testMissingExplicitZeroAndWrongTypeAreDistinguished() {
        let missing = LegacyDefaultsInterpreter.interpret([:])
        XCTAssertNil(missing.currentTotal)
        XCTAssertTrue(missing.issues.isEmpty)

        let zero = LegacyDefaultsInterpreter.interpret(["totalIntake": .integer(0)])
        XCTAssertEqual(zero.currentTotal, 0)
        XCTAssertTrue(zero.issues.isEmpty)

        let wrong = LegacyDefaultsInterpreter.interpret(["totalIntake": .string("12"), "date": .integer(3), "Date": .string("x"), "searchLanguage": .bool(true)])
        XCTAssertNil(wrong.currentTotal)
        XCTAssertEqual(wrong.issues.map(\.key).sorted(), ["Date", "date", "searchLanguage", "totalIntake"])
    }

    func testTargetAcceptsStringOrNumberButKeepsOriginalText() {
        XCTAssertEqual(LegacyDefaultsInterpreter.interpret(["targetProtein": .string("120.5")]).target, "120.5")
        XCTAssertEqual(LegacyDefaultsInterpreter.interpret(["targetProtein": .integer(90)]).target, "90")
        XCTAssertEqual(LegacyDefaultsInterpreter.interpret(["targetProtein": .data(base64: "AA==")]).issues.count, 1)
    }

    func testDefaultsValueRoundTripsThroughJSON() throws {
        let values: [String: LegacyDefaultsValue] = [
            "date": .string("2026-09-28-Mon"),
            "Date": .date(secondsSince1970: 1_790_638_200.123456, iso8601: "2026-09-28T23:30:00.123Z"),
            "totalIntake": .integer(-5),
            "targetProtein": .double(1.5),
            "flag": .bool(false),
            "blob": .data(base64: "AQID"),
            "weird": .unsupported(typeName: "NSArray"),
            "gone": .missing,
        ]
        let data = try JSONEncoder().encode(values)
        XCTAssertEqual(try JSONDecoder().decode([String: LegacyDefaultsValue].self, from: data), values)
    }

    func testCaptureConvenienceInterpretsAndKeepsIssues() {
        let capture = LegacyCapture(
            realmFilePresent: true,
            defaults: ["totalIntake": .integer(55), "date": .string("2026-09-23-Tue"), "targetProtein": .bool(true)],
            foods: [.init(id: "a", name: "우유", protein: 10)], history: [], favorites: [], searchHistory: []
        )
        XCTAssertEqual(capture.raw.currentTotal, 55)
        XCTAssertEqual(capture.raw.savedDayLabel, "2026-09-23-Tue")
        XCTAssertEqual(capture.typeIssues, [.init(key: "targetProtein", found: .bool(true))])
    }
}
