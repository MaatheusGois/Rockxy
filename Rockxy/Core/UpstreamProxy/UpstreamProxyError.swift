import Foundation

// MARK: - UpstreamProxyError

enum UpstreamProxyError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case authenticationRequired
    case authenticationRejected
    case connectRejected(statusCode: Int)
    case malformedResponse
    case responseTooLarge
    case unsupportedSOCKS5AuthMethod(UInt8)
    case socks5Reply(SOCKS5Reply)
    case targetHostTooLong
    case pacURLInvalid
    case pacTargetURLInvalid
    case pacEvaluationFailed(String)
    case pacNoSupportedRoute
    case pacSOCKS5Unavailable
    case timeout

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            message
        case .authenticationRequired:
            String(localized: "Upstream proxy authentication is required.")
        case .authenticationRejected:
            String(localized: "Upstream proxy authentication was rejected.")
        case let .connectRejected(statusCode):
            String(localized: "Upstream proxy CONNECT failed with HTTP \(statusCode).")
        case .malformedResponse:
            String(localized: "Upstream proxy returned a malformed response.")
        case .responseTooLarge:
            String(localized: "Upstream proxy handshake response exceeded the size limit.")
        case let .unsupportedSOCKS5AuthMethod(method):
            String(localized: "SOCKS5 proxy selected unsupported authentication method \(method).")
        case let .socks5Reply(reply):
            reply.errorDescription
        case .targetHostTooLong:
            String(localized: "SOCKS5 target host is too long.")
        case .pacURLInvalid:
            String(localized: "Automatic proxy configuration URL is invalid.")
        case .pacTargetURLInvalid:
            String(localized: "Automatic proxy configuration target URL is invalid.")
        case let .pacEvaluationFailed(message):
            String(localized: "Automatic proxy configuration failed: \(message)")
        case .pacNoSupportedRoute:
            String(localized: "Automatic proxy configuration did not return a supported proxy route.")
        case .pacSOCKS5Unavailable:
            String(localized: "Automatic proxy configuration selected SOCKS5, which is unavailable in this build.")
        case .timeout:
            String(localized: "Upstream proxy connection timed out.")
        }
    }
}

// MARK: - SOCKS5Reply

enum SOCKS5Reply: UInt8, CaseIterable {
    case succeeded = 0x00
    case generalFailure = 0x01
    case connectionNotAllowed = 0x02
    case networkUnreachable = 0x03
    case hostUnreachable = 0x04
    case connectionRefused = 0x05
    case ttlExpired = 0x06
    case commandNotSupported = 0x07
    case addressTypeNotSupported = 0x08

    // MARK: Lifecycle

    init(code: UInt8) {
        self = Self(rawValue: code) ?? .generalFailure
    }

    // MARK: Internal

    var errorDescription: String {
        switch self {
        case .succeeded:
            String(localized: "SOCKS5 proxy connection succeeded.")
        case .generalFailure:
            String(localized: "SOCKS5 proxy reported a general failure.")
        case .connectionNotAllowed:
            String(localized: "SOCKS5 proxy rejected the connection by rule.")
        case .networkUnreachable:
            String(localized: "SOCKS5 proxy could not reach the network.")
        case .hostUnreachable:
            String(localized: "SOCKS5 proxy could not reach the host.")
        case .connectionRefused:
            String(localized: "SOCKS5 target connection was refused.")
        case .ttlExpired:
            String(localized: "SOCKS5 target connection TTL expired.")
        case .commandNotSupported:
            String(localized: "SOCKS5 proxy does not support CONNECT.")
        case .addressTypeNotSupported:
            String(localized: "SOCKS5 proxy does not support domain-name targets.")
        }
    }
}
