import Foundation
import Combine
import HelloProteinCore

/// Screen state for the day-based record home. The store is the single write
/// owner; this model only mirrors the last committed `AppState`.
///
/// Every change builds a candidate, asks the store to commit it, and applies
/// the committed state to the screen only after success. Failures keep the
/// previous screen data and report a typed error.
@available(iOS 15.0, *)
final class RecordHomeViewModel: ObservableObject {
    enum GoalState: Equatable {
        case goal(ProteinAmount)
        case noHistory
        case notSet
        case needsReview(raw: String?)
        case integrityError(String)
    }

    enum ActionError: Error, Equatable {
        case input(ProteinInputError)
        /// Failed before the file was replaced. Input is kept; the same save can be retried.
        case storage(String)
        case integrity(String)
        case notFound
        case busy
        /// The file was replaced but the result could not be read back. No
        /// other write is accepted until `reconfirm` succeeds. The ID names the
        /// operation whose outcome is pending; nil when the store was left
        /// unconfirmed by a commit that carried no ID (migration).
        case unconfirmed(operationID: String?)
        /// `reconfirm` read the store and the pending operation is not in it.
        /// Input is kept; the same save can be retried.
        case notApplied
        /// `reconfirm` could not read the store. Nothing is known yet: the
        /// pending state stays and the read can be tried again. Distinct from
        /// `.storage`, which promises that nothing was changed.
        case reconfirmFailed(String)
        /// The goal sheet's start day is no longer today. Nothing was written;
        /// the input is kept and the user updates the start day explicitly.
        case goalDateChanged(today: CalendarDay)
    }

    /// A save whose commit outcome is unknown. Cleared only by a successful reload.
    struct PendingSave: Equatable {
        let operationID: String?
        let day: CalendarDay
    }

    @Published private(set) var selectedDay: CalendarDay
    @Published private(set) var log: DailyLog
    /// nil means the stored log could not be summed; the screen must say so.
    @Published private(set) var totalCentigrams: Int64?
    @Published private(set) var goalState: GoalState = .notSet
    @Published private(set) var isBusy = false
    @Published private(set) var today: CalendarDay
    @Published private(set) var pendingSave: PendingSave?
    /// Mirrors of the last confirmed state for the goal sheet.
    @Published private(set) var goals: [ProteinGoal] = []
    @Published private(set) var goalReview = GoalReview(needsReview: false, raw: nil)

    struct GoalReview: Equatable {
        let needsReview: Bool
        let raw: String?
    }

    let timeZone: TimeZone
    let decimalSeparator: String

    private(set) var state: AppState
    private let store: AppStateStore
    private let now: () -> Date
    private let workQueue: DispatchQueue
    private let mainQueue: DispatchQueue

    init(
        store: AppStateStore,
        state: AppState,
        now: @escaping () -> Date = Date.init,
        timeZone: TimeZone = .autoupdatingCurrent,
        decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
        workQueue: DispatchQueue = DispatchQueue(label: "com.devsom.ProteinTracker.record-home"),
        mainQueue: DispatchQueue = .main
    ) {
        self.store = store
        self.state = state
        self.now = now
        self.timeZone = timeZone
        self.decimalSeparator = decimalSeparator
        self.workQueue = workQueue
        self.mainQueue = mainQueue
        let today = CalendarDay.today(now: now(), timeZone: timeZone) ?? (try! CalendarDay(iso8601: "2000-01-01"))
        self.today = today
        self.selectedDay = today
        self.log = try! DailyLog(day: today)
        // A store that is already blocked (an earlier commit in this process
        // ended unconfirmed) shows the pending state from the first frame, so
        // the reconfirm action is reachable instead of every save failing.
        if store.hasUnconfirmedCommit {
            self.pendingSave = PendingSave(operationID: store.unconfirmedOperationID, day: today)
        }
        refresh()
    }

    // MARK: Navigation

    var visibleDays: [CalendarDay] {
        (-3...3).compactMap { selectedDay.adding(days: $0) }
    }

    func select(_ day: CalendarDay) {
        selectedDay = day
        refresh()
    }

    func select(date: Date) {
        if let day = CalendarDay.today(now: date, timeZone: timeZone) { select(day) }
    }

    func selectToday() {
        refreshToday()
        select(today)
    }

