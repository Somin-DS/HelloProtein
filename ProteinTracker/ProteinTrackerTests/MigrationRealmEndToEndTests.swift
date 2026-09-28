import XCTest
import RealmSwift
import HelloProteinCore
import MigrationCore

/// Real Realm file → gateway → coordinator → schema 2 store, in a temp dir.
final class MigrationRealmEndToEndTests: XCTestCase {
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var realmURL: URL { directory.appendingPathComponent("legacy/default.realm") }
    private var paths: RenewalPaths { RenewalPaths(rootDirectory: directory.appendingPathComponent("HelloProtein")) }
    private let today = try! CalendarDay(iso8601: "2026-09-28")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("E2E-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("legacy"), withIntermediateDirectories: true)
        suiteName = "E2E-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try FileManager.default.removeItem(at: directory)
    }

    private func seed() throws {
        try autoreleasepool {
            let realm = try Realm(configuration: Realm.Configuration(fileURL: realmURL, objectTypes: LegacyRealmSnapshotReader.objectTypes))
            try realm.write {
                realm.add(DailyProtein(proteinName: "우유", proteinIntake: 10))
                realm.add(DailyProtein(proteinName: "계란", proteinIntake: 35))
                realm.add(StatProtein(date: "2026-09-20-일", originDate: Date(timeIntervalSince1970: 1_758_326_400), totalIntake: 70))
                realm.add(StatProtein(date: "2026-09-22-화", originDate: Date(timeIntervalSince1970: 1_758_499_200), totalIntake: 15))
                realm.add(Favorites(proteinName: "닭가슴살", proteinIntake: 23))
                realm.add(SearchHistory(proteinName: "egg"))
            }
            realm.invalidate()
        }
        defaults.set("2026-09-23-화", forKey: "date")
        defaults.set(Date(timeIntervalSince1970: 1_758_585_600), forKey: "Date")
        defaults.set(55, forKey: "totalIntake")
        defaults.set("120", forKey: "targetProtein")
        defaults.set("Korean(한글)", forKey: "searchLanguage")
    }

    private func coordinator(interrupt: @escaping (InterruptionPoint) throws -> Void = { _ in }) -> MigrationCoordinator {
        let store = FileAppStateStore(fileURL: paths.storeFileURL, hooks: StoreCommitHooks { stage in
            if stage == .beforeReplace { try interrupt(.beforeReplace) }
            if stage == .afterReplace { try interrupt(.afterReplace) }
        })
        return MigrationCoordinator(
            store: store,
            legacy: RealmLegacySourceGateway(realmFileURL: realmURL, defaults: defaults, backupDirectory: paths.legacyBackupDirectory),
            evidence: FileMigrationEvidenceStore(directory: paths.evidenceDirectory),
            environment: MigrationEnvironment(today: today, now: { Date(timeIntervalSince1970: 1_790_600_000) }, interrupt: interrupt)
        )
    }

    func testRealUpgradePreservesEverythingAndOriginalIsUnchanged() throws {
        try seed()
        let originalBytes = try Data(contentsOf: realmURL)
        guard case .ready(let state) = coordinator().launch() else { return XCTFail("expected ready") }

        XCTAssertEqual(state.migration.origin, .legacyImport)
        XCTAssertEqual(state.logs.map(\.day.iso8601), ["2026-09-20", "2026-09-22", "2026-09-23"])
        let current = try XCTUnwrap(state.log(for: CalendarDay(iso8601: "2026-09-23")))
        XCTAssertEqual(current.records.map(\.name), ["우유", "계란"])
        XCTAssertEqual(try current.totalProteinCentigrams(), 5_500)
        XCTAssertEqual(current.legacyAdjustmentCentigrams, 1_000)
        XCTAssertEqual(try state.log(for: CalendarDay(iso8601: "2026-09-20"))?.totalProteinCentigrams(), 7_000)
        XCTAssertEqual(try state.log(for: CalendarDay(iso8601: "2026-09-22"))?.totalProteinCentigrams(), 1_500)
        XCTAssertEqual(state.favorites.map(\.name), ["닭가슴살"])
        XCTAssertEqual(state.searchHistory.map(\.value), ["egg"])
        XCTAssertEqual(state.goals.first?.amount.centigrams, 12_000)
        XCTAssertEqual(state.settings.searchLanguage.resolved, .korean)

        // Store on disk equals the returned state; evidence complete; original untouched.
        XCTAssertEqual(try FileAppStateStore(fileURL: paths.storeFileURL).load(), state)
        let evidence = FileMigrationEvidenceStore(directory: paths.evidenceDirectory)
        XCTAssertEqual(try evidence.latestBackup()?.fingerprint, state.migration.sourceFingerprint)
        XCTAssertNotNil(try evidence.completionEvidence())
        XCTAssertEqual(try Data(contentsOf: realmURL), originalBytes)
        XCTAssertEqual(defaults.integer(forKey: "totalIntake"), 55)
        XCTAssertEqual(defaults.string(forKey: "date"), "2026-09-23-화")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.legacyBackupDirectory.appendingPathComponent("default.realm").path))
    }

    func testCrashBeforeReplaceThenRelaunchCompletesWithoutDuplicates() throws {
        try seed()
        struct Crash: Error {}
        var armed = true
        let first = coordinator { point in
            if armed && point == .beforeReplace { armed = false; throw Crash() }
        }.launch()
        guard case .recovery(let recovery) = first else { return XCTFail("expected recovery") }
        XCTAssertEqual(recovery.kind, .interrupted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.storeFileURL.path))
        XCTAssertNotNil(try FileMigrationEvidenceStore(directory: paths.evidenceDirectory).latestBackup())

        guard case .ready(let state) = coordinator().launch() else { return XCTFail("expected ready") }
        XCTAssertEqual(state.logs.flatMap(\.records).count, 2)
        XCTAssertEqual(state.favorites.count, 1)
        guard case .ready(let again) = coordinator().launch() else { return XCTFail("expected ready") }
        XCTAssertEqual(again, state)
    }

    func testUserEditsSurviveAnotherLaunch() throws {
        try seed()
        guard case .ready = coordinator().launch() else { return XCTFail("expected ready") }
        let store = FileAppStateStore(fileURL: paths.storeFileURL)
        let day = try CalendarDay(iso8601: "2026-09-20")
        try store.modify { state in
            var log = state.log(for: day)!
            try log.add(FoodRecord(id: "user-1", day: day, name: "두부", quantity: nil, protein: ProteinAmount(centigrams: 1_000), source: .manual))
            try log.setLegacyDailyTotal(7_500)
            try state.upsert(log)
        }
        guard case .ready(let state) = coordinator().launch() else { return XCTFail("expected ready") }
        let log = try XCTUnwrap(state.log(for: day))
        XCTAssertEqual(try log.totalProteinCentigrams(), 7_500)
        XCTAssertEqual(log.legacyAdjustmentCentigrams, 6_500)
        XCTAssertEqual(log.legacyAggregate?.importedTotalCentigrams, 7_000)
        XCTAssertEqual(log.records.map(\.id), ["user-1"])
    }
}
