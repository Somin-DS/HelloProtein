import Foundation
import Combine
import HelloProteinCore

/// State of one search tab visit: the draft the user is typing, the query
/// whose results are shown, the results and the selection with its fixed
/// record IDs. Lookups go to the injected provider; every write (history,
/// language, records) stays with `RecordHomeViewModel`, which the sheet
/// calls. Callbacks are checked against a generation counter so a cancelled,
/// late or reordered answer never touches the screen.
@available(iOS 15.0, *)
final class SearchSessionModel: ObservableObject {
    enum Status: Equatable {
        /// No query executed: the recent searches are shown.
        case idle
        case searching
        case results
        case empty
        case failed(SearchProviderError)
        /// The provider for this language cannot be used (no key, no service).
        case unavailable
    }

    @Published var queryDraft = ""
    /// The query the current results belong to; editing the draft does not change it.
    @Published private(set) var executedQuery: String?
    /// The confirmed language the results were fetched in.
    @Published private(set) var language: SearchLanguage
    @Published private(set) var status: Status = .idle
    @Published private(set) var results: [SearchResultItem] = []
    /// Selected result IDs in selection order.
    @Published private(set) var selected: [String] = []
    @Published private(set) var nextPage: SearchPageRequest?
    @Published private(set) var isLoadingMore = false
    /// Set when a further page failed; the first page and the selection stay.
    @Published private(set) var pageError: SearchProviderError?
    /// IDs whose content changed between pages and were dropped from the selection.
    @Published private(set) var droppedSelectionIDs: [String] = []
    /// Amounts applied per selected result (by result ID). Absent means the
    /// row's reference amount. Dropped with the row's selection, with a new
    /// generation and with the whole selection; never written anywhere.
    @Published private(set) var amountDrafts: [String: FoodQuantity] = [:]

    private var snapshots: [String: SearchResultItem] = [:]
    /// Record IDs per result for the current generation; a re-selection
    /// reuses the ID, a new search gets new ones.
    private var recordIDs: [String: String] = [:]
    private var provider: FoodSearchProvider
    private let makeProvider: (SearchLanguage) -> FoodSearchProvider
    private let mainQueue: DispatchQueue
    private let makeID: () -> String
    private var generation = 0
    private var requestHandle: SearchRequestHandle?
    private var pageHandle: SearchRequestHandle?

    init(language: SearchLanguage,
         makeProvider: @escaping (SearchLanguage) -> FoodSearchProvider,
         mainQueue: DispatchQueue = .main,
         makeID: @escaping () -> String = { UUID().uuidString }) {
        self.language = language
        self.makeProvider = makeProvider
        self.provider = makeProvider(language)
        self.mainQueue = mainQueue
        self.makeID = makeID
    }

    // MARK: Derived

    var hasSelection: Bool { !selected.isEmpty }
    var isSearching: Bool { status == .searching }
    /// One selection per selected row in selection order. A row with a basis
    /// carries it and the applied (or reference) amount with the protein
    /// computed from the basis; a row without one is the verified snapshot
    /// as shown, the old way.
    var selections: [SearchSelection] {
        selected.compactMap { id in
            guard let item = snapshots[id], let centigrams = item.proteinCentigrams, let reference = item.reference,
                  let recordID = recordIDs[id] else { return nil }
            if let basis = item.calculationBasis {
                let quantity = amountDrafts[id] ?? basis.referenceQuantity
                guard let computed = try? basis.protein(for: quantity) else { return nil }
                return SearchSelection(itemKey: id, recordID: recordID, name: item.name,
                                       proteinCentigrams: computed.centigrams, quantity: quantity, basis: basis)
            }
            return SearchSelection(itemKey: id, recordID: recordID, name: item.name,
                                   proteinCentigrams: centigrams, quantity: reference.quantity)
        }
    }
    /// The amount applied to a selected row and the protein it yields, or nil
    /// when the row is at its reference amount (or has no basis).
    func appliedAmount(for item: SearchResultItem) -> (quantity: FoodQuantity, centigrams: Int64)? {
        guard let quantity = amountDrafts[item.id], let basis = snapshots[item.id]?.calculationBasis,
              let computed = try? basis.protein(for: quantity) else { return nil }
        return (quantity, computed.centigrams)
    }
    /// nil when the checked sum overflows.
    var totalCentigrams: Int64? { try? SearchRecordBatch.totalCentigrams(selections) }

