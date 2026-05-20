import Foundation
import NIOHTTP1
import os

nonisolated(unsafe) private let proxyHandlerSharedLogger = Logger(
    subsystem: RockxyIdentity.current.logSubsystem,
    category: "ProxyHandlerShared"
)

// MARK: - ProxyHandlerShared

/// Shared utilities extracted from HTTPProxyHandler and HTTPSProxyRelayHandler
/// to eliminate duplication. Only proven, identical seams are extracted here.
enum ProxyHandlerShared {
    // MARK: Internal

    struct MapRemoteRewrite {
        let head: HTTPRequestHead
        let requestData: HTTPRequestData
        let upstreamHost: String
        let upstreamPort: Int
        let scheme: String
    }

    /// Decision returned by `oversizeRelayDecision` when a response body chunk
    /// pushes the capture buffer past the cap. Drives both the script-deferral
    /// flush logic and the response-breakpoint preservation.
    enum OversizeRelayDecision: Equatable {
        /// Continue buffering for the breakpoint UI, do not flush. Reached when
        /// a response breakpoint is armed even if the script hook was deferring.
        case keepBufferingForBreakpoint
        /// Flush the buffered head + body to the client and resume streaming.
        /// Reached when scripting was deferring but no breakpoint is in play.
        case flushBufferedAndResumeStreaming
        /// Streaming was already happening (no script defer, no breakpoint defer);
        /// nothing to flush, just continue.
        case alreadyStreaming
    }

    /// Pure helper that codifies the truncation-branch decision in
    /// `UpstreamResponseHandler.channelRead(.body)`. Extracted so the behavior
    /// can be unit-tested without a full NIO channel test harness.
    nonisolated static func oversizeRelayDecision(
        deferRelayForScript: Bool,
        shouldBreakOnResponse: Bool
    )
        -> OversizeRelayDecision
    {
        if deferRelayForScript, shouldBreakOnResponse {
            return .keepBufferingForBreakpoint
        }
        if deferRelayForScript {
            return .flushBufferedAndResumeStreaming
        }
        return .alreadyStreaming
    }

    /// Determines whether the next response body chunk should be captured or dropped.
    /// Returns `true` if the buffer is already at or past the capture limit.
    nonisolated static func shouldTruncateCapture(
        currentBufferSize: Int,
        incomingChunkSize: Int,
        maxSize: Int = ProxyLimits.maxResponseBodySize
    )
        -> Bool
    {
        currentBufferSize + incomingChunkSize > maxSize
    }

    /// Wraps a downstream transaction callback with matched-rule metadata injection.
    /// Used by both HTTP and HTTPS handlers to decorate transactions before delivery.
    nonisolated static func makeTransactionCallback(
        for matchedRule: ProxyRule?,
        downstream: @escaping @Sendable (HTTPTransaction) -> Void
    )
        -> @Sendable (HTTPTransaction) -> Void
    {
        let matchedRuleID = matchedRule?.id
        let matchedRuleName = matchedRule?.name
        let matchedRuleActionSummary = matchedRule?.action.matchedRuleActionSummary
        let matchedRulePattern = matchedRule?.matchCondition.urlPattern

        return { transaction in
            transaction.matchedRuleID = matchedRuleID
            transaction.matchedRuleName = matchedRuleName
            transaction.matchedRuleActionSummary = matchedRuleActionSummary
            transaction.matchedRulePattern = matchedRulePattern
            downstream(transaction)
        }
    }

