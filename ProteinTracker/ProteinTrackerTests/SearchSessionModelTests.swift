import XCTest
import HelloProteinCore

/// A provider whose answers the test releases by hand, so late, reordered
/// and cancelled completions can be driven deterministically.
@available(iOS 15.0, *)
final class ScriptedSearchProvider: FoodSearchProvider {
    final class Handle: SearchRequestHandle {
        let query: String
        let page: SearchPageRequest?
        let completion: (Result<SearchResultPage, SearchProviderError>) -> Void
        private(set) var cancelled = false
        init(query: String, page: SearchPageRequest?, completion: @escaping (Result<SearchResultPage, SearchProviderError>) -> Void) {
            self.query = query; self.page = page; self.completion = completion
        }
        func cancel() { cancelled = true }
        /// Delivers the answer regardless of cancellation, like a network callback that was already in flight.
        func deliver(_ result: Result<SearchResultPage, SearchProviderError>) { completion(result) }
    }

    let providerID: String
    private(set) var requests: [Handle] = []
    init(providerID: String = "scripted") { self.providerID = providerID }

    @discardableResult
    func search(query: String, page: SearchPageRequest?,
                completion: @escaping (Result<SearchResultPage, SearchProviderError>) -> Void) -> SearchRequestHandle {
        let handle = Handle(query: query, page: page, completion: completion)
        requests.append(handle)
        return handle
    }
}

@available(iOS 15.0, *)
final class SearchSessionModelTests: XCTestCase {
    private let queue = DispatchQueue(label: "search-session-tests")
    private var providers: [SearchLanguage: ScriptedSearchProvider] = [:]
    private var idCounter = 0

    private func item(_ id: String, name: String? = nil, centigrams: Int64? = 2_300, provider: String = "scripted",
                      unavailability: SearchItemUnavailability? = nil) -> SearchResultItem {
        SearchResultItem(providerID: provider, dataVersion: "v1", itemID: id, name: name ?? "Food \(id)", rawProtein: "23",
                         proteinCentigrams: centigrams, rounded: false,
                         reference: SearchReferenceAmount(quantity: try! FoodQuantity(value: "100", unit: .gram)),
                         sourceKey: "renewal_search_source_usda", unavailability: unavailability)
    }

    private func page(_ items: [SearchResultItem], next: SearchPageRequest? = nil) -> SearchResultPage {
        SearchResultPage(items: items, nextPage: next)
    }

    private func makeSession(language: SearchLanguage = .english) -> SearchSessionModel {
        providers = [.english: ScriptedSearchProvider(providerID: "en"), .korean: ScriptedSearchProvider(providerID: "ko")]
        let providers = self.providers
        return SearchSessionModel(language: language, makeProvider: { providers[$0]! }, mainQueue: queue,
                                  makeID: { [unowned self] in self.idCounter += 1; return "rec-\(self.idCounter)" })
    }

    private func sync<T>(_ body: @escaping () -> T) -> T { queue.sync(execute: body) }
    private func drain() { queue.sync {} }

    /// Executes a search whose history write succeeds immediately.
    private func execute(_ session: SearchSessionModel, _ query: String, history: @escaping (String, @escaping () -> Void) -> Void = { _, proceed in proceed() }) {
        sync { session.execute(query: query, recordHistory: history) }
        drain()
    }

    private var en: ScriptedSearchProvider { providers[.english]! }

    // MARK: Explicit search and history

    func testExecuteRecordsHistoryThenAsksTheProviderOnceAndABlankQueryDoesNothing() {
        let session = makeSession()
        var recorded: [String] = []
        execute(session, "  egg ") { term, proceed in recorded.append(term); proceed() }
        XCTAssertEqual(recorded, ["egg"])
        XCTAssertEqual(sync { session.executedQuery }, "egg")
        XCTAssertEqual(sync { session.status }, .searching)
        XCTAssertEqual(en.requests.map(\.query), ["egg"])

        execute(session, "   ") { _, _ in XCTFail("blank queries are never recorded") }
        XCTAssertEqual(en.requests.count, 1)
        XCTAssertEqual(sync { session.executedQuery }, "egg", "the blank query changed nothing")

        en.requests[0].deliver(.success(page([item("1"), item("2")])))
        drain()
        XCTAssertEqual(sync { session.status }, .results)
        XCTAssertEqual(sync { session.results.map(\.itemID) }, ["1", "2"])
    }

