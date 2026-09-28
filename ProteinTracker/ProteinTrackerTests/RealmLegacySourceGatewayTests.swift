import XCTest
import RealmSwift
import MigrationCore

/// Real Realm files in a temporary directory plus an isolated UserDefaults
/// suite. The user's default Realm and standard defaults are never touched.
final class RealmLegacySourceGatewayTests: XCTestCase {
    private var directory: URL!
    private var realmURL: URL { directory.appendingPathComponent("legacy/default.realm") }
    private var backupDirectory: URL { directory.appendingPathComponent("evidence/legacy-backup") }
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("GatewayTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("legacy"), withIntermediateDirectories: true)
        suiteName = "GatewayTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try FileManager.default.removeItem(at: directory)
    }

    private func writeLegacyRealm() throws {
        let configuration = Realm.Configuration(fileURL: realmURL, objectTypes: LegacyRealmSnapshotReader.objectTypes)
        try autoreleasepool {
            let realm = try Realm(configuration: configuration)
            try realm.write {
                realm.add(DailyProtein(proteinName: "우유", proteinIntake: 10))
                realm.add(DailyProtein(proteinName: "계란", proteinIntake: 35))
                realm.add(StatProtein(date: "2026-09-20-일", originDate: Date(timeIntervalSince1970: 1_758_326_400), totalIntake: 70))
                realm.add(Favorites(proteinName: "닭가슴살", proteinIntake: 23))
                realm.add(SearchHistory(proteinName: "egg"))
                realm.add(SearchHistory(proteinName: "egg"))
            }
            realm.invalidate()
        }
        defaults.set("2026-09-23-화", forKey: "date")
        defaults.set(Date(timeIntervalSince1970: 1_758_585_600.25), forKey: "Date")
        defaults.set(55, forKey: "totalIntake")
        defaults.set("120", forKey: "targetProtein")
        defaults.set("Korean(한글)", forKey: "searchLanguage")
    }

    private func gateway() -> RealmLegacySourceGateway {
        RealmLegacySourceGateway(realmFileURL: realmURL, defaults: defaults, backupDirectory: backupDirectory)
    }

    private func logicalValues(at url: URL) throws -> (foods: [(String, Int)], stats: [(String, Int)], favorites: [(String, Int)], searches: [String]) {
        try autoreleasepool {
            let realm = try Realm(configuration: Realm.Configuration(fileURL: url, readOnly: true, objectTypes: LegacyRealmSnapshotReader.objectTypes))
            defer { realm.invalidate() }
            return (
                realm.objects(DailyProtein.self).map { ($0.proteinName, $0.proteinIntake) },
                realm.objects(StatProtein.self).map { ($0.date, $0.totalIntake) },
                realm.objects(Favorites.self).map { ($0.proteinName, $0.proteinIntake) },
                realm.objects(SearchHistory.self).map { $0.proteinName }
            )
        }
    }

