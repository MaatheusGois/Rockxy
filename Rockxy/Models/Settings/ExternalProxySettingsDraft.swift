import Foundation

// MARK: - ExternalProxyProtocolSelection

enum ExternalProxyProtocolSelection: CaseIterable, Identifiable {
    case automatic
    case http
    case https
    case socks5

    // MARK: Lifecycle

    init(_ type: UpstreamProxyType) {
        switch type {
        case .http:
            self = .http
        case .https:
            self = .https
        case .socks5:
            self = .socks5
        }
    }

    // MARK: Internal

    var id: String {
        rawIdentifier
    }

    var rawIdentifier: String {
        switch self {
        case .automatic:
            "automatic"
        case .http:
            "http"
        case .https:
            "https"
        case .socks5:
            "socks5"
        }
    }

    var displayName: String {
        switch self {
        case .automatic:
            String(localized: "Automatic Proxy Configuration")
        case .http:
            String(localized: "Web Proxy (HTTP)")
        case .https:
            String(localized: "Secure Web Proxy (HTTPS)")
        case .socks5:
            String(localized: "SOCKS Proxy")
        }
    }

    var proxyType: UpstreamProxyType? {
        switch self {
        case .automatic:
            nil
        case .http:
            .http
        case .https:
            .https
        case .socks5:
            .socks5
        }
    }

    func canPersist(using policy: any AppPolicy) -> Bool {
        switch self {
        case .automatic:
            false
        case .socks5:
            policy.upstreamProxyAllowsSOCKS5
        case .http,
             .https:
            true
        }
    }
}

// MARK: - ExternalProxySettingsDraft

struct ExternalProxySettingsDraft: Equatable {
    var isEnabled = false
    var selectedProtocol: ExternalProxyProtocolSelection = .http
    var host = ""
    var portText = "8080"
    var pacURL = ""
    var usesAuthentication = false
    var username = ""
    var password = ""
    var bypassText = ""
    var bypassLocalhost = true

    var parsedBypassPatterns: [String] {
        bypassText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func configuration() throws -> UpstreamProxyConfiguration {
        guard let type = selectedProtocol.proxyType else {
            throw ExternalProxySettingsDraftError.automaticProxyConfigurationUnsupported
        }
        let parsedPort = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return UpstreamProxyConfiguration(
            isEnabled: isEnabled,
            type: type,
            host: host,
            port: parsedPort,
            hasCredentials: usesAuthentication,
            username: usesAuthentication ? username : nil,
            bypassHostPatterns: parsedBypassPatterns,
            bypassLocalhost: bypassLocalhost
        )
    }

    func credentials() -> UpstreamProxyCredentials? {
        guard usesAuthentication else {
            return nil
        }
        return UpstreamProxyCredentials(username: username, password: password)
    }
}

// MARK: - ExternalProxySettingsDraftError

enum ExternalProxySettingsDraftError: Error, Equatable, LocalizedError {
    case automaticProxyConfigurationUnsupported

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .automaticProxyConfigurationUnsupported:
            String(localized: "Automatic proxy configuration is not supported yet.")
        }
    }
}