    func testHistoryOutcomeDoesNotStopTheLookupAndALateHistoryCallbackIsIgnored() {
        let session = makeSession()
        var proceedFirst: (() -> Void)?
        execute(session, "egg") { _, proceed in proceedFirst = proceed }
        XCTAssertTrue(en.requests.isEmpty, "the lookup waits for the history outcome")
        // A second explicit search supersedes the first before its history callback returned.
        execute(session, "milk") { _, proceed in proceed() }
        XCTAssertEqual(en.requests.map(\.query), ["milk"])
        proceedFirst?()
        drain()
        XCTAssertEqual(en.requests.map(\.query), ["milk"], "the stale history callback starts no lookup")
        XCTAssertEqual(sync { session.executedQuery }, "milk")
    }

    func testReversedAnswersKeepOnlyTheLatestGenerationAndCancelTheOlderRequest() {
        let session = makeSession()
        execute(session, "a")
        execute(session, "b")
        XCTAssertTrue(en.requests[0].cancelled)
        XCTAssertFalse(en.requests[1].cancelled)
        // B answers first, then the stale A answer arrives anyway.
        en.requests[1].deliver(.success(page([item("b1")])))
        en.requests[0].deliver(.success(page([item("a1"), item("a2")])))
        drain()
        XCTAssertEqual(sync { session.results.map(\.itemID) }, ["b1"])
        XCTAssertEqual(sync { session.status }, .results)
        // The other order: A's late answer, then B's.
        execute(session, "c")
        execute(session, "d")
        en.requests[2].deliver(.failure(.network("late")))
        drain()
        XCTAssertEqual(sync { session.status }, .searching, "a stale failure does not end the live request's loading")
        en.requests[3].deliver(.success(page([])))
        drain()
        XCTAssertEqual(sync { session.status }, .empty)
    }

    func testEveryFailureEndsLoadingAndRetryRepeatsOnlyTheLookup() {
        let session = makeSession()
        var historyWrites = 0
        execute(session, "egg") { _, proceed in historyWrites += 1; proceed() }
        en.requests[0].deliver(.failure(.timeout))
        drain()
        XCTAssertEqual(sync { session.status }, .failed(.timeout))
        sync { session.retry() }
        drain()
        XCTAssertEqual(historyWrites, 1, "retry writes no history")
        XCTAssertEqual(en.requests.map(\.query), ["egg", "egg"])
        XCTAssertEqual(sync { session.status }, .searching)
        en.requests[1].deliver(.failure(.localData("missing")))
        drain()
        XCTAssertEqual(sync { session.status }, .failed(.localData("missing")))
        sync { session.retry() }
        en.requests[2].deliver(.failure(.notConfigured))
        drain()
        XCTAssertEqual(sync { session.status }, .unavailable)
        sync { session.retry() }
        drain()
        XCTAssertEqual(en.requests.count, 3, "retry applies to failed lookups only")
        XCTAssertEqual(sync { session.queryDraft }, "", "the draft is never touched by the session")
    }

    func testAProviderCancellingTheCurrentRequestEndsLoadingWithARetry() {
        let session = makeSession()
        execute(session, "egg") { _, proceed in proceed() }
        en.requests[0].deliver(.failure(.cancelled))
        drain()
        XCTAssertEqual(sync { session.status }, .failed(.cancelled), "no endless searching state")
        XCTAssertFalse(sync { session.isSearching })
        sync { session.retry() }
        drain()
        XCTAssertEqual(en.requests.map(\.query), ["egg", "egg"])
    }

    // MARK: Selection and record IDs

    func testSelectionKeepsOrderFixesRecordIDsPerGenerationAndSkipsUnselectableRows() {
        let session = makeSession()
        execute(session, "egg")
        let zero = item("z", centigrams: nil, unavailability: .zeroProtein)
        en.requests[0].deliver(.success(page([item("1"), item("2", centigrams: 900), zero])))
        drain()
        sync {
            session.toggle(session.results[1])
            session.toggle(session.results[0])
            session.toggle(zero)
        }
        XCTAssertEqual(sync { session.selected }, ["scripted|v1|2", "scripted|v1|1"])
        let selections = sync { session.selections }
        XCTAssertEqual(selections.map(\.recordID), ["rec-1", "rec-2"])
        XCTAssertEqual(selections.map(\.proteinCentigrams), [900, 2_300])
        XCTAssertEqual(selections.map(\.quantity.value), ["100", "100"])
        XCTAssertEqual(sync { session.totalCentigrams }, 3_200)
        // Deselect and re-select keeps the ID; a new search assigns new ones.
        sync { session.toggle(session.results[1]); session.toggle(session.results[1]) }
        XCTAssertEqual(sync { session.selections.map(\.recordID) }, ["rec-2", "rec-1"])
        execute(session, "milk")
        XCTAssertTrue(sync { session.selected.isEmpty })
        en.requests[1].deliver(.success(page([item("1")])))
        drain()
        sync { session.toggle(session.results[0]) }
        XCTAssertEqual(sync { session.selections.map(\.recordID) }, ["rec-3"], "new generation, new ID")
    }

