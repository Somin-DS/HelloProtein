import XCTest
import SwiftUI
import UIKit
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
    /// What the model's injected clock returns; tests move it past midnight.
    private var clock: Date!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("VMTests-\(UUID().uuidString)")
        clock = now
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
        RecordHomeViewModel(store: store, state: state, now: { self.clock }, timeZone: seoul,
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
        guard case .failed(.reconfirmFailed) = stillBlocked else { return XCTFail("\(stillBlocked)") }
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
        guard case .failed(.reconfirmFailed) = wait({ model.reconfirm(completion: $0) }) else { return XCTFail("expected reconfirmFailed") }
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

    // MARK: Phase 1B: state doubles for the three re-check outcomes and the delete contract

    /// Counts writes so the sheet contract "cancel writes nothing, confirm deletes once" can be checked.
    final class CountingStore: AppStateStore {
        let inner: AppStateStore
        private(set) var modifyCalls = 0
        private(set) var loadCalls = 0
        init(inner: AppStateStore) { self.inner = inner }
        func load() throws -> AppState { loadCalls += 1; return try inner.load() }
        var unconfirmedOperationID: String? { inner.unconfirmedOperationID }
        var hasUnconfirmedCommit: Bool { inner.hasUnconfirmedCommit }
        func modify(operationID: String?, _ change: (inout AppState) throws -> Void) throws -> AppState {
            modifyCalls += 1
            return try inner.modify(operationID: operationID, change)
        }
    }

    private func seededWithRecord(_ id: String = "old-1") throws -> (AppState, CalendarDay) {
        var seeded = try seededState()
        let day = try CalendarDay(iso8601: "2026-09-20")
        var log = try XCTUnwrap(seeded.log(for: day))
        try log.add(FoodRecord(id: id, day: day, name: "우유", quantity: nil, protein: ProteinAmount(centigrams: 1_000), source: .legacy))
        try seeded.upsert(log)
        return (seeded, day)
    }

    func testConfirmedDeleteWritesExactlyOnceAndNothingBeforeThat() throws {
        let (state, day) = try seededWithRecord()
        try FileAppStateStore(fileURL: storeURL).commit(state)
        let store = CountingStore(inner: FileAppStateStore(fileURL: storeURL))
        let model = makeModel(store: store, state: state)
        sync { model.select(day) }
        // Opening the sheet, cancelling the prompt: no write.
        XCTAssertEqual(store.modifyCalls, 0)
        XCTAssertEqual(wait { model.deleteRecord(day: day, id: "old-1", completion: $0) }, .ok)
        XCTAssertEqual(store.modifyCalls, 1)
        XCTAssertTrue(sync { model.log.records.isEmpty })
        XCTAssertEqual(try FileAppStateStore(fileURL: storeURL).load().log(for: day)?.records.count, 0)
        // Re-reading is the only thing a "retry" may do before writing again.
        XCTAssertEqual(store.loadCalls, 0)
    }

    func testSaveOutcomeDoubleNotAppliedUnlocksAndKeepsTheRowSoTheDeleteCanBeRepeated() throws {
        let (state, day) = try seededWithRecord()
        try FileAppStateStore(fileURL: storeURL).commit(state)
        let counting = CountingStore(inner: FileAppStateStore(fileURL: storeURL))
        let store = SaveOutcomeInjectingStore(inner: counting, mode: .notApplied)
        let model = makeModel(store: store, state: state)
        sync { model.select(day) }

        let deletion = wait { model.deleteRecord(day: day, id: "old-1", completion: $0) }
        guard case .failed(.unconfirmed) = deletion else { return XCTFail("\(deletion)") }
        XCTAssertNotNil(sync { model.pendingSave })
        XCTAssertEqual(counting.modifyCalls, 0, "the double reports indeterminate without writing")
        XCTAssertEqual(sync { model.log.records.map(\.id) }, ["old-1"], "screen keeps the confirmed state")

        XCTAssertEqual(wait { model.reconfirm(completion: $0) }, .failed(.notApplied))
        XCTAssertEqual(counting.loadCalls, 1, "reconfirm reads, it never re-writes")
        XCTAssertNil(sync { model.pendingSave }, "unlocked again")
        XCTAssertEqual(sync { model.log.records.map(\.id) }, ["old-1"], "the row is still there and can be deleted again")

        XCTAssertEqual(wait { model.deleteRecord(day: day, id: "old-1", completion: $0) }, .ok)
        XCTAssertEqual(counting.modifyCalls, 1)
        XCTAssertEqual(try FileAppStateStore(fileURL: storeURL).load().log(for: day)?.records.count, 0)
    }

    func testSaveOutcomeDoubleReadFailureKeepsPendingUntilARetryOfTheReadSucceeds() throws {
        let state = try seededState()
        try FileAppStateStore(fileURL: storeURL).commit(state)
        let counting = CountingStore(inner: FileAppStateStore(fileURL: storeURL))
        let store = SaveOutcomeInjectingStore(inner: counting, mode: .readFailure)
        let model = makeModel(store: store, state: state)
        let day = try CalendarDay(iso8601: "2026-09-20")
        sync { model.select(day) }

        let first = wait { model.addRecord(day: day, id: "rec-1", name: "두부", proteinText: "8", completion: $0) }
        guard case .failed(.unconfirmed(let operationID)) = first, operationID != nil else { return XCTFail("\(first)") }
        XCTAssertEqual(counting.modifyCalls, 1, "the write landed before the outcome was lost")
        XCTAssertTrue(sync { model.log.records.isEmpty }, "screen keeps the confirmed state")

        // Writes stay refused and the first re-read fails: pending stays, nothing is re-written.
        XCTAssertEqual(wait { model.addRecord(day: day, id: "rec-1", name: "두부", proteinText: "8", completion: $0) },
                       .failed(.unconfirmed(operationID: operationID)))
        let failedRead = wait { model.reconfirm(completion: $0) }
        guard case .failed(.reconfirmFailed) = failedRead else { return XCTFail("\(failedRead)") }
        XCTAssertNotNil(sync { model.pendingSave })
        XCTAssertEqual(counting.loadCalls, 0, "the double failed before reaching the file")
        XCTAssertEqual(counting.modifyCalls, 1)

        // The next read succeeds: the operation is found exactly once.
        XCTAssertEqual(wait { model.reconfirm(completion: $0) }, .ok)
        XCTAssertNil(sync { model.pendingSave })
        XCTAssertEqual(sync { model.log.records.map(\.id) }, ["rec-1"])
        XCTAssertEqual(counting.modifyCalls, 1, "no second write")
        XCTAssertEqual(try FileAppStateStore(fileURL: storeURL).load().log(for: day)?.records.map(\.id), ["rec-1"])
    }

    // MARK: Goal settings

    private var sept29: CalendarDay { try! CalendarDay(iso8601: "2026-09-29") }
    private var sept30: CalendarDay { try! CalendarDay(iso8601: "2026-09-30") }

    private func reviewState() throws -> AppState {
        let base = try seededState()
        var settings = base.settings
        settings.goalNeedsReview = true
        settings.legacyTargetRaw = "120g"
        return try AppState(logs: base.logs, favorites: base.favorites, searchHistory: base.searchHistory,
                            settings: settings, goals: [], migration: base.migration)
    }

    func testFirstGoalAppliesFromTodayAndEarlierDaysStayWithoutHistory() throws {
        let noGoals = try reviewState()
        var settings = noGoals.settings
        settings.goalNeedsReview = false
        settings.legacyTargetRaw = nil
        let state = try AppState(logs: noGoals.logs, favorites: [], searchHistory: [], settings: settings, goals: [], migration: noGoals.migration)
        let (model, _) = try makeModel(state: state)
        XCTAssertEqual(sync { model.goalState }, .notSet)
        XCTAssertEqual(sync { model.today }, sept29)
        XCTAssertEqual(wait { model.setGoal(day: self.sept29, id: "goal-1", proteinText: "110", completion: $0) }, .ok)
        XCTAssertEqual(sync { model.goalState }, .goal(try ProteinAmount(centigrams: 11_000)))
        XCTAssertEqual(sync { model.goals.map(\.id) }, ["goal-1"])
        sync { model.select(try! CalendarDay(iso8601: "2026-09-28")) }
        XCTAssertEqual(sync { model.goalState }, .noHistory, "no goal is guessed for days before the first one")
        let reloaded = try FileAppStateStore(fileURL: storeURL).load()
        XCTAssertEqual(reloaded.goals.map { "\($0.id)/\($0.effectiveFrom.iso8601)/\($0.amount.centigrams)" }, ["goal-1/2026-09-29/11000"])
    }

    func testSameDaySaveReplacesTheEntryAndNextDayKeepsTheEarlierGoal() throws {
        let (model, _) = try makeModel() // migrated goal 120 from 09-28
        XCTAssertEqual(wait { model.setGoal(day: self.sept29, id: "goal-a", proteinText: "130", completion: $0) }, .ok)
        XCTAssertEqual(wait { model.setGoal(day: self.sept29, id: "goal-b", proteinText: "125", completion: $0) }, .ok)
        XCTAssertEqual(sync { model.goals.map(\.effectiveFrom.iso8601) }, ["2026-09-28", "2026-09-29"], "one entry per day")
        XCTAssertEqual(sync { model.goals.last?.id }, "goal-b")
        XCTAssertEqual(sync { try? model.goal(on: self.sept29) }??.amount.centigrams, 12_500)
        XCTAssertEqual(sync { try? model.goal(on: try! CalendarDay(iso8601: "2026-09-28")) }??.amount.centigrams, 12_000, "yesterday keeps the migrated goal")

        // Next day: a new goal keeps the earlier entries untouched.
        clock = now.addingTimeInterval(86_400)
        XCTAssertEqual(wait { model.setGoal(day: self.sept30, id: "goal-c", proteinText: "140", completion: $0) }, .ok)
        XCTAssertEqual(sync { model.goals.map(\.effectiveFrom.iso8601) }, ["2026-09-28", "2026-09-29", "2026-09-30"])
        XCTAssertEqual(sync { try? model.goal(on: self.sept29) }??.amount.centigrams, 12_500)
        XCTAssertEqual(try FileAppStateStore(fileURL: storeURL).load().goals.count, 3)
    }

    func testSavingClearsTheReviewFlagInTheSameCommitAndKeepsTheRawValue() throws {
        let state = try reviewState()
        let (model, _) = try makeModel(state: state)
        XCTAssertEqual(sync { model.goalState }, .needsReview(raw: "120g"))
        XCTAssertEqual(sync { model.goalReview }, .init(needsReview: true, raw: "120g"))
        XCTAssertEqual(wait { model.setGoal(day: self.sept29, id: "goal-1", proteinText: "100", completion: $0) }, .ok)
        XCTAssertEqual(sync { model.goalReview }, .init(needsReview: false, raw: "120g"), "raw text is preserved, flag cleared")
        let reloaded = try FileAppStateStore(fileURL: storeURL).load()
        XCTAssertFalse(reloaded.settings.goalNeedsReview)
        XCTAssertEqual(reloaded.settings.legacyTargetRaw, "120g")
        XCTAssertEqual(reloaded.goals.map(\.id), ["goal-1"])
        XCTAssertEqual(reloaded.migration, state.migration)
        XCTAssertEqual(reloaded.logs, state.logs)
    }

    func testUnchangedValueIsANoOpUnlessTheReviewFlagMustBeCleared() throws {
        let state = try seededState()
        try FileAppStateStore(fileURL: storeURL).commit(state)
        let store = CountingStore(inner: FileAppStateStore(fileURL: storeURL))
        let model = makeModel(store: store, state: state)
        XCTAssertEqual(wait { model.setGoal(day: self.sept29, id: "goal-1", proteinText: "120", completion: $0) }, .ok)
        XCTAssertEqual(store.modifyCalls, 0, "same value as the goal in effect: nothing written")
        XCTAssertEqual(sync { model.goals.count }, 1)
        XCTAssertEqual(wait { model.setGoal(day: self.sept29, id: "goal-1", proteinText: "120.0", completion: $0) }, .ok)
        XCTAssertEqual(store.modifyCalls, 0, "formatting differences do not matter once parsed")

        // Same value but the review flag is set: one atomic write.
        let review = try reviewState()
        let goals = try [ProteinGoal(id: "legacy:goal:targetProtein", effectiveFrom: CalendarDay(iso8601: "2026-09-28"), amount: ProteinAmount(centigrams: 12_000))]
        let flagged = try AppState(logs: review.logs, favorites: [], searchHistory: [], settings: review.settings, goals: goals, migration: review.migration)
        try FileAppStateStore(fileURL: storeURL).commit(flagged)
        let store2 = CountingStore(inner: FileAppStateStore(fileURL: storeURL))
        let model2 = makeModel(store: store2, state: flagged)
        XCTAssertEqual(wait { model2.setGoal(day: self.sept29, id: "goal-2", proteinText: "120", completion: $0) }, .ok)
        XCTAssertEqual(store2.modifyCalls, 1)
        XCTAssertFalse(sync { model2.goalReview.needsReview })
        XCTAssertEqual(sync { model2.goals.map(\.effectiveFrom.iso8601) }, ["2026-09-28", "2026-09-29"])
    }

    func testStaleDayIsRefusedWithoutAWriteAndSucceedsAfterAnExplicitUpdate() throws {
        let state = try seededState()
        try FileAppStateStore(fileURL: storeURL).commit(state)
        let store = CountingStore(inner: FileAppStateStore(fileURL: storeURL))
        let model = makeModel(store: store, state: state)
        clock = now.addingTimeInterval(86_400) // midnight passed while the sheet was open
        XCTAssertEqual(wait { model.setGoal(day: self.sept29, id: "goal-1", proteinText: "150", completion: $0) },
                       .failed(.goalDateChanged(today: sept30)))
        XCTAssertEqual(store.modifyCalls, 0)
        XCTAssertEqual(sync { model.today }, sept30, "the refusal already refreshed today")
        XCTAssertEqual(sync { model.goals.count }, 1)
        // The user updates the start day explicitly and saves again with the same session ID.
        XCTAssertEqual(wait { model.setGoal(day: self.sept30, id: "goal-1", proteinText: "150", completion: $0) }, .ok)
        XCTAssertEqual(store.modifyCalls, 1)
        XCTAssertEqual(sync { model.goals.map(\.effectiveFrom.iso8601) }, ["2026-09-28", "2026-09-30"])
        // Moving back is refused the same way.
        clock = now
        XCTAssertEqual(wait { model.setGoal(day: self.sept30, id: "goal-2", proteinText: "160", completion: $0) },
                       .failed(.goalDateChanged(today: sept29)))
        XCTAssertEqual(store.modifyCalls, 1)
    }

    func testGoalInputErrorsAndPreReplaceFailureChangeNothing() throws {
        let state = try seededState()
        try FileAppStateStore(fileURL: storeURL).commit(state)
        let store = CountingStore(inner: FileAppStateStore(fileURL: storeURL))
        let model = makeModel(store: store, state: state)
        let cases: [(String, ProteinInputError)] = [("", .empty), ("abc", .notANumber), ("1,5", .groupingSeparatorNotAllowed),
                                                     ("1.234", .tooManyFractionDigits), ("0", .notPositive), ("-5", .notANumber),
                                                     ("99999999999999999999", .overflow)]
        for (text, expected) in cases {
            XCTAssertEqual(wait { model.setGoal(day: self.sept29, id: "goal-1", proteinText: text, completion: $0) }, .failed(.input(expected)), text)
        }
        XCTAssertEqual(store.modifyCalls, 0)

        struct FailingWriter: StoreFileWriter {
            func write(_ data: Data, to url: URL) throws { throw StoreError.writeFailed("disk full") }
        }
        let review = try reviewState()
        let (failing, _) = try makeModel(writer: FailingWriter(), state: review)
        let result = wait { failing.setGoal(day: self.sept29, id: "goal-1", proteinText: "100", completion: $0) }
        guard case .failed(.storage) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(sync { failing.goalReview }, .init(needsReview: true, raw: "120g"), "flag untouched after a pre-replace failure")
        XCTAssertTrue(sync { failing.goals.isEmpty })
        let reloaded = try FileAppStateStore(fileURL: storeURL).load()
        XCTAssertTrue(reloaded.settings.goalNeedsReview)
        XCTAssertTrue(reloaded.goals.isEmpty)
    }

    func testGoalSaveRefusedWhilePendingAndRetriedOnceAfterNotApplied() throws {
        let state = try seededState()
        try FileAppStateStore(fileURL: storeURL).commit(state)
        let counting = CountingStore(inner: FileAppStateStore(fileURL: storeURL))
        let store = SaveOutcomeInjectingStore(inner: counting, mode: .notApplied)
        let model = makeModel(store: store, state: state)
        let first = wait { model.setGoal(day: self.sept29, id: "goal-1", proteinText: "130", completion: $0) }
        guard case .failed(.unconfirmed(let operationID)) = first else { return XCTFail("\(first)") }
        XCTAssertEqual(sync { model.goals.count }, 1, "screen keeps the confirmed history")
        XCTAssertEqual(wait { model.setGoal(day: self.sept29, id: "goal-1", proteinText: "130", completion: $0) },
                       .failed(.unconfirmed(operationID: operationID)))
        XCTAssertEqual(wait { model.addRecord(day: self.sept29, id: "r", name: nil, proteinText: "1", completion: $0) },
                       .failed(.unconfirmed(operationID: operationID)), "every write is blocked while pending")
        XCTAssertEqual(wait { model.reconfirm(completion: $0) }, .failed(.notApplied))
        XCTAssertEqual(counting.modifyCalls, 0)
        XCTAssertEqual(wait { model.setGoal(day: self.sept29, id: "goal-1", proteinText: "130", completion: $0) }, .ok)
        XCTAssertEqual(counting.modifyCalls, 1)
        XCTAssertEqual(try FileAppStateStore(fileURL: storeURL).load().goals.map(\.id), ["legacy:goal:targetProtein", "goal-1"])
    }

    func testGoalReconfirmAfterRealReplaceFailureAppliesTheOriginalDayEvenPastMidnight() throws {
        guard geteuid() != 0 else { throw XCTSkip("root ignores permissions") }
        let (model, _) = try makeModel(hooks: unreadableAfterFirstReplace())
        let first = wait { model.setGoal(day: self.sept29, id: "goal-1", proteinText: "130", completion: $0) }
        guard case .failed(.unconfirmed) = first else { return XCTFail("\(first)") }
        let read = wait { model.reconfirm(completion: $0) }
        guard case .failed(.reconfirmFailed) = read else { return XCTFail("\(read)") }
        XCTAssertNotNil(sync { model.pendingSave })
        clock = now.addingTimeInterval(86_400) // midnight passes while pending
        try restoreStoreAccess()
        XCTAssertEqual(wait { model.reconfirm(completion: $0) }, .ok, "the write that landed is confirmed as is")
        XCTAssertEqual(sync { model.goals.map(\.effectiveFrom.iso8601) }, ["2026-09-28", "2026-09-29"], "the goal kept the day it was validated for")
    }

    func testSaveOutcomeDoubleOnlyAffectsTheFirstWrite() throws {
        let state = try seededState()
        try FileAppStateStore(fileURL: storeURL).commit(state)
        let store = SaveOutcomeInjectingStore(inner: FileAppStateStore(fileURL: storeURL), mode: .notApplied)
        let model = makeModel(store: store, state: state)
        let day = try CalendarDay(iso8601: "2026-09-20")
        sync { model.select(day) }
        guard case .failed(.unconfirmed) = wait({ model.addRecord(day: day, id: "rec-1", name: nil, proteinText: "8", completion: $0) }) else { return XCTFail() }
        XCTAssertEqual(wait { model.reconfirm(completion: $0) }, .failed(.notApplied))
        XCTAssertEqual(wait { model.addRecord(day: day, id: "rec-1", name: nil, proteinText: "8", completion: $0) }, .ok)
        XCTAssertEqual(wait { model.setLegacyTotal(day: day, totalText: "80", completion: $0) }, .ok)
        XCTAssertEqual(sync { model.totalCentigrams }, 8_000)
    }
}

