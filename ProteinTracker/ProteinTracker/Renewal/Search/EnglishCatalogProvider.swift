import Foundation
import HelloProteinCore

/// The legacy English catalog, with per-row exact-match attestations against
/// the official USDA SR Legacy archive. Only attested rows use its 100 g reference.
/// Rows are identified by the
/// catalog version and their fixed position in the file; the version must
/// change whenever the file is replaced (`EnglishCatalogProviderTests` pins
/// the file's digest and row count to this constant).
final class EnglishCatalogProvider: FoodSearchProvider {
    static let identifier = "usda-sr-legacy-local"
    /// Bumped together with the file. "2332" is the row count of this edition.
    static let catalogVersion = "protein-en.2332.2"
    static let resourceName = "Protein-En"

    struct Row: Equatable {
        let index: Int
        let name: String
        let rawProtein: String
        var verifiedFDCID: String? = nil
    }

    let providerID: String = EnglishCatalogProvider.identifier
    private let url: URL?
    private let queue = DispatchQueue(label: "com.devsom.ProteinTracker.english-catalog", qos: .userInitiated)
    private let lock = NSLock()
    private var cachedRows: Result<[Row], SearchProviderError>?

    init(url: URL?) { self.url = url }

    convenience init(bundle: Bundle = .main) {
        self.init(url: bundle.url(forResource: Self.resourceName, withExtension: "json"))
    }

    // MARK: Loading

    /// Rows in file order. Loaded once; a load failure is cached too, so the
    /// user sees the same "data couldn't be loaded" state until relaunch.
    func rows() -> Result<[Row], SearchProviderError> {
        lock.lock(); defer { lock.unlock() }
        if let cachedRows { return cachedRows }
        let result = Self.load(url: url)
        cachedRows = result
        return result
    }

    static func load(url: URL?) -> Result<[Row], SearchProviderError> {
        guard let url else { return .failure(.localData("catalog resource missing")) }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { return .failure(.localData("catalog unreadable")) }
        do { return .success(try parse(data)) }
        catch let error as CatalogJSON.ParseError { return .failure(.localData("catalog JSON invalid at \(error.offset): \(error.reason)")) }
        catch { return .failure(.localData(String(describing: error))) }
    }

    /// Food and Protein are required; VerifiedFDCID is optional verification metadata.
    static func parse(_ data: Data) throws -> [Row] {
        guard let items = try CatalogJSON.parse(data).arrayValue else { throw CatalogJSON.ParseError(offset: 0, reason: "top level is not an array") }
        return try items.enumerated().map { index, item in
            guard let name = item["Food"]?.stringValue else { throw CatalogJSON.ParseError(offset: index, reason: "row \(index) has no Food string") }
            guard case .number(let protein)? = item["Protein"] else { throw CatalogJSON.ParseError(offset: index, reason: "row \(index) has no Protein number") }
            return Row(index: index, name: name, rawProtein: protein, verifiedFDCID: item["VerifiedFDCID"]?.stringValue)
        }
    }

    // MARK: Search

    /// Case- and diacritic-insensitive substring match on the trimmed query,
    /// in catalog order, all matches in one page. A blank query matches nothing
    /// (the session shows recent searches instead of asking).
    @discardableResult
    func search(query: String, page: SearchPageRequest?,
                completion: @escaping (Result<SearchResultPage, SearchProviderError>) -> Void) -> SearchRequestHandle {
        let handle = CancellableHandle()
        queue.async {
            guard !handle.isCancelled else { return completion(.failure(.cancelled)) }
            switch self.rows() {
            case .failure(let error): completion(.failure(error))
            case .success(let rows):
                let items = Self.matches(for: query, in: rows).map(Self.item)
                guard !handle.isCancelled else { return completion(.failure(.cancelled)) }
                completion(.success(SearchResultPage(items: items, nextPage: nil)))
            }
        }
        return handle
    }

    static func matches(for query: String, in rows: [Row]) -> [Row] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return rows.filter { $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    static let per100g = SearchReferenceAmount(quantity: try! FoodQuantity(value: "100", unit: .gram))

    /// Verified conversion of the row's gram text; a value that is not a plain
    /// positive decimal stays visible as unavailable, never silently fixed.
    static func item(_ row: Row) -> SearchResultItem {
        var centigrams: Int64?
        var rounded = false
        var unavailability: SearchItemUnavailability?
        do {
            let conversion = try ProteinGramsText.centigrams(row.rawProtein)
            rounded = conversion.rounded
            if conversion.centigrams > 0 { centigrams = conversion.centigrams } else { unavailability = .zeroProtein }
        } catch ProteinGramsTextError.negative {
            unavailability = .negativeProtein
        } catch ProteinGramsTextError.overflow {
            unavailability = .proteinOutOfRange
        } catch {
            unavailability = .invalidProtein
        }
        // Only exact name/value matches against the pinned official archive
        // have a verified reference. Unmatched legacy values stay visible.
        let verified = row.verifiedFDCID?.isEmpty == false
        if !verified { unavailability = .unknownReference }
        return SearchResultItem(providerID: identifier, dataVersion: catalogVersion, itemID: String(row.index),
                                name: row.name, rawProtein: row.rawProtein, proteinCentigrams: centigrams, rounded: rounded,
                                reference: verified ? per100g : nil,
                                sourceKey: verified ? "renewal_search_source_usda" : "renewal_search_source_unverified",
                                unavailability: unavailability)
    }
}

/// Picks the provider for a confirmed search language. Korean has no verified
/// service at the moment (the legacy I2790 service answers "service not
/// found"), so it is reported as not configured instead of calling anything.
enum SearchProviderFactory {
    static let koreanProviderID = "mfds-korean"

    static func make(for language: SearchLanguage, bundle: Bundle = .main) -> FoodSearchProvider {
        switch language {
        case .english: return EnglishCatalogProvider(bundle: bundle)
        case .korean: return UnconfiguredSearchProvider(providerID: koreanProviderID)
        }
    }
}

#if DEBUG
/// DEBUG-only provider double for UI runs: the first request fails with the
/// given error, later ones go through to the real provider. Never in Release.
final class FailingOnceSearchProvider: FoodSearchProvider {
    enum Failure: String {
        case network
        case localData
        case timeout
        case service
    }

    private let inner: FoodSearchProvider
    private let lock = NSLock()
    private var pending: Failure?

    init(inner: FoodSearchProvider, failure: Failure) {
        self.inner = inner
        self.pending = failure
    }

    var providerID: String { inner.providerID }

    @discardableResult
    func search(query: String, page: SearchPageRequest?,
                completion: @escaping (Result<SearchResultPage, SearchProviderError>) -> Void) -> SearchRequestHandle {
        lock.lock()
        let failure = pending
        pending = nil
        lock.unlock()
        guard let failure else { return inner.search(query: query, page: page, completion: completion) }
        let handle = CancellableHandle()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            guard !handle.isCancelled else { return completion(.failure(.cancelled)) }
            NSLog("HelloProtein: simulated search failure %@", failure.rawValue)
            switch failure {
            case .network: completion(.failure(.network("simulated")))
            case .localData: completion(.failure(.localData("simulated")))
            case .timeout: completion(.failure(.timeout))
            case .service: completion(.failure(.service(code: "SIM-1", message: "simulated")))
            }
        }
        return handle
    }
}
#endif
