import Foundation

// MARK: - UpstreamProxyConfigurationError

enum UpstreamProxyConfigurationError: LocalizedError, Equatable {
    case hostInvalid
    case portOutOfRange
    case usernameTooLong
    case passwordTooLong
    case bypassPatternInvalid(String)
    case tooManyBypassEntries(limit: Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .hostInvalid:
            String(localized: "Upstream proxy host is invalid.")
        case .portOutOfRange:
            String(localized: "Upstream proxy port must be between 1 and 65535.")
        case .usernameTooLong:
            String(localized: "Upstream proxy username must be 255 bytes or fewer.")
        case .passwordTooLong:
            String(localized: "Upstream proxy password must be 255 bytes or fewer.")
        case let .bypassPatternInvalid(pattern):
            String(localized: "Upstream proxy bypass pattern is invalid: \(pattern)")
        case let .tooManyBypassEntries(limit):
            String(localized: "Upstream proxy bypass list is limited to \(limit) entries.")
        }
    }
}
