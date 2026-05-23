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
}
