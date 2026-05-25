import CFNetwork
import Foundation
@testable import Rockxy
import Testing

@Suite("UpstreamPACResolver")
struct UpstreamPACResolverTests {
    @Test("maps DIRECT PAC result")
    func directRoute() throws {
        let result = UpstreamPACResolver.route(from: [
            proxy(type: kCFProxyTypeNone as String)
        ])

        #expect(try result.get() == .direct)
    }

    @Test("maps HTTP, HTTPS, and SOCKS PAC proxy results")
    func proxyRoutes() throws {
        let http = UpstreamPACResolver.route(from: [
            proxy(type: kCFProxyTypeHTTP as String, host: "proxy.example.com", port: 8_080)
        ])
        #expect(try http.get() == .proxy(type: .http, host: "proxy.example.com", port: 8_080))

        let https = UpstreamPACResolver.route(from: [
            proxy(type: kCFProxyTypeHTTPS as String, host: "secure-proxy.example.com", port: 8_443)
        ])
        #expect(try https.get() == .proxy(type: .https, host: "secure-proxy.example.com", port: 8_443))

        let socks = UpstreamPACResolver.route(from: [
            proxy(type: kCFProxyTypeSOCKS as String, host: "socks.example.com", port: 1_080)
        ])
        #expect(try socks.get() == .proxy(type: .socks5, host: "socks.example.com", port: 1_080))
    }

    @Test("uses first supported PAC route")
    func firstSupportedRoute() throws {
        let result = UpstreamPACResolver.route(from: [
            proxy(type: "FTP", host: "unsupported.example.com", port: 21),
            proxy(type: kCFProxyTypeHTTP as String, host: "proxy.example.com", port: 8_080),
            proxy(type: kCFProxyTypeHTTPS as String, host: "secure-proxy.example.com", port: 8_443)
        ])

        #expect(try result.get() == .proxy(type: .http, host: "proxy.example.com", port: 8_080))
    }

    @Test("fails when PAC result has no supported route")
    func noSupportedRoute() {
        let missingHost = UpstreamPACResolver.route(from: [
            proxy(type: kCFProxyTypeHTTP as String, host: nil, port: 8_080)
        ])
        #expect(throws: UpstreamProxyError.pacNoSupportedRoute) {
            try missingHost.get()
        }

        let invalidPort = UpstreamPACResolver.route(from: [
            proxy(type: kCFProxyTypeHTTP as String, host: "proxy.example.com", port: 0)
        ])
        #expect(throws: UpstreamProxyError.pacNoSupportedRoute) {
            try invalidPort.get()
        }
    }

    private func proxy(type: String, host: String? = nil, port: Int? = nil) -> NSDictionary {
        let dictionary = NSMutableDictionary()
        dictionary[kCFProxyTypeKey] = type
        if let host {
            dictionary[kCFProxyHostNameKey] = host
        }
        if let port {
            dictionary[kCFProxyPortNumberKey] = NSNumber(value: port)
        }
        return dictionary
    }
}
