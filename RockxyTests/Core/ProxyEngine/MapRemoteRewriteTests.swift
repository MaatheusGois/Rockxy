import Foundation
import NIOHTTP1
@testable import Rockxy
import Testing

// Regression tests for `MapRemoteRewrite` in the core proxy engine layer.

struct MapRemoteRewriteTests {
    @Test("Blank path preserves original path")
    func blankPathPreserves() throws {
        let config = MapRemoteConfiguration(host: "staging.com")
        let originalURL = try #require(URL(string: "https://prod.com/v2/users?page=1"))

        let path = config.path ?? originalURL.path
        #expect(path == "/v2/users")
    }

    @Test("Blank query preserves original query")
    func blankQueryPreserves() throws {
        let config = MapRemoteConfiguration(host: "staging.com")
        let originalURL = try #require(URL(string: "https://prod.com/v2/users?page=1"))

        let query = config.query ?? originalURL.query
        #expect(query == "page=1")
    }

    @Test("Scheme replacement changes protocol")
    func schemeReplacement() {
        let config = MapRemoteConfiguration(scheme: "http")
        let scheme = config.scheme ?? "https"
        #expect(scheme == "http")
    }

    @Test("Host replacement changes upstream target")
    func hostReplacement() {
        let config = MapRemoteConfiguration(host: "staging.example.com")
        let originalHost = "prod.example.com"
        let upstreamHost = config.host ?? originalHost
        #expect(upstreamHost == "staging.example.com")
    }

    @Test("Port replacement changes connection port")
    func portReplacement() {
        let config = MapRemoteConfiguration(port: 8_443)
        let originalPort = 443
        let port = config.port ?? originalPort
        #expect(port == 8_443)
    }

    @Test("Path replacement overrides original path")
    func pathReplacement() {
        let config = MapRemoteConfiguration(path: "/api/v2")
        let originalPath = "/api/v1"
        let path = config.path ?? originalPath
        #expect(path == "/api/v2")
    }

    @Test("Query replacement overrides original query")
    func queryReplacement() {
        let config = MapRemoteConfiguration(query: "debug=true")
        let originalQuery: String? = "page=1"
        let query = config.query ?? originalQuery
        #expect(query == "debug=true")
    }

    @Test("Preserve-host keeps original host in header")
    func preserveHostHeader() {
        let config = MapRemoteConfiguration(host: "staging.com", preserveHostHeader: true)
        let originalHost = "prod.com"
        let upstreamHost = config.host ?? originalHost
        let hostHeader = config.preserveHostHeader ? originalHost : upstreamHost

        #expect(upstreamHost == "staging.com")
        #expect(hostHeader == "prod.com")
    }

    @Test("Non-preserve-host uses upstream host in header")
    func nonPreserveHostHeader() {
        let config = MapRemoteConfiguration(host: "staging.com", preserveHostHeader: false)
        let originalHost = "prod.com"
        let upstreamHost = config.host ?? originalHost
        let hostHeader = config.preserveHostHeader ? originalHost : upstreamHost

        #expect(hostHeader == "staging.com")
    }

    @Test("All fields nil means no override")
    func noOverride() {
        let config = MapRemoteConfiguration()
        #expect(config.hasOverride == false)
    }

    @Test("Single field set is an override")
    func singleFieldOverride() {
        #expect(MapRemoteConfiguration(host: "x").hasOverride == true)
        #expect(MapRemoteConfiguration(scheme: "http").hasOverride == true)
        #expect(MapRemoteConfiguration(port: 8_080).hasOverride == true)
        #expect(MapRemoteConfiguration(path: "/new").hasOverride == true)
        #expect(MapRemoteConfiguration(query: "a=b").hasOverride == true)
    }

    @Test("Component-by-component independence")
    func componentIndependence() throws {
        let config = MapRemoteConfiguration(scheme: "http", host: "staging.com", port: 8_080)
        let originalURL = try #require(URL(string: "https://prod.com/api/v1?key=123"))

        let scheme = config.scheme ?? originalURL.scheme
        let host = config.host ?? originalURL.host
        let port = config.port ?? originalURL.port
        let path = config.path ?? originalURL.path
        let query = config.query ?? originalURL.query

        #expect(scheme == "http")
        #expect(host == "staging.com")
        #expect(port == 8_080)
        #expect(path == "/api/v1")
        #expect(query == "key=123")
    }

