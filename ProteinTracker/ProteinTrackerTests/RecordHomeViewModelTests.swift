import XCTest
import HelloProteinCore

@available(iOS 15.0, *)
final class RecordHomeViewModelTests: XCTestCase {
    func testGoalPresentationClampsVisualProgressButKeepsExactExcess() {
        let over = GoalProgressPresentation(total: 13_200, goal: 12_000)
        XCTAssertEqual(over.fraction, 1)
        XCTAssertEqual(over.excessCentigrams, 1_200)
        XCTAssertTrue(over.isReached)
        let under = GoalProgressPresentation(total: 5_170, goal: 12_000)
        XCTAssertEqual(under.fraction, Double(5_170) / 12_000, accuracy: 0.000001)
        XCTAssertNil(under.excessCentigrams)
        XCTAssertFalse(under.isReached)
    }

    func testGoalPresentationHandlesSignedAndExtremeTotalsWithoutOverflow() {
        let negative = GoalProgressPresentation(total: .min, goal: .max)
        XCTAssertEqual(negative.fraction, 0)
        XCTAssertNil(negative.excessCentigrams)
        XCTAssertFalse(negative.isReached)
        let large = GoalProgressPresentation(total: .max, goal: 1)
        XCTAssertEqual(large.excessCentigrams, Int64.max - 1)
        let exact = GoalProgressPresentation(total: .max, goal: .max)
        XCTAssertTrue(exact.isReached)
        XCTAssertNil(exact.excessCentigrams)
        XCTAssertEqual(GoalProgressPresentation(total: 1, goal: 0).fraction, 0)
    }

    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("app-state.json") }
    private let queue = DispatchQueue(label: "vm-tests")
    private let seoul = TimeZone(identifier: "Asia/Seoul")!
    private let now = Date(timeIntervalSince1970: 1_790_638_200) // 2026-09-28T23:30Z → 09-29 in Seoul

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("VMTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try FileManager.default.removeItem(at: directory)
    }

    private func seededState() throws -> AppState {
        let legacyDay = try CalendarDay(iso8601: "2026-09-20")
        let log = try DailyLog(day: legacyDay, legacyAdjustmentCentigrams: 7_000, legacyAggregate: LegacyAggregate(
            sourceID: "legacy:stat:1", importedTotalCentigrams: 7_000, importedDetailSumCentigrams: 0,
            originalLabel: "2026-09-20-일", originalInstant: nil))
        return try AppState(
            logs: [log], favorites: [], searchHistory: [],
            settings: AppSettings(searchLanguage: .interpret(raw: nil), legacyTargetRaw: "120", goalNeedsReview: false),
            goals: [ProteinGoal(id: "legacy:goal:targetProtein", effectiveFrom: CalendarDay(iso8601: "2026-09-28"), amount: ProteinAmount(centigrams: 12_000))],
            migration: MigrationRecord(origin: .legacyImport, migrationVersion: 1, completedAt: "2026-09-28T00:00:00.000Z",
                                       sourceFingerprint: "fp", verification: MigrationVerification(
                                           legacyFoodCount: 0, legacyHistoryCount: 1, favoriteCount: 0, searchTermCount: 0,
                                           legacyDayCount: 1, legacyCurrentTotalCentigrams: nil, legacyHistoryTotalCentigrams: 7_000))
        )
    }

    private func makeModel(writer: StoreFileWriter = DefaultStoreFileWriter(),
                           hooks: StoreCommitHooks = StoreCommitHooks(),
                           state: AppState? = nil) throws -> (RecordHomeViewModel, FileAppStateStore) {
        let state = try state ?? seededState()
        try FileAppStateStore(fileURL: storeURL).commit(state)
        let store = FileAppStateStore(fileURL: storeURL, writer: writer, hooks: hooks)
        return (makeModel(store: store, state: state), store)
    }

    private func makeModel(store: AppStateStore, state: AppState) -> RecordHomeViewModel {
        RecordHomeViewModel(store: store, state: state, now: { self.now }, timeZone: seoul,
                            decimalSeparator: ".", workQueue: queue, mainQueue: queue)
    }

    /// Fires the final read-back failure exactly once by revoking read access right after the rename.
    private func unreadableAfterFirstReplace() -> StoreCommitHooks {
        let url = storeURL
        var armed = true
        return StoreCommitHooks { stage in
            if stage == .afterReplace && armed {
                armed = false
                try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
            }
        }
    }

    private func restoreStoreAccess() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storeURL.path)
    }

    enum Outcome: Equatable {
        case ok
        case failed(RecordHomeViewModel.ActionError)
        init(_ result: Result<Void, RecordHomeViewModel.ActionError>) {
            switch result {
            case .success: self = .ok
            case .failure(let error): self = .failed(error)
            }
        }
    }

    private func wait(_ body: (@escaping (Result<Void, RecordHomeViewModel.ActionError>) -> Void) -> Void) -> Outcome {
        let expectation = expectation(description: "action")
        var captured: Outcome!
        body { result in captured = Outcome(result); expectation.fulfill() }
        waitForExpectations(timeout: 5)
        return captured
    }

    private func sync<T>(_ body: @escaping () -> T) -> T { queue.sync(execute: body) }

    func testTodayComesFromInjectedClockAndZone() throws {
        let (model, _) = try makeModel()
        XCTAssertEqual(model.today.iso8601, "2026-09-29")
        XCTAssertEqual(model.selectedDay, model.today)
        XCTAssertEqual(model.visibleDays.map(\.iso8601).first, "2026-09-26")
        XCTAssertEqual(model.visibleDays.count, 7)
        XCTAssertEqual(model.goalState, .goal(try ProteinAmount(centigrams: 12_000)))
    }

    func testPastDayShowsLegacyTotalAndNoGoalHistory() throws {
        let (model, _) = try makeModel()
        sync { model.select(try! CalendarDay(iso8601: "2026-09-20")) }
        XCTAssertEqual(model.log.detailState, .legacyTotalOnly)
        XCTAssertEqual(model.totalCentigrams, 7_000)
        XCTAssertEqual(model.goalState, .noHistory)
    }

    func testAddEditDeletePersistAndSurviveStoreRecreation() throws {
        let (model, _) = try makeModel()
        let day = try CalendarDay(iso8601: "2026-09-29")
        XCTAssertEqual(wait { model.addRecord(day: day, name: "닭가슴살", proteinText: "23.5", completion: $0) }, .ok)
        let added = sync { model.log.records }
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(sync { model.totalCentigrams }, 2_350)

        let id = added[0].id
        XCTAssertEqual(wait { model.updateRecord(day: day, id: id, name: nil, proteinText: "30", completion: $0) }, .ok)
        let updated = sync { model.log.records[0] }
        XCTAssertEqual(updated.id, id)
        XCTAssertEqual(updated.protein.centigrams, 3_000)
        XCTAssertNil(updated.name)
        XCTAssertEqual(updated.source, .manual)

        let reloaded = try FileAppStateStore(fileURL: storeURL).load()
        XCTAssertEqual(reloaded.log(for: day)?.records, [updated])

        XCTAssertEqual(wait { model.deleteRecord(day: day, id: id, completion: $0) }, .ok)
        XCTAssertTrue(sync { model.log.records.isEmpty })
        XCTAssertNil(try FileAppStateStore(fileURL: storeURL).load().log(for: day), "empty non-legacy day is not stored")
    }

    func testEditKeepsSourceQuantityAndLegacyIdentity() throws {
        let day = try CalendarDay(iso8601: "2026-09-23")
        let legacy = try FoodRecord(id: "legacy:daily:1", day: day, name: "우유", quantity: FoodQuantity(value: "200", unit: .milliliter),
                                    protein: ProteinAmount(centigrams: 1_000), source: .legacy, legacySourceID: "1")
        var state = try seededState()
        try state.upsert(DailyLog(day: day, records: [legacy]))
        try FileAppStateStore(fileURL: storeURL).commit(state)
        let model = RecordHomeViewModel(store: FileAppStateStore(fileURL: storeURL), state: state, now: { self.now }, timeZone: seoul,
                                        decimalSeparator: ".", workQueue: queue, mainQueue: queue)
        XCTAssertEqual(wait { model.updateRecord(day: day, id: legacy.id, name: "우유 (저지방)", proteinText: "9", completion: $0) }, .ok)
        let record = try XCTUnwrap(FileAppStateStore(fileURL: storeURL).load().log(for: day)?.record(id: legacy.id))
        XCTAssertEqual(record.quantity, legacy.quantity)
        XCTAssertEqual(record.source, .legacy)
        XCTAssertEqual(record.legacySourceID, "1")
        XCTAssertEqual(record.protein.centigrams, 900)
        XCTAssertEqual(record.name, "우유 (저지방)")
    }

    func testSaveTargetsTheSheetDayEvenAfterSelectionChanges() throws {
        let (model, _) = try makeModel()
        let target = try CalendarDay(iso8601: "2026-09-25")
        sync { model.select(try! CalendarDay(iso8601: "2026-09-26")) }
        XCTAssertEqual(wait { model.addRecord(day: target, name: nil, proteinText: "5", completion: $0) }, .ok)
        XCTAssertTrue(sync { model.log.records.isEmpty }, "selected day unchanged")
        XCTAssertEqual(try FileAppStateStore(fileURL: storeURL).load().log(for: target)?.records.count, 1)
    }

    func testLegacyTotalEditUsesTotalMinusDetails() throws {
        let (model, _) = try makeModel()
        let day = try CalendarDay(iso8601: "2026-09-20")
        sync { model.select(day) }
        XCTAssertEqual(wait { model.addRecord(day: day, name: "두부", proteinText: "10", completion: $0) }, .ok)
        XCTAssertEqual(sync { model.totalCentigrams }, 8_000)
        XCTAssertEqual(wait { model.setLegacyTotal(day: day, totalText: "75", completion: $0) }, .ok)
        let log = sync { model.log }
        XCTAssertEqual(log.legacyAdjustmentCentigrams, 6_500)
        XCTAssertEqual(try log.totalProteinCentigrams(), 7_500)
        XCTAssertEqual(log.legacyAggregate?.userEditedTotalCentigrams, 7_500)
        XCTAssertEqual(log.legacyAggregate?.importedTotalCentigrams, 7_000)
        // Not allowed on a day without a legacy total.
        let plain = try CalendarDay(iso8601: "2026-09-29")
        XCTAssertEqual(wait { model.setLegacyTotal(day: plain, totalText: "10", completion: $0) }, .failed(.notFound))
    }

    func testInputErrorsAreTypedAndChangeNothing() throws {
        let (model, _) = try makeModel()
        let day = try CalendarDay(iso8601: "2026-09-29")
        let cases: [(String, ProteinInputError)] = [("", .empty), ("12abc", .notANumber), ("1,234", .groupingSeparatorNotAllowed),
                                                    ("1.234", .tooManyFractionDigits), ("0", .notPositive)]
        for (text, expected) in cases {
            XCTAssertEqual(wait { model.addRecord(day: day, name: nil, proteinText: text, completion: $0) }, .failed(.input(expected)), text)
        }
        XCTAssertTrue(sync { model.log.records.isEmpty })
        XCTAssertNil(try FileAppStateStore(fileURL: storeURL).load().log(for: day))
    }

    func testStorageFailureKeepsScreenStateAndReportsStorageError() throws {
        struct FailingWriter: StoreFileWriter {
            func write(_ data: Data, to url: URL) throws { throw StoreError.writeFailed("disk full") }
        }
        let (model, _) = try makeModel(writer: FailingWriter())
        let day = try CalendarDay(iso8601: "2026-09-20")
        sync { model.select(day) }
        let result = wait { model.addRecord(day: day, name: "x", proteinText: "5", completion: $0) }
        guard case .failed(.storage(let detail)) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(detail.contains("disk full"))
        XCTAssertEqual(sync { model.totalCentigrams }, 7_000)
        XCTAssertTrue(sync { model.log.records.isEmpty })
        XCTAssertFalse(sync { model.isBusy })
        XCTAssertEqual(try FileAppStateStore(fileURL: storeURL).load().log(for: day)?.records.count, 0)
    }

    func testSecondActionWhileBusyIsRejectedAndNothingIsLost() throws {
        let (model, _) = try makeModel()
        let day = try CalendarDay(iso8601: "2026-09-29")
        let first = expectation(description: "first")
        let second = expectation(description: "second")
        var secondResult: Outcome?
        queue.sync {
            model.addRecord(day: day, name: "a", proteinText: "1") { _ in first.fulfill() }
            model.addRecord(day: day, name: "b", proteinText: "2") { secondResult = Outcome($0); second.fulfill() }
        }
        waitForExpectations(timeout: 5)
        XCTAssertEqual(secondResult, .failed(.busy))
        XCTAssertEqual(sync { model.log.records.count }, 1)
        XCTAssertEqual(wait { model.addRecord(day: day, name: "b", proteinText: "2", completion: $0) }, .ok)
        XCTAssertEqual(sync { model.log.records.map(\.name) }, ["a", "b"])
    }

    func testGoalStatesForNeedsReviewAndNotSet() throws {
        var state = try seededState()
        state.settings.goalNeedsReview = true
        let reviewState = try AppState(logs: state.logs, favorites: [], searchHistory: [], settings: state.settings, goals: [], migration: state.migration)
        XCTAssertEqual(RecordHomeViewModel.goalState(for: try CalendarDay(iso8601: "2026-09-29"), in: reviewState), .needsReview(raw: "120"))
        let noGoal = try AppState(logs: [], favorites: [], searchHistory: [], settings: .freshInstall, goals: [],
                                  migration: MigrationRecord(origin: .freshInstall, migrationVersion: 1, completedAt: "x", sourceFingerprint: nil, verification: nil))
        XCTAssertEqual(RecordHomeViewModel.goalState(for: try CalendarDay(iso8601: "2026-09-29"), in: noGoal), .notSet)
    }


    func testLegacyTotalCanBeSetToZeroOrNegative() throws {
        let (model, _) = try makeModel()
        let day = try CalendarDay(iso8601: "2026-09-20")
        sync { model.select(day) }
        XCTAssertEqual(wait { model.setLegacyTotal(day: day, totalText: "0", completion: $0) }, .ok)
        XCTAssertEqual(sync { model.totalCentigrams }, 0)
        XCTAssertEqual(wait { model.addRecord(day: day, name: "두부", proteinText: "10", completion: $0) }, .ok)
        XCTAssertEqual(wait { model.setLegacyTotal(day: day, totalText: "-5", completion: $0) }, .ok)
        let log = sync { model.log }
        XCTAssertEqual(log.legacyAdjustmentCentigrams, -1_500)
        XCTAssertEqual(try log.totalProteinCentigrams(), -500)
        XCTAssertEqual(log.legacyAggregate?.importedTotalCentigrams, 7_000)
    }

    // MARK: Unconfirmed saves (R2)

    func testIndeterminateSaveBlocksFurtherWritesAndConvergesToOneRecordAfterReconfirm() throws {
        guard geteuid() != 0 else { throw XCTSkip("root ignores permissions") }
        let (model, _) = try makeModel(hooks: unreadableAfterFirstReplace())
        let day = try CalendarDay(iso8601: "2026-09-20")
        sync { model.select(day) }

        // rename succeeded, final read-back failed → unconfirmed, screen keeps the confirmed state.
        let first = wait { model.addRecord(day: day, id: "rec-1", name: "닭가슴살", proteinText: "23", completion: $0) }
        guard case .failed(.unconfirmed(let operationID)) = first else { return XCTFail("\(first)") }
        XCTAssertEqual(sync { model.pendingSave }, .init(operationID: operationID, day: day))
        XCTAssertEqual(sync { model.totalCentigrams }, 7_000, "screen shows the last confirmed state, not a guess")
        XCTAssertTrue(sync { model.log.records.isEmpty })
        XCTAssertFalse(sync { model.isBusy })

        // Every further write is refused while the outcome is unknown, including a naive retry.
        XCTAssertEqual(wait { model.addRecord(day: day, id: "rec-1", name: "닭가슴살", proteinText: "23", completion: $0) },
                       .failed(.unconfirmed(operationID: operationID)))
        XCTAssertEqual(wait { model.setLegacyTotal(day: day, totalText: "80", completion: $0) },
                       .failed(.unconfirmed(operationID: operationID)))

        // Reconfirmation while the file is still unreadable fails and keeps the pending state.
        let stillBlocked = wait { model.reconfirm(completion: $0) }
        guard case .failed(.storage) = stillBlocked else { return XCTFail("\(stillBlocked)") }
        XCTAssertNotNil(sync { model.pendingSave })

        // Access restored: the reload shows the operation landed exactly once and the save converges.
        try restoreStoreAccess()
        XCTAssertEqual(wait { model.reconfirm(completion: $0) }, .ok)
        XCTAssertNil(sync { model.pendingSave })
        XCTAssertEqual(sync { model.log.records.map(\.id) }, ["rec-1"])
        XCTAssertEqual(sync { model.totalCentigrams }, 9_300, "total increased once")

        // A different, later entry is a separate operation and is stored as its own row.
        XCTAssertEqual(wait { model.addRecord(day: day, id: "rec-2", name: "닭가슴살", proteinText: "23", completion: $0) }, .ok)
        XCTAssertEqual(sync { model.log.records.map(\.id) }, ["rec-1", "rec-2"])

        // A fresh launch reads the same file: still exactly those rows.
        let relaunched = try FileAppStateStore(fileURL: storeURL).load()
        XCTAssertEqual(relaunched.log(for: day)?.records.map(\.id), ["rec-1", "rec-2"])
        XCTAssertEqual(try relaunched.log(for: day)?.totalProteinCentigrams(), 11_600)
    }

    func testReconfirmReportsNotAppliedWhenTheFileLacksTheOperationAndTheRetrySavesOnce() throws {
        // A store that reports "indeterminate" once without having written anything,
        // the shape of "rename returned but the process/OS lost the write".
        final class IndeterminateOnceStore: AppStateStore {
            let inner: FileAppStateStore
            var armed = true
            init(inner: FileAppStateStore) { self.inner = inner }
            func load() throws -> AppState { try inner.load() }
            var unconfirmedOperationID: String? { inner.unconfirmedOperationID }
            var hasUnconfirmedCommit: Bool { inner.hasUnconfirmedCommit }
            func modify(operationID: String?, _ change: (inout AppState) throws -> Void) throws -> AppState {
                if armed { armed = false; throw StoreCommitError.indeterminate(.verificationMismatch(.finalFile)) }
                return try inner.modify(operationID: operationID, change)
            }
        }
        let state = try seededState()
        try FileAppStateStore(fileURL: storeURL).commit(state)
        let store = IndeterminateOnceStore(inner: FileAppStateStore(fileURL: storeURL))
        let model = makeModel(store: store, state: state)
        let day = try CalendarDay(iso8601: "2026-09-20")
        sync { model.select(day) }

        let first = wait { model.addRecord(day: day, id: "rec-1", name: "두부", proteinText: "8", completion: $0) }
        guard case .failed(.unconfirmed) = first else { return XCTFail("\(first)") }
        XCTAssertEqual(wait { model.reconfirm(completion: $0) }, .failed(.notApplied))
        XCTAssertNil(sync { model.pendingSave }, "the state is known again: nothing was written")
        XCTAssertTrue(sync { model.log.records.isEmpty })

        // Same editing session, same record ID: exactly one row after the retry.
        XCTAssertEqual(wait { model.addRecord(day: day, id: "rec-1", name: "두부", proteinText: "8", completion: $0) }, .ok)
        XCTAssertEqual(sync { model.log.records.map(\.id) }, ["rec-1"])
        XCTAssertEqual(try FileAppStateStore(fileURL: storeURL).load().log(for: day)?.records.count, 1)
    }

    func testDeleteAndEditWithUnknownOutcomeAreReconfirmedNotRetriedBlindly() throws {
        guard geteuid() != 0 else { throw XCTSkip("root ignores permissions") }
        var seeded = try seededState()
        let day = try CalendarDay(iso8601: "2026-09-20")
        var log = try XCTUnwrap(seeded.log(for: day))
        try log.add(FoodRecord(id: "old-1", day: day, name: "우유", quantity: nil, protein: ProteinAmount(centigrams: 1_000), source: .legacy))
        try seeded.upsert(log)
        let (model, _) = try makeModel(hooks: unreadableAfterFirstReplace(), state: seeded)
        sync { model.select(day) }

        let deletion = wait { model.deleteRecord(day: day, id: "old-1", completion: $0) }
        guard case .failed(.unconfirmed) = deletion else { return XCTFail("\(deletion)") }
        XCTAssertEqual(sync { model.log.records.map(\.id) }, ["old-1"], "screen still shows the confirmed state")
        // Retrying the deletion blindly is refused instead of producing a notFound surprise.
        guard case .failed(.unconfirmed) = wait({ model.deleteRecord(day: day, id: "old-1", completion: $0) }) else { return XCTFail() }

        try restoreStoreAccess()
        XCTAssertEqual(wait { model.reconfirm(completion: $0) }, .ok, "the deletion had landed")
        XCTAssertTrue(sync { model.log.records.isEmpty })
        XCTAssertEqual(try FileAppStateStore(fileURL: storeURL).load().log(for: day)?.records.count, 0)
    }

    func testScreenStartedOnAnAlreadyBlockedStoreShowsThePendingStateAndReconfirmClearsIt() throws {
        guard geteuid() != 0 else { throw XCTSkip("root ignores permissions") }
        // The launch commit (no operation ID) ended unconfirmed, and the same
        // store instance is handed to the screen, as SceneDelegate does.
        let state = try seededState()
        let url = storeURL
        var armed = true
        let store = FileAppStateStore(fileURL: url, hooks: StoreCommitHooks { stage in
            if stage == .afterReplace && armed {
                armed = false
                try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
            }
        })
        XCTAssertThrowsError(try store.commit(state))
        XCTAssertTrue(store.hasUnconfirmedCommit)

        let model = makeModel(store: store, state: state)
        XCTAssertEqual(sync { model.pendingSave }, .init(operationID: nil, day: model.today),
                       "the blocked store is visible from the first frame")
        let day = try CalendarDay(iso8601: "2026-09-20")
        sync { model.select(day) }
        // A save is refused as unconfirmed (reconfirm reachable), never as a plain storage failure.
        XCTAssertEqual(wait { model.addRecord(day: day, id: "rec-1", name: "두부", proteinText: "8", completion: $0) },
                       .failed(.unconfirmed(operationID: nil)))

        // Still unreadable: the pending state stays.
        guard case .failed(.storage) = wait({ model.reconfirm(completion: $0) }) else { return XCTFail("expected storage error") }
        XCTAssertNotNil(sync { model.pendingSave })

        try restoreStoreAccess()
        XCTAssertEqual(wait { model.reconfirm(completion: $0) }, .ok, "a pending save without an ID is confirmed by the read alone")
        XCTAssertNil(sync { model.pendingSave })
        XCTAssertFalse(store.hasUnconfirmedCommit)
        XCTAssertEqual(wait { model.addRecord(day: day, id: "rec-1", name: "두부", proteinText: "8", completion: $0) }, .ok)
        XCTAssertEqual(try FileAppStateStore(fileURL: url).load().log(for: day)?.records.map(\.id), ["rec-1"])
    }

    func testBlockedStoreRefusalNamesTheEarlierOperationNotTheNewOne() throws {
        guard geteuid() != 0 else { throw XCTSkip("root ignores permissions") }
        let (model, store) = try makeModel(hooks: unreadableAfterFirstReplace())
        let day = try CalendarDay(iso8601: "2026-09-20")
        sync { model.select(day) }
        let first = wait { model.addRecord(day: day, id: "rec-1", name: "닭", proteinText: "23", completion: $0) }
        guard case .failed(.unconfirmed(let earlier)) = first, earlier != nil else { return XCTFail("\(first)") }

        // A second screen on the same (still blocked) store starts pending with that same ID.
        let second = makeModel(store: store, state: sync { model.state })
        XCTAssertEqual(sync { second.pendingSave }?.operationID, earlier)
        XCTAssertEqual(wait { second.addRecord(day: day, id: "rec-2", name: "x", proteinText: "1", completion: $0) },
                       .failed(.unconfirmed(operationID: earlier)))
        try restoreStoreAccess()
        XCTAssertEqual(wait { second.reconfirm(completion: $0) }, .ok)
        sync { second.select(day) }
        XCTAssertEqual(sync { second.log.records.map(\.id) }, ["rec-1"])
    }
}
