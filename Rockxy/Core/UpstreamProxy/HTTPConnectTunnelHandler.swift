import Foundation
import NIOCore

// MARK: - HTTPConnectTunnelHandler

final class HTTPConnectTunnelHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        targetHost: String,
        targetPort: Int,
        credentials: UpstreamProxyCredentials?,
        completionPromise: EventLoopPromise<Void>
    ) {
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.credentials = credentials
        self.completionPromise = completionPromise
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    func handlerAdded(context: ChannelHandlerContext) {
        var request = "CONNECT \(targetHost):\(targetPort) HTTP/1.1\r\n"
        request += "Host: \(targetHost):\(targetPort)\r\n"
        request += "Proxy-Connection: Keep-Alive\r\n"
        if let credentials {
            let rawValue = "\(credentials.username):\(credentials.password)"
            let encoded = Data(rawValue.utf8).base64EncodedString()
            request += "Proxy-Authorization: Basic \(encoded)\r\n"
        }
        request += "\r\n"

        var buffer = context.channel.allocator.buffer(capacity: request.utf8.count)
        buffer.writeString(request)
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        guard let chunk = incoming.readString(length: incoming.readableBytes) else {
            fail(context: context, error: UpstreamProxyError.malformedResponse)
            return
        }
        responseBuffer += chunk

        guard responseBuffer.utf8.count <= ProxyLimits.maxUpstreamHandshakeResponseSize else {
            fail(context: context, error: UpstreamProxyError.responseTooLarge)
            return
        }

        guard let headerEnd = responseBuffer.range(of: "\r\n\r\n") else {
            return
        }

        let responseHead = String(responseBuffer[..<headerEnd.lowerBound])
        let statusLine = responseHead.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first
        let parts = statusLine?.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true) ?? []
        guard parts.count >= 2, let status = Int(parts[1]) else {
            fail(context: context, error: UpstreamProxyError.malformedResponse)
            return
        }

        guard status == 200 else {
            let error: UpstreamProxyError = status == 407
                ? (credentials == nil ? .authenticationRequired : .authenticationRejected)
                : .connectRejected(statusCode: status)
            fail(context: context, error: error)
            return
        }

        context.pipeline.removeHandler(self).whenComplete { [completionPromise] result in
            switch result {
            case .success:
                completionPromise.succeed(())
            case let .failure(error):
                completionPromise.fail(error)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(context: context, error: error)
    }

    // MARK: Private

    private let targetHost: String
    private let targetPort: Int
    private let credentials: UpstreamProxyCredentials?
    private let completionPromise: EventLoopPromise<Void>
    private var responseBuffer = ""
    private var didComplete = false

    private func fail(context: ChannelHandlerContext, error: Error) {
        guard !didComplete else {
            return
        }
        didComplete = true
        completionPromise.fail(error)
        context.close(promise: nil)
    }
}
