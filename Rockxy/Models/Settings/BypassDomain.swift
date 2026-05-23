import Foundation

/// A domain entry in the Bypass Proxy List.
/// Domains matching these patterns are excluded from Rockxy's system proxy.
/// Supports exact matches and wildcard prefixes (e.g., `*.local`).
struct BypassDomain: Identifiable, Codable, Hashable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), domain: String, isEnabled: Bool = true) {
        self.id = id
        self.domain = domain
        self.isEnabled = isEnabled
    }

    // MARK: Internal

    let id: UUID
    var domain: String
    var isEnabled: Bool

    /// Checks whether the given host matches this bypass domain pattern.
    ///
    /// - Wildcard: `*.local` matches `myhost.local`, `sub.myhost.local`
    /// - Exact: `localhost` matches only `localhost`
    func matches(_ host: String) -> Bool {
        HostPatternMatcher.matches(host: host, pattern: domain, extendedWildcards: false)
    }
}
