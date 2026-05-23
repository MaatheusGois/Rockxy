import Foundation
import NIOCore
import NIOEmbedded
@testable import Rockxy
import Testing

@Suite("SOCKS5ClientHandler")
struct SOCKS5ClientHandlerTests {
    @Test("performs no-auth domain CONNECT handshake")
    func noAuthHandshake() throws {
        let channel = EmbeddedChannel()
        let promise = channel.eventLoop.makePromise(of: Void.self)
        try channel.pipeline.addHandler(SOCKS5ClientHandler(
            targetHost: "api.example.com",
            targetPort: 443,
            credentials: nil,
            completionPromise: promise
        )).wait()

        var greeting = try #require(try channel.readOutbound(as: ByteBuffer.self))
        #expect(greeting.readBytes(length: greeting.readableBytes) == [0x05, 0x01, 0x00])

        var method = channel.allocator.buffer(bytes: [0x05, 0x00])
        try channel.writeInbound(method)
        var connect = try #require(try channel.readOutbound(as: ByteBuffer.self))
        let bytes = connect.readBytes(length: connect.readableBytes) ?? []
        #expect(bytes.prefix(5) == [0x05, 0x01, 0x00, 0x03, 0x0F])
        #expect(bytes.suffix(2) == [0x01, 0xBB])

        var success = channel.allocator.buffer(bytes: [0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0x1F, 0x90])
        try channel.writeInbound(success)
        try promise.futureResult.wait()
        try channel.finish(acceptAlreadyClosed: true)
    }

    @Test("performs username/password auth and maps rejection")
    func usernamePasswordAuth() throws {
        let channel = EmbeddedChannel()
        let promise = channel.eventLoop.makePromise(of: Void.self)
        try channel.pipeline.addHandler(SOCKS5ClientHandler(
            targetHost: "api.example.com",
            targetPort: 80,
            credentials: UpstreamProxyCredentials(username: "u", password: "p"),
            completionPromise: promise
        )).wait()

        var greeting = try #require(try channel.readOutbound(as: ByteBuffer.self))
        #expect(greeting.readBytes(length: greeting.readableBytes) == [0x05, 0x02, 0x00, 0x02])

        var method = channel.allocator.buffer(bytes: [0x05, 0x02])
        try channel.writeInbound(method)
        var auth = try #require(try channel.readOutbound(as: ByteBuffer.self))
        #expect(auth.readBytes(length: auth.readableBytes) == [0x01, 0x01, 0x75, 0x01, 0x70])

        var rejected = channel.allocator.buffer(bytes: [0x01, 0x01])
        try channel.writeInbound(rejected)
        #expect(throws: UpstreamProxyError.authenticationRejected) {
            try promise.futureResult.wait()
        }
        try channel.finish(acceptAlreadyClosed: true)
    }

    @Test("maps every SOCKS5 reply code")
    func replyCodes() throws {
        for reply in SOCKS5Reply.allCases where reply != .succeeded {
            let channel = EmbeddedChannel()
            let promise = channel.eventLoop.makePromise(of: Void.self)
            try channel.pipeline.addHandler(SOCKS5ClientHandler(
                targetHost: "api.example.com",
                targetPort: 443,
                credentials: nil,
                completionPromise: promise
            )).wait()
            _ = try channel.readOutbound(as: ByteBuffer.self)
            var method = channel.allocator.buffer(bytes: [0x05, 0x00])
            try channel.writeInbound(method)
            _ = try channel.readOutbound(as: ByteBuffer.self)

            var response = channel.allocator.buffer(bytes: [0x05, reply.rawValue, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
            try channel.writeInbound(response)
            #expect(throws: UpstreamProxyError.socks5Reply(reply)) {
                try promise.futureResult.wait()
            }
            try channel.finish(acceptAlreadyClosed: true)
        }
    }
}
