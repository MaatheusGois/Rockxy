import Foundation
@testable import Rockxy
import Testing

@Suite("HostPatternMatcher")
struct HostPatternMatcherTests {
    @Test("matches exact hosts case-insensitively")
    func exactMatch() {
        #expect(HostPatternMatcher.matches(host: "API.Example.com", pattern: "api.example.COM"))
        #expect(!HostPatternMatcher.matches(host: "xapi.example.com", pattern: "api.example.com"))
    }

    @Test("matches star and question mark wildcards")
    func wildcardMatch() {
        #expect(HostPatternMatcher.matches(host: "api.example.com", pattern: "*.example.com"))
        #expect(HostPatternMatcher.matches(host: "host", pattern: "?ost"))
        #expect(!HostPatternMatcher.matches(host: "toast", pattern: "?ost"))
    }

    @Test("preserves legacy bypass wildcard behavior")
    func legacyBypassWildcard() {
        #expect(HostPatternMatcher.matches(host: "api.local", pattern: "*.local", extendedWildcards: false))
        #expect(!HostPatternMatcher.matches(host: "local", pattern: "*.local", extendedWildcards: false))
        #expect(!HostPatternMatcher.matches(host: "host", pattern: "?ost", extendedWildcards: false))
    }

    @Test("detects localhost variants")
    func localhostVariants() {
        #expect(HostPatternMatcher.isLocalhost("localhost"))
        #expect(HostPatternMatcher.isLocalhost("api.localhost"))
        #expect(HostPatternMatcher.isLocalhost("127.0.0.1"))
        #expect(HostPatternMatcher.isLocalhost("127.4.5.6"))
        #expect(HostPatternMatcher.isLocalhost("::1"))
        #expect(HostPatternMatcher.isLocalhost("[::1]"))
        #expect(!HostPatternMatcher.isLocalhost("192.168.0.1"))
    }

    @Test("validates pattern shape")
    func patternValidation() {
        #expect(HostPatternMatcher.isValid(pattern: "*.example.com"))
        #expect(HostPatternMatcher.isValid(pattern: "127.0.0.1"))
        #expect(!HostPatternMatcher.isValid(pattern: ""))
        #expect(!HostPatternMatcher.isValid(pattern: "bad host"))
    }
}