    // MARK: Explicit search

    /// Trimmed query or nil when blank: a blank query is never searched or recorded.
    static func normalized(_ query: String) -> String? { SearchHistoryCollection.normalizedQuery(query) }

    /// Starts a new search generation for `query`. The previous request is
    /// cancelled, results and selection are cleared, the draft is left alone.
    /// `recordHistory` is the caller's write of the term (through the view
    /// model); it calls `proceed` when the history outcome has been handled,
    /// and only then is the provider asked, if this generation is still live.
    func execute(query: String, recordHistory: (String, _ proceed: @escaping () -> Void) -> Void) {
        guard let trimmed = Self.normalized(query) else { return }
        beginGeneration()
        executedQuery = trimmed
        status = .searching
        let current = generation
        recordHistory(trimmed) { [weak self] in
            guard let self else { return }
            self.mainQueue.async {
                guard self.generation == current, self.status == .searching, self.executedQuery == trimmed else { return }
                self.request(query: trimmed, generation: current)
            }
        }
    }

    /// Repeats only the lookup for the executed query: no history write.
    func retry() {
        guard let query = executedQuery, case .failed = status else { return }
        beginGeneration()
        executedQuery = query
        status = .searching
        request(query: query, generation: generation)
    }

    private func beginGeneration() {
        generation += 1
        requestHandle?.cancel()
        requestHandle = nil
        pageHandle?.cancel()
        pageHandle = nil
        isLoadingMore = false
        pageError = nil
        results = []
        selected = []
        snapshots = [:]
        recordIDs = [:]
        nextPage = nil
        droppedSelectionIDs = []
        amountDrafts = [:]
    }

    private func request(query: String, generation current: Int) {
        requestHandle = provider.search(query: query, page: nil) { [weak self] result in
            self?.mainQueue.async {
                guard let self, self.generation == current else { return }
                self.requestHandle = nil
                switch result {
                case .success(let page):
                    self.results = page.items
                    self.nextPage = page.nextPage
                    self.status = page.items.isEmpty ? .empty : .results
                case .failure(.notConfigured):
                    self.status = .unavailable
                case .failure(let error):
                    // Includes a cancellation of the current request by the
                    // provider: loading ends and the user can retry. Our own
                    // cancellations belong to an older generation and never
                    // reach this point.
                    self.status = .failed(error)
                }
            }
        }
    }

    // MARK: Pages

    /// Fetches the next page of the current generation. Never two at once;
    /// a failure keeps everything shown and can be retried.
    func loadMore() {
        guard let page = nextPage, !isLoadingMore, status == .results else { return }
        let current = generation
        isLoadingMore = true
        pageError = nil
        pageHandle = provider.search(query: executedQuery ?? "", page: page) { [weak self] result in
            self?.mainQueue.async {
                guard let self, self.generation == current else { return }
                self.isLoadingMore = false
                self.pageHandle = nil
                switch result {
                case .success(let next): self.append(next)
                case .failure(.cancelled): break
                case .failure(let error): self.pageError = error
                }
            }
        }
    }

    /// Rows already shown are not repeated. A row whose content differs from
    /// the one shown under the same ID is not swapped in silently: the shown
    /// row is updated only after its selection is cleared and reported.
    private func append(_ page: SearchResultPage) {
        var seen = Set(results.map(\.id))
        var dropped: [String] = []
        for item in page.items {
            if seen.contains(item.id) {
                if let index = results.firstIndex(where: { $0.id == item.id }), results[index] != item {
                    if selected.contains(item.id) {
                        selected.removeAll { $0 == item.id }
                        snapshots[item.id] = nil
                        amountDrafts[item.id] = nil
                        dropped.append(item.id)
                    }
                    // Show the new value only after discarding its old selection.
                    results[index] = item
                }
                continue
            }
            seen.insert(item.id)
            results.append(item)
        }
        droppedSelectionIDs = dropped
        nextPage = page.nextPage
    }

