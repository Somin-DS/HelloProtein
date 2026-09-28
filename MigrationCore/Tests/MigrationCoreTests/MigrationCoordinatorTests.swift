import XCTest
import HelloProteinCore
@testable import MigrationCore

/// In-memory stand-in for Realm/UserDefaults. Records whether anything tried
/// to write, which must never happen.
final class FakeLegacyGateway: LegacySourceGateway {
    var stored: LegacyCapture?
    var probeError: Error?
    var captureError: Error?
    private(set) var captureCount = 0

    init(capture: LegacyCapture?) { self.stored = capture }

    var onProbe: (() -> Void)?

    func probe() throws -> LegacyProbe {
        onProbe?()
        if let probeError { throw probeError }
        guard let stored else { return LegacyProbe(realmFilePresent: false, presentDefaultsKeys: []) }
        return LegacyProbe(
            realmFilePresent: stored.realmFilePresent,
            presentDefaultsKeys: stored.defaults.keys.sorted()
        )
    }

    func capture() throws -> LegacyCapture {
        captureCount += 1
        if let captureError { throw captureError }
        guard let stored else { throw NSError(domain: "fake", code: 1) }
        return stored
    }
}

final class MigrationCoordinatorTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("app-state.json") }
    private var evidenceDirectory: URL { directory.appendingPathComponent("migration") }
    private let today = try! CalendarDay(iso8601: "2026-09-28")
    private var clock = Date(timeIntervalSince1970: 1_790_600_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MigrationCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try FileManager.default.removeItem(at: directory)
    }

    private func legacyCapture(milkProtein: Int = 10) -> LegacyCapture {
        LegacyCapture(
            realmFilePresent: true,
            defaults: [
                "date": .string("2026-09-23-Tue"),
                "Date": .date(secondsSince1970: 1_790_000_000, iso8601: "2026-09-21T12:53:20.000Z"),
                "totalIntake": .integer(55),
                "targetProtein": .string("120"),
                "searchLanguage": .string("Korean(한글)"),
            ],
            foods: [.init(id: "f1", name: "우유", protein: milkProtein), .init(id: "f2", name: "계란", protein: 35)],
            history: [.init(id: "s1", dayLabel: "2026-09-20-Sun", storedDate: Date(timeIntervalSince1970: 1_758_326_400), total: 70)],
            favorites: [.init(id: "v1", name: "Protein", protein: 25)],
            searchHistory: [.init(id: "q1", value: "egg")]
        )
    }

    private func makeCoordinator(
        gateway: LegacySourceGateway,
        interrupt: @escaping (InterruptionPoint) throws -> Void = { _ in },
        storeHooks: StoreCommitHooks = StoreCommitHooks(),
        writer: StoreFileWriter = DefaultStoreFileWriter()
    ) -> MigrationCoordinator {
        MigrationCoordinator(
            store: FileAppStateStore(fileURL: storeURL, writer: writer, hooks: storeHooks),
            legacy: gateway,
            evidence: FileMigrationEvidenceStore(directory: evidenceDirectory),
            environment: MigrationEnvironment(today: today, now: { self.clock }, migrationVersion: 1, interrupt: interrupt)
        )
    }

    private func readyState(_ outcome: LaunchOutcome, file: StaticString = #filePath, line: UInt = #line) throws -> AppState {
        guard case .ready(let state) = outcome else {
            XCTFail("expected ready, got \(outcome)", file: file, line: line)
            throw UnexpectedOutcome()
        }
        return state
    }

    private func recovery(_ outcome: LaunchOutcome, file: StaticString = #filePath, line: UInt = #line) throws -> RecoveryState {
        guard case .recovery(let state) = outcome else {
            XCTFail("expected recovery, got \(outcome)", file: file, line: line)
            throw UnexpectedOutcome()
        }
        return state
    }

    // MARK: Happy paths

    func testFreshInstallCreatesExplicitEmptyStoreOnce() throws {
        let gateway = FakeLegacyGateway(capture: nil)
        let state = try readyState(makeCoordinator(gateway: gateway).launch())
        XCTAssertEqual(state.migration.origin, .freshInstall)
        XCTAssertTrue(state.logs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertEqual(gateway.captureCount, 0)
        XCTAssertNotNil(try FileMigrationEvidenceStore(directory: evidenceDirectory).completionEvidence())
        XCTAssertNil(try FileMigrationEvidenceStore(directory: evidenceDirectory).latestBackup())

        // Second launch reuses the store.
        XCTAssertEqual(try readyState(makeCoordinator(gateway: gateway).launch()), state)
    }

    func testLegacyImportBacksUpBeforeMappingAndCommitsEverythingAtOnce() throws {
        var order: [String] = []
        let gateway = FakeLegacyGateway(capture: legacyCapture())
        let evidence = FileMigrationEvidenceStore(directory: evidenceDirectory)
        let coordinator = makeCoordinator(gateway: gateway, interrupt: { point in
            order.append(point.rawValue)
            if point == .afterBackup {
                XCTAssertNotNil(try evidence.latestBackup(), "backup exists before mapping")
                XCTAssertFalse(FileManager.default.fileExists(atPath: self.storeURL.path), "no store before commit")
            }
            if point == .afterMapping {
                XCTAssertFalse(FileManager.default.fileExists(atPath: self.storeURL.path), "no store before commit")
                XCTAssertNil(try evidence.completionEvidence(), "no completion marker before commit")
            }
        })
        let state = try readyState(coordinator.launch())
        XCTAssertEqual(order, ["beforeBackup", "afterBackup", "afterMapping", "beforeFirstScreen"])
        XCTAssertEqual(state.migration.origin, .legacyImport)
        XCTAssertEqual(state.logs.map(\.day.iso8601), ["2026-09-20", "2026-09-23"])
        XCTAssertEqual(try state.log(for: CalendarDay(iso8601: "2026-09-23"))?.totalProteinCentigrams(), 5_500)
        XCTAssertEqual(state.favorites.count, 1)
        XCTAssertEqual(state.searchHistory.count, 1)
        XCTAssertEqual(state.goals.first?.effectiveFrom, today)
        let backup = try XCTUnwrap(evidence.latestBackup())
        XCTAssertEqual(backup.fingerprint, state.migration.sourceFingerprint)
        XCTAssertEqual(backup.capture, legacyCapture(), "backup is lossless")
        XCTAssertEqual(try evidence.completionEvidence()?.migration, state.migration)
        XCTAssertEqual(gateway.captureCount, 1)
    }

    func testCompletedStoreIsNeverReMigratedEvenIfLegacyChanged() throws {
        let gateway = FakeLegacyGateway(capture: legacyCapture())
        let migrated = try readyState(makeCoordinator(gateway: gateway).launch())

        // User edits after migration.
        let store = FileAppStateStore(fileURL: storeURL)
        let day = try CalendarDay(iso8601: "2026-09-20")
        try store.modify { state in
            var log = state.log(for: day)!
            try log.add(FoodRecord(id: "user", day: day, name: "닭가슴살", quantity: nil, protein: ProteinAmount(centigrams: 2_000), source: .manual))
            try state.upsert(log)
        }

        // Legacy source changes its fingerprint (as if the old app ran again).
        gateway.stored = LegacyCapture(realmFilePresent: true, defaults: ["totalIntake": .integer(999), "date": .string("2026-09-27-Sun")],
                                        foods: [], history: [], favorites: [], searchHistory: [])
        let second = try readyState(makeCoordinator(gateway: gateway).launch())
        XCTAssertEqual(try second.log(for: day)?.totalProteinCentigrams(), 9_000)
        XCTAssertEqual(second.migration, migrated.migration)
        XCTAssertEqual(gateway.captureCount, 1, "no second capture")
    }

    // MARK: Interruptions

    func testEveryInterruptionPointResumesToTheSameFinalStateWithoutDuplicates() throws {
        struct Crash: Error {}
        let reference = try readyState(makeCoordinator(gateway: FakeLegacyGateway(capture: legacyCapture())).launch())
        try FileManager.default.removeItem(at: storeURL)
        try FileManager.default.removeItem(at: evidenceDirectory)

        for point in InterruptionPoint.allCases {
            let gateway = FakeLegacyGateway(capture: legacyCapture())
            var armed = true
            let interrupt: (InterruptionPoint) throws -> Void = { current in
                if armed && current == point { armed = false; throw Crash() }
            }
            let hooks = StoreCommitHooks { stage in
                if armed && point == .afterTemporaryWrite && stage == .temporaryFile { armed = false; throw Crash() }
                if armed && point == .beforeReplace && stage == .beforeReplace { armed = false; throw Crash() }
                if armed && point == .afterReplace && stage == .afterReplace { armed = false; throw Crash() }
            }
            let first = makeCoordinator(gateway: gateway, interrupt: interrupt, storeHooks: hooks).launch()
            let recovery = try self.recovery(first)
            // A crash after the rename is an unconfirmed commit, not a pre-commit interruption.
            XCTAssertEqual(recovery.kind, point == .afterReplace ? .verificationFailed : .interrupted, "\(point)")
            XCTAssertTrue(recovery.canRetry)

            let storeExistsAfterCrash = FileManager.default.fileExists(atPath: storeURL.path)
            switch point {
            case .beforeBackup, .afterBackup, .afterMapping, .afterTemporaryWrite, .beforeReplace:
                XCTAssertFalse(storeExistsAfterCrash, "\(point): previous good state is 'no store'")
            case .afterReplace, .beforeFirstScreen:
                XCTAssertTrue(storeExistsAfterCrash, "\(point): committed state survives")
            }
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".") }
            XCTAssertTrue(leftovers.isEmpty, "\(point): no temp files \(leftovers)")

            // Re-create the coordinator as a new launch would.
            let resumed = try readyState(makeCoordinator(gateway: gateway, interrupt: interrupt, storeHooks: hooks).launch(), line: #line)
            XCTAssertEqual(resumed.logs, reference.logs, "\(point)")
            XCTAssertEqual(resumed.favorites, reference.favorites, "\(point)")
            XCTAssertEqual(resumed.searchHistory, reference.searchHistory, "\(point)")
            XCTAssertEqual(resumed.goals, reference.goals, "\(point)")
            XCTAssertEqual(resumed.migration.sourceFingerprint, reference.migration.sourceFingerprint, "\(point)")
            XCTAssertEqual(resumed.logs.flatMap(\.records).count, 2, "\(point): no duplicated rows")

            // A third launch is a no-op.
            XCTAssertEqual(try readyState(makeCoordinator(gateway: gateway).launch()), resumed)
            try FileManager.default.removeItem(at: storeURL)
            try FileManager.default.removeItem(at: evidenceDirectory)
        }
    }

    func testWriteFailureDuringCommitLeavesNoStoreAndBackupIntact() throws {
        struct FailingWriter: StoreFileWriter {
            func write(_ data: Data, to url: URL) throws { throw StoreError.writeFailed("disk full") }
        }
        let gateway = FakeLegacyGateway(capture: legacyCapture())
        let recovery = try recovery(makeCoordinator(gateway: gateway, writer: FailingWriter()).launch())
        XCTAssertEqual(recovery.kind, .commitFailed)
        XCTAssertTrue(recovery.backupAvailable)
        XCTAssertTrue(recovery.canRetry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertNil(try FileMigrationEvidenceStore(directory: evidenceDirectory).completionEvidence())
        XCTAssertNotNil(try readyState(makeCoordinator(gateway: gateway).launch()))
    }

    // MARK: Invalid or unrepresentable sources

    func testInvalidLegacyDataIsBackedUpButNeverPartiallyImported() throws {
        var capture = legacyCapture()
        capture = LegacyCapture(realmFilePresent: true, defaults: capture.defaults,
                                foods: capture.raw.foods,
                                history: capture.raw.history + [.init(id: "s2", dayLabel: "2026-09-20-Sun", storedDate: Date(), total: 80)],
                                favorites: capture.raw.favorites, searchHistory: capture.raw.searchHistory)
        let recovery = try recovery(makeCoordinator(gateway: FakeLegacyGateway(capture: capture)).launch())
        XCTAssertEqual(recovery.kind, .legacyInvalid)
        XCTAssertTrue(recovery.detail.contains("ambiguousHistoricalDay"))
        XCTAssertTrue(recovery.backupAvailable)
        XCTAssertTrue(recovery.originalPreserved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testNegativeFoodStopsInRecoveryWithBackup() throws {
        let capture = LegacyCapture(realmFilePresent: true, defaults: legacyCapture().defaults,
                                    foods: [.init(id: "bad", name: "x", protein: -1)], history: [], favorites: [], searchHistory: [])
        let recovery = try recovery(makeCoordinator(gateway: FakeLegacyGateway(capture: capture)).launch())
        XCTAssertEqual(recovery.kind, .legacyUnrepresentable)
        XCTAssertTrue(recovery.backupAvailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testWrongDefaultsTypeStopsAfterBackup() throws {
        var defaults = legacyCapture().defaults
        defaults["totalIntake"] = .string("55")
        let capture = LegacyCapture(realmFilePresent: true, defaults: defaults, foods: legacyCapture().raw.foods, history: [], favorites: [], searchHistory: [])
        let recovery = try recovery(makeCoordinator(gateway: FakeLegacyGateway(capture: capture)).launch())
        XCTAssertEqual(recovery.kind, .unexpectedDefaultsType)
        XCTAssertEqual(recovery.detail, "totalIntake")
        XCTAssertTrue(recovery.backupAvailable)
    }

    func testBackupFailureStopsBeforeMapping() throws {
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: evidenceDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: evidenceDirectory.path) }
        guard geteuid() != 0 else { throw XCTSkip("root ignores permissions") }
        let recovery = try recovery(makeCoordinator(gateway: FakeLegacyGateway(capture: legacyCapture())).launch())
        XCTAssertEqual(recovery.kind, .backupFailed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testCaptureFailureIsRecoverable() throws {
        let gateway = FakeLegacyGateway(capture: legacyCapture())
        gateway.captureError = NSError(domain: "realm", code: 7)
        let recovery = try recovery(makeCoordinator(gateway: gateway).launch())
        XCTAssertEqual(recovery.kind, .legacyCaptureFailed)
        XCTAssertTrue(recovery.canRetry)
        gateway.captureError = nil
        XCTAssertNotNil(try readyState(makeCoordinator(gateway: gateway).launch()))
    }

    // MARK: Store states

    func testCorruptUnsupportedAndUnreadableStoresGoToRecoveryWithoutReset() throws {
        let gateway = FakeLegacyGateway(capture: legacyCapture())
        try Data("garbage".utf8).write(to: storeURL)
        XCTAssertEqual(try recovery(makeCoordinator(gateway: gateway).launch()).kind, .storeCorrupt)
        XCTAssertEqual(try Data(contentsOf: storeURL), Data("garbage".utf8), "corrupt file untouched")

        try Data(#"{"schemaVersion":7}"#.utf8).write(to: storeURL)
        XCTAssertEqual(try recovery(makeCoordinator(gateway: gateway).launch()).kind, .storeUnsupportedSchema)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: storeURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storeURL.path) }
        if geteuid() != 0 {
            XCTAssertEqual(try recovery(makeCoordinator(gateway: gateway).launch()).kind, .storeUnreadable)
        }
        XCTAssertEqual(gateway.captureCount, 0, "legacy data never touched while the store is broken")
    }

    func testMissingStoreWithCompletionEvidenceIsLossNotFreshInstall() throws {
        let gateway = FakeLegacyGateway(capture: nil)
        _ = try readyState(makeCoordinator(gateway: gateway).launch())
        try FileManager.default.removeItem(at: storeURL)
        let recovery = try recovery(makeCoordinator(gateway: gateway).launch())
        XCTAssertEqual(recovery.kind, .storeLost)
        XCTAssertFalse(recovery.canRetry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path), "no silent re-creation")
    }

    func testBackupOnlyWithoutLegacyRetriesFromBackup() throws {
        // Simulate: backup written, process died, and the legacy source is gone.
        let evidence = FileMigrationEvidenceStore(directory: evidenceDirectory)
        let capture = legacyCapture()
        try evidence.writeBackup(BackupRecord(fingerprint: try LegacyFingerprint.sha256Hex(of: capture),
                                              capturedAt: "2026-09-28T00:00:00.000Z", capture: capture))
        let gateway = FakeLegacyGateway(capture: nil)
        let state = try readyState(makeCoordinator(gateway: gateway).launch())
        XCTAssertEqual(state.migration.origin, .legacyImport)
        XCTAssertEqual(state.logs.count, 2)
        XCTAssertEqual(gateway.captureCount, 0)
    }

    func testTamperedBackupIsNotUsed() throws {
        let evidence = FileMigrationEvidenceStore(directory: evidenceDirectory)
        try evidence.writeBackup(BackupRecord(fingerprint: "wrong", capturedAt: "x", capture: legacyCapture()))
        let recovery = try recovery(makeCoordinator(gateway: FakeLegacyGateway(capture: nil)).launch())
        XCTAssertEqual(recovery.kind, .evidenceCorrupt, "contents that do not hash to the fingerprint are not a backup")
        XCTAssertFalse(recovery.canRetry)
        XCTAssertFalse(recovery.backupAvailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testBackupWithEditedContentsUnderTheOldFingerprintStopsALegacyMigration() throws {
        // A backup whose body was changed (a food value) while its fingerprint
        // still matches the live legacy source. Decoding succeeds, so without a
        // content check it would be kept as "the" backup and only fail later.
        let live = legacyCapture()
        let fingerprint = try LegacyFingerprint.sha256Hex(of: live)
        let edited = legacyCapture(milkProtein: 99)
        XCTAssertNotEqual(try LegacyFingerprint.sha256Hex(of: edited), fingerprint)
        let evidence = FileMigrationEvidenceStore(directory: evidenceDirectory)
        try evidence.writeBackup(BackupRecord(fingerprint: fingerprint, capturedAt: "x", capture: edited))
        let before = try snapshot(evidenceDirectory)

        let gateway = FakeLegacyGateway(capture: live)
        let recovery = try recovery(makeCoordinator(gateway: gateway).launch())
        XCTAssertEqual(recovery.kind, .evidenceCorrupt)
        XCTAssertFalse(recovery.backupAvailable)
        XCTAssertEqual(gateway.captureCount, 0, "stops before capturing")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path), "no migration completes on top of an untrusted backup")
        XCTAssertEqual(try snapshot(evidenceDirectory), before, "the tampered file is preserved, not silently replaced")
    }

    // MARK: Schema 1

    private func writeSchema1() throws {
        let json = #"{"schemaVersion":1,"logs":[{"day":"2026-09-25","records":[{"id":"p1","day":"2026-09-25","protein":1500,"source":"manual"}],"legacyAdjustmentCentigrams":null}]}"#
        try Data(json.utf8).write(to: storeURL)
    }

    func testSchema1AloneIsPreservedAndUpgraded() throws {
        try writeSchema1()
        let state = try readyState(makeCoordinator(gateway: FakeLegacyGateway(capture: nil)).launch())
        XCTAssertEqual(state.migration.origin, .schema1Upgrade)
        XCTAssertEqual(try state.log(for: CalendarDay(iso8601: "2026-09-25"))?.totalProteinCentigrams(), 1_500)
        let preserved = FileMigrationEvidenceStore(directory: evidenceDirectory).schema1BackupURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: preserved.path))
        XCTAssertTrue(String(decoding: try Data(contentsOf: preserved), as: UTF8.self).contains(#""schemaVersion":1"#))
    }

    func testSchema1WithLegacyDataIsAnExplicitConflict() throws {
        try writeSchema1()
        let recovery = try recovery(makeCoordinator(gateway: FakeLegacyGateway(capture: legacyCapture())).launch())
        XCTAssertEqual(recovery.kind, .schema1Conflict)
        XCTAssertFalse(recovery.canRetry)
        XCTAssertTrue(String(decoding: try Data(contentsOf: storeURL), as: UTF8.self).contains(#""schemaVersion":1"#), "schema 1 file untouched")
    }

    // MARK: Evidence files that exist but cannot be trusted (R1)

    private var completionURL: URL { evidenceDirectory.appendingPathComponent("migration-completed.json") }
    private var backupURL: URL { evidenceDirectory.appendingPathComponent("legacy-capture.json") }

    private func writeEvidenceBytes(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func snapshot(_ directory: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        guard FileManager.default.fileExists(atPath: directory.path) else { return result }
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            result[name] = try Data(contentsOf: directory.appendingPathComponent(name))
        }
        return result
    }

    func testCorruptCompletionWithoutStoreOrLegacyStopsInsteadOfFreshInstall() throws {
        try writeEvidenceBytes(#"{"migration": {"origin": "legacyImport""#, to: completionURL)
        let before = try snapshot(evidenceDirectory)
        let gateway = FakeLegacyGateway(capture: nil)
        let recovery = try recovery(makeCoordinator(gateway: gateway).launch())
        XCTAssertEqual(recovery.kind, .evidenceCorrupt)
        XCTAssertFalse(recovery.canRetry)
        XCTAssertFalse(recovery.backupAvailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path), "no fresh install over a damaged marker")
        XCTAssertEqual(try snapshot(evidenceDirectory), before, "evidence bytes untouched")
        XCTAssertEqual(gateway.captureCount, 0)
    }

    func testUnreadableCompletionWithLegacyPresentDoesNotReMigrate() throws {
        guard geteuid() != 0 else { throw XCTSkip("root ignores permissions") }
        let gateway = FakeLegacyGateway(capture: legacyCapture())
        // Complete a migration, then lose the store and make the marker unreadable.
        _ = try readyState(makeCoordinator(gateway: gateway).launch())
        try FileManager.default.removeItem(at: storeURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: completionURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: completionURL.path) }
        let capturesBefore = gateway.captureCount
        var probed = false
        gateway.onProbe = { probed = true }

        let recovery = try recovery(makeCoordinator(gateway: gateway).launch())
        XCTAssertEqual(recovery.kind, .evidenceUnreadable)
        XCTAssertTrue(recovery.canRetry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path), "no re-import: the new records are not in the old source")
        XCTAssertEqual(gateway.captureCount, capturesBefore, "old source not captured")
        XCTAssertFalse(probed, "old source not even probed")

        // Access restored: the marker is valid again and the launch reports the loss, not a fresh install.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: completionURL.path)
        XCTAssertEqual(try self.recovery(makeCoordinator(gateway: gateway).launch()).kind, .storeLost)
    }

    func testCorruptOnlyBackupWithoutStoreNeverCreatesAFreshInstall() throws {
        try writeEvidenceBytes(#"{"fingerprint": "abc", "capturedAt": "x", "capture": {"broken": true}}"#, to: backupURL)
        let before = try snapshot(evidenceDirectory)
        let gateway = FakeLegacyGateway(capture: nil)
        let recovery = try recovery(makeCoordinator(gateway: gateway).launch())
        XCTAssertEqual(recovery.kind, .evidenceCorrupt)
        XCTAssertFalse(recovery.backupAvailable, "a damaged file is not an available backup")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertEqual(try snapshot(evidenceDirectory), before)
    }

    func testCorruptBackupWithLegacyPresentStopsBeforeCaptureAndDoesNotOverwriteIt() throws {
        try writeEvidenceBytes("not json", to: backupURL)
        let before = try snapshot(evidenceDirectory)
        let gateway = FakeLegacyGateway(capture: legacyCapture())
        let recovery = try recovery(makeCoordinator(gateway: gateway).launch())
        XCTAssertEqual(recovery.kind, .evidenceCorrupt)
        XCTAssertEqual(gateway.captureCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertEqual(try snapshot(evidenceDirectory), before, "the damaged backup is preserved, not replaced")
    }

    func testUnsupportedEvidenceFormatStopsExplicitly() throws {
        try writeEvidenceBytes(#"{"evidenceFormatVersion": 99, "migration": {}, "writtenAt": "x"}"#, to: completionURL)
        let recovery = try recovery(makeCoordinator(gateway: FakeLegacyGateway(capture: nil)).launch())
        XCTAssertEqual(recovery.kind, .evidenceUnsupported)
        XCTAssertFalse(recovery.canRetry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    func testCorruptCompletionNextToAValidBackupStillReportsTheBackup() throws {
        // A real migration leaves a valid backup behind; then the store is lost and the marker damaged.
        _ = try readyState(makeCoordinator(gateway: FakeLegacyGateway(capture: legacyCapture())).launch())
        try FileManager.default.removeItem(at: storeURL)
        try writeEvidenceBytes("{", to: completionURL)
        let before = try snapshot(evidenceDirectory)
        let recovery = try recovery(makeCoordinator(gateway: FakeLegacyGateway(capture: nil)).launch())
        XCTAssertEqual(recovery.kind, .evidenceCorrupt)
        XCTAssertTrue(recovery.backupAvailable, "the damaged marker must not hide a decodable backup")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertEqual(try snapshot(evidenceDirectory), before)
    }

    func testNewerCaptureFormatInsideBackupIsUnsupportedEvenWhenItsBodyDoesNotDecode() throws {
        try writeEvidenceBytes(#"{"evidenceFormatVersion": 1, "fingerprint": "abc", "capturedAt": "x", "capture": {"captureFormatVersion": 99, "shape": "unknown"}}"#, to: backupURL)
        let before = try snapshot(evidenceDirectory)
        let recovery = try recovery(makeCoordinator(gateway: FakeLegacyGateway(capture: nil)).launch())
        XCTAssertEqual(recovery.kind, .evidenceUnsupported)
        XCTAssertFalse(recovery.canRetry)
        XCTAssertFalse(recovery.backupAvailable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertEqual(try snapshot(evidenceDirectory), before)
    }

    func testNothingAtAllStillCreatesAFreshInstall() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidenceDirectory.path))
        let state = try readyState(makeCoordinator(gateway: FakeLegacyGateway(capture: nil)).launch())
        XCTAssertEqual(state.migration.origin, .freshInstall)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertEqual(FileMigrationEvidenceStore(directory: evidenceDirectory).inspectCompletion().value?.migration, state.migration)
    }

    func testReadyStoreWithCorruptCompletionKeepsRecordsAndLeavesTheMarkerAlone() throws {
        let gateway = FakeLegacyGateway(capture: legacyCapture())
        let migrated = try readyState(makeCoordinator(gateway: gateway).launch())
        // The user keeps working after migration.
        let store = FileAppStateStore(fileURL: storeURL)
        let day = try CalendarDay(iso8601: "2026-09-27")
        try store.modify(operationID: "op-1") { state in
            var log = try DailyLog(day: day)
            try log.add(FoodRecord(id: "new-1", day: day, name: "두부", quantity: nil, protein: ProteinAmount(centigrams: 900), source: .manual))
            try state.upsert(log)
        }
        try writeEvidenceBytes("{corrupt", to: completionURL)
        let markerBefore = try Data(contentsOf: completionURL)

        let state = try readyState(makeCoordinator(gateway: gateway).launch())
        XCTAssertEqual(state.log(for: day)?.records.map(\.id), ["new-1"], "user records preserved")
        XCTAssertEqual(state.migration, migrated.migration)
        XCTAssertEqual(try Data(contentsOf: completionURL), markerBefore, "a damaged marker is never overwritten by a launch")
        guard case .corrupt = FileMigrationEvidenceStore(directory: evidenceDirectory).inspectCompletion() else {
            return XCTFail("marker should still be reported as corrupt")
        }
    }

    func testEvidenceWrittenBeforeFormatVersionsStillReads() throws {
        let capture = legacyCapture()
        let fingerprint = try LegacyFingerprint.sha256Hex(of: capture)
        let evidence = FileMigrationEvidenceStore(directory: evidenceDirectory)
        try evidence.writeBackup(BackupRecord(fingerprint: fingerprint, capturedAt: "2026-09-28T00:00:00.000Z", capture: capture))
        // Strip the version fields the way an older build would have written the files.
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: backupURL)) as! [String: Any]
        json.removeValue(forKey: "evidenceFormatVersion")
        try JSONSerialization.data(withJSONObject: json).write(to: backupURL)
        let backup = try XCTUnwrap(evidence.inspectBackup().value)
        XCTAssertEqual(backup.evidenceFormatVersion, 1)
        XCTAssertEqual(backup.capture, capture)

        try writeEvidenceBytes(#"{"migration": {"origin": "freshInstall", "migrationVersion": 1, "completedAt": "x"}, "writtenAt": "x"}"#, to: completionURL)
        XCTAssertEqual(evidence.inspectCompletion().value?.evidenceFormatVersion, 1)
    }
}

private struct UnexpectedOutcome: Error {}