    /// Recomputes "today" from the injected clock; the selection is untouched.
    func refreshToday() {
        if let day = CalendarDay.today(now: now(), timeZone: timeZone) { today = day }
    }

    func shift(days: Int) {
        if let day = selectedDay.adding(days: days) { select(day) }
    }

    // MARK: Changes

    /// `id` is the record ID; the editor keeps one ID for its whole session so
    /// a retry after a failed save never produces a second record.
    func addRecord(day: CalendarDay, id: String = UUID().uuidString, name: String?, proteinText: String,
                   completion: @escaping (Result<Void, ActionError>) -> Void) {
        let protein: ProteinAmount
        do { protein = try ProteinInput.parse(proteinText, decimalSeparator: decimalSeparator) }
        catch let error as ProteinInputError { return completion(.failure(.input(error))) }
        catch { return completion(.failure(.integrity(String(describing: error)))) }
        perform(day: day, completion: completion) { state in
            var log = try state.log(for: day) ?? DailyLog(day: day)
            try log.add(FoodRecord(id: id, day: day, name: name, quantity: nil, protein: protein, source: .manual))
            try state.upsert(log)
        }
    }

    /// Keeps ID, day, quantity, source and legacy identity; changes only the
    /// fields the user edited.
    func updateRecord(day: CalendarDay, id: String, name: String?, proteinText: String,
                      completion: @escaping (Result<Void, ActionError>) -> Void) {
        let protein: ProteinAmount
        do { protein = try ProteinInput.parse(proteinText, decimalSeparator: decimalSeparator) }
        catch let error as ProteinInputError { return completion(.failure(.input(error))) }
        catch { return completion(.failure(.integrity(String(describing: error)))) }
        perform(day: day, completion: completion) { state in
            guard var log = state.log(for: day), let existing = log.record(id: id) else {
                throw ActionError.notFound
            }
            try log.update(existing.withChanges(name: .some(name), protein: protein))
            try state.upsert(log)
        }
    }

    func deleteRecord(day: CalendarDay, id: String, completion: @escaping (Result<Void, ActionError>) -> Void) {
        perform(day: day, completion: completion) { state in
            guard var log = state.log(for: day), log.record(id: id) != nil else { throw ActionError.notFound }
            try log.delete(id: id)
            try state.upsert(log)
        }
    }

    /// Replaces a legacy day's total; the adjustment becomes total − details.
    func setLegacyTotal(day: CalendarDay, totalText: String,
                        completion: @escaping (Result<Void, ActionError>) -> Void) {
        let totalCentigrams: Int64
        do { totalCentigrams = try ProteinInput.parseSignedTotal(totalText, decimalSeparator: decimalSeparator) }
        catch let error as ProteinInputError { return completion(.failure(.input(error))) }
        catch { return completion(.failure(.integrity(String(describing: error)))) }
        perform(day: day, completion: completion) { state in
            guard var log = state.log(for: day), log.hasLegacyTotal else { throw ActionError.notFound }
            try log.setLegacyDailyTotal(totalCentigrams)
            try state.upsert(log)
        }
    }

    // MARK: Goal

    /// The goal in effect on `day` from the last confirmed state, or nil when
    /// the history does not cover it. Throws on a history integrity failure.
    func goal(on day: CalendarDay) throws -> ProteinGoal? {
        try state.goal(on: day)
    }

    /// Sets the goal that applies from `day`, which must still be today at the
    /// moment of the call: the clock is re-read first and a stale day is
    /// refused without a write. `id` is fixed for the editing session. The
    /// review flag left by the migration is cleared in the same commit. A
    /// value equal to the goal already in effect, with no flag to clear, is a
    /// confirmed no-op and never creates a history entry.
    func setGoal(day: CalendarDay, id: String = UUID().uuidString, proteinText: String,
                 completion: @escaping (Result<Void, ActionError>) -> Void) {
        if let pending = pendingSave { return completion(.failure(.unconfirmed(operationID: pending.operationID))) }
        guard !isBusy else { return completion(.failure(.busy)) }
        refreshToday()
        guard day == today else { return completion(.failure(.goalDateChanged(today: today))) }
        let amount: ProteinAmount
        do { amount = try ProteinInput.parse(proteinText, decimalSeparator: decimalSeparator) }
        catch let error as ProteinInputError { return completion(.failure(.input(error))) }
        catch { return completion(.failure(.integrity(String(describing: error)))) }
        if !state.settings.goalNeedsReview, let current = try? state.goal(on: day), current.amount == amount {
            return completion(.success(()))
        }
        perform(day: day, completion: completion) { state in
            try state.replaceGoal(on: day, with: ProteinGoal(id: id, effectiveFrom: day, amount: amount))
            state.settings.goalNeedsReview = false
        }
    }