    /// Rebuild the outbound `HTTPRequestHead` from a (possibly script-mutated)
    /// `HTTPRequestData`, scoped to the safe mutation kinds: method, origin-form
    /// path + query, headers, and a recomputed `Content-Length` when the original
    /// carried one.
    ///
    /// Host / port / scheme changes are intentionally NOT propagated here — those
    /// are discarded during `ScriptRequestContext.apply(to:pluginID:)` before
    /// this function ever sees the request. Cross-host rewrite remains the
    /// responsibility of the `MapRemote` rule action.
    ///
    /// `Transfer-Encoding: chunked` bodies keep their chunked framing; no
    /// `Content-Length` is added. Requests that originally had `Content-Length`
    /// get it recomputed from `requestData.body?.count ?? 0`.
    nonisolated static func buildForwardHead(
        from requestData: HTTPRequestData,
        originalHead: HTTPRequestHead
    )
        -> HTTPRequestHead
    {
        let resolvedMethod: HTTPMethod
        if HTTPMethodRawValues.contains(requestData.method.uppercased()) {
            resolvedMethod = HTTPMethod(rawValue: requestData.method.uppercased())
        } else {
            warnOnce(kind: "invalid-method", details: "\(requestData.method)")
            resolvedMethod = originalHead.method
        }

        let uri: String
        let path = requestData.url.path.isEmpty ? "/" : requestData.url.path
        if let query = requestData.url.query, !query.isEmpty {
            uri = "\(path)?\(query)"
        } else {
            uri = path
        }

        var headers = HTTPHeaders(requestData.headers.map { ($0.name, $0.value) })

        // Framing policy: scripts may have mutated the body, so we must always
        // make the framing reflect the actual outgoing bytes:
        //
        // - Chunked uploads: drop any Content-Length (they're mutually exclusive
        //   per RFC 9112 §6) and keep the chunked framing.
        // - Otherwise: write Content-Length matching the mutated body size,
        //   even if the original request had no body / no Content-Length. This
        //   prevents downstream servers from hanging on a missing length when a
        //   script added a body to a previously bodyless request.
        let isChunked = headers["Transfer-Encoding"].contains(where: {
            $0.lowercased().contains("chunked")
        })
        if isChunked {
            headers.remove(name: "Content-Length")
        } else {
            let size = requestData.body?.count ?? 0
            headers.replaceOrAdd(name: "Content-Length", value: "\(size)")
        }

        return HTTPRequestHead(
            version: originalHead.version,
            method: resolvedMethod,
            uri: uri,
            headers: headers
        )
    }

    nonisolated static func buildMapRemoteRewrite(
        configuration: MapRemoteConfiguration,
        originalHead: HTTPRequestHead,
        requestData: HTTPRequestData,
        fallbackScheme: String,
        fallbackHost: String,
        fallbackPort: Int? = nil
    )
        -> MapRemoteRewrite
    {
        let originalURL = requestData.url
        let schemeOverride = normalizedScheme(configuration.scheme)
        let originalScheme = normalizedScheme(originalURL.scheme) ?? fallbackScheme.lowercased()
        let scheme = schemeOverride ?? originalScheme
        let upstreamHost = configuration.host ?? (originalURL.host ?? fallbackHost)
        let upstreamPort = resolvedMapRemotePort(
            configuration: configuration,
            schemeOverride: schemeOverride,
            scheme: scheme,
            originalURL: originalURL,
            fallbackPort: fallbackPort
        )
        let remotePath = configuration.path ?? originalURL.path
        let remoteQuery = configuration.query ?? originalURL.query

        let effectivePath = remotePath.isEmpty ? "/" : remotePath
        let encodedQuery = remoteQuery.flatMap(percentEncodedQuery)
        let uri = encodedQuery.map { "\(effectivePath)?\($0)" } ?? effectivePath

        var modifiedHead = originalHead
        modifiedHead.uri = configuration.preserveOriginalURL ? originalHead.uri : uri

        let hostHeaderValue: String
        if configuration.preserveHostHeader {
            hostHeaderValue = originalHead.headers.first(name: "Host")
                ?? hostHeader(host: originalURL.host ?? fallbackHost, port: originalURL.port ?? fallbackPort, scheme: originalScheme)
        } else {
            hostHeaderValue = hostHeader(host: upstreamHost, port: upstreamPort, scheme: scheme)
        }
        modifiedHead.headers.replaceOrAdd(name: "Host", value: NetworkValidator.sanitizeHeaderValue(hostHeaderValue))

        let urlString = mapRemoteURLString(
            scheme: scheme,
            host: upstreamHost,
            port: upstreamPort,
            pathAndQuery: uri
        )

        // swiftlint:disable:next force_unwrapping
        let fallbackURL = URL(string: "\(fallbackScheme.lowercased())://localhost/")!
        let modifiedData = HTTPRequestData(
            method: requestData.method,
            url: URL(string: urlString) ?? fallbackURL,
            httpVersion: requestData.httpVersion,
            headers: modifiedHead.headers.map { HTTPHeader(name: $0.name, value: $0.value) },
            body: requestData.body,
            contentType: requestData.contentType
        )

        return MapRemoteRewrite(
            head: modifiedHead,
            requestData: modifiedData,
            upstreamHost: upstreamHost,
            upstreamPort: upstreamPort,
            scheme: scheme
        )
    }