    @Test("Legacy URL parsing produces correct configuration")
    func legacyParsing() {
        let config = MapRemoteConfiguration(fromLegacyURL: "https://staging.example.com:8443/api/v2?debug=1")
        #expect(config.scheme == "https")
        #expect(config.host == "staging.example.com")
        #expect(config.port == 8_443)
        #expect(config.path == "/api/v2")
        #expect(config.query == "debug=1")
        #expect(config.preserveHostHeader == false)
    }

    @Test("Legacy URL parsing preserves percent-encoded query")
    func legacyParsingPreservesEncodedQuery() {
        let config = MapRemoteConfiguration(fromLegacyURL: "HTTPS://Httpbin.org/Get?filter=hello%20world&id=1&id=2")

        #expect(config.scheme == "https")
        #expect(config.host == "Httpbin.org")
        #expect(config.path == "/Get")
        #expect(config.query == "filter=hello%20world&id=1&id=2")
    }

    @Test("HTTP to HTTPS baseline rewrite forwards mapped host header and preserves query")
    func baselineHTTPToHTTPSRewrite() throws {
        let requestData = makeRequest(
            url: "http://127.0.0.1:43210/rockxy-demo/environment?expected=staging",
            headers: [
                HTTPHeader(name: "Host", value: "127.0.0.1:43210"),
                HTTPHeader(name: "X-App-Environment", value: "production"),
            ]
        )
        let head = makeHead(
            uri: "http://127.0.0.1:43210/rockxy-demo/environment?expected=staging",
            headers: [("Host", "127.0.0.1:43210")]
        )
        let rewrite = ProxyHandlerShared.buildMapRemoteRewrite(
            configuration: MapRemoteConfiguration(
                scheme: "HTTPS",
                host: "httpbin.org",
                path: "/get"
            ),
            originalHead: head,
            requestData: requestData,
            fallbackScheme: "http",
            fallbackHost: "localhost"
        )
        let forwardHead = ProxyHandlerShared.buildForwardHead(from: rewrite.requestData, originalHead: rewrite.head)

        #expect(rewrite.scheme == "https")
        #expect(rewrite.upstreamHost == "httpbin.org")
        #expect(rewrite.upstreamPort == 443)
        #expect(rewrite.requestData.url.absoluteString == "https://httpbin.org/get?expected=staging")
        #expect(rewrite.head.uri == "/get?expected=staging")
        #expect(forwardHead.headers.first(name: "Host") == "httpbin.org")
    }

    @Test("Mapped non-default port is included in URL and Host header")
    func nonDefaultPortIncludedInURLAndHostHeader() {
        let requestData = makeRequest(url: "http://prod.example.com/api", headers: [
            HTTPHeader(name: "Host", value: "prod.example.com"),
        ])
        let head = makeHead(uri: "/api", headers: [("Host", "prod.example.com")])
        let rewrite = ProxyHandlerShared.buildMapRemoteRewrite(
            configuration: MapRemoteConfiguration(
                scheme: "https",
                host: "staging.example.com",
                port: 8_443
            ),
            originalHead: head,
            requestData: requestData,
            fallbackScheme: "http",
            fallbackHost: "localhost"
        )

        #expect(rewrite.requestData.url.absoluteString == "https://staging.example.com:8443/api")
        #expect(rewrite.requestData.headers.first { $0.name == "Host" }?.value == "staging.example.com:8443")
    }

    @Test("Preserve host header keeps the original host authority")
    func preserveHostHeaderKeepsOriginalAuthority() {
        let requestData = makeRequest(url: "http://127.0.0.1:43210/api", headers: [
            HTTPHeader(name: "Host", value: "127.0.0.1:43210"),
        ])
        let head = makeHead(uri: "/api", headers: [("Host", "127.0.0.1:43210")])
        let rewrite = ProxyHandlerShared.buildMapRemoteRewrite(
            configuration: MapRemoteConfiguration(
                scheme: "https",
                host: "httpbin.org",
                preserveHostHeader: true
            ),
            originalHead: head,
            requestData: requestData,
            fallbackScheme: "http",
            fallbackHost: "localhost"
        )

        #expect(rewrite.requestData.url.absoluteString == "https://httpbin.org/api")
        #expect(rewrite.requestData.headers.first { $0.name == "Host" }?.value == "127.0.0.1:43210")
    }