    // MARK: Unconfirmed saves

    /// Re-reads the store after an indeterminate commit. Success means the
    /// pending operation is in the file (the save converged); `.notApplied`
    /// means it is not and the same save may be retried; a storage error
    /// leaves the pending state in place for the user to try again later.
    /// Nothing is ever written here.
    func reconfirm(completion: @escaping (Result<Void, ActionError>) -> Void) {
        guard let pending = pendingSave else { return completion(.success(())) }
        guard !isBusy else { return completion(.failure(.busy)) }
        isBusy = true
        let store = self.store
        workQueue.async {
            let result: Result<AppState, ActionError>
            // A failed read is reported as exactly that: the outcome is still
            // unknown, so the pending state stays and nothing is promised.
            do { result = .success(try store.load()) }
            catch { result = .failure(.reconfirmFailed(String(describing: error))) }
            self.mainQueue.async {
                self.isBusy = false
                switch result {
                case .success(let state):
                    self.state = state
                    self.pendingSave = nil
                    self.refresh()
                    // A pending save without an ID has nothing to look for: the
                    // successful read alone re-establishes the state.
                    let applied = pending.operationID == nil || state.lastOperationID == pending.operationID
                    completion(applied ? .success(()) : .failure(.notApplied))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: Internals

    private func perform(day: CalendarDay, completion: @escaping (Result<Void, ActionError>) -> Void,
                         _ change: @escaping (inout AppState) throws -> Void) {
        if let pending = pendingSave { return completion(.failure(.unconfirmed(operationID: pending.operationID))) }
        guard !isBusy else { return completion(.failure(.busy)) }
        isBusy = true
        let store = self.store
        let operationID = UUID().uuidString
        workQueue.async {
            let result: Result<AppState, ActionError>
            do {
                result = .success(try store.modify(operationID: operationID, change))
            } catch let error as ActionError {
                result = .failure(error)
            } catch StoreCommitError.indeterminate(.previousCommitUnconfirmed(let earlier)) {
                // The store is still blocked by an earlier commit; that is the
                // operation whose outcome must be checked, not this one.
                result = .failure(.unconfirmed(operationID: earlier))
            } catch StoreCommitError.indeterminate {
                result = .failure(.unconfirmed(operationID: operationID))
            } catch let error as StoreCommitError {
                result = .failure(.storage(String(describing: error.underlying)))
            } catch let error as StoreError {
                result = .failure(.storage(String(describing: error)))
            } catch let error as ProteinInputError {
                result = .failure(.input(error))
            } catch {
                result = .failure(.integrity(String(describing: error)))
            }
            self.mainQueue.async {
                self.isBusy = false
                switch result {
                case .success(let state):
                    self.state = state
                    self.refresh()
                    completion(.success(()))
                case .failure(.unconfirmed(let pendingID)):
                    // The file may hold the change already; the screen keeps
                    // showing the last confirmed state until a reload says so.
                    self.pendingSave = PendingSave(operationID: pendingID, day: day)
                    completion(.failure(.unconfirmed(operationID: pendingID)))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    private func refresh() {
        log = state.log(for: selectedDay) ?? ((try? DailyLog(day: selectedDay)) ?? log)
        totalCentigrams = try? log.totalProteinCentigrams()
        goalState = Self.goalState(for: selectedDay, in: state)
        goals = state.goals
        goalReview = GoalReview(needsReview: state.settings.goalNeedsReview, raw: state.settings.legacyTargetRaw)
    }

    static func goalState(for day: CalendarDay, in state: AppState) -> GoalState {
        if state.goals.isEmpty {
            return state.settings.goalNeedsReview ? .needsReview(raw: state.settings.legacyTargetRaw) : .notSet
        }
        do {
            if let goal = try state.goal(on: day) { return .goal(goal.amount) }
            return .noHistory
        } catch {
            // A goal-history integrity failure is shown as an error, never as "no history".
            return .integrityError(String(describing: error))
        }
    }
}
