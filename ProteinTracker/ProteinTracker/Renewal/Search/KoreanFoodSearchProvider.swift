import Foundation
import HelloProteinCore

/// MFDS FoodNtrCpntDbInfo03. No legacy I2790 keys or inferred 100 g portions.
/// A raw (decoded) data.go.kr service key is supplied through local build settings.
final class KoreanFoodSearchProvider: FoodSearchProvider {
    let providerID = "mfds-korean"
    static let pageSize = 20
    static let endpoint = URL(string: "https://apis.data.go.kr/1471000/FoodNtrCpntDbInfo03/getFoodNtrCpntDbInq03")!
    private let key: String?
    private let session: URLSession

    init(serviceKey: String?, session: URLSession = .shared) {
        let value = serviceKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        key = value.isEmpty || value.contains("$(") || value.contains("${") ? nil : value
        self.session = session
    }

    @discardableResult
    func search(query: String, page: SearchPageRequest?,
                completion: @escaping (Result<SearchResultPage, SearchProviderError>) -> Void) -> SearchRequestHandle {
        guard let key else {
            completion(.failure(.notConfigured))
            return CancellableHandle()
        }
        let request: URLRequest
        do { request = try Self.request(query: query, page: page, key: key) }
        catch { completion(.failure(.invalidResponse("Invalid search request"))); return CancellableHandle() }
        let pageNumber = ((page?.startIndex ?? 1) - 1) / Self.pageSize + 1
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error as? URLError {
                switch error.code {
                case .cancelled: completion(.failure(.cancelled))
                case .timedOut: completion(.failure(.timeout))
                default: completion(.failure(.network("Request failed")))
                }
                return
            }
            guard error == nil else { completion(.failure(.network("Request failed"))); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse("Missing HTTP response"))); return
            }
            guard (200..<300).contains(http.statusCode) else {
                // Neither raw server bodies nor URLs containing the key leave the adapter.
                completion(.failure(.service(code: String(http.statusCode), message: "HTTP request rejected"))); return
            }
            guard let data else { completion(.failure(.invalidResponse("Missing response data"))); return }
            do { completion(.success(try Self.decode(data, expectedPage: pageNumber))) }
            catch let error as SearchProviderError { completion(.failure(error)) }
            catch { completion(.failure(.invalidResponse("Invalid food response"))) }
        }
        task.resume()
        return TaskHandle(task)
    }

    static func request(query: String, page: SearchPageRequest?, key: String) throws -> URLRequest {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = page?.startIndex ?? 1
        guard !query.isEmpty, start > 0, (start - 1) % pageSize == 0,
              start <= Int.max - pageSize,
              page == nil || page?.endIndex == start + pageSize - 1 else {
            throw SearchProviderError.invalidResponse("Invalid page")
        }
        var url = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "serviceKey", value: key),
                          URLQueryItem(name: "type", value: "json"),
                          URLQueryItem(name: "pageNo", value: String((start - 1) / pageSize + 1)),
                          URLQueryItem(name: "numOfRows", value: String(pageSize)),
                          URLQueryItem(name: "FOOD_NM_KR", value: query)]
        // Form-style servers may interpret a literal + as a space.
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let requestURL = url.url else { throw SearchProviderError.invalidResponse("Invalid query") }
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func decode(_ data: Data, expectedPage: Int) throws -> SearchResultPage {
        let document = try CatalogJSON.parse(data)
        let root = document["response"] ?? document
        guard let header = root["header"], let code = header["resultCode"]?.numberText else {
            throw SearchProviderError.invalidResponse("Missing result header")
        }
        guard code == "00" || code == "0" else {
            // Whitelist the code shape; the upstream error message might echo credentials.
            let safeCode = code.count <= 3 && code.allSatisfy({ $0.isASCII && $0.isNumber }) ? code : "API"
            throw SearchProviderError.service(code: safeCode, message: "Food service rejected the request")
        }
        guard let body = root["body"], let countText = body["totalCount"]?.numberText,
              let count = Int(countText), count >= 0,
              let pageText = body["pageNo"]?.numberText, Int(pageText) == expectedPage,
              let sizeText = body["numOfRows"]?.numberText, Int(sizeText) == pageSize else {
            throw SearchProviderError.invalidResponse("Invalid page metadata")
        }
        let container = body["items"]
        let rows: [CatalogJSON.Value]
        if let array = container?.arrayValue { rows = array }
        else if let item = container?["item"] {
            if let array = item.arrayValue { rows = array }
            else if case .object = item { rows = [item] }
            else { throw SearchProviderError.invalidResponse("Invalid items") }
        } else if count == 0, container == nil || container == .null || container?.stringValue == "" {
            rows = []
        } else { throw SearchProviderError.invalidResponse("Missing items") }
        guard expectedPage > 0, expectedPage <= (Int.max - pageSize * 2) / pageSize, rows.count <= pageSize else {
            throw SearchProviderError.invalidResponse("Invalid page size")
        }
        let offset = (expectedPage - 1) * pageSize
        guard offset <= count, rows.count == min(pageSize, count - offset) else {
            throw SearchProviderError.invalidResponse("Incomplete page")
        }
        let items = try rows.map(item)
        guard Set(items.map(\.id)).count == items.count else { throw SearchProviderError.invalidResponse("Duplicate food IDs") }
        let hasMore = offset + rows.count < count
        let next = hasMore ? SearchPageRequest(startIndex: offset + pageSize + 1, endIndex: offset + pageSize * 2) : nil
        return SearchResultPage(items: items, nextPage: next)
    }

    static func item(_ row: CatalogJSON.Value) throws -> SearchResultItem {
        guard let id = row["FOOD_CD"]?.stringValue, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let name = row["FOOD_NM_KR"]?.stringValue, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SearchProviderError.invalidResponse("Missing food identity")
        }
        let raw = row["AMT_NUM3"]?.numberText ?? ""
        let reference = reference(row["SERVING_SIZE"]?.stringValue ?? "")
        var amount: Int64?
        var rounded = false
        var unavailable: SearchItemUnavailability?
        do {
            let parsed = try ProteinGramsText.centigrams(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            rounded = parsed.rounded
            if parsed.centigrams > 0 { amount = parsed.centigrams } else { unavailable = .zeroProtein }
        } catch ProteinGramsTextError.negative { unavailable = .negativeProtein }
        catch ProteinGramsTextError.overflow { unavailable = .proteinOutOfRange }
        catch { unavailable = .invalidProtein }
        if reference == nil { unavailable = .unknownReference }
        return SearchResultItem(providerID: "mfds-korean", dataVersion: "FoodNtrCpntDbInfo03", itemID: id,
                                name: name, rawProtein: raw, proteinCentigrams: amount, rounded: rounded,
                                reference: reference, sourceKey: "renewal_search_source_mfds", unavailability: unavailable)
    }

    /// Only explicit units in SERVING_SIZE are accepted. No serving/weight fallback.
    static func reference(_ text: String) -> SearchReferenceAmount? {
        let pattern = #"^([0-9]+(?:\.[0-9]+)?)\s*(g|mL|ml|㎖|그램|밀리리터)$"#
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let numberRange = Range(match.range(at: 1), in: value), let unitRange = Range(match.range(at: 2), in: value) else { return nil }
        let unit: FoodQuantity.Unit = ["g", "그램"].contains(String(value[unitRange])) ? .gram : .milliliter
        guard let quantity = try? FoodQuantity(value: String(value[numberRange]), unit: unit) else { return nil }
        return SearchReferenceAmount(quantity: quantity)
    }

    private final class TaskHandle: SearchRequestHandle {
        let task: URLSessionDataTask
        init(_ task: URLSessionDataTask) { self.task = task }
        func cancel() { task.cancel() }
    }
}
