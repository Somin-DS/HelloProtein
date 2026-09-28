import XCTest
import HelloProteinCore

@available(iOS 15.0, *)
final class RecordHomeViewModelTests: XCTestCase {
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

    private func makeModel(writer: StoreFileWriter = DefaultStoreFileWriter()) throws -> (RecordHomeViewModel, FileAppStateStore) {
        let state = try seededState()
        try FileAppStateStore(fileURL: storeURL).commit(state)
        let store = FileAppStateStore(fileURL: storeURL, writer: writer)
        let model = RecordHomeViewModel(store: store, state: state, now: { self.now }, timeZone: seoul,
                                        decimalSeparator: ".", workQueue: queue, mainQueue: queue)
        return (model, store)
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
}
