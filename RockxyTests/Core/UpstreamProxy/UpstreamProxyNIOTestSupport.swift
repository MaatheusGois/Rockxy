import Foundation
import NIOCore
import NIOPosix

// MARK: - UpstreamProxyStringCapture

final class UpstreamProxyStringCapture: @unchecked Sendable {
    // MARK: Internal

    func fulfill(_ value: String) {
        lock.lock()
        if self.value == nil {
            self.value = value
            semaphore.signal()
        }
        lock.unlock()
    }

    func wait(timeout: TimeInterval = 2) -> String? {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return nil
        }
        lock.lock()
        let result = value
        lock.unlock()
        return result
    }

    // MARK: Private

    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var value: String?
}

func startUpstreamProxyTestServer(
    group: EventLoopGroup,
    childInitializer: @escaping (Channel) -> EventLoopFuture<Void>
)
    throws -> Channel
{
    try ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .childChannelInitializer(childInitializer)
        .bind(host: "127.0.0.1", port: 0)
        .wait()
}

// MARK: - UpstreamProxyByteCaptureHandler

final class UpstreamProxyByteCaptureHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(capture: UpstreamProxyStringCapture) {
        self.capture = capture
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let value = buffer.readString(length: buffer.readableBytes) {
            capture.fulfill(value)
        }
    }

    // MARK: Private

    private let capture: UpstreamProxyStringCapture
}

// MARK: - UpstreamProxyHTTPConnectStubHandler

final class UpstreamProxyHTTPConnectStubHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        capture: UpstreamProxyStringCapture,
        response: String? = "HTTP/1.1 200 Connection Established\r\n\r\n"
    ) {
        self.capture = capture
        self.response = response
    }

    // MARK: Internal

    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        guard let chunk = incoming.readString(length: incoming.readableBytes) else {
            return
        }
        request += chunk
        guard request.contains("\r\n\r\n") else {
            return
        }
        capture.fulfill(request)
        if let response {
            var buffer = context.channel.allocator.buffer(capacity: response.utf8.count)
            buffer.writeString(response)
            context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
        }
    }

    // MARK: Private

    private let capture: UpstreamProxyStringCapture
    private let response: String?
    private var request = ""
}
