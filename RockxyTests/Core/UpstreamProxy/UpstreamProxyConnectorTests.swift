import Foundation
import NIOCore
import NIOPosix
@testable import Rockxy
import Testing

@Suite("UpstreamProxyConnector")
struct UpstreamProxyConnectorTests {
    // MARK: Internal

    @Test("disabled configuration uses direct outbound bytes")
    func disabledUsesDirectConnect() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let capture = UpstreamProxyStringCapture()
        let server = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyByteCaptureHandler(capture: capture))
        }
        defer { try? server.close().wait() }

        let channel = try UpstreamProxyConnector.connect(
            eventLoop: group.next(),
            targetHost: "127.0.0.1",
            targetPort: serverPort(server),
            configuration: nil
        ) { channel in
            channel.eventLoop.makeSucceededVoidFuture()
        }.wait()
        defer { try? channel.close().wait() }

        var buffer = channel.allocator.buffer(capacity: 5)
        buffer.writeString("hello")
        try channel.writeAndFlush(buffer).wait()

        #expect(capture.wait() == "hello")
    }

    @Test("bypass list short-circuits an enabled upstream proxy")
    func bypassUsesDirectConnect() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let capture = UpstreamProxyStringCapture()
        let server = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyByteCaptureHandler(capture: capture))
        }
        defer { try? server.close().wait() }

        let configuration = UpstreamProxyResolvedConfiguration(
            configuration: UpstreamProxyConfiguration(
                isEnabled: true,
                host: "192.0.2.10",
                port: 65_000,
                bypassHostPatterns: ["127.0.0.1"]
            ),
            credentials: nil
        )
        let channel = try UpstreamProxyConnector.connect(
            eventLoop: group.next(),
            targetHost: "127.0.0.1",
            targetPort: serverPort(server),
            configuration: configuration
        ) { channel in
            channel.eventLoop.makeSucceededVoidFuture()
        }.wait()
        defer { try? channel.close().wait() }

        var buffer = channel.allocator.buffer(capacity: 6)
        buffer.writeString("direct")
        try channel.writeAndFlush(buffer).wait()

        #expect(capture.wait() == "direct")
    }

    @Test("HTTP upstream proxy performs CONNECT before initializer")
    func httpConnectHandshake() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let capture = UpstreamProxyStringCapture()
        let proxy = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyHTTPConnectStubHandler(capture: capture))
        }
        defer { try? proxy.close().wait() }

        let configuration = UpstreamProxyResolvedConfiguration(
            configuration: UpstreamProxyConfiguration(
                isEnabled: true,
                type: .http,
                host: "127.0.0.1",
                port: serverPort(proxy)
            ),
            credentials: nil
        )
        let initializerCapture = UpstreamProxyStringCapture()
        let channel = try UpstreamProxyConnector.connect(
            eventLoop: group.next(),
            targetHost: "api.example.com",
            targetPort: 443,
            configuration: configuration
        ) { channel in
            initializerCapture.fulfill("initialized")
            return channel.eventLoop.makeSucceededVoidFuture()
        }.wait()
        defer { try? channel.close().wait() }

        let request = capture.wait()
        #expect(request?.contains("CONNECT api.example.com:443 HTTP/1.1") == true)
        #expect(request?.contains("Host: api.example.com:443") == true)
        #expect(initializerCapture.wait() == "initialized")
    }

    @Test("automatic PAC direct route connects to target without upstream proxy")
    func automaticPACDirectRoute() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let capture = UpstreamProxyStringCapture()
        let server = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyByteCaptureHandler(capture: capture))
        }
        defer { try? server.close().wait() }

        let configuration = UpstreamProxyResolvedConfiguration(
            configuration: UpstreamProxyConfiguration(
                isEnabled: true,
                type: .automatic,
                pacURL: "https://proxy.example.com/proxy.pac"
            ),
            credentials: nil
        )
        let channel = try UpstreamProxyConnector.connect(
            eventLoop: group.next(),
            targetScheme: "http",
            targetHost: "127.0.0.1",
            targetPort: serverPort(server),
            configuration: configuration,
            pacResolver: { eventLoop, pacURL, targetScheme, targetHost, targetPort in
                #expect(pacURL.absoluteString == "https://proxy.example.com/proxy.pac")
                #expect(targetScheme == "http")
                #expect(targetHost == "127.0.0.1")
                #expect(targetPort == serverPort(server))
                return eventLoop.makeSucceededFuture(.direct)
            }
        ) { channel in
            channel.eventLoop.makeSucceededVoidFuture()
        }.wait()
        defer { try? channel.close().wait() }

        var buffer = channel.allocator.buffer(capacity: 6)
        buffer.writeString("direct")
        try channel.writeAndFlush(buffer).wait()

        #expect(capture.wait() == "direct")
    }

    @Test("automatic PAC HTTP route reuses CONNECT handshake")
    func automaticPACHTTPRoute() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let capture = UpstreamProxyStringCapture()
        let proxy = try startUpstreamProxyTestServer(group: group) { channel in
            channel.pipeline.addHandler(UpstreamProxyHTTPConnectStubHandler(capture: capture))
        }
        defer { try? proxy.close().wait() }

        let configuration = UpstreamProxyResolvedConfiguration(
            configuration: UpstreamProxyConfiguration(
                isEnabled: true,
                type: .automatic,
                pacURL: "https://proxy.example.com/proxy.pac"
            ),
            credentials: nil
        )
        let channel = try UpstreamProxyConnector.connect(
            eventLoop: group.next(),
            targetScheme: "https",
            targetHost: "api.example.com",
            targetPort: 443,
            configuration: configuration,
            pacResolver: { eventLoop, _, _, _, _ in
                eventLoop.makeSucceededFuture(.proxy(type: .http, host: "127.0.0.1", port: serverPort(proxy)))
            }
        ) { channel in
            channel.eventLoop.makeSucceededVoidFuture()
        }.wait()
        defer { try? channel.close().wait() }

        let request = capture.wait()
        #expect(request?.contains("CONNECT api.example.com:443 HTTP/1.1") == true)
        #expect(request?.contains("Host: api.example.com:443") == true)
    }

    @Test("automatic PAC SOCKS route respects policy snapshot")
    func automaticPACSOCKSRouteRequiresPolicy() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let configuration = UpstreamProxyResolvedConfiguration(
            configuration: UpstreamProxyConfiguration(
                isEnabled: true,
                type: .automatic,
                pacURL: "https://proxy.example.com/proxy.pac"
            ),
            credentials: nil,
            allowsSOCKS5: false
        )

        #expect(throws: UpstreamProxyError.pacSOCKS5Unavailable) {
            try UpstreamProxyConnector.connect(
                eventLoop: group.next(),
                targetScheme: "https",
                targetHost: "api.example.com",
                targetPort: 443,
                configuration: configuration,
                pacResolver: { eventLoop, _, _, _, _ in
                    eventLoop.makeSucceededFuture(.proxy(type: .socks5, host: "127.0.0.1", port: 1_080))
                }
            ) { channel in
                channel.eventLoop.makeSucceededVoidFuture()
            }.wait()
        }
    }

    // MARK: Private

    private func serverPort(_ channel: Channel) -> Int {
        channel.localAddress?.port ?? 0
    }
}