    // MARK: Pages

    func testPagesAppendWithoutDuplicatesAndAChangedSelectedRowIsDeselectedAndReported() {
        let session = makeSession()
        execute(session, "egg")
        let next = SearchPageRequest(startIndex: 3, endIndex: 4)
        en.requests[0].deliver(.success(page([item("1"), item("2")], next: next)))
        drain()
        sync { session.toggle(session.results[0]); session.toggle(session.results[1]) }
        sync { session.loadMore(); session.loadMore() }
        drain()
        XCTAssertEqual(en.requests.count, 2, "no concurrent duplicate page request")
        XCTAssertEqual(en.requests[1].page, next)
        XCTAssertTrue(sync { session.isLoadingMore })
        en.requests[1].deliver(.failure(.network("drop")))
        drain()
        XCTAssertEqual(sync { session.pageError }, .network("drop"))
        XCTAssertEqual(sync { session.results.count }, 2, "the first page stays")
        XCTAssertEqual(sync { session.selected.count }, 2, "the selection stays")
        sync { session.loadMore() }
        en.requests[2].deliver(.success(page([item("2"), item("1", name: "Renamed"), item("3")], next: nil)))
        drain()
        XCTAssertEqual(sync { session.results.map(\.itemID) }, ["1", "2", "3"])
        XCTAssertEqual(sync { session.results[0].name }, "Food 1", "the shown row is not swapped silently")
        XCTAssertEqual(sync { session.selected }, ["scripted|v1|2"])
        XCTAssertEqual(sync { session.droppedSelectionIDs }, ["scripted|v1|1"])
        XCTAssertNil(sync { session.nextPage })
        XCTAssertNil(sync { session.pageError })
    }

    // MARK: Language and leaving

    func testLanguageChangeAppliesOnlyWhenToldAndSwitchesTheProvider() {
        let session = makeSession()
        sync { session.queryDraft = "egg" }
        execute(session, "egg")
        en.requests[0].deliver(.success(page([item("1")])))
        drain()
        sync { session.toggle(session.results[0]) }
        // Nothing happens until the sheet confirms the write.
        XCTAssertEqual(sync { session.selected.count }, 1)
        sync { session.applyLanguage(.english) }
        XCTAssertEqual(sync { session.selected.count }, 1, "same language is a no-op")
        sync { session.applyLanguage(.korean) }
        drain()
        XCTAssertEqual(sync { session.language }, .korean)
        XCTAssertTrue(sync { session.selected.isEmpty })
        XCTAssertTrue(sync { session.results.isEmpty })
        XCTAssertNil(sync { session.executedQuery })
        XCTAssertEqual(sync { session.status }, .idle)
        XCTAssertEqual(sync { session.queryDraft }, "egg", "the draft waits for an explicit search")
        execute(session, "계란")
        XCTAssertEqual(providers[.korean]!.requests.map(\.query), ["계란"])
        XCTAssertEqual(en.requests.count, 1)
        // The old provider's late answer is ignored.
        en.requests[0].deliver(.success(page([item("stale")])))
        drain()
        XCTAssertEqual(sync { session.status }, .searching)
    }

    func testInvalidateCancelsAndClearsSoAnAnswerAfterLeavingIsIgnored() {
        let session = makeSession()
        sync { session.queryDraft = "egg" }
        execute(session, "egg")
        sync { session.invalidate() }
        XCTAssertTrue(en.requests[0].cancelled)
        en.requests[0].deliver(.success(page([item("1")])))
        drain()
        XCTAssertEqual(sync { session.status }, .idle)
        XCTAssertTrue(sync { session.results.isEmpty })
        XCTAssertNil(sync { session.executedQuery })
        XCTAssertEqual(sync { session.queryDraft }, "")
    }
}
