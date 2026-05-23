import Foundation

// MARK: - AppPolicyViolation

enum AppPolicyViolation: LocalizedError, Equatable {
    case upstreamProxySOCKS5Unavailable
    case upstreamProxyAuthenticationUnavailable
    case upstreamProxyBypassEntryLimitReached(limit: Int)
    case protobufSchemaUploadUnavailable
    case protobufSchemaLimitReached(limit: Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .upstreamProxySOCKS5Unavailable:
            String(localized: "SOCKS5 upstream proxy is unavailable in this build.")
        case .upstreamProxyAuthenticationUnavailable:
            String(localized: "Upstream proxy authentication is unavailable in this build.")
        case let .upstreamProxyBypassEntryLimitReached(limit):
            String(localized: "Upstream proxy bypass list is limited to \(limit) entries in this build.")
        case .protobufSchemaUploadUnavailable:
            String(localized: "Protobuf schema upload is unavailable in this build.")
        case let .protobufSchemaLimitReached(limit):
            String(localized: "Protobuf schema storage is limited to \(limit) schemas in this build.")
        }
    }
}