    func testProbeDoesNotCreateARealmFile() throws {
        let probe = try gateway().probe()
        XCTAssertFalse(probe.realmFilePresent)
        XCTAssertEqual(probe.presentDefaultsKeys, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: realmURL.path))
        defaults.set("120", forKey: "targetProtein")
        XCTAssertEqual(try gateway().probe().presentDefaultsKeys, ["targetProtein"])
    }

    func testCaptureWithoutRealmFileReadsDefaultsOnlyAndCreatesNoRealm() throws {
        defaults.set("120", forKey: "targetProtein")
        defaults.set(0, forKey: "totalIntake")
        let capture = try gateway().capture()
        XCTAssertFalse(capture.realmFilePresent)
        XCTAssertTrue(capture.raw.foods.isEmpty)
        XCTAssertEqual(capture.raw.target, "120")
        XCTAssertEqual(capture.raw.currentTotal, 0)
        XCTAssertEqual(capture.defaults["totalIntake"], .integer(0))
        XCTAssertEqual(capture.defaults["date"], .missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: realmURL.path), "no default.realm must be created")
    }

    func testCaptureCopiesFirstOpensCopyReadOnlyAndLeavesOriginalIdentical() throws {
        try writeLegacyRealm()
        let before = try Data(contentsOf: realmURL)
        let beforeLogical = try logicalValues(at: realmURL)
        // Seeding and the logical read above opened the original; drop their
        // companion files so any open by the gateway would be visible.
        for suffix in [".lock", ".note", ".management"] {
            try? FileManager.default.removeItem(atPath: realmURL.path + suffix)
        }

        let capture = try gateway().capture()
        XCTAssertFalse(FileManager.default.fileExists(atPath: realmURL.path + ".lock"), "original never opened")

        XCTAssertTrue(capture.realmFilePresent)
        XCTAssertEqual(capture.raw.foods.map(\.name), ["우유", "계란"])
        XCTAssertEqual(capture.raw.foods.map(\.protein), [10, 35])
        XCTAssertEqual(capture.raw.history.map(\.dayLabel), ["2026-09-20-일"])
        XCTAssertEqual(capture.raw.history.map(\.total), [70])
        XCTAssertEqual(capture.raw.favorites.map(\.protein), [23])
        XCTAssertEqual(capture.raw.searchHistory.map(\.value), ["egg", "egg"], "duplicates preserved")
        XCTAssertEqual(capture.raw.savedDayLabel, "2026-09-23-화")
        XCTAssertEqual(capture.raw.savedDate?.timeIntervalSince1970, 1_758_585_600.25)
        XCTAssertEqual(capture.raw.currentTotal, 55)
        XCTAssertEqual(capture.raw.target, "120")
        XCTAssertEqual(capture.raw.searchLanguage, "Korean(한글)")
        XCTAssertTrue(capture.typeIssues.isEmpty)
        XCTAssertEqual(capture.raw.foods.map(\.id).count, Set(capture.raw.foods.map(\.id)).count)

        // Original bytes untouched; pristine physical copy exists; no read copies remain.
        XCTAssertEqual(try Data(contentsOf: realmURL), before)
        let pristine = gateway().pristineCopyURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: pristine.path))
        let afterLogical = try logicalValues(at: realmURL)
        XCTAssertEqual(afterLogical.foods.map(\.0), beforeLogical.foods.map(\.0))
        XCTAssertEqual(try logicalValues(at: pristine).stats.map(\.1), [70])
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: backupDirectory.path).filter { $0.hasPrefix("read-copy") }
        XCTAssertTrue(leftovers.isEmpty, "\(leftovers)")
    }

    func testRepeatedCaptureGivesSameFingerprintAndKeepsFirstPristineCopy() throws {
        try writeLegacyRealm()
        let first = try gateway().capture()
        let pristineBytes = try Data(contentsOf: gateway().pristineCopyURL)
        let second = try gateway().capture()
        XCTAssertEqual(first, second)
        XCTAssertEqual(try LegacyFingerprint.sha256Hex(of: first), try LegacyFingerprint.sha256Hex(of: second))
        XCTAssertEqual(try Data(contentsOf: gateway().pristineCopyURL), pristineBytes)
    }

    func testWrongDefaultsTypesAreReportedNotCoerced() throws {
        try writeLegacyRealm()
        defaults.set("55", forKey: "totalIntake")
        defaults.set(true, forKey: "searchLanguage")
        defaults.set(12.5, forKey: "targetProtein")
        let capture = try gateway().capture()
        XCTAssertEqual(capture.defaults["totalIntake"], .string("55"))
        XCTAssertEqual(capture.defaults["searchLanguage"], .bool(true))
        XCTAssertEqual(capture.defaults["targetProtein"], .double(12.5))
        XCTAssertEqual(capture.typeIssues.map(\.key).sorted(), ["searchLanguage", "totalIntake"])
        XCTAssertNil(capture.raw.currentTotal)
        XCTAssertEqual(capture.raw.target, "12.5")
    }

    func testTypedValueClassification() {
        XCTAssertEqual(LegacyRealmSnapshotReader.typedValue(nil), .missing)
        XCTAssertEqual(LegacyRealmSnapshotReader.typedValue(NSNumber(value: 7)), .integer(7))
        XCTAssertEqual(LegacyRealmSnapshotReader.typedValue(NSNumber(value: true)), .bool(true))
        XCTAssertEqual(LegacyRealmSnapshotReader.typedValue(NSNumber(value: 1.5)), .double(1.5))
        XCTAssertEqual(LegacyRealmSnapshotReader.typedValue("x"), .string("x"))
        XCTAssertEqual(LegacyRealmSnapshotReader.typedValue(Data([1])), .data(base64: "AQ=="))
        if case .date(let seconds, _)? = Optional(LegacyRealmSnapshotReader.typedValue(Date(timeIntervalSince1970: 5))) {
            XCTAssertEqual(seconds, 5)
        } else { XCTFail("date") }
        if case .unsupported = LegacyRealmSnapshotReader.typedValue([1, 2]) {} else { XCTFail("array") }
    }
}
