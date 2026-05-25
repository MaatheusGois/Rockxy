import CFNetwork
import Foundation
import NIOCore

// MARK: - UpstreamPACRoute

enum UpstreamPACRoute: Equatable {
    case direct
    case proxy(type: UpstreamProxyType, host: String, port: Int)

    // MARK: Internal

    var displayName: String {
        switch self {
        case .direct:
            String(localized: "DIRECT")
        case let .proxy(type, host, port):
            "\(type.displayName) \(host):\(port)"
        }
    }
}

typealias UpstreamPACResolverFunction = @Sendable (
    EventLoop,
    URL,
    String,
    String,
    Int
) -> EventLoopFuture<UpstreamPACRoute>

// MARK: - UpstreamPACResolver

nonisolated enum UpstreamPACResolver {
    // MARK: Internal

    static func resolve(
        eventLoop: EventLoop,
        pacURL: URL,
        targetScheme: String,
        targetHost: String,
        targetPort: Int
    )
        -> EventLoopFuture<UpstreamPACRoute>
    {
        guard let targetURL = makeTargetURL(scheme: targetScheme, host: targetHost, port: targetPort) else {
            return eventLoop.makeFailedFuture(UpstreamProxyError.pacTargetURLInvalid)
        }

        let promise = eventLoop.makePromise(of: UpstreamPACRoute.self)
        let box = PACEvaluationBox(eventLoop: eventLoop, promise: promise)
        let retainedBox = Unmanaged.passRetained(box)
        var context = CFStreamClientContext(
            version: 0,
            info: retainedBox.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let source = CFNetworkExecuteProxyAutoConfigurationURL(
            pacURL as CFURL,
            targetURL as CFURL,
            upstreamPACResolverCallback,
            &context
        )

        box.setSource(source)
        let timeoutTask = eventLoop.scheduleTask(in: ProxyTimeouts.upstreamPACResolution) {
            box.complete(.failure(.timeout))
        }
        promise.futureResult.whenComplete { _ in
            timeoutTask.cancel()
        }

        DispatchQueue.global(qos: .utility).async {
            guard let runLoop = CFRunLoopGetCurrent() else {
                box.complete(.failure(.pacEvaluationFailed(String(localized: "Unable to start PAC evaluation."))))
                retainedBox.release()
                return
            }
            box.setRunLoop(runLoop)
            CFRunLoopAddSource(runLoop, source, .defaultMode)
            if !box.isCompleted {
                CFRunLoopRun()
            }
            retainedBox.release()
        }

        return promise.futureResult
    }

    static func route(from proxies: [NSDictionary]) -> Result<UpstreamPACRoute, UpstreamProxyError> {
        for proxy in proxies {
            guard let proxyType = stringValue(proxy[kCFProxyTypeKey]) else {
                continue
            }
            if proxyType == kCFProxyTypeNone as String {
                return .success(.direct)
            } else if proxyType == kCFProxyTypeHTTP as String {
                if let route = proxyRoute(type: .http, proxy: proxy) {
                    return .success(route)
                }
            } else if proxyType == kCFProxyTypeHTTPS as String {
                if let route = proxyRoute(type: .https, proxy: proxy) {
                    return .success(route)
                }
            } else if proxyType == kCFProxyTypeSOCKS as String {
                if let route = proxyRoute(type: .socks5, proxy: proxy) {
                    return .success(route)
                }
            }
        }
        return .failure(.pacNoSupportedRoute)
    }

    // MARK: Private

    private static func makeTargetURL(scheme: String, host: String, port: Int) -> URL? {
        var components = URLComponents()
        components.scheme = normalizedScheme(scheme)
        components.host = host
        components.port = port
        components.path = "/"
        return components.url
    }

    private static func normalizedScheme(_ scheme: String) -> String {
        switch scheme.lowercased() {
        case "ws":
            "http"
        case "wss":
            "https"
        default:
            scheme.lowercased()
        }
    }

    private static func proxyRoute(type: UpstreamProxyType, proxy: NSDictionary) -> UpstreamPACRoute? {
        guard let host = stringValue(proxy[kCFProxyHostNameKey]),
              let port = intValue(proxy[kCFProxyPortNumberKey]),
              port > 0,
              port <= 65_535 else
        {
            return nil
        }
        return .proxy(type: type, host: host, port: port)
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }
}

// MARK: - PACEvaluationBox

private final class PACEvaluationBox: @unchecked Sendable {
    // MARK: Lifecycle

    init(eventLoop: EventLoop, promise: EventLoopPromise<UpstreamPACRoute>) {
        self.eventLoop = eventLoop
        self.promise = promise
    }

    // MARK: Internal

    var isCompleted: Bool {
        lock.lock()
        let value = completed
        lock.unlock()
        return value
    }

    func setSource(_ source: CFRunLoopSource) {
        lock.lock()
        self.source = source
        lock.unlock()
    }

    func setRunLoop(_ runLoop: CFRunLoop) {
        lock.lock()
        self.runLoop = runLoop
        lock.unlock()
    }

    func complete(_ result: Result<UpstreamPACRoute, UpstreamProxyError>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let source = source
        let runLoop = runLoop
        lock.unlock()

        if let source {
            CFRunLoopSourceInvalidate(source)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }

        eventLoop.execute {
            switch result {
            case let .success(route):
                self.promise.succeed(route)
            case let .failure(error):
                self.promise.fail(error)
            }
        }
    }

    // MARK: Private

    private let eventLoop: EventLoop
    private let promise: EventLoopPromise<UpstreamPACRoute>
    private let lock = NSLock()
    private var completed = false
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
}

private func upstreamPACResolverCallback(
    _ client: UnsafeMutableRawPointer,
    _ proxyList: CFArray?,
    _ error: CFError?
) {
    let box = Unmanaged<PACEvaluationBox>.fromOpaque(client).takeUnretainedValue()
    if let error {
        let message = CFErrorCopyDescription(error) as String? ?? String(localized: "Unknown PAC error")
        box.complete(.failure(.pacEvaluationFailed(message)))
        return
    }
    let proxies = (proxyList as? [NSDictionary]) ?? []
    box.complete(UpstreamPACResolver.route(from: proxies))
}
