import Foundation

// MARK: - UpstreamProxyConfiguration

struct UpstreamProxyConfiguration: Codable, Equatable {
    // MARK: Lifecycle

    init(
        isEnabled: Bool = false,
        type: UpstreamProxyType = .http,
        host: String = "",
        port: Int = 8_080,
        pacURL: String? = nil,
        hasCredentials: Bool = false,
        username: String? = nil,
        bypassHostPatterns: [String] = [],
        bypassLocalhost: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.type = type
        self.host = host
        self.port = port
        self.pacURL = pacURL
        self.hasCredentials = hasCredentials
        self.username = username
        self.bypassHostPatterns = bypassHostPatterns
        self.bypassLocalhost = bypassLocalhost
    }

    // MARK: Internal

    static let disabled = UpstreamProxyConfiguration()

    var isEnabled: Bool
    var type: UpstreamProxyType
    var host: String
    var port: Int
    var pacURL: String?
    var hasCredentials: Bool
    var username: String?
    var bypassHostPatterns: [String]
    var bypassLocalhost: Bool

    var resolvedPACURL: URL? {
        guard let pacURL else {
            return nil
        }
        return URL(string: pacURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func validate(
        credentials: UpstreamProxyCredentials? = nil,
        bypassEntryLimit: Int? = nil
    )
        throws
    {
        if type == .automatic {
            if isEnabled {
                try validatePACURL()
            }
        } else {
            guard port > 0, port <= 65_535 else {
                throw UpstreamProxyConfigurationError.portOutOfRange
            }

            if isEnabled {
                guard Self.isValidHost(host) else {
                    throw UpstreamProxyConfigurationError.hostInvalid
                }
            }
        }

        if let username, username.utf8.count > 255 {
            throw UpstreamProxyConfigurationError.usernameTooLong
        }
        if let credentials {
            if credentials.username.utf8.count > 255 {
                throw UpstreamProxyConfigurationError.usernameTooLong
            }
            if credentials.password.utf8.count > 255 {
                throw UpstreamProxyConfigurationError.passwordTooLong
            }
        }

        let normalizedPatterns = bypassHostPatterns.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for pattern in normalizedPatterns where !HostPatternMatcher.isValid(pattern: pattern) {
            throw UpstreamProxyConfigurationError.bypassPatternInvalid(pattern)
        }

        if let bypassEntryLimit, normalizedPatterns.count > bypassEntryLimit {
            throw UpstreamProxyConfigurationError.tooManyBypassEntries(limit: bypassEntryLimit)
        }
    }

    // MARK: Private

    private func validatePACURL() throws {
        guard let pacURL,
              !pacURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else
        {
            throw UpstreamProxyConfigurationError.pacURLRequired
        }
        guard let url = resolvedPACURL,
              let scheme = url.scheme?.lowercased(),
              !scheme.isEmpty else
        {
            throw UpstreamProxyConfigurationError.pacURLInvalid
        }
        guard scheme == "http" || scheme == "https" else {
            throw UpstreamProxyConfigurationError.pacURLUnsupportedScheme
        }
        guard url.host?.isEmpty == false else {
            throw UpstreamProxyConfigurationError.pacURLInvalid
        }
    }

    private static func isValidHost(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 253 else {
            return false
        }
        guard !trimmed.contains("://"),
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains("@") else
        {
            return false
        }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x21 && scalar.value != 0x7F && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }
}