    @Test("HTTPS to HTTP downgrade uses the mapped HTTP target")
    func httpsToHTTPDowngradeRewrite() {
        let requestData = makeRequest(url: "https://api.example.com/v1/users", headers: [
            HTTPHeader(name: "Host", value: "api.example.com"),
        ])
        let head = makeHead(uri: "/v1/users", headers: [("Host", "api.example.com")])
        let rewrite = ProxyHandlerShared.buildMapRemoteRewrite(
            configuration: MapRemoteConfiguration(
                scheme: "HTTP",
                host: "localhost",
                port: 8_080
            ),
            originalHead: head,
            requestData: requestData,
            fallbackScheme: "https",
            fallbackHost: "api.example.com",
            fallbackPort: 443
        )

        #expect(rewrite.scheme == "http")
        #expect(rewrite.upstreamHost == "localhost")
        #expect(rewrite.upstreamPort == 8_080)
        #expect(rewrite.requestData.url.absoluteString == "http://localhost:8080/v1/users")
        #expect(rewrite.head.headers.first(name: "Host") == "localhost:8080")
    }

    @Test("Query override preserves encoding and duplicate keys")
    func queryOverridePreservesEncodingAndDuplicateKeys() {
        let requestData = makeRequest(url: "http://prod.example.com/api?expected=staging")
        let head = makeHead(uri: "/api?expected=staging")
        let rewrite = ProxyHandlerShared.buildMapRemoteRewrite(
            configuration: MapRemoteConfiguration(
                host: "staging.example.com",
                query: "filter=hello%20world&id=1&id=2"
            ),
            originalHead: head,
            requestData: requestData,
            fallbackScheme: "http",
            fallbackHost: "localhost"
        )

        #expect(rewrite.head.uri == "/api?filter=hello%20world&id=1&id=2")
        #expect(URLComponents(url: rewrite.requestData.url, resolvingAgainstBaseURL: false)?.percentEncodedQuery == "filter=hello%20world&id=1&id=2")
    }

    @Test("Matched rule metadata is attached to failed mapped transactions")
    func matchedRuleMetadataAttachedToFailedTransaction() throws {
        let rule = ProxyRule(
            name: "Remote",
            matchCondition: RuleMatchCondition(urlPattern: ".*api\\.example\\.com.*"),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "offline.example.com"))
        )
        let requestData = makeRequest(url: "https://api.example.com/v1")
        let transaction = HTTPTransaction(request: requestData, state: .failed)
        let captured = CapturedTransactionBox()
        let callback = ProxyHandlerShared.makeTransactionCallback(for: rule) {
            captured.transaction = $0
        }

        callback(transaction)

        let result = try #require(captured.transaction)
        #expect(result.matchedRuleID == rule.id)
        #expect(result.matchedRuleName == "Remote")
        #expect(result.matchedRuleActionSummary == "Map Remote")
        #expect(result.matchedRulePattern == ".*api\\.example\\.com.*")
    }

    private func makeRequest(
        method: String = "GET",
        url: String,
        headers: [HTTPHeader] = [],
        body: Data? = nil
    )
        -> HTTPRequestData
    {
        HTTPRequestData(
            method: method,
            // swiftlint:disable:next force_unwrapping
            url: URL(string: url)!,
            httpVersion: "1.1",
            headers: headers,
            body: body
        )
    }

    private func makeHead(
        method: HTTPMethod = .GET,
        uri: String,
        headers: [(String, String)] = []
    )
        -> HTTPRequestHead
    {
        var head = HTTPRequestHead(version: .http1_1, method: method, uri: uri)
        for (name, value) in headers {
            head.headers.add(name: name, value: value)
        }
        return head
    }
}

private final class CapturedTransactionBox: @unchecked Sendable {
    var transaction: HTTPTransaction?
}
