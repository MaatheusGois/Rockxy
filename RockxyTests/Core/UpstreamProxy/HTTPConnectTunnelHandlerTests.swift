import Foundation
import NIOCore
import NIOEmbedded
@testable import Rockxy
import Testing

@Suite("HTTPConnectTunnelHandler")
struct HTTPConnectTunnelHandlerTests {
    @Test("writes CONNECT request and succeeds on 200")
    func connectSuccess() throws {
        let channel = EmbeddedChannel()
        let promise = channel.eventLoop.makePromise(of: Void.self)
        try channel.pipeline.addHandler(HTTPConnectTunnelHandler(
            targetHost: "api.example.com",
            targetPort: 443,
            credentials: nil,
            completionPromise: promise
        )).wait()

        var outbound = try #require(try channel.readOutbound(as: ByteBuffer.self))
        let request = outbound.readString(length: outbound.readableBytes)
        #expect(request?.contains("CONNECT api.example.com:443 HTTP/1.1") == true)
        #expect(request?.contains("Host: api.example.com:443") == true)

        var response = channel.allocator.buffer(string: "HTTP/1.1 200 Connection Established\r\n\r\n")
        try channel.writeInbound(response)
        try promise.futureResult.wait()
        try? channel.close().wait()
    }

    @Test("adds Basic auth header")
    func proxyAuthorizationHeader() throws {
        let channel = EmbeddedChannel()
        let promise = channel.eventLoop.makePromise(of: Void.self)
        try channel.pipeline.addHandler(HTTPConnectTunnelHandler(
            targetHost: "api.example.com",
            targetPort: 443,
            credentials: UpstreamProxyCredentials(username: "user", password: "pass"),
            completionPromise: promise
        )).wait()

        var outbound = try #require(try channel.readOutbound(as: ByteBuffer.self))
        let request = outbound.readString(length: outbound.readableBytes)
        #expect(request?.contains("Proxy-Authorization: Basic dXNlcjpwYXNz") == true)
        try channel.close().wait()
    }

    @Test("maps 407 to auth error")
    func authError() throws {
        let channel = EmbeddedChannel()
        let promise = channel.eventLoop.makePromise(of: Void.self)
        var capturedError: Error?
        promise.futureResult.whenFailure { error in
            capturedError = error
        }
        try channel.pipeline.addHandler(HTTPConnectTunnelHandler(
            targetHost: "api.example.com",
            targetPort: 443,
            credentials: nil,
            completionPromise: promise
        )).wait()
        _ = try channel.readOutbound(as: ByteBuffer.self)

        var response = channel.allocator.buffer(string: "HTTP/1.1 407 Proxy Authentication Required\r\n\r\n")
        try channel.writeInbound(response)
        #expect(capturedError as? UpstreamProxyError == .authenticationRequired)
        try? channel.close().wait()
    }

    @Test("rejects malformed and oversize responses")
    func malformedAndOversize() throws {
        let malformed = EmbeddedChannel()
        let malformedPromise = malformed.eventLoop.makePromise(of: Void.self)
        var malformedError: Error?
        malformedPromise.futureResult.whenFailure { error in
            malformedError = error
        }
        try malformed.pipeline.addHandler(HTTPConnectTunnelHandler(
            targetHost: "api.example.com",
            targetPort: 443,
            credentials: nil,
            completionPromise: malformedPromise
        )).wait()
        _ = try malformed.readOutbound(as: ByteBuffer.self)
        var bad = malformed.allocator.buffer(string: "wat\r\n\r\n")
        try malformed.writeInbound(bad)
        #expect(malformedError as? UpstreamProxyError == .malformedResponse)
        try? malformed.close().wait()

        let oversize = EmbeddedChannel()
        let oversizePromise = oversize.eventLoop.makePromise(of: Void.self)
        var oversizeError: Error?
        oversizePromise.futureResult.whenFailure { error in
            oversizeError = error
        }
        try oversize.pipeline.addHandler(HTTPConnectTunnelHandler(
            targetHost: "api.example.com",
            targetPort: 443,
            credentials: nil,
            completionPromise: oversizePromise
        )).wait()
        _ = try oversize.readOutbound(as: ByteBuffer.self)
        var huge = oversize.allocator.buffer(string: String(
            repeating: "a",
            count: ProxyLimits.maxUpstreamHandshakeResponseSize + 1
        ))
        try oversize.writeInbound(huge)
        #expect(oversizeError as? UpstreamProxyError == .responseTooLarge)
        try? oversize.close().wait()
    }
}
