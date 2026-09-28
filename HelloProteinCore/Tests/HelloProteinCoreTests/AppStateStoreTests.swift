import XCTest
@testable import HelloProteinCore

final class AppStateStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL { directory.appendingPathComponent("app-state.json") }
    private let day = try! CalendarDay(iso8601: "2026-09-28")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func state(records: [FoodRecord] = []) throws -> AppState {
        let log = try DailyLog(day: day, records: records, legacyAdjustmentCentigrams: 1_000,
                               legacyAggregate: LegacyAggregate(
                                   sourceID: "legacy:defaults:totalIntake", importedTotalCentigrams: 1_000,
                                   importedDetailSumCentigrams: 0, originalLabel: "2026-09-28-Mon", originalInstant: nil))
        return try AppState(
            logs: [log],
            favorites: [FavoriteFood(id: "legacy:favorite:1", name: "Milk", proteinCentigrams: 800, position: 0)],
            searchHistory: [SearchTerm(id: "legacy:search:1", value: "egg", position: 0)],
            settings: AppSettings(searchLanguage: .interpret(raw: "Korean(한글)"), legacyTargetRaw: "120", goalNeedsReview: false),
            goals: [ProteinGoal(id: "legacy:goal:targetProtein", effectiveFrom: day, amount: ProteinAmount(centigrams: 12_000))],
            migration: MigrationRecord(origin: .legacyImport, migrationVersion: 1, completedAt: "2026-09-28T10:00:00Z",
                                       sourceFingerprint: "abc", verification: MigrationVerification(
                                           legacyFoodCount: 0, legacyHistoryCount: 0, favoriteCount: 1, searchTermCount: 1,
                                           legacyDayCount: 1, legacyCurrentTotalCentigrams: 1_000, legacyHistoryTotalCentigrams: 0))
        )
    }

    private func record(_ id: String, centigrams: Int64 = 500) throws -> FoodRecord {
        try FoodRecord(id: id, day: day, name: nil, quantity: nil,
                       protein: ProteinAmount(centigrams: centigrams), source: .manual)
    }

    func testCommitAndReloadRoundTripWholeState() throws {
        let original = try state()
        try FileAppStateStore(fileURL: fileURL).commit(original)
        let reloaded = try FileAppStateStore(fileURL: fileURL).load()
        XCTAssertEqual(reloaded, original)
        XCTAssertEqual(FileAppStateStore.inspect(fileURL: fileURL), .ready(original))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(leftovers, ["app-state.json"], "no temporary files remain")
    }

    func testMissingStoreIsAnErrorNotAnEmptyState() {
        XCTAssertEqual(FileAppStateStore.inspect(fileURL: fileURL), .missing)
        XCTAssertThrowsError(try FileAppStateStore(fileURL: fileURL).load()) {
            XCTAssertEqual($0 as? StoreError, .missing)
        }
        XCTAssertThrowsError(try FileAppStateStore(fileURL: fileURL).modify { _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCorruptUnsupportedAndSchema1FilesAreDistinguished() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: fileURL)
        if case .corrupt = FileAppStateStore.inspect(fileURL: fileURL) {} else { XCTFail("corrupt") }

        try Data(#"{"schemaVersion": 9, "logs": []}"#.utf8).write(to: fileURL)
        XCTAssertEqual(FileAppStateStore.inspect(fileURL: fileURL), .unsupportedSchema(9))
        XCTAssertThrowsError(try FileAppStateStore(fileURL: fileURL).load()) {
            XCTAssertEqual($0 as? StoreError, .unsupportedSchema(9))
        }

        let schema1 = #"{"schemaVersion":1,"logs":[{"day":"2026-09-28","records":[],"legacyAdjustmentCentigrams":700}]}"#
        try Data(schema1.utf8).write(to: fileURL)
        guard case .legacySchema1(let logs) = FileAppStateStore.inspect(fileURL: fileURL) else {
            return XCTFail("schema 1 expected")
        }
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(try logs[0].totalProteinCentigrams(), 700)

        // Schema 2 with a broken invariant (duplicate day) is corrupt, not ready.
        var encoded = try JSONEncoder().encode(state())
        var json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        json = json.replacingOccurrences(of: #""logs":[{"#, with: #""logs":[{"day":"2026-09-28","records":[]},{"#)
        encoded = Data(json.utf8)
        try encoded.write(to: fileURL)
        if case .corrupt = FileAppStateStore.inspect(fileURL: fileURL) {} else { XCTFail("duplicate day must be corrupt") }
    }

    func testUnreadableFileIsNotTreatedAsMissing() throws {
        try FileAppStateStore(fileURL: fileURL).commit(state())
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path) }
        guard geteuid() != 0 else { throw XCTSkip("root can read everything") }
        if case .unreadable = FileAppStateStore.inspect(fileURL: fileURL) {} else { XCTFail("unreadable expected") }
    }

    func testWriteFailureKeepsPreviousFileAndLeavesNoTemporaryFile() throws {
        let original = try state()
        try FileAppStateStore(fileURL: fileURL).commit(original)

        struct FailingWriter: StoreFileWriter {
            func write(_ data: Data, to url: URL) throws {
                try data.prefix(10).write(to: url)
                throw StoreError.writeFailed("disk full")
            }
        }
        let failing = FileAppStateStore(fileURL: fileURL, writer: FailingWriter())
        XCTAssertThrowsError(try failing.modify { state in
            try state.upsert(DailyLog(day: self.day, records: [self.record("new")], legacyAdjustmentCentigrams: 1_000,
                                      legacyAggregate: state.logs[0].legacyAggregate))
        }) {
            XCTAssertEqual(($0 as? StoreCommitError)?.underlying, .writeFailed("disk full"))
        }
        XCTAssertEqual(try FileAppStateStore(fileURL: fileURL).load(), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["app-state.json"])
    }

    func testTruncatedTemporaryFileIsDetectedBeforeReplace() throws {
        let original = try state()
        try FileAppStateStore(fileURL: fileURL).commit(original)
        struct TruncatingWriter: StoreFileWriter {
            func write(_ data: Data, to url: URL) throws { try data.prefix(data.count / 2).write(to: url) }
        }
        let store = FileAppStateStore(fileURL: fileURL, writer: TruncatingWriter())
        XCTAssertThrowsError(try store.modify { $0.settings.goalNeedsReview = true }) {
            XCTAssertEqual(($0 as? StoreCommitError)?.underlying, .verificationMismatch(.temporaryFile))
        }
        XCTAssertEqual(try FileAppStateStore(fileURL: fileURL).load(), original)
    }

    func testInterruptionBeforeReplaceKeepsOldFileAndAfterReplaceKeepsNewFile() throws {
        let original = try state()
        try FileAppStateStore(fileURL: fileURL).commit(original)
        struct Crash: Error {}

        let before = FileAppStateStore(fileURL: fileURL, hooks: StoreCommitHooks { stage in
            if stage == .beforeReplace { throw Crash() }
        })
        XCTAssertThrowsError(try before.modify { $0.settings.goalNeedsReview = true }) {
            XCTAssertEqual(($0 as? StoreCommitError)?.underlying, .interrupted(.beforeReplace))
        }
        XCTAssertEqual(try FileAppStateStore(fileURL: fileURL).load(), original)

        let after = FileAppStateStore(fileURL: fileURL, hooks: StoreCommitHooks { stage in
            if stage == .afterReplace { throw Crash() }
        })
        XCTAssertThrowsError(try after.modify(operationID: "op-1") { $0.settings.goalNeedsReview = true }) {
            XCTAssertEqual($0 as? StoreCommitError, .indeterminate(.interrupted(.afterReplace)))
        }
        XCTAssertTrue(after.hasUnconfirmedCommit)
        XCTAssertEqual(after.unconfirmedOperationID, "op-1")
        XCTAssertEqual(try FileAppStateStore(fileURL: fileURL).load().settings.goalNeedsReview, true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["app-state.json"])
    }

    func testModifyRejectsInvalidCandidateWithoutTouchingFile() throws {
        let original = try state()
        try FileAppStateStore(fileURL: fileURL).commit(original)
        let store = FileAppStateStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.modify { state in
            state.favorites.append(try FavoriteFood(id: "legacy:favorite:1", name: "dup", proteinCentigrams: 1, position: 9))
        }) {
            XCTAssertEqual($0 as? AppStateError, .duplicateFavoriteID("legacy:favorite:1"))
        }
        XCTAssertEqual(try store.load(), original)
    }

    func testConcurrentModificationsAcrossInstancesLoseNoUpdates() throws {
        try FileAppStateStore(fileURL: fileURL).commit(state())
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "writers", attributes: .concurrent)
        var failures = 0
        let failureLock = NSLock()
        for index in 0..<20 {
            group.enter()
            queue.async {
                defer { group.leave() }
                let store = FileAppStateStore(fileURL: self.fileURL)
                do {
                    try store.modify { state in
                        var log = state.log(for: self.day)!
                        try log.add(self.record("record-\(index)"))
                        try state.upsert(log)
                    }
                } catch {
                    failureLock.lock(); failures += 1; failureLock.unlock()
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
        XCTAssertEqual(failures, 0)
        let final = try FileAppStateStore(fileURL: fileURL).load()
        XCTAssertEqual(final.log(for: day)?.records.count, 20)
        XCTAssertEqual(try final.log(for: day)?.totalProteinCentigrams(), 1_000 + 20 * 500)
    }

    func testUpsertRemovesEmptyDaysButKeepsLegacyOnlyDays() throws {
        var current = try state()
        let other = try CalendarDay(iso8601: "2026-09-27")
        try current.upsert(DailyLog(day: other))
        XCTAssertNil(current.log(for: other))
        try current.upsert(DailyLog(day: other, legacyAdjustmentCentigrams: 0))
        XCTAssertEqual(current.log(for: other)?.detailState, .legacyTotalOnly)
        XCTAssertEqual(current.logs.map(\.day.iso8601), ["2026-09-27", "2026-09-28"])
    }

    func testLegacyImportRequiresCompleteMigrationMetadata() throws {
        XCTAssertThrowsError(try AppState(
            logs: [], favorites: [], searchHistory: [], settings: .freshInstall, goals: [],
            migration: MigrationRecord(origin: .legacyImport, migrationVersion: 1, completedAt: "2026-09-28T00:00:00Z",
                                       sourceFingerprint: nil, verification: nil)
        )) {
            XCTAssertEqual($0 as? AppStateError, .incompleteMigrationMetadata("sourceFingerprint"))
        }
        XCTAssertThrowsError(try AppState(
            logs: [], favorites: [], searchHistory: [], settings: .freshInstall, goals: [],
            migration: MigrationRecord(origin: .freshInstall, migrationVersion: 1, completedAt: "",
                                       sourceFingerprint: nil, verification: nil)
        )) {
            XCTAssertEqual($0 as? AppStateError, .incompleteMigrationMetadata("completedAt"))
        }
    }

    func testDecodingSchema2CannotBypassInvariants() throws {
        let day = self.day
        let goal = #"{"id":"g","effectiveFrom":"2026-09-01","amount":100}"#
        let json = """
        {"schemaVersion":2,"logs":[],"favorites":[],"searchHistory":[],
         "settings":{"searchLanguage":{"raw":null,"resolved":"english","isFallback":true},"legacyTargetRaw":null,"goalNeedsReview":false},
         "goals":[\(goal),\(goal.replacingOccurrences(of: #""id":"g""#, with: #""id":"h""#))],
         "migration":{"origin":"freshInstall","migrationVersion":1,"completedAt":"2026-09-28T00:00:00Z","sourceFingerprint":null,"verification":null}}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(AppState.self, from: Data(json.utf8))) {
            XCTAssertEqual($0 as? AppStateError, .goalHistory(.duplicateGoalEffectiveDate(try! CalendarDay(iso8601: "2026-09-01"))))
        }
        _ = day
    }


    func testInterruptionAfterTemporaryWriteKeepsOldFileAndLeavesNoTemp() throws {
        let original = try state()
        try FileAppStateStore(fileURL: fileURL).commit(original)
        struct Crash: Error {}
        let store = FileAppStateStore(fileURL: fileURL, hooks: StoreCommitHooks { stage in
            if stage == .temporaryFile { throw Crash() }
        })
        XCTAssertThrowsError(try store.modify { $0.settings.goalNeedsReview = true }) {
            XCTAssertEqual(($0 as? StoreCommitError)?.underlying, .interrupted(.temporaryFile))
        }
        XCTAssertEqual(try FileAppStateStore(fileURL: fileURL).load(), original)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".") }
        XCTAssertTrue(leftovers.isEmpty, "\(leftovers)")
    }

    func testDurableWriterReportsFailureInsteadOfRaising() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A directory cannot be opened for writing: must surface as StoreError, not an ObjC exception.
        XCTAssertThrowsError(try DurableFileWriter.write(Data("x".utf8), toExistingFile: directory)) { error in
            guard case .writeFailed(let detail)? = error as? StoreError else { return XCTFail("\(error)") }
            XCTAssertTrue(detail.hasPrefix("open:"), detail)
        }
        XCTAssertThrowsError(try DurableFileWriter.write(Data("x".utf8), toExistingFile: directory.appendingPathComponent("missing.json")))
    }

    func testStaleTemporaryFilesAreRemovedOnlyWhenOld() throws {
        let original = try state()
        try FileAppStateStore(fileURL: fileURL).commit(original)
        let fresh = directory.appendingPathComponent(".app-state.json.tmp-fresh")
        let old = directory.appendingPathComponent(".app-state.json.tmp-old")
        try Data("{".utf8).write(to: fresh)
        try Data("{".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-2 * FileAppStateStore.staleTemporaryFileAge)], ofItemAtPath: old.path)
        try FileAppStateStore(fileURL: fileURL).modify { $0.settings.goalNeedsReview = true }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path), "a recent temp file may belong to another writer")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "an hour-old temp file is garbage")
        XCTAssertEqual(try FileAppStateStore(fileURL: fileURL).load().settings.goalNeedsReview, true)
    }

    // MARK: Commit outcome contract (R2)

    func testFailureBeforeRenameIsNotCommittedAndRetryable() throws {
        let original = try state()
        try FileAppStateStore(fileURL: fileURL).commit(original)
        struct Crash: Error {}
        let store = FileAppStateStore(fileURL: fileURL, hooks: StoreCommitHooks { stage in
            if stage == .beforeReplace { throw Crash() }
        })
        XCTAssertThrowsError(try store.modify(operationID: "op-a") { $0.settings.goalNeedsReview = true }) {
            XCTAssertEqual($0 as? StoreCommitError, .notCommitted(.interrupted(.beforeReplace)))
        }
        XCTAssertFalse(store.hasUnconfirmedCommit)
        XCTAssertEqual(try FileAppStateStore(fileURL: fileURL).load(), original, "disk still holds the previous value")
        XCTAssertNil(try FileAppStateStore(fileURL: fileURL).load().lastOperationID)
        // The same operation can simply be retried on the same store instance.
        let plain = FileAppStateStore(fileURL: fileURL)
        let committed = try plain.modify(operationID: "op-a") { $0.settings.goalNeedsReview = true }
        XCTAssertEqual(committed.lastOperationID, "op-a")
        XCTAssertEqual(try plain.load().settings.goalNeedsReview, true)
    }

    func testFinalReadFailureAfterRenameIsIndeterminateBlocksWritesAndConvergesOnReload() throws {
        guard geteuid() != 0 else { throw XCTSkip("root ignores permissions") }
        let original = try state()
        try FileAppStateStore(fileURL: fileURL).commit(original)
        let fileURL = self.fileURL
        // Make the final read-back fail for real, once: revoke read permission right after the rename.
        var armed = true
        let store = FileAppStateStore(fileURL: fileURL, hooks: StoreCommitHooks { stage in
            if stage == .afterReplace && armed {
                armed = false
                try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
            }
        })
        let record = try FoodRecord(id: "r1", day: day, name: "닭", quantity: nil, protein: ProteinAmount(centigrams: 2_000), source: .manual)
        let day = self.day
        XCTAssertThrowsError(try store.modify(operationID: "op-add") { state in
            var log = try XCTUnwrap(state.log(for: day))
            try log.add(record)
            try state.upsert(log)
        }) {
            XCTAssertEqual($0 as? StoreCommitError, .indeterminate(.verificationMismatch(.finalFile)))
        }
        XCTAssertTrue(store.hasUnconfirmedCommit)
        XCTAssertEqual(store.unconfirmedOperationID, "op-add")

        // Every further write is refused until the state is confirmed. The
        // refusal is `indeterminate`: the disk state is unknown, so "retry the
        // same operation" would be wrong advice.
        XCTAssertThrowsError(try store.modify(operationID: "op-other") { $0.settings.goalNeedsReview = true }) {
            XCTAssertEqual($0 as? StoreCommitError, .indeterminate(.previousCommitUnconfirmed(operationID: "op-add")))
        }
        XCTAssertThrowsError(try store.commit(original)) {
            XCTAssertEqual($0 as? StoreCommitError, .indeterminate(.previousCommitUnconfirmed(operationID: "op-add")))
        }
        // The block is per file path: another instance on the same file is refused too.
        let other = FileAppStateStore(fileURL: fileURL)
        XCTAssertTrue(other.hasUnconfirmedCommit)
        XCTAssertEqual(other.unconfirmedOperationID, "op-add")
        XCTAssertThrowsError(try other.modify(operationID: "op-third") { $0.settings.goalNeedsReview = true }) {
            XCTAssertEqual($0 as? StoreCommitError, .indeterminate(.previousCommitUnconfirmed(operationID: "op-add")))
        }
        // A different file is unaffected.
        let unrelated = FileAppStateStore(fileURL: fileURL.deletingLastPathComponent().appendingPathComponent("other.json"))
        XCTAssertFalse(unrelated.hasUnconfirmedCommit)
        try unrelated.commit(original)
        // Still unreadable: reconfirmation fails and the block stays.
        XCTAssertThrowsError(try store.load())
        XCTAssertTrue(store.hasUnconfirmedCommit)

        // Access restored: the reload shows the operation landed exactly once.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        let confirmed = try store.load()
        XCTAssertFalse(store.hasUnconfirmedCommit)
        XCTAssertEqual(confirmed.lastOperationID, "op-add")
        XCTAssertEqual(confirmed.log(for: day)?.records.map(\.id), ["r1"])
        // No temp files linger and writes work again.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".") }
        XCTAssertTrue(leftovers.isEmpty, "\(leftovers)")
        let next = try store.modify(operationID: "op-next") { $0.settings.goalNeedsReview = true }
        XCTAssertEqual(next.lastOperationID, "op-next")
        XCTAssertEqual(next.log(for: day)?.records.count, 1, "the retry logic never re-adds r1")
    }

    func testSchema2FileWithoutOperationIDStillDecodesAndRoundTrips() throws {
        let original = try state()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var json = try JSONSerialization.jsonObject(with: encoder.encode(original)) as! [String: Any]
        json.removeValue(forKey: "lastOperationID")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: fileURL)
        let store = FileAppStateStore(fileURL: fileURL)
        let loaded = try store.load()
        XCTAssertNil(loaded.lastOperationID)
        XCTAssertEqual(loaded.logs, original.logs)
        XCTAssertEqual(loaded.favorites, original.favorites)
        let written = try store.modify(operationID: "op-z") { _ in }
        XCTAssertEqual(written.lastOperationID, "op-z")
        XCTAssertEqual(try store.load().lastOperationID, "op-z")
        let cleared = try store.modify { _ in }
        XCTAssertNil(cleared.lastOperationID, "a write without an operation ID clears the stale claim")
    }

    func testInspectFindingAReadyFileLiftsTheWriteBlockLikeLoad() throws {
        guard geteuid() != 0 else { throw XCTSkip("root ignores permissions") }
        let original = try state()
        try FileAppStateStore(fileURL: fileURL).commit(original)
        let fileURL = self.fileURL
        var armed = true
        let store = FileAppStateStore(fileURL: fileURL, hooks: StoreCommitHooks { stage in
            if stage == .afterReplace && armed {
                armed = false
                try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
            }
        })
        XCTAssertThrowsError(try store.modify(operationID: "op-1") { $0.settings.goalNeedsReview = true })
        XCTAssertTrue(store.hasUnconfirmedCommit)
        // Still unreadable: inspect reports it and the block stays.
        guard case .unreadable = store.inspect() else { return XCTFail("expected unreadable") }
        XCTAssertTrue(store.hasUnconfirmedCommit)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        // The launch path inspects rather than loads; a ready result confirms the state.
        guard case .ready(let confirmed) = FileAppStateStore(fileURL: fileURL).inspect() else { return XCTFail("expected ready") }
        XCTAssertEqual(confirmed.lastOperationID, "op-1")
        XCTAssertFalse(store.hasUnconfirmedCommit)
        try store.modify(operationID: "op-2") { $0.settings.goalNeedsReview = false }
        XCTAssertEqual(try store.load().lastOperationID, "op-2")
    }

    func testCommitRethrowsValidationErrorsUnchanged() throws {
        var invalid = try state()
        invalid.favorites.append(try FavoriteFood(id: "legacy:favorite:1", name: "dup", proteinCentigrams: 1, position: 9))
        XCTAssertThrowsError(try FileAppStateStore(fileURL: fileURL).commit(invalid)) { error in
            XCTAssertEqual(error as? AppStateError, .duplicateFavoriteID("legacy:favorite:1"), "not wrapped as a storage failure: \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
