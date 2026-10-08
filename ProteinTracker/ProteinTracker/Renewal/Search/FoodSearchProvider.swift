import Foundation
import HelloProteinCore

/// A verified reference amount a result's protein value refers to, e.g.
/// "per 100 g". Only units the record store supports; no conversions.
struct SearchReferenceAmount: Equatable {
    let quantity: FoodQuantity
}

/// Why a result row cannot be added directly. Shown next to the row; the row
/// itself stays visible so the user can still use its name.
enum SearchItemUnavailability: Equatable {
    /// The reference amount is missing, zero or in an unsupported unit.
    case unknownReference
    /// The protein value is not a plain decimal number.
    case invalidProtein
    /// The protein value is negative.
    case negativeProtein
    /// The protein value is a number but outside the range the store can hold.
    case proteinOutOfRange
    /// The protein value rounds to 0 (or is 0): nothing to log.
    case zeroProtein
}

/// One search result exactly as the provider verified it. Provider data
/// (`providerID`, `dataVersion`, `itemID`) identifies the row during the
/// session only; the persisted record stores name, protein, quantity and
/// `source: .search`.
struct SearchResultItem: Equatable, Identifiable {
    let providerID: String
    /// Catalog or API data version the `itemID` is stable within.
    let dataVersion: String
    let itemID: String
    let name: String
    /// The provider's protein value verbatim, for display and evidence.
    let rawProtein: String
    /// Verified centigrams, present only when the row can be added.
    let proteinCentigrams: Int64?
    /// True when `proteinCentigrams` was rounded from a longer decimal.
    let rounded: Bool
    let reference: SearchReferenceAmount?
    /// Localized key naming the data source, shown on the row.
    let sourceKey: String
    let unavailability: SearchItemUnavailability?

    var id: String { "\(providerID)|\(dataVersion)|\(itemID)" }
    var isSelectable: Bool { unavailability == nil && proteinCentigrams != nil && reference != nil }
}

/// One page of results. `nextPage` is nil when the provider's contract says
/// there is nothing more; a provider never guesses.
struct SearchResultPage: Equatable {
    let items: [SearchResultItem]
    let nextPage: SearchPageRequest?
}

/// Where the next page starts, in the provider's own terms.
struct SearchPageRequest: Equatable {
    let startIndex: Int
    let endIndex: Int
}

enum SearchProviderError: Error, Equatable {
    /// The provider cannot be used at all: no key, empty key or an
    /// unsubstituted build variable. Never carries the key.
    case notConfigured
    /// Transport failure (offline, DNS, TLS). The description is for logs
    /// and never includes the URL.
    case network(String)
    case timeout
    /// The response could not be decoded into the documented shape.
    case invalidResponse(String)
    /// The service answered with an error code of its own.
    case service(code: String, message: String)
    /// The bundled catalog could not be read or decoded.
    case localData(String)
    case cancelled
}

/// A running search request. Cancelling guarantees the completion is either
/// never called or called with `.cancelled`; callers still check their own
/// generation because a completion may already be queued.
protocol SearchRequestHandle: AnyObject {
    func cancel()
}

/// Food lookup only. No history, no language, no writes. Implementations are
/// injected so the session can be tested with fixtures and delayed answers.
protocol FoodSearchProvider: AnyObject {
    var providerID: String { get }
    /// `page` nil means the first page. The completion may run on any queue.
    @discardableResult
    func search(query: String, page: SearchPageRequest?,
                completion: @escaping (Result<SearchResultPage, SearchProviderError>) -> Void) -> SearchRequestHandle
}

/// A provider that answers every request with `.notConfigured`: used when the
/// Korean service key is absent so the screen shows the unavailable state
/// instead of hanging or hitting the network without credentials.
final class UnconfiguredSearchProvider: FoodSearchProvider {
    let providerID: String
    init(providerID: String) { self.providerID = providerID }

    @discardableResult
    func search(query: String, page: SearchPageRequest?,
                completion: @escaping (Result<SearchResultPage, SearchProviderError>) -> Void) -> SearchRequestHandle {
        let handle = CancellableHandle()
        DispatchQueue.global().async {
            guard !handle.isCancelled else { return completion(.failure(.cancelled)) }
            completion(.failure(.notConfigured))
        }
        return handle
    }
}

/// Simple thread-safe flag used by in-process providers.
final class CancellableHandle: SearchRequestHandle {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
