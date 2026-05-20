import Foundation
@testable import Rockxy
import Testing

struct MapRemoteRuleMatchingAuditTests {
    @Test("Baseline host port path wildcard rule matches the wrong-environment request")
    func baselineHostPortPathRuleMatches() async throws {
        let engine = RuleEngine()
        let pattern = RulePatternBuilder.regexSource(
            rawPattern: "127.0.0.1:43210/rockxy-demo/environment",
            matchType: .wildcard,
            includeSubpaths: false
        )
        let rule = mapRemoteRule(pattern: pattern)
        await engine.addRule(rule)

        let url = try #require(URL(string: "http://127.0.0.1:43210/rockxy-demo/environment?expected=staging"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [
            HTTPHeader(name: "X-App-Environment", value: "production"),
            HTTPHeader(name: "X-Rockxy-Scenario-Id", value: "wrong-environment"),
            HTTPHeader(name: "X-Rockxy-Step-Id", value: "production-config"),
        ])

        guard case let .mapRemote(configuration) = result else {
            Issue.record("Expected Map Remote to match baseline host:port/path rule")
            return
        }
        #expect(configuration.host == "httpbin.org")
        #expect(configuration.path == "/get")
    }

    @Test("Omitted port does not match a request on a non-default explicit port")
    func omittedPortDoesNotMatchExplicitNonDefaultPort() async throws {
        let engine = RuleEngine()
        let pattern = RulePatternBuilder.regexSource(
            rawPattern: "127.0.0.1/rockxy-demo/environment",
            matchType: .wildcard,
            includeSubpaths: false
        )
        await engine.addRule(mapRemoteRule(pattern: pattern))

        let url = try #require(URL(string: "http://127.0.0.1:43210/rockxy-demo/environment?expected=staging"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])

        #expect(result == nil)
    }

    @Test("Subpaths off uses exact boundary for trailing slash and sibling paths")
    func subpathsOffUsesExactBoundary() async throws {
        let engine = RuleEngine()
        let pattern = RulePatternBuilder.regexSource(
            rawPattern: "/rockxy-demo/environment",
            matchType: .wildcard,
            includeSubpaths: false
        )
        await engine.addRule(mapRemoteRule(pattern: pattern))

        let exact = try #require(URL(string: "http://127.0.0.1:43210/rockxy-demo/environment?expected=staging"))
        let trailingSlash = try #require(URL(string: "http://127.0.0.1:43210/rockxy-demo/environment/"))
        let sibling = try #require(URL(string: "http://127.0.0.1:43210/rockxy-demo/environment-prod"))

        #expect(await engine.evaluate(method: "GET", url: exact, headers: []) != nil)
        #expect(await engine.evaluate(method: "GET", url: trailingSlash, headers: []) == nil)
        #expect(await engine.evaluate(method: "GET", url: sibling, headers: []) == nil)
    }

    @Test("Wildcard star positions and question mark semantics are distinct")
    func wildcardPositionsAndQuestionMarkSemantics() async throws {
        let prefix = RulePatternBuilder.regexSource(
            rawPattern: "*/environment",
            matchType: .wildcard,
            includeSubpaths: false
        )
        let suffix = RulePatternBuilder.regexSource(
            rawPattern: "/rockxy-demo/*",
            matchType: .wildcard,
            includeSubpaths: false
        )
        let middle = RulePatternBuilder.regexSource(
            rawPattern: "/rockxy-demo/*/config",
            matchType: .wildcard,
            includeSubpaths: false
        )
        let question = RulePatternBuilder.regexSource(
            rawPattern: "/env?/config",
            matchType: .wildcard,
            includeSubpaths: false
        )

        #expect(try regex(prefix).firstMatch(in: "http://x.test/rockxy-demo/environment") != nil)
        #expect(try regex(suffix).firstMatch(in: "http://x.test/rockxy-demo/a/b") != nil)
        #expect(try regex(middle).firstMatch(in: "http://x.test/rockxy-demo/staging/config") != nil)
        #expect(try regex(question).firstMatch(in: "http://x.test/env1/config") != nil)
        #expect(try regex(question).firstMatch(in: "http://x.test/env12/config") == nil)
    }

    @Test("Disabled Map Remote rules are skipped and later enabled rules can match")
    func disabledRuleDoesNotShadowEnabledRule() async throws {
        let engine = RuleEngine()
        let first = mapRemoteRule(
            name: "Disabled",
            isEnabled: false,
            pattern: ".*example\\.com.*",
            host: "disabled.example.com"
        )
        let second = mapRemoteRule(
            name: "Enabled",
            isEnabled: true,
            pattern: ".*example\\.com.*",
            host: "enabled.example.com"
        )
        await engine.addRule(first)
        await engine.addRule(second)

        let url = try #require(URL(string: "https://example.com/api"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])

        if case let .mapRemote(configuration) = result {
            #expect(configuration.host == "enabled.example.com")
        } else {
            Issue.record("Expected enabled Map Remote rule to match")
        }
    }

    @Test("Map Remote rules are first match wins and do not chain")
    func firstMatchWinsNoChaining() async throws {
        let engine = RuleEngine()
        await engine.addRule(mapRemoteRule(pattern: ".*host-a\\.example.*", host: "host-b.example"))
        await engine.addRule(mapRemoteRule(pattern: ".*host-b\\.example.*", host: "host-c.example"))

        let url = try #require(URL(string: "https://host-a.example/api"))
        let result = await engine.evaluate(method: "GET", url: url, headers: [])

        if case let .mapRemote(configuration) = result {
            #expect(configuration.host == "host-b.example")
        } else {
            Issue.record("Expected only the first Map Remote rule to fire")
        }
    }

    private func mapRemoteRule(
        name: String = "Remote",
        isEnabled: Bool = true,
        pattern: String,
        host: String = "httpbin.org"
    )
        -> ProxyRule
    {
        ProxyRule(
            name: name,
            isEnabled: isEnabled,
            matchCondition: RuleMatchCondition(urlPattern: pattern),
            action: .mapRemote(configuration: MapRemoteConfiguration(
                scheme: "https",
                host: host,
                path: "/get"
            ))
        )
    }

    private func regex(_ pattern: String) throws -> NSRegularExpression {
        try NSRegularExpression(pattern: pattern)
    }
}

private extension NSRegularExpression {
    func firstMatch(in value: String) -> NSTextCheckingResult? {
        firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
    }
}
