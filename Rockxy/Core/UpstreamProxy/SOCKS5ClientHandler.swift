import Foundation
import NIOCore

// MARK: - SOCKS5ClientHandler

final class SOCKS5ClientHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
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
        var buffer = context.channel.allocator.buffer(capacity: credentials == nil ? 3 : 4)
        buffer.writeInteger(UInt8(0x05))
        if credentials == nil {
            buffer.writeInteger(UInt8(0x01))
            buffer.writeInteger(UInt8(0x00))
        } else {
            buffer.writeInteger(UInt8(0x02))
            buffer.writeInteger(UInt8(0x00))
            buffer.writeInteger(UInt8(0x02))
        }
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        incomingBuffer.writeBuffer(&incoming)
        process(context: context)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(context: context, error: error)
    }

    // MARK: Private

    private enum State {
        case methodSelection
        case usernamePassword
        case connectReply
        case complete
    }

    private let targetHost: String
    private let targetPort: Int
    private let credentials: UpstreamProxyCredentials?
    private let completionPromise: EventLoopPromise<Void>
    private var incomingBuffer = ByteBuffer()
    private var state = State.methodSelection
    private var didComplete = false

    private func process(context: ChannelHandlerContext) {
        switch state {
        case .methodSelection:
            guard incomingBuffer.readableBytes >= 2 else {
                return
            }
            guard incomingBuffer.readInteger(as: UInt8.self) == 0x05,
                  let method = incomingBuffer.readInteger(as: UInt8.self) else
            {
                fail(context: context, error: UpstreamProxyError.malformedResponse)
                return
            }

            switch method {
            case 0x00:
                state = .connectReply
                sendConnectRequest(context: context)
            case 0x02:
                guard credentials != nil else {
                    fail(context: context, error: UpstreamProxyError.unsupportedSOCKS5AuthMethod(method))
                    return
                }
                state = .usernamePassword
                sendUsernamePassword(context: context)
            case 0xFF:
                fail(context: context, error: UpstreamProxyError.authenticationRequired)
                return
            default:
                fail(context: context, error: UpstreamProxyError.unsupportedSOCKS5AuthMethod(method))
                return
            }
            process(context: context)
        case .usernamePassword:
            guard incomingBuffer.readableBytes >= 2 else {
                return
            }
            guard incomingBuffer.readInteger(as: UInt8.self) == 0x01,
                  let status = incomingBuffer.readInteger(as: UInt8.self) else
            {
                fail(context: context, error: UpstreamProxyError.malformedResponse)
                return
            }
            guard status == 0x00 else {
                fail(context: context, error: UpstreamProxyError.authenticationRejected)
                return
            }
            state = .connectReply
            sendConnectRequest(context: context)
            process(context: context)
        case .connectReply:
            guard incomingBuffer.readableBytes >= 5 else {
                return
            }
            let readerIndex = incomingBuffer.readerIndex
            guard incomingBuffer.readInteger(as: UInt8.self) == 0x05,
                  let replyCode = incomingBuffer.readInteger(as: UInt8.self),
                  incomingBuffer.readInteger(as: UInt8.self) == UInt8(0x00),
                  let atyp = incomingBuffer.readInteger(as: UInt8.self) else
            {
                incomingBuffer.moveReaderIndex(to: readerIndex)
                fail(context: context, error: UpstreamProxyError.malformedResponse)
                return
            }

            let addressLength: Int
            switch atyp {
            case 0x01:
                addressLength = 4
            case 0x03:
                guard let length = incomingBuffer.readInteger(as: UInt8.self) else {
                    incomingBuffer.moveReaderIndex(to: readerIndex)
                    return
                }
                addressLength = Int(length)
            case 0x04:
                addressLength = 16
            default:
                fail(context: context, error: UpstreamProxyError.malformedResponse)
                return
            }

            guard incomingBuffer.readableBytes >= addressLength + 2 else {
                incomingBuffer.moveReaderIndex(to: readerIndex)
                return
            }
            incomingBuffer.moveReaderIndex(forwardBy: addressLength + 2)

            let reply = SOCKS5Reply(code: replyCode)
            guard reply == .succeeded else {
                fail(context: context, error: UpstreamProxyError.socks5Reply(reply))
                return
            }

            state = .complete
            context.pipeline.removeHandler(self).whenComplete { [completionPromise] result in
                switch result {
                case .success:
                    completionPromise.succeed(())
                case let .failure(error):
                    completionPromise.fail(error)
                }
            }
        case .complete:
            return
        }
    }

    private func sendUsernamePassword(context: ChannelHandlerContext) {
        guard let credentials else {
            fail(context: context, error: UpstreamProxyError.authenticationRequired)
            return
        }
        let username = Array(credentials.username.utf8)
        let password = Array(credentials.password.utf8)
        guard username.count <= 255, password.count <= 255 else {
            fail(context: context, error: UpstreamProxyError.authenticationRejected)
            return
        }

        var buffer = context.channel.allocator.buffer(capacity: 3 + username.count + password.count)
        buffer.writeInteger(UInt8(0x01))
        buffer.writeInteger(UInt8(username.count))
        buffer.writeBytes(username)
        buffer.writeInteger(UInt8(password.count))
        buffer.writeBytes(password)
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    private func sendConnectRequest(context: ChannelHandlerContext) {
        let hostBytes = Array(targetHost.utf8)
        guard hostBytes.count <= 255 else {
            fail(context: context, error: UpstreamProxyError.targetHostTooLong)
            return
        }

        var buffer = context.channel.allocator.buffer(capacity: 7 + hostBytes.count)
        buffer.writeInteger(UInt8(0x05))
        buffer.writeInteger(UInt8(0x01))
        buffer.writeInteger(UInt8(0x00))
        buffer.writeInteger(UInt8(0x03))
        buffer.writeInteger(UInt8(hostBytes.count))
        buffer.writeBytes(hostBytes)
        buffer.writeInteger(UInt16(targetPort), endianness: .big)
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    private func fail(context: ChannelHandlerContext, error: Error) {
        guard !didComplete else {
            return
        }
        didComplete = true
        completionPromise.fail(error)
        context.close(promise: nil)
    }
}
