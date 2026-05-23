import Foundation

// MARK: - UpstreamProxyTestResult

struct UpstreamProxyTestResult: Equatable {
    let targetHost: String
    let targetPort: Int
    let negotiatedType: UpstreamProxyType?
    let duration: Duration
}