    /// Rebuild the outbound response head from a script-mutated `HTTPResponseData`.
    ///
    /// The relay path sends the full mutated body in a fixed-length write, so
    /// any stale `Transfer-Encoding` is removed and `Content-Length` is replaced
    /// with the actual mutated body size.
    nonisolated static func buildRelayResponseHead(
        from responseData: HTTPResponseData,
        originalHead: HTTPResponseHead?
    )
        -> HTTPResponseHead
    {
        let status = HTTPResponseStatus(statusCode: responseData.statusCode)
        var head = HTTPResponseHead(
            version: originalHead?.version ?? .http1_1,
            status: status
        )
        head.headers = HTTPHeaders(responseData.headers.map { ($0.name, $0.value) })

        let bodySize = responseData.body?.count ?? 0
        head.headers.remove(name: "Transfer-Encoding")
        head.headers.replaceOrAdd(name: "Content-Length", value: "\(bodySize)")
        return head
    }

    // MARK: Private

    /// Lowercase set of RFC-defined methods we accept from scripts.
    nonisolated private static let HTTPMethodRawValues: Set<String> = [
        "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE", "CONNECT",
    ]

    nonisolated(unsafe) private static var warned: Set<String> = []
    private static let warnedLock = NSLock()

    private static func warnOnce(kind: String, details: String) {
        let key = "\(kind)|\(details)"
        warnedLock.lock()
        defer { warnedLock.unlock() }
        guard !warned.contains(key) else {
            return
        }
        warned.insert(key)
        proxyHandlerSharedLogger.warning("buildForwardHead: \(kind) \(details)")
    }

    private static func normalizedScheme(_ scheme: String?) -> String? {
        guard let scheme = scheme?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scheme.isEmpty else
        {
            return nil
        }
        return scheme.lowercased()
    }

    private static func resolvedMapRemotePort(
        configuration: MapRemoteConfiguration,
        schemeOverride: String?,
        scheme: String,
        originalURL: URL,
        fallbackPort: Int?
    )
        -> Int
    {
        if let port = configuration.port {
            return port
        }
        if schemeOverride == nil {
            return originalURL.port ?? fallbackPort ?? defaultPort(for: scheme)
        }
        return defaultPort(for: scheme)
    }

    private static func defaultPort(for scheme: String) -> Int {
        switch scheme.lowercased() {
        case "https", "wss":
            443
        default:
            80
        }
    }

    private static func isDefaultPort(_ port: Int, for scheme: String) -> Bool {
        port == defaultPort(for: scheme)
    }

    private static func hostHeader(host: String, port: Int?, scheme: String) -> String {
        guard let port, !isDefaultPort(port, for: scheme) else {
            return host
        }
        return "\(hostForAuthority(host)):\(port)"
    }

    private static func hostForAuthority(_ host: String) -> String {
        if host.contains(":"), !host.hasPrefix("["), !host.hasSuffix("]") {
            return "[\(host)]"
        }
        return host
    }

    private static func mapRemoteURLString(
        scheme: String,
        host: String,
        port: Int,
        pathAndQuery: String
    )
        -> String
    {
        var urlString = "\(scheme)://\(hostForAuthority(host))"
        if !isDefaultPort(port, for: scheme) {
            urlString += ":\(port)"
        }
        urlString += pathAndQuery
        return urlString
    }

    private static func percentEncodedQuery(_ query: String) -> String? {
        guard !query.isEmpty else {
            return query
        }
        if let components = URLComponents(string: "https://rockxy.invalid/?\(query)"),
           let encoded = components.percentEncodedQuery
        {
            return encoded
        }
        return query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    }
}
