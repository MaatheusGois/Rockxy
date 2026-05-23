import Foundation

// MARK: - UpstreamProxyResolvedConfiguration

struct UpstreamProxyResolvedConfiguration: Equatable {
    let configuration: UpstreamProxyConfiguration
    let credentials: UpstreamProxyCredentials?

    var isEnabled: Bool {
        configuration.isEnabled
    }

    func shouldBypass(targetHost: String) -> Bool {
        if configuration.bypassLocalhost, HostPatternMatcher.isLocalhost(targetHost) {
            return true
        }
        return configuration.bypassHostPatterns.contains {
            HostPatternMatcher.matches(host: targetHost, pattern: $0)
        }
    }
}
