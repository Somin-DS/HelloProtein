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
        /// A selected favorite was edited or removed since it was picked, or
        /// its stored amount cannot be a record. Nothing was written; the
        /// user re-checks the selection.
        case selectionChanged
    }

    /// What a write was for. The sheet that issued it decides what a
    /// confirmed outcome means (close, leave edit mode, stay); the model only
    /// carries the context. Runtime only, never persisted.
    enum OperationKind: Equatable {
        case record
        case favoriteBatch
        case favoriteEdit
        case favoriteDelete
        /// N records from search results.
        case searchBatch
        /// An executed search term recorded in the recent-searches list.
        case searchHistory
        case searchHistoryDelete
        case searchLanguage
        case goal
        case legacyTotal
        /// Left blocked by a commit from before this screen existed.
        case unknown
    }

    /// A save whose commit outcome is unknown. Cleared only by a successful reload.
    struct PendingSave: Equatable {
        let operationID: String?
        let day: CalendarDay
        var kind: OperationKind = .unknown
    }

    /// Whether the optional "also save as favorite" part of a record save
    /// created an entry, reused an identical one, or was not asked for.
    enum FavoriteOutcome: Equatable {
        case notRequested
        case created
        case alreadyExisted
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
    /// Favorites in display (position) order, from the last confirmed state.
    @Published private(set) var favorites: [FavoriteFood] = []
    /// Recent searches in display (position) order, from the last confirmed state.
    @Published private(set) var searchHistory: [SearchTerm] = []
    /// The confirmed food-search language setting (raw value kept as stored).
    @Published private(set) var searchLanguage: SearchLanguageSetting = .interpret(raw: nil)

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
            self.pendingSave = PendingSave(operationID: store.unconfirmedOperationID, day: today, kind: .unknown)
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
        addRecord(day: day, id: id, name: name, proteinText: proteinText, favoriteID: nil) { completion($0.map { _ in () }) }
    }

    /// Adds the record and, when `favoriteID` is given, a favorite with the
    /// same name and amount in the same commit: both land or neither does.
    /// An identical favorite (trimmed name and amount) is reused instead of
    /// duplicated and reported as `.alreadyExisted`; the record is still saved.
    func addRecord(day: CalendarDay, id: String = UUID().uuidString, name: String?, proteinText: String,
                   favoriteID: String?, completion: @escaping (Result<FavoriteOutcome, ActionError>) -> Void) {
        let protein: ProteinAmount
        do { protein = try ProteinInput.parse(proteinText, decimalSeparator: decimalSeparator) }
        catch let error as ProteinInputError { return completion(.failure(.input(error))) }
        catch { return completion(.failure(.integrity(String(describing: error)))) }
        var outcome = FavoriteOutcome.notRequested
        perform(day: day, kind: .record, completion: { completion($0.map { outcome }) }) { state in
            var log = try state.log(for: day) ?? DailyLog(day: day)
            try log.add(FoodRecord(id: id, day: day, name: name, quantity: nil, protein: protein, source: .manual))
            try state.upsert(log)
            outcome = try Self.saveFavorite(id: favoriteID, name: name, protein: protein, in: &state)
        }
    }

    /// Keeps ID, day, quantity, source and legacy identity; changes only the
    /// fields the user edited.
    func updateRecord(day: CalendarDay, id: String, name: String?, proteinText: String,
                      completion: @escaping (Result<Void, ActionError>) -> Void) {
        updateRecord(day: day, id: id, name: name, proteinText: proteinText, favoriteID: nil) { completion($0.map { _ in () }) }
    }

    /// Same as `addRecord(favoriteID:)` for an existing record: the edit and
    /// the optional favorite share one commit.
    func updateRecord(day: CalendarDay, id: String, name: String?, proteinText: String,
                      favoriteID: String?, completion: @escaping (Result<FavoriteOutcome, ActionError>) -> Void) {
        let protein: ProteinAmount
        do { protein = try ProteinInput.parse(proteinText, decimalSeparator: decimalSeparator) }
        catch let error as ProteinInputError { return completion(.failure(.input(error))) }
        catch { return completion(.failure(.integrity(String(describing: error)))) }
        var outcome = FavoriteOutcome.notRequested
        perform(day: day, kind: .record, completion: { completion($0.map { outcome }) }) { state in
            guard var log = state.log(for: day), let existing = log.record(id: id) else {
                throw ActionError.notFound
            }
            try log.update(existing.withChanges(name: .some(name), protein: protein))
            try state.upsert(log)
            outcome = try Self.saveFavorite(id: favoriteID, name: name, protein: protein, in: &state)
        }
    }

    /// The favorite half of a record save. The name is stored trimmed (empty
    /// when the record has none); an exact duplicate is reused, never merged.
    private static func saveFavorite(id: String?, name: String?, protein: ProteinAmount,
                                     in state: inout AppState) throws -> FavoriteOutcome {
        guard let id else { return .notRequested }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if FavoriteCollection.existing(name: trimmed, proteinCentigrams: protein.centigrams, in: state.favorites) != nil {
            return .alreadyExisted
        }
        try state.setFavorites(FavoriteCollection.appending(id: id, name: trimmed, proteinCentigrams: protein.centigrams,
                                                            to: state.favorites))
        return .created
    }

    func deleteRecord(day: CalendarDay, id: String, completion: @escaping (Result<Void, ActionError>) -> Void) {
        perform(day: day, kind: .record, completion: completion) { state in
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
        perform(day: day, kind: .legacyTotal, completion: completion) { state in
            guard var log = state.log(for: day), log.hasLegacyTotal else { throw ActionError.notFound }
            try log.setLegacyDailyTotal(totalCentigrams)
            try state.upsert(log)
        }
    }

    // MARK: Favorites

    /// Adds one record per selected favorite to `day` in a single commit.
    /// Every selection is re-checked against the latest favorites inside the
    /// commit; any mismatch, invalid amount or overflow writes nothing. The
    /// record IDs come from the selections, so a retry never adds twice.
    func addFavoriteRecords(day: CalendarDay, selections: [FavoriteSelection],
                            completion: @escaping (Result<Void, ActionError>) -> Void) {
        perform(day: day, kind: .favoriteBatch, completion: completion) { state in
            let records = try FavoriteBatch.records(for: selections, on: day, favorites: state.favorites)
            var log = try state.log(for: day) ?? DailyLog(day: day)
            for record in records { try log.add(record) }
            try state.upsert(log)
        }
    }

    /// Changes the name and amount of one favorite; ID, position and legacy
    /// identity stay. The amount must parse as a positive entry. Daily logs
    /// are not touched.
    func updateFavorite(id: String, name: String, proteinText: String,
                        completion: @escaping (Result<Void, ActionError>) -> Void) {
        let protein: ProteinAmount
        do { protein = try ProteinInput.parse(proteinText, decimalSeparator: decimalSeparator) }
        catch let error as ProteinInputError { return completion(.failure(.input(error))) }
        catch { return completion(.failure(.integrity(String(describing: error)))) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        perform(day: selectedDay, kind: .favoriteEdit, completion: completion) { state in
            do {
                try state.setFavorites(FavoriteCollection.replacing(id: id, name: trimmed, proteinCentigrams: protein.centigrams,
                                                                    in: state.favorites))
            } catch FavoriteCollectionError.notFound { throw ActionError.notFound }
        }
    }

    /// Removes exactly that favorite. Records logged from it stay.
    func deleteFavorite(id: String, completion: @escaping (Result<Void, ActionError>) -> Void) {
        perform(day: selectedDay, kind: .favoriteDelete, completion: completion) { state in
            do { try state.setFavorites(FavoriteCollection.removing(id: id, from: state.favorites)) }
            catch FavoriteCollectionError.notFound { throw ActionError.notFound }
        }
    }

    // MARK: Search

    /// Adds one record per selected search result to `day` in a single
    /// commit, with the verified reference quantity each result showed. The
    /// snapshot the user confirmed is written as is; no provider is consulted
    /// again. Record IDs come from the selections, so a retry never adds twice.
    func addSearchRecords(day: CalendarDay, selections: [SearchSelection],
                          completion: @escaping (Result<Void, ActionError>) -> Void) {
        perform(day: day, kind: .searchBatch, completion: completion) { state in
            let records = try SearchRecordBatch.records(for: selections, on: day)
            var log = try state.log(for: day) ?? DailyLog(day: day)
            for record in records { try log.add(record) }
            try state.upsert(log)
        }
    }

    /// Records an explicitly executed search in the recent-searches list: an
    /// exact (trimmed) match moves to the front keeping its identity, otherwise
    /// a new entry with `newID` is inserted. `newID` is fixed by the caller for
    /// the attempt and its retries. A blank query is refused without a write.
    func recordSearchTerm(query: String, newID: String, completion: @escaping (Result<Void, ActionError>) -> Void) {
        guard SearchHistoryCollection.normalizedQuery(query) != nil else { return completion(.failure(.input(.empty))) }
        perform(day: selectedDay, kind: .searchHistory, completion: completion) { state in
            do { try state.setSearchHistory(SearchHistoryCollection.recording(query: query, newID: newID, in: state.searchHistory)) }
            catch SearchHistoryError.blankQuery { throw ActionError.input(.empty) }
            catch let error as SearchHistoryError { throw ActionError.integrity(String(describing: error)) }
        }
    }

    /// Removes exactly that recent search. Nothing else changes.
    func deleteSearchTerm(id: String, completion: @escaping (Result<Void, ActionError>) -> Void) {
        perform(day: selectedDay, kind: .searchHistoryDelete, completion: completion) { state in
            do { try state.setSearchHistory(SearchHistoryCollection.removing(id: id, from: state.searchHistory)) }
            catch SearchHistoryError.notFound { throw ActionError.notFound }
        }
    }

    /// Stores the food-search language as the raw value `interpret` reads
    /// back. Selecting the language that is already confirmed is a no-op
    /// without a write; a fallback setting (unknown raw value) is replaced
    /// only by this explicit choice, never corrected by a read.
    func setSearchLanguage(_ language: SearchLanguage, completion: @escaping (Result<Void, ActionError>) -> Void) {
        if let pending = pendingSave { return completion(.failure(.unconfirmed(operationID: pending.operationID))) }
        guard !isBusy else { return completion(.failure(.busy)) }
        let current = state.settings.searchLanguage
        if !current.isFallback, current.resolved == language { return completion(.success(())) }
        perform(day: selectedDay, kind: .searchLanguage, completion: completion) { state in
            state.settings.searchLanguage = .confirmed(language)
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
        perform(day: day, kind: .goal, completion: completion) { state in
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

    private func perform(day: CalendarDay, kind: OperationKind, completion: @escaping (Result<Void, ActionError>) -> Void,
                         _ change: @escaping (inout AppState) throws -> Void) {
        if let pending = pendingSave { return completion(.failure(.unconfirmed(operationID: pending.operationID))) }
        guard !isBusy else { return completion(.failure(.busy)) }
        isBusy = true
        let store = self.store
        let operationID = UUID().uuidString
        workQueue.async {
            let result: Result<AppState, ActionError>
            var reloadedState: AppState?
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
            } catch let error as SearchBatchError {
                result = .failure(Self.actionError(for: error))
            } catch let error as FavoriteBatchError {
                let actionError = Self.actionError(for: error)
                if actionError == .selectionChanged {
                    // The failed transaction wrote nothing. Refresh before the
                    // sheet prunes snapshots, so re-selection uses current values.
                    do {
                        reloadedState = try store.load()
                        result = .failure(actionError)
                    } catch {
                        result = .failure(.storage(String(describing: error)))
                    }
                } else {
                    result = .failure(actionError)
                }
            } catch {
                result = .failure(.integrity(String(describing: error)))
            }
            let confirmedState = reloadedState
            self.mainQueue.async {
                if let confirmedState = confirmedState {
                    self.state = confirmedState
                    self.refresh()
                }
                self.isBusy = false
                switch result {
                case .success(let state):
                    self.state = state
                    self.refresh()
                    completion(.success(()))
                case .failure(.unconfirmed(let pendingID)):
                    // The file may hold the change already; the screen keeps
                    // showing the last confirmed state until a reload says so.
                    self.pendingSave = PendingSave(operationID: pendingID, day: day, kind: kind)
                    completion(.failure(.unconfirmed(operationID: pendingID)))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    /// A stale or unusable selection is the user's to fix; the rest are
    /// programming errors and surface as integrity failures.
    private static func actionError(for error: FavoriteBatchError) -> ActionError {
        switch error {
        case .selectionChanged, .invalidAmount: return .selectionChanged
        case .arithmeticOverflow: return .input(.overflow)
        case .emptySelection, .duplicateSelection, .duplicateRecordID: return .integrity(String(describing: error))
        }
    }

    /// A search selection that can no longer be logged is the user's to
    /// re-check; the rest are programming errors.
    private static func actionError(for error: SearchBatchError) -> ActionError {
        switch error {
        case .invalidAmount: return .selectionChanged
        case .arithmeticOverflow: return .input(.overflow)
        case .emptySelection, .duplicateSelection, .duplicateRecordID: return .integrity(String(describing: error))
        }
    }

    private func refresh() {
        log = state.log(for: selectedDay) ?? ((try? DailyLog(day: selectedDay)) ?? log)
        totalCentigrams = try? log.totalProteinCentigrams()
        goalState = Self.goalState(for: selectedDay, in: state)
        goals = state.goals
        goalReview = GoalReview(needsReview: state.settings.goalNeedsReview, raw: state.settings.legacyTargetRaw)
        favorites = FavoriteCollection.ordered(state.favorites)
        searchHistory = SearchHistoryCollection.ordered(state.searchHistory)
        searchLanguage = state.settings.searchLanguage
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
