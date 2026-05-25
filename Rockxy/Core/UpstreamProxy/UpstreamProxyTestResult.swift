import Foundation

// MARK: - UpstreamProxyTestResult

struct UpstreamProxyTestResult: Equatable {
    // MARK: Lifecycle

    init(
        targetHost: String,
        targetPort: Int,
        negotiatedType: UpstreamProxyType?,
        duration: Duration,
        resolvedPACRoute: UpstreamPACRoute? = nil
    ) {
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.negotiatedType = negotiatedType
        self.duration = duration
        self.resolvedPACRoute = resolvedPACRoute
    }

    // MARK: Internal

    let targetHost: String
    let targetPort: Int
    let negotiatedType: UpstreamProxyType?
    let duration: Duration
    let resolvedPACRoute: UpstreamPACRoute?
}
