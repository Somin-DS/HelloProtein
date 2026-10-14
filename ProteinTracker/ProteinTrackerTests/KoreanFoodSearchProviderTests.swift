import XCTest
import HelloProteinCore

final class KoreanFoodSearchProviderTests: XCTestCase {
    private func row(_ id: String = "food-1", protein: String = "23.125", portion: String = "100g") -> [String: String] {
        ["FOOD_CD": id, "FOOD_NM_KR": "닭가슴살", "AMT_NUM3": protein, "SERVING_SIZE": portion]
    }
    private func response(_ rows: [[String: String]], count: Int? = nil, page: Int = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["header": ["resultCode": "00", "resultMsg": "NORMAL SERVICE"],
            "body": ["items": rows, "totalCount": count ?? rows.count, "pageNo": page, "numOfRows": 20]])
    }
    func testRequestEncodesRawKeyAndSpecialFoodNamesWithoutChangingTheirMeaning() throws {
        let query = "계란 & 우유/+%'"
        let request = try KoreanFoodSearchProvider.request(query: query, page: .init(startIndex: 21, endIndex: 40), key: "test+/=")
        let parts = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: parts.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(parts.scheme, "https")
        XCTAssertEqual(parts.host, "apis.data.go.kr")
        XCTAssertEqual(values["serviceKey"], "test+/=")
        XCTAssertEqual(values["FOOD_NM_KR"], query)
        XCTAssertEqual(values["pageNo"], "2")
        XCTAssertEqual(values["numOfRows"], "20")
        XCTAssertEqual(values["type"], "json")
        XCTAssertTrue(request.url!.absoluteString.contains("%2B"))
        XCTAssertThrowsError(try KoreanFoodSearchProvider.request(query: "x", page: .init(startIndex: 2, endIndex: 21), key: "test"))
    }
    func testMapsIdentityProteinAndExplicitReferenceWithoutWeightFallback() throws {
        let page = try KoreanFoodSearchProvider.decode(response([row()]), expectedPage: 1)
        let item = try XCTUnwrap(page.items.first)
        XCTAssertEqual(item.id, "mfds-korean|FoodNtrCpntDbInfo03|food-1")
        XCTAssertEqual(item.proteinCentigrams, 2313)
        XCTAssertTrue(item.rounded)
        XCTAssertEqual(item.reference?.quantity, try FoodQuantity(value: "100", unit: .gram))
        XCTAssertTrue(item.isSelectable)
        XCTAssertNil(page.nextPage)
        let records = try SearchRecordBatch.records(for: [.init(itemKey: item.id, recordID: "r1", name: item.name,
            proteinCentigrams: item.proteinCentigrams!, quantity: item.reference!.quantity)], on: CalendarDay(iso8601: "2026-10-01"))
        XCTAssertEqual(records[0].source, .search)
        XCTAssertEqual(records[0].quantity, item.reference?.quantity)
        XCTAssertEqual(KoreanFoodSearchProvider.reference(" 200 mL ")?.quantity.unit, .milliliter)
        for unknown in ["100", "1회", "1 serving", "100mg", "0g", "100g당", "", "NaN g"] {
            XCTAssertNil(KoreanFoodSearchProvider.reference(unknown), unknown)
        }
        let unverified = try KoreanFoodSearchProvider.decode(response([row(portion: "100")]), expectedPage: 1).items[0]
        XCTAssertFalse(unverified.isSelectable)
        XCTAssertEqual(unverified.unavailability, .unknownReference)
    }
    func testZeroNegativeAndMissingProteinRemainUnselectable() throws {
        for (value, reason) in [("0", SearchItemUnavailability.zeroProtein), ("-1", .negativeProtein),
                                ("0.004", .zeroProtein), ("N/A", .invalidProtein), ("", .invalidProtein),
                                ("9999999999999999999999", .proteinOutOfRange)] {
            let item = try KoreanFoodSearchProvider.decode(response([row(protein: value)]), expectedPage: 1).items[0]
            XCTAssertEqual(item.unavailability, reason)
            XCTAssertFalse(item.isSelectable)
        }
    }
    func testPaginationUsesValidatedTotalAndRejectsIncompleteOrWrongPages() throws {
        let first = try KoreanFoodSearchProvider.decode(response((0..<20).map { row("f\($0)") }, count: 21), expectedPage: 1)
        XCTAssertEqual(first.nextPage, SearchPageRequest(startIndex: 21, endIndex: 40))
        XCTAssertNil(try KoreanFoodSearchProvider.decode(response([row()], count: 21, page: 2), expectedPage: 2).nextPage)
        XCTAssertThrowsError(try KoreanFoodSearchProvider.decode(response([row()], count: 21), expectedPage: 1))
        XCTAssertThrowsError(try KoreanFoodSearchProvider.decode(response([row()]), expectedPage: 2))
        XCTAssertTrue(try KoreanFoodSearchProvider.decode(response([]), expectedPage: 1).items.isEmpty)
        XCTAssertThrowsError(try KoreanFoodSearchProvider.decode(response([row(), row()]), expectedPage: 1))
    }
    func testDocumentedItemsWrapperAndNoRowsAreHandled() throws {
        let body: [String: Any] = ["items": ["item": row()], "totalCount": "1", "pageNo": "1", "numOfRows": "20"]
        let data = try JSONSerialization.data(withJSONObject: ["response": ["header": ["resultCode": "00"], "body": body]])
        XCTAssertEqual(try KoreanFoodSearchProvider.decode(data, expectedPage: 1).items.count, 1)
        let empty = Data(#"{"header":{"resultCode":"00"},"body":{"totalCount":0,"pageNo":1,"numOfRows":20}}"#.utf8)
        XCTAssertTrue(try KoreanFoodSearchProvider.decode(empty, expectedPage: 1).items.isEmpty)
    }
    func testServerErrorsNeverExposeRawMessagesAndMalformedResponsesFail() {
        let data = Data(#"{"header":{"resultCode":"30","resultMsg":"SECRET URL serviceKey=private"}}"#.utf8)
        XCTAssertThrowsError(try KoreanFoodSearchProvider.decode(data, expectedPage: 1)) { error in
            guard case SearchProviderError.service(let code, let message) = error else { return XCTFail("wrong error") }
            XCTAssertEqual(code, "30")
            XCTAssertFalse(message.contains("SECRET"))
        }
        for body in ["<OpenAPI_ServiceResponse>private</OpenAPI_ServiceResponse>", "{}", "not JSON"] {
            XCTAssertThrowsError(try KoreanFoodSearchProvider.decode(Data(body.utf8), expectedPage: 1))
        }
    }
    func testMissingAndPlaceholderKeysNeverStartTransport() {
        for key in [nil, "", "  ", "$(MFDS_API_KEY)", "${MFDS_API_KEY}"] as [String?] {
            let done = expectation(description: "no key")
            KoreanFoodSearchProvider(serviceKey: key).search(query: "계란", page: nil) { result in
                guard case .failure(.notConfigured) = result else { return XCTFail("missing key must fail closed") }
                done.fulfill()
            }
            waitForExpectations(timeout: 1)
        }
    }

    private final class StubProtocol: URLProtocol {
        static var reply: (URLRequest) throws -> (Int, Data) = { _ in (200, Data()) }
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            do {
                let (status, data) = try Self.reply(request)
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
        override func stopLoading() {}
    }
    func testTransportSuccessHTTPTimeoutAndCancellation() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let provider = KoreanFoodSearchProvider(serviceKey: "synthetic-test-key", session: session)
        let data = try response([row()])
        let cases: [(Int?, URLError.Code?, SearchProviderError?)] = [(200, nil, nil),
            (403, nil, .service(code: "403", message: "HTTP request rejected")),
            (nil, .timedOut, .timeout), (nil, .cancelled, .cancelled),
            (nil, .notConnectedToInternet, .network("Request failed"))]
        for (status, failure, expected) in cases {
            StubProtocol.reply = { _ in
                if let failure { throw URLError(failure) }
                return (status!, data)
            }
            let done = expectation(description: "transport")
            provider.search(query: "계란", page: nil) { result in
                switch result {
                case .success(let page): XCTAssertNil(expected); XCTAssertEqual(page.items.count, 1)
                case .failure(let error): XCTAssertEqual(error, expected)
                }
                done.fulfill()
            }
            waitForExpectations(timeout: 3)
        }
    }
}
