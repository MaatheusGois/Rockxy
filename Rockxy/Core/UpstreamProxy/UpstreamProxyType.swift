import Foundation

// MARK: - UpstreamProxyType

enum UpstreamProxyType: String, Codable, CaseIterable {
    case http
    case https
    case socks5

    // MARK: Internal

    var displayName: String {
        switch self {
        case .http:
            String(localized: "HTTP")
        case .https:
            String(localized: "HTTPS")
        case .socks5:
            String(localized: "SOCKS5")
        }
    }
}
