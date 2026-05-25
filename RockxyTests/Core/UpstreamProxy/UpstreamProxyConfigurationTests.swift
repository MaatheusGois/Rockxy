import Foundation
@testable import Rockxy
import Testing

@Suite("UpstreamProxyConfiguration")
struct UpstreamProxyConfigurationTests {
    @Test("validates enabled host")
    func enabledHostValidation() {
        var config = UpstreamProxyConfiguration(isEnabled: true, host: "")
        #expect(throws: UpstreamProxyConfigurationError.hostInvalid) {
            try config.validate()
        }

        config.host = "proxy.example.com"
        #expect(throws: Never.self) {
            try config.validate()
        }
    }

    @Test("validates port range")
    func portValidation() {
        let low = UpstreamProxyConfiguration(port: 0)
        #expect(throws: UpstreamProxyConfigurationError.portOutOfRange) {
            try low.validate()
        }

        let high = UpstreamProxyConfiguration(port: 65_536)
        #expect(throws: UpstreamProxyConfigurationError.portOutOfRange) {
            try high.validate()
        }
    }

    @Test("validates automatic proxy configuration PAC URL")
    func automaticPACValidation() {
        let valid = UpstreamProxyConfiguration(
            isEnabled: true,
            type: .automatic,
            host: "",
            port: 0,
            pacURL: " https://proxy.example.com/proxy.pac "
        )
        #expect(throws: Never.self) {
            try valid.validate()
        }
        #expect(valid.resolvedPACURL?.absoluteString == "https://proxy.example.com/proxy.pac")

        let missing = UpstreamProxyConfiguration(isEnabled: true, type: .automatic)
        #expect(throws: UpstreamProxyConfigurationError.pacURLRequired) {
            try missing.validate()
        }

        let invalid = UpstreamProxyConfiguration(isEnabled: true, type: .automatic, pacURL: "not a url")
        #expect(throws: UpstreamProxyConfigurationError.pacURLInvalid) {
            try invalid.validate()
        }

        let unsupported = UpstreamProxyConfiguration(isEnabled: true, type: .automatic, pacURL: "file:///tmp/proxy.pac")
        #expect(throws: UpstreamProxyConfigurationError.pacURLUnsupportedScheme) {
            try unsupported.validate()
        }
    }

    @Test("validates RFC 1929 credential byte length")
    func credentialLengthValidation() {
        let tooLong = String(repeating: "a", count: 256)
        let config = UpstreamProxyConfiguration(username: tooLong)
        #expect(throws: UpstreamProxyConfigurationError.usernameTooLong) {
            try config.validate()
        }

        let credentials = UpstreamProxyCredentials(username: "user", password: tooLong)
        #expect(throws: UpstreamProxyConfigurationError.passwordTooLong) {
            try UpstreamProxyConfiguration().validate(credentials: credentials)
        }
    }

    @Test("validates bypass patterns and cap")
    func bypassValidation() {
        let malformed = UpstreamProxyConfiguration(bypassHostPatterns: ["bad host"])
        #expect(throws: UpstreamProxyConfigurationError.bypassPatternInvalid("bad host")) {
            try malformed.validate()
        }

        let tooMany = UpstreamProxyConfiguration(bypassHostPatterns: ["a.com", "b.com", "c.com", "d.com"])
        #expect(throws: UpstreamProxyConfigurationError.tooManyBypassEntries(limit: 3)) {
            try tooMany.validate(bypassEntryLimit: 3)
        }
    }

    @Test("decodes legacy upstream proxy configuration without PAC URL")
    func legacyDecodeWithoutPACURL() throws {
        let json = """
        {
          "isEnabled": true,
          "type": "http",
          "host": "proxy.example.com",
          "port": 8080,
          "hasCredentials": false,
          "bypassHostPatterns": [],
          "bypassLocalhost": true
        }
        """
        let data = try #require(json.data(using: .utf8))

        let decoded = try JSONDecoder().decode(UpstreamProxyConfiguration.self, from: data)

        #expect(decoded.type == .http)
        #expect(decoded.host == "proxy.example.com")
        #expect(decoded.pacURL == nil)
    }
}