@available(iOS 15.0, *)
final class DayStripLayoutTests: XCTestCase {
    @MainActor
    func testWidthChangesSwitchBetweenScrollingAndSevenColumns() async throws {
        let day = try CalendarDay(iso8601: "2026-10-05")
        let days = try (2...8).map { try CalendarDay(iso8601: "2026-10-0\($0)") }
        func root(width: CGFloat) -> some View {
            DayStrip(days: days, selected: day, today: day, recordedDays: [],
                     onSelect: { _ in }, onShift: { _ in })
                .environment(\.sizeCategory, .large)
                .frame(width: width - 40)
        }
        let host = UIHostingController(rootView: root(width: 320))
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        func scrollViews(_ view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        func settle(width: CGFloat) async throws {
            // Constrain the SwiftUI host content, rather than resizing the
            // simulator's UIWindow (UIKit may restore its screen bounds).
            host.rootView = root(width: width)
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 300_000_000)
            host.view.layoutIfNeeded()
        }
        try await settle(width: 320)
        let narrowScroll = try XCTUnwrap(scrollViews(host.view).first)
        XCTAssertGreaterThan(narrowScroll.contentSize.width, narrowScroll.bounds.width)
        XCTAssertLessThanOrEqual(narrowScroll.bounds.width, 280.5)
        try await settle(width: 375)
        let remaining = scrollViews(host.view).map { "bounds=\($0.bounds), content=\($0.contentSize)" }
        XCTAssertTrue(remaining.isEmpty, "375 pt should show seven columns without scrolling: \(remaining)")
        try await settle(width: 320)
        XCTAssertFalse(scrollViews(host.view).isEmpty, "Resizing must restore scrolling")
    }
}