    // MARK: Selection

    func isSelected(_ item: SearchResultItem) -> Bool { selected.contains(item.id) }

    func toggle(_ item: SearchResultItem) {
        guard item.isSelectable else { return }
        if let index = selected.firstIndex(of: item.id) {
            // Deselecting forgets the applied amount; a re-selection starts
            // from the reference amount with the same record ID.
            selected.remove(at: index)
            snapshots[item.id] = nil
            amountDrafts[item.id] = nil
        } else {
            if recordIDs[item.id] == nil { recordIDs[item.id] = makeID() }
            snapshots[item.id] = item
            selected.append(item.id)
        }
    }

    func clearSelection() {
        selected = []
        snapshots = [:]
        amountDrafts = [:]
    }

    // MARK: Amount editing

    /// What the amount editor was opened with: the exact row snapshot, its
    /// basis, the session's record ID and the amount to start from. Apply is
    /// checked against all of it, so a changed row never receives an old amount.
    struct AmountEditTarget: Equatable, Identifiable {
        let item: SearchResultItem
        let basis: CalculationBasis
        let recordID: String
        /// The applied amount, or the reference amount when none was applied.
        let current: FoodQuantity
        let generation: Int
        var id: String { item.id }
    }

    enum AmountApplyOutcome: Equatable {
        case applied
        /// The row is no longer selected, or its snapshot or the search
        /// generation changed meanwhile. Nothing was changed; re-select.
        case selectionChanged
    }

    /// nil when the row is not selected as this very snapshot or has no basis.
    func amountEditTarget(for item: SearchResultItem) -> AmountEditTarget? {
        guard selected.contains(item.id), let snapshot = snapshots[item.id], snapshot == item,
              let basis = snapshot.calculationBasis, let recordID = recordIDs[item.id] else { return nil }
        return AmountEditTarget(item: snapshot, basis: basis, recordID: recordID,
                                current: amountDrafts[item.id] ?? basis.referenceQuantity, generation: generation)
    }

    /// Stores `quantity` for the row the editor was opened for, provided the
    /// row is still selected with the same snapshot, record ID and search
    /// generation and the basis can compute it. Selection order and record
    /// ID are untouched. The amount is the session's draft only; no write.
    func applyAmount(_ quantity: FoodQuantity, for target: AmountEditTarget) -> AmountApplyOutcome {
        guard target.generation == generation, selected.contains(target.id), snapshots[target.id] == target.item,
              recordIDs[target.id] == target.recordID, snapshots[target.id]?.calculationBasis == target.basis,
              quantity.unit == target.basis.referenceQuantity.unit,
              (try? target.basis.protein(for: quantity)) != nil else { return .selectionChanged }
        amountDrafts[target.id] = quantity
        return .applied
    }

    /// Freeze the displayed snapshot while a language or record write runs.
    /// Late page callbacks cannot mutate selections during a pending save.
    func cancelPagesKeepingResults() {
        guard status == .results else { return }
        generation += 1
        requestHandle?.cancel()
        requestHandle = nil
        pageHandle?.cancel()
        pageHandle = nil
        isLoadingMore = false
    }

    // MARK: Language and leaving

    /// Called only after the language write was confirmed: results and
    /// selection of the old language are dropped, the draft stays, and the
    /// next explicit search uses the new provider.
    func applyLanguage(_ language: SearchLanguage) {
        guard language != self.language else { return }
        beginGeneration()
        self.language = language
        provider = makeProvider(language)
        executedQuery = nil
        status = .idle
    }

    /// Leaving the tab or closing the sheet: cancel everything and forget the
    /// results. Re-entering starts from the saved language and recent list.
    func invalidate() {
        beginGeneration()
        executedQuery = nil
        status = .idle
        queryDraft = ""
    }
}
