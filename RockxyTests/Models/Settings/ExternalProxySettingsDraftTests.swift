import Foundation
@testable import Rockxy
import Testing

// MARK: - ExternalProxySettingsDraftTests

@Suite("ExternalProxySettingsDraft")
struct ExternalProxySettingsDraftTests {
    @Test("Automatic proxy configuration is selectable but not persisted")
    func automaticProxyConfigurationIsUnsupported() {
        let draft = ExternalProxySettingsDraft(
            isEnabled: true,
            selectedProtocol: .automatic,
            pacURL: "http://my-server.com/proxy.pac"
        )

        #expect(throws: ExternalProxySettingsDraftError.automaticProxyConfigurationUnsupported) {
            try draft.configuration()
        }
        #expect(!ExternalProxyProtocolSelection.automatic.canPersist(using: DefaultAppPolicy()))
    }

    @Test("HTTP draft creates an HTTP upstream proxy configuration")
    func httpConfiguration() throws {
        let draft = ExternalProxySettingsDraft(
            isEnabled: true,
            selectedProtocol: .http,
            host: "proxy.example.com",
            portText: "8080",
            bypassText: " localhost, *.internal, , api.example.com ",
            bypassLocalhost: true
        )

        let configuration = try draft.configuration()

        #expect(configuration.isEnabled)
        #expect(configuration.type == .http)
        #expect(configuration.host == "proxy.example.com")
        #expect(configuration.port == 8_080)
        #expect(configuration.bypassHostPatterns == ["localhost", "*.internal", "api.example.com"])
        #expect(configuration.bypassLocalhost)
        #expect(draft.credentials() == nil)
    }

    @Test("HTTPS draft creates an HTTPS upstream proxy configuration")
    func httpsConfiguration() throws {
        let draft = ExternalProxySettingsDraft(
            isEnabled: true,
            selectedProtocol: .https,
            host: "secure-proxy.example.com",
            portText: " 8443 ",
            bypassLocalhost: false
        )

        let configuration = try draft.configuration()

        #expect(configuration.type == .https)
        #expect(configuration.host == "secure-proxy.example.com")
        #expect(configuration.port == 8_443)
        #expect(!configuration.bypassLocalhost)
    }

    @Test("SOCKS draft creates a SOCKS5 configuration before store policy enforcement")
    func socksConfiguration() throws {
        let draft = ExternalProxySettingsDraft(
            isEnabled: true,
            selectedProtocol: .socks5,
            host: "127.0.0.1",
            portText: "1080"
        )

        let configuration = try draft.configuration()

        #expect(configuration.type == .socks5)
        #expect(configuration.host == "127.0.0.1")
        #expect(configuration.port == 1_080)
        #expect(!ExternalProxyProtocolSelection.socks5.canPersist(using: DefaultAppPolicy()))
        #expect(ExternalProxyProtocolSelection.socks5.canPersist(using: SOCKSAllowedPolicy()))
    }

    @Test("Authentication credentials are created only when requested")
    func credentials() {
        let unauthenticated = ExternalProxySettingsDraft(
            selectedProtocol: .http,
            host: "proxy.example.com",
            username: "ignored",
            password: "ignored"
        )
        #expect(unauthenticated.credentials() == nil)

        let authenticated = ExternalProxySettingsDraft(
            selectedProtocol: .http,
            host: "proxy.example.com",
            usesAuthentication: true,
            username: "user",
            password: "secret"
        )
        #expect(authenticated.credentials()?.username == "user")
        #expect(authenticated.credentials()?.password == "secret")
    }

    @Test("Invalid port text flows to configuration validation")
    func invalidPortValidation() throws {
        let draft = ExternalProxySettingsDraft(
            isEnabled: true,
            selectedProtocol: .http,
            host: "proxy.example.com",
            portText: "not-a-port"
        )

        let configuration = try draft.configuration()

        #expect(configuration.port == 0)
        #expect(throws: UpstreamProxyConfigurationError.portOutOfRange) {
            try configuration.validate()
        }
    }

    @Test("Selection maps persisted upstream proxy types without policy fallback")
    func selectionMapping() {
        #expect(ExternalProxyProtocolSelection(.http) == .http)
        #expect(ExternalProxyProtocolSelection(.https) == .https)
        #expect(ExternalProxyProtocolSelection(.socks5) == .socks5)
    }
}

// MARK: - SOCKSAllowedPolicy

private struct SOCKSAllowedPolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 10
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
    let upstreamProxyAllowsSOCKS5 = true
    let upstreamProxyAllowsAuthentication = false
    let maxUpstreamProxyBypassEntries = 3
    let protobufDecodingAllowsSchemaUpload = false
    let maxProtobufSchemas = 0
}
