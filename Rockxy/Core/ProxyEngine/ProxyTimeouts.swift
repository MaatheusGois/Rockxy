import NIOCore

// MARK: - ProxyTimeouts

nonisolated enum ProxyTimeouts {
    static let upstreamConnect: TimeAmount = .seconds(10)
    static let upstreamHandshake: TimeAmount = .seconds(10)
    static let upstreamPACResolution: TimeAmount = .seconds(10)
    static let outboundConnect: TimeAmount = .seconds(5)
}
