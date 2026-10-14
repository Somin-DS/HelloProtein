import XCTest
import HelloProteinCore
@testable import MigrationCore

/// Schema 2 → 3 promotion at launch: the original bytes are backed up and
/// hashed, the promoted file is committed through the verified store path,
/// and every interruption or damaged evidence file stops without data loss.
/// Only synthetic schema 1/2 fixtures are used.
final class SchemaPromotionTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("app-state.json") }
    private var evidenceDirectory: URL { directory.appendingPathComponent("migration") }
    private var evidence: FileMigrationEvidenceStore { FileMigrationEvidenceStore(directory: evidenceDirectory) }
    private let today = try! CalendarDay(iso8601: "2026-10-14")
    private let clock = Date(timeIntervalSince1970: 1_792_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SchemaPromotionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: evidenceDirectory.path)
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: Fixtures

    /// A schema 2 document as the previous build wrote it: a legacy import
    /// with a signed adjustment, a search record with a reference quantity,
    /// favorites, history, goals, a confirmed language and a user operation ID.
    private func schema2JSON(lastOperationID: String? = "op-user-42") -> String {
        let operation = lastOperationID.map { #","lastOperationID":"\#($0)""# } ?? ""
        return """
        {"schemaVersion":2,
         "logs":[
           {"day":"2026-09-23","records":[{"id":"legacy:food:f1","day":"2026-09-23","name":"우유","protein":1000,"source":"legacy","legacySourceID":"f1"}],
            "legacyAdjustmentCentigrams":-500,
            "legacyAggregate":{"sourceID":"legacy:defaults:totalIntake","importedTotalCentigrams":500,"importedDetailSumCentigrams":1000,"originalLabel":"2026-09-23-Tue","originalInstant":null}},
           {"day":"2026-10-01","records":[],"legacyAdjustmentCentigrams":0},
           {"day":"2026-10-13","records":[
             {"id":"s1","day":"2026-10-13","name":"샌드위치_닭가슴살","quantity":{"value":"100","unit":"gram"},"protein":1218,"source":"search"},
             {"id":"m1","day":"2026-10-13","name":"닭가슴살","protein":2300,"source":"manual"},
             {"id":"q1","day":"2026-10-13","quantity":{"value":"12345678901234567890.5","unit":"ounce"},"protein":1,"source":"favorite"}]}
         ],
         "favorites":[{"id":"legacy:favorite:v1","name":"Protein","proteinCentigrams":2500,"position":0,"legacySourceID":"v1"},
                      {"id":"fav-2","name":"","proteinCentigrams":-100,"position":1}],
         "searchHistory":[{"id":"legacy:search:q1","value":"egg","position":0,"legacySourceID":"q1"}],
         "settings":{"searchLanguage":{"raw":"Korean(한글)","resolved":"korean","isFallback":false},"legacyTargetRaw":"120","goalNeedsReview":false},
         "goals":[{"id":"legacy:goal:targetProtein","effectiveFrom":"2026-09-28","amount":12000},{"id":"g2","effectiveFrom":"2026-10-12","amount":13000}],
         "migration":{"origin":"legacyImport","migrationVersion":1,"completedAt":"2026-09-28T10:00:00.000Z","sourceFingerprint":"abc123",
                      "verification":{"legacyFoodCount":1,"legacyHistoryCount":0,"favoriteCount":1,"searchTermCount":1,"legacyDayCount":1,"legacyCurrentTotalCentigrams":500,"legacyHistoryTotalCentigrams":0}}\(operation)}
        """
    }

    @discardableResult
    private func writeSchema2(lastOperationID: String? = "op-user-42") throws -> Data {
        let data = Data(schema2JSON(lastOperationID: lastOperationID).utf8)
        try data.write(to: storeURL)
        return data
    }

    private func makeCoordinator(
        legacy: LegacyCapture? = nil,
        interrupt: @escaping (InterruptionPoint) throws -> Void = { _ in },
        storeHooks: StoreCommitHooks = StoreCommitHooks(),
        writer: StoreFileWriter = DefaultStoreFileWriter()
    ) -> MigrationCoordinator {
        MigrationCoordinator(
            store: FileAppStateStore(fileURL: storeURL, writer: writer, hooks: storeHooks),
            legacy: FakeLegacyGateway(capture: legacy),
            evidence: evidence,
            environment: MigrationEnvironment(today: today, now: { self.clock }, migrationVersion: 1, interrupt: interrupt)
        )
    }

    private func readyState(_ outcome: LaunchOutcome, file: StaticString = #filePath, line: UInt = #line) throws -> AppState {
        guard case .ready(let state) = outcome else {
            XCTFail("expected ready, got \(outcome)", file: file, line: line)
            throw Unexpected()
        }
        return state
    }

    private func recovery(_ outcome: LaunchOutcome, file: StaticString = #filePath, line: UInt = #line) throws -> RecoveryState {
        guard case .recovery(let state) = outcome else {
            XCTFail("expected recovery, got \(outcome)", file: file, line: line)
            throw Unexpected()
        }
        return state
    }

    private func storeText() throws -> String { String(decoding: try Data(contentsOf: storeURL), as: UTF8.self) }

    private func snapshot(_ directory: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        guard FileManager.default.fileExists(atPath: directory.path) else { return result }
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            result[name] = try Data(contentsOf: directory.appendingPathComponent(name))
        }
        return result
    }

    // MARK: Promotion

    func testSchema2FileIsPromotedOnceWithBackupDigestAndEvidence() throws {
        let original = try writeSchema2()
        let expected = try AppState.decodeSchema2(original)
        // A completion marker from the original Realm migration is already there.
        try evidence.writeCompletionEvidence(CompletionEvidence(migration: expected.migration, writtenAt: "2026-09-28T10:00:01.000Z"))
        let markerBefore = try Data(contentsOf: evidence.completionURL)

        var points: [String] = []
        let state = try readyState(makeCoordinator(interrupt: { points.append($0.rawValue) }).launch())
        XCTAssertEqual(points, ["beforeBackup", "afterBackup", "afterMapping", "beforeFirstScreen"])

        // Content preserved exactly, in the current schema, with no basis anywhere.
        XCTAssertEqual(state, expected)
        XCTAssertEqual(state.schemaVersion, 3)
        XCTAssertEqual(state.lastOperationID, "op-user-42", "the user's operation ID is not replaced by the promotion")
        XCTAssertEqual(state.migration.origin, .legacyImport)
        XCTAssertEqual(state.migration.completedAt, "2026-09-28T10:00:00.000Z")
        XCTAssertEqual(state.logs.map(\.day.iso8601), ["2026-09-23", "2026-10-01", "2026-10-13"])
        XCTAssertEqual(try state.log(for: CalendarDay(iso8601: "2026-09-23"))?.totalProteinCentigrams(), 500)
        XCTAssertEqual(state.log(for: try CalendarDay(iso8601: "2026-09-23"))?.legacyAdjustmentCentigrams, -500)
        XCTAssertEqual(state.log(for: try CalendarDay(iso8601: "2026-10-01"))?.detailState, .legacyTotalOnly)
        XCTAssertEqual(state.log(for: try CalendarDay(iso8601: "2026-10-13"))?.records.map(\.id), ["s1", "m1", "q1"])
        XCTAssertEqual(state.log(for: try CalendarDay(iso8601: "2026-10-13"))?.records[2].quantity?.value, "12345678901234567890.5", "long old quantities are kept")
        XCTAssertTrue(state.logs.flatMap(\.records).allSatisfy { $0.calculationBasis == nil })
        XCTAssertEqual(state.favorites.map(\.proteinCentigrams), [2_500, -100])
        XCTAssertEqual(state.searchHistory.map(\.value), ["egg"])
        XCTAssertEqual(state.settings.searchLanguage.raw, "Korean(한글)")
        XCTAssertEqual(state.goals.map(\.amount.centigrams), [12_000, 13_000])

        // On disk: a schema 3 file the store opens directly.
        XCTAssertTrue(try storeText().contains(#""schemaVersion":3"#))
        XCTAssertEqual(try FileAppStateStore(fileURL: storeURL).load(), state)

        // Backup: the exact original bytes, with their digest in the evidence.
        let backup = try XCTUnwrap(evidence.inspectSchema2Backup().value)
        XCTAssertEqual(backup.data, original)
        XCTAssertEqual(backup.sha256, LegacyFingerprint.sha256Hex(of: original))
        let promotion = try XCTUnwrap(evidence.inspectSchemaPromotion().value)
        XCTAssertEqual(promotion.fromSchemaVersion, 2)
        XCTAssertEqual(promotion.toSchemaVersion, 3)
        XCTAssertEqual(promotion.backupSHA256, backup.sha256)
        XCTAssertEqual(promotion.backupByteCount, original.count)
        XCTAssertTrue(promotion.operationID.hasPrefix("schema-promotion-"))
        XCTAssertNotEqual(promotion.operationID, state.lastOperationID)
        XCTAssertEqual(promotion.promotedAt, LegacySnapshotBuilder.instantString(clock))
        XCTAssertEqual(try Data(contentsOf: evidence.completionURL), markerBefore, "the original migration marker is untouched")
        XCTAssertNil(try evidence.latestBackup(), "no legacy capture is invented")

        // Second launch: opened as is, nothing rewritten.
        let evidenceBefore = try snapshot(evidenceDirectory)
        let storeBefore = try Data(contentsOf: storeURL)
        XCTAssertEqual(try readyState(makeCoordinator(interrupt: { XCTAssertNotEqual($0, .afterBackup, "no second promotion") }).launch()), state)
        XCTAssertEqual(try snapshot(evidenceDirectory), evidenceBefore)
        XCTAssertEqual(try Data(contentsOf: storeURL), storeBefore)
    }

    func testSchema2FileWithoutOperationIDPromotesWithNilID() throws {
        try writeSchema2(lastOperationID: nil)
        let state = try readyState(makeCoordinator().launch())
        XCTAssertNil(state.lastOperationID)
        XCTAssertFalse(try storeText().contains("lastOperationID"))
        XCTAssertFalse(try storeText().contains("calculationBasis"))
        // The user can write right away and the ID semantics are the usual ones.
        let written = try FileAppStateStore(fileURL: storeURL).modify(operationID: "op-next") { $0.settings.goalNeedsReview = true }
        XCTAssertEqual(written.lastOperationID, "op-next")
    }

    func testUserWritesAfterPromotionCarryABasisAndOldRecordsStayUntouched() throws {
        try writeSchema2()
        let promoted = try readyState(makeCoordinator().launch())
        let store = FileAppStateStore(fileURL: storeURL)
        let day = try CalendarDay(iso8601: "2026-10-14")
        let basis = try CalculationBasis.providerSnapshot(proteinGramsText: "12.18", referenceQuantity: FoodQuantity(value: "100", unit: .gram),
                                                          providerID: "mfds", dataVersion: "2026-10", itemID: "D1")
        try store.modify(operationID: "op-add") { state in
            var log = try DailyLog(day: day)
            try log.add(FoodRecord(id: "new", day: day, name: "닭가슴살", quantity: FoodQuantity(value: "150", unit: .gram), basis: basis))
            try state.upsert(log)
        }
        let reloaded = try readyState(makeCoordinator().launch())
        XCTAssertEqual(reloaded.log(for: day)?.records.first?.protein.centigrams, 1_827)
        XCTAssertEqual(reloaded.log(for: day)?.records.first?.calculationBasis, basis)
        XCTAssertEqual(reloaded.logs.filter { $0.day != day }, promoted.logs, "every pre-existing day is byte-for-byte the same state")
        XCTAssertEqual(reloaded.lastOperationID, "op-add")
    }

    // MARK: Interruption and resume

    func testEveryInterruptionLeavesSchema2OrSchema3NeverAMixAndResumes() throws {
        struct Crash: Error {}
        let original = try writeSchema2()
        let expected = try AppState.decodeSchema2(original)
        for point in InterruptionPoint.allCases {
            try original.write(to: storeURL)
            try? FileManager.default.removeItem(at: evidenceDirectory)
            var armed = true
            let interrupt: (InterruptionPoint) throws -> Void = { current in
                if armed && current == point { armed = false; throw Crash() }
            }
            let hooks = StoreCommitHooks { stage in
                if armed && point == .afterTemporaryWrite && stage == .temporaryFile { armed = false; throw Crash() }
                if armed && point == .beforeReplace && stage == .beforeReplace { armed = false; throw Crash() }
                if armed && point == .afterReplace && stage == .afterReplace { armed = false; throw Crash() }
            }
            let recovery = try self.recovery(makeCoordinator(interrupt: interrupt, storeHooks: hooks).launch())
            XCTAssertEqual(recovery.kind, point == .afterReplace ? .verificationFailed : .interrupted, "\(point)")
            XCTAssertTrue(recovery.canRetry, "\(point)")
            XCTAssertTrue(recovery.originalPreserved, "\(point)")

            let text = try storeText()
            switch point {
            case .beforeBackup, .afterBackup, .afterMapping, .afterTemporaryWrite, .beforeReplace:
                XCTAssertEqual(try Data(contentsOf: storeURL), original, "\(point): the schema 2 file is untouched")
            case .afterReplace, .beforeFirstScreen:
                XCTAssertTrue(text.contains(#""schemaVersion":3"#), "\(point): the promoted file stays")
            }
            if point != .beforeBackup {
                XCTAssertEqual(evidence.inspectSchema2Backup().value?.data, original, "\(point): backup written before anything else")
            }
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".") }
            XCTAssertTrue(leftovers.isEmpty, "\(point): \(leftovers)")

            // Next launch converges to the same promoted state.
            let resumed = try readyState(makeCoordinator(interrupt: interrupt, storeHooks: hooks).launch())
            XCTAssertEqual(resumed, expected, "\(point)")
            XCTAssertEqual(evidence.inspectSchema2Backup().value?.data, original, "\(point)")
            XCTAssertEqual(evidence.inspectSchemaPromotion().value?.backupSHA256, LegacyFingerprint.sha256Hex(of: original), "\(point)")
            XCTAssertEqual(try readyState(makeCoordinator().launch()), resumed, "\(point): third launch is a no-op")
        }
    }

    func testWriteFailureBeforeReplaceKeepsSchema2AndRetriesNextLaunch() throws {
        struct FailingWriter: StoreFileWriter {
            func write(_ data: Data, to url: URL) throws { throw StoreError.writeFailed("disk full") }
        }
        let original = try writeSchema2()
        let recovery = try recovery(makeCoordinator(writer: FailingWriter()).launch())
        XCTAssertEqual(recovery.kind, .commitFailed)
        XCTAssertTrue(recovery.canRetry)
        XCTAssertEqual(try Data(contentsOf: storeURL), original)
        XCTAssertNotNil(evidence.inspectSchema2Backup().value)
        XCTAssertTrue(evidence.inspectSchemaPromotion().isMissing)
        XCTAssertEqual(try readyState(makeCoordinator().launch()), try AppState.decodeSchema2(original))
    }

    func testExistingMatchingBackupIsReusedAndNotRewritten() throws {
        let original = try writeSchema2()
        try evidence.writeSchema2Backup(original)
        let backupBefore = try FileManager.default.attributesOfItem(atPath: evidence.schema2BackupURL.path)[.modificationDate] as? Date
        _ = try readyState(makeCoordinator().launch())
        XCTAssertEqual(evidence.inspectSchema2Backup().value?.data, original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: evidence.schema2BackupURL.path)[.modificationDate] as? Date, backupBefore)
    }

    func testPromotionEvidenceForTheSameOriginalResumesPromotion() throws {
        // The promoted file was replaced by its schema 2 backup (e.g. restored by hand): same digest, so promote again.
        let original = try writeSchema2()
        _ = try readyState(makeCoordinator().launch())
        let promotionBefore = try Data(contentsOf: evidence.schemaPromotionURL)
        try original.write(to: storeURL)
        let state = try readyState(makeCoordinator().launch())
        XCTAssertEqual(state, try AppState.decodeSchema2(original))
        XCTAssertTrue(try storeText().contains(#""schemaVersion":3"#))
        XCTAssertEqual(try Data(contentsOf: evidence.schemaPromotionURL), promotionBefore, "evidence is not rewritten")
    }

    // MARK: Evidence that cannot be trusted

    func testBackupOfADifferentSchema2FileStopsWithoutOverwriting() throws {
        try writeSchema2()
        try evidence.writeSchema2Backup(Data(schema2JSON(lastOperationID: "op-other").utf8))
        let before = try snapshot(evidenceDirectory)
        let storeBefore = try Data(contentsOf: storeURL)
        let recovery = try recovery(makeCoordinator().launch())
        XCTAssertEqual(recovery.kind, .schemaBackupMismatch)
        XCTAssertFalse(recovery.canRetry)
        XCTAssertEqual(try Data(contentsOf: storeURL), storeBefore, "schema 2 file untouched")
        XCTAssertEqual(try snapshot(evidenceDirectory), before, "the other backup is not replaced")
        XCTAssertTrue(evidence.inspectSchemaPromotion().isMissing)
    }

    func testPromotionEvidenceForADifferentOriginalStopsBeforeWritingABackup() throws {
        try writeSchema2()
        try evidence.writeSchemaPromotionEvidence(SchemaPromotionEvidence(fromSchemaVersion: 2, toSchemaVersion: 3, backupSHA256: "deadbeef",
                                                                          backupByteCount: 1, promotedAt: "x", operationID: "schema-promotion-x"))
        let before = try snapshot(evidenceDirectory)
        let storeBefore = try Data(contentsOf: storeURL)
        let recovery = try recovery(makeCoordinator().launch())
        XCTAssertEqual(recovery.kind, .schemaBackupMismatch)
        XCTAssertFalse(recovery.canRetry)
        XCTAssertEqual(try Data(contentsOf: storeURL), storeBefore)
        XCTAssertEqual(try snapshot(evidenceDirectory), before, "no backup is written on a stop path")
        XCTAssertTrue(evidence.inspectSchema2Backup().isMissing)
    }

    func testCorruptAndUnreadableSchemaBackupsStopBeforeAnyWrite() throws {
        try writeSchema2()
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try Data("{not schema 2".utf8).write(to: evidence.schema2BackupURL)
        let before = try snapshot(evidenceDirectory)
        let storeBefore = try Data(contentsOf: storeURL)
        var recovery = try recovery(makeCoordinator().launch())
        XCTAssertEqual(recovery.kind, .evidenceCorrupt)
        XCTAssertFalse(recovery.canRetry)
        XCTAssertEqual(try snapshot(evidenceDirectory), before)
        XCTAssertEqual(try Data(contentsOf: storeURL), storeBefore)

        // A schema 3 document under the schema 2 backup name is also not a schema 2 backup.
        try Data(schema2JSON().replacingOccurrences(of: #""schemaVersion":2"#, with: #""schemaVersion":3"#).utf8).write(to: evidence.schema2BackupURL)
        XCTAssertEqual(try self.recovery(makeCoordinator().launch()).kind, .evidenceCorrupt)

        guard geteuid() != 0 else { throw XCTSkip("root ignores permissions") }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: evidence.schema2BackupURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: evidence.schema2BackupURL.path) }
        recovery = try self.recovery(makeCoordinator().launch())
        XCTAssertEqual(recovery.kind, .evidenceUnreadable)
        XCTAssertTrue(recovery.canRetry)
        XCTAssertEqual(try Data(contentsOf: storeURL), storeBefore)
    }

    func testCorruptPromotionEvidenceStopsAndIsLeftAlone() throws {
        try writeSchema2()
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: evidence.schemaPromotionURL)
        let before = try snapshot(evidenceDirectory)
        let storeBefore = try Data(contentsOf: storeURL)
        XCTAssertEqual(try recovery(makeCoordinator().launch()).kind, .evidenceCorrupt)
        XCTAssertEqual(try Data(contentsOf: storeURL), storeBefore)
        XCTAssertEqual(try snapshot(evidenceDirectory)["schema-promotion.json"], before["schema-promotion.json"])

        try Data(#"{"evidenceFormatVersion":9,"fromSchemaVersion":2,"toSchemaVersion":3,"backupSHA256":"x","backupByteCount":1,"promotedAt":"x","operationID":"x"}"#.utf8)
            .write(to: evidence.schemaPromotionURL)
        XCTAssertEqual(try recovery(makeCoordinator().launch()).kind, .evidenceUnsupported)
    }

    func testBackupWriteFailureStopsBeforeTouchingTheStore() throws {
        guard geteuid() != 0 else { throw XCTSkip("root ignores permissions") }
        let original = try writeSchema2()
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: evidenceDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: evidenceDirectory.path) }
        let recovery = try recovery(makeCoordinator().launch())
        XCTAssertEqual(recovery.kind, .schemaBackupFailed)
        XCTAssertTrue(recovery.canRetry)
        XCTAssertEqual(try Data(contentsOf: storeURL), original)
        // Permissions restored: the next launch promotes.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: evidenceDirectory.path)
        XCTAssertEqual(try readyState(makeCoordinator().launch()), try AppState.decodeSchema2(original))
    }

    // MARK: Missing store next to promotion evidence

    func testMissingStoreWithPromotionEvidenceOrSchemaBackupIsLossNotFreshInstall() throws {
        try writeSchema2()
        _ = try readyState(makeCoordinator().launch())
        try FileManager.default.removeItem(at: storeURL)
        // Even without the completion marker, the promotion evidence proves a store existed.
        try FileManager.default.removeItem(at: evidence.completionURL)
        var recovery = try recovery(makeCoordinator().launch())
        XCTAssertEqual(recovery.kind, .storeLost)
        XCTAssertFalse(recovery.canRetry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))

        try FileManager.default.removeItem(at: evidence.schemaPromotionURL)
        recovery = try self.recovery(makeCoordinator().launch())
        XCTAssertEqual(recovery.kind, .storeLost, "a schema 2 backup alone is still proof")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }

    // MARK: Other store states

    func testInvalidSchema2DocumentsAndHigherSchemasGoToRecovery() throws {
        try Data(schema2JSON().replacingOccurrences(of: #""source":"search"}"#, with: #""source":"search","calculationBasis":{"proteinGramsText":"12.18","referenceQuantity":{"value":"100","unit":"gram"},"origin":"providerSnapshot","provider":{"providerID":"p","dataVersion":"v","itemID":"i"}}}"#).utf8)
            .write(to: storeURL)
        let storeBefore = try Data(contentsOf: storeURL)
        var recovery = try recovery(makeCoordinator().launch())
        XCTAssertEqual(recovery.kind, .storeCorrupt, "a basis inside a schema 2 file is not silently accepted")
        XCTAssertTrue(recovery.detail.contains("not part of schema 2"), recovery.detail)
        XCTAssertEqual(try Data(contentsOf: storeURL), storeBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: evidence.schema2BackupURL.path), "nothing backed up for a corrupt file")

        try Data(schema2JSON().replacingOccurrences(of: #""schemaVersion":2"#, with: #""schemaVersion":4"#).utf8).write(to: storeURL)
        recovery = try self.recovery(makeCoordinator().launch())
        XCTAssertEqual(recovery.kind, .storeUnsupportedSchema)
        XCTAssertEqual(recovery.detail, "schema 4")
        XCTAssertFalse(recovery.canRetry)

        // A schema 3 file whose basis does not yield the stored protein is corrupt, not repaired.
        func schema3(basisProtein: String) -> Data {
            Data(schema2JSON().replacingOccurrences(of: #""schemaVersion":2"#, with: #""schemaVersion":3"#)
                .replacingOccurrences(of: #""source":"search"}"#, with: #""source":"search","calculationBasis":{"proteinGramsText":"\#(basisProtein)","referenceQuantity":{"value":"100","unit":"gram"},"origin":"providerSnapshot","provider":{"providerID":"p","dataVersion":"v","itemID":"i"}}}"#).utf8)
        }
        try schema3(basisProtein: "12.18").write(to: storeURL)
        XCTAssertEqual(try readyState(makeCoordinator().launch()).log(for: CalendarDay(iso8601: "2026-10-13"))?.records.first?.calculationBasis?.proteinGramsText, "12.18")
        try schema3(basisProtein: "12.19").write(to: storeURL)
        recovery = try self.recovery(makeCoordinator().launch())
        XCTAssertEqual(recovery.kind, .storeCorrupt)
        XCTAssertTrue(recovery.detail.contains("differs from computed"), recovery.detail)
        XCTAssertEqual(try Data(contentsOf: storeURL), schema3(basisProtein: "12.19"), "left exactly as found")
    }

    func testSchema3FileWithoutPromotionEvidenceOpensWithoutWritingAnything() throws {
        try writeSchema2()
        let promoted = try readyState(makeCoordinator().launch())
        try FileManager.default.removeItem(at: evidence.schemaPromotionURL)
        try FileManager.default.removeItem(at: evidence.schema2BackupURL)
        let before = try snapshot(evidenceDirectory)
        let storeBefore = try Data(contentsOf: storeURL)
        XCTAssertEqual(try readyState(makeCoordinator().launch()), promoted)
        XCTAssertEqual(try snapshot(evidenceDirectory), before, "the valid file wins; without a backup no evidence is reconstructed")
        XCTAssertEqual(try Data(contentsOf: storeURL), storeBefore)

        // A backup of some other schema 2 document next to the file: the
        // marker is not reconstructed from it, and the file still opens.
        try evidence.writeSchema2Backup(Data(schema2JSON(lastOperationID: "op-other").utf8))
        let withOtherBackup = try snapshot(evidenceDirectory)
        XCTAssertEqual(try readyState(makeCoordinator().launch()), promoted)
        XCTAssertEqual(try snapshot(evidenceDirectory), withOtherBackup, "no marker for a backup that is not this store's original")
        XCTAssertTrue(evidence.inspectSchemaPromotion().isMissing)
    }

    // MARK: Other origins land on the current schema directly

    func testSchema1UpgradeFreshInstallAndLegacyImportWriteSchema3WithoutAPromotionStep() throws {
        // Schema 1 → current, in memory, with the schema 1 file preserved.
        try Data(#"{"schemaVersion":1,"logs":[{"day":"2026-09-25","records":[{"id":"p1","day":"2026-09-25","protein":1500,"source":"manual"}],"legacyAdjustmentCentigrams":null}]}"#.utf8).write(to: storeURL)
        var state = try readyState(makeCoordinator().launch())
        XCTAssertEqual(state.migration.origin, .schema1Upgrade)
        XCTAssertEqual(state.schemaVersion, 3)
        XCTAssertTrue(try storeText().contains(#""schemaVersion":3"#))
        XCTAssertTrue(FileManager.default.fileExists(atPath: evidence.schema1BackupURL.path))
        XCTAssertTrue(evidence.inspectSchema2Backup().isMissing, "no intermediate schema 2 file is produced or backed up")
        XCTAssertTrue(evidence.inspectSchemaPromotion().isMissing)

        // Fresh install → current.
        try FileManager.default.removeItem(at: storeURL)
        try FileManager.default.removeItem(at: evidenceDirectory)
        state = try readyState(makeCoordinator().launch())
        XCTAssertEqual(state.migration.origin, .freshInstall)
        XCTAssertTrue(try storeText().contains(#""schemaVersion":3"#))
        XCTAssertTrue(evidence.inspectSchemaPromotion().isMissing)

        // Realm/UserDefaults → current.
        try FileManager.default.removeItem(at: storeURL)
        try FileManager.default.removeItem(at: evidenceDirectory)
        let capture = LegacyCapture(
            realmFilePresent: true,
            defaults: ["date": .string("2026-09-23-Tue"), "totalIntake": .integer(55), "targetProtein": .string("120")],
            foods: [.init(id: "f1", name: "우유", protein: 10)], history: [], favorites: [], searchHistory: []
        )
        state = try readyState(makeCoordinator(legacy: capture).launch())
        XCTAssertEqual(state.migration.origin, .legacyImport)
        XCTAssertTrue(try storeText().contains(#""schemaVersion":3"#))
        XCTAssertTrue(state.logs.flatMap(\.records).allSatisfy { $0.calculationBasis == nil })
        XCTAssertTrue(evidence.inspectSchemaPromotion().isMissing)
        XCTAssertNotNil(try evidence.latestBackup())
    }

    func testSchema1AndLegacyTogetherStillConflict() throws {
        try Data(#"{"schemaVersion":1,"logs":[]}"#.utf8).write(to: storeURL)
        let capture = LegacyCapture(realmFilePresent: true, defaults: ["date": .string("2026-09-23-Tue"), "totalIntake": .integer(55)],
                                    foods: [], history: [], favorites: [], searchHistory: [])
        XCTAssertEqual(try recovery(makeCoordinator(legacy: capture).launch()).kind, .schema1Conflict)
        XCTAssertTrue(try storeText().contains(#""schemaVersion":1"#))
    }

    func testSchema2PromotionIgnoresLegacyDataThatIsStillOnTheDevice() throws {
        // A migrated user never gets re-imported, whatever the old source still holds.
        let original = try writeSchema2()
        let capture = LegacyCapture(realmFilePresent: true, defaults: ["totalIntake": .integer(999), "date": .string("2026-09-27-Sun")],
                                    foods: [], history: [], favorites: [], searchHistory: [])
        let gateway = FakeLegacyGateway(capture: capture)
        var probed = false
        gateway.onProbe = { probed = true }
        let coordinator = MigrationCoordinator(store: FileAppStateStore(fileURL: storeURL), legacy: gateway, evidence: evidence,
                                               environment: MigrationEnvironment(today: today, now: { self.clock }))
        XCTAssertEqual(try readyState(coordinator.launch()), try AppState.decodeSchema2(original))
        XCTAssertFalse(probed)
        XCTAssertEqual(gateway.captureCount, 0)
    }

    private struct Unexpected: Error {}
}
