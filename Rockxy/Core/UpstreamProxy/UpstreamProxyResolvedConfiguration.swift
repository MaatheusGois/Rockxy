import Foundation

// MARK: - UpstreamProxyResolvedConfiguration

struct UpstreamProxyResolvedConfiguration: Equatable {
    // MARK: Lifecycle

    init(
        configuration: UpstreamProxyConfiguration,
        credentials: UpstreamProxyCredentials?,
        allowsSOCKS5: Bool = false
    ) {
        self.configuration = configuration
        self.credentials = credentials
        self.allowsSOCKS5 = allowsSOCKS5
    }

    // MARK: Internal

    let configuration: UpstreamProxyConfiguration
    let credentials: UpstreamProxyCredentials?
    let allowsSOCKS5: Bool

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
