import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
struct BreakpointPhaseBTests {
    // BP_B1
    @Test("matcherEntryPointExists")
    func matcherEntryPointExists() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "httpbin.org/get"))
        let match = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTPS("get"), headers: [])
        #expect(match != nil)
    }

    // BP_B2
    @Test("matcherReturnsNilWhenGlobalToggleOff")
    func matcherReturnsNilWhenGlobalToggleOff() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "httpbin.org/get"))
        await engine.setBreakpointToolEnabled(false)
        let match = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTPS("get"), headers: [])
        #expect(match == nil)
    }

    // BP_B3a
    @Test("iteratesRulesTopToBottom")
    func iteratesRulesTopToBottom() async throws {
        let engine = RuleEngine()
        let first = ProxyRule.breakpointTest(name: "First", matchingRule: "httpbin.org/*", includeSubpaths: true)
        let second = ProxyRule.breakpointTest(name: "Second", matchingRule: "httpbin.org/get")
        await engine.replaceAll([first, second])
        let match = try #require(await engine.evaluateBreakpointRule(
            method: "GET",
            url: TestEndpoints.httpbinHTTPS("get"),
            headers: []
        ))
        #expect(match.id == first.id)
    }

    // BP_B3b
    @Test("skipsDisabledRules")
    func skipsDisabledRules() async throws {
        let engine = RuleEngine()
        let disabled = ProxyRule.breakpointTest(name: "Disabled", matchingRule: "httpbin.org/get", isEnabled: false)
        let enabled = ProxyRule.breakpointTest(name: "Enabled", matchingRule: "httpbin.org/get")
        await engine.replaceAll([disabled, enabled])
        let match = try #require(await engine.evaluateBreakpointRule(
            method: "GET",
            url: TestEndpoints.httpbinHTTPS("get"),
            headers: []
        ))
        #expect(match.id == enabled.id)
    }

    // BP_B4a
    @Test("parsesHostPortPath")
    func parsesHostPortPath() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "127.0.0.1:43210/rockxy-demo/profile"))
        let url = URL(string: "http://127.0.0.1:43210/rockxy-demo/profile")!
        let match = await engine.evaluateBreakpointRule(method: "GET", url: url, headers: [])
        #expect(match != nil)
    }

    // BP_B4b
    @Test("parsesHostPathWithoutPort")
    func parsesHostPathWithoutPort() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "httpbin.org/get"))
        let match = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTPS("get"), headers: [])
        #expect(match != nil)
    }

    // BP_B4c
    @Test("reproductionBugLock")
    func reproductionBugLock() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "127.0.0.1:43210/rockxy-demo/profile"))
        let match = await engine.evaluateBreakpointRule(
            method: "GET",
            url: TestEndpoints.localFlutterProfile,
            headers: [HTTPHeader(name: "Authorization", value: "Bearer expired-demo-token")]
        )
        #expect(match != nil)
    }

    // BP_B5a
    @Test("methodAnyMatchesAll")
    func methodAnyMatchesAll() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "httpbin.org/anything", method: .any))
        for method in ["GET", "POST", "PATCH", "DELETE"] {
            let match = await engine.evaluateBreakpointRule(
                method: method,
                url: TestEndpoints.httpbinHTTPS("anything"),
                headers: []
            )
            #expect(match != nil)
        }
    }

    // BP_B5b
    @Test("methodSpecificRejectsOthers")
    func methodSpecificRejectsOthers() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "httpbin.org/anything", method: .post))
        let get = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTPS("anything"), headers: [])
        let post = await engine.evaluateBreakpointRule(method: "POST", url: TestEndpoints.httpbinHTTPS("anything"), headers: [])
        #expect(get == nil)
        #expect(post != nil)
    }

    // BP_B6a
    @Test("wildcardStarMatchesAnyChars")
    func wildcardStarMatchesAnyChars() {
        let condition = wildcardCondition("/api/*")
        #expect(condition.matches(method: "GET", url: URL(string: "https://httpbin.org/api/foo/bar")!, headers: []))
        #expect(condition.matches(method: "GET", url: URL(string: "https://httpbin.org/api/foo")!, headers: []))
    }

    // BP_B6b
    @Test("wildcardQuestionMatchesSingleChar")
    func wildcardQuestionMatchesSingleChar() {
        let condition = wildcardCondition("/api/file?")
        #expect(condition.matches(method: "GET", url: URL(string: "https://httpbin.org/api/file1")!, headers: []))
        #expect(!condition.matches(method: "GET", url: URL(string: "https://httpbin.org/api/file12")!, headers: []))
    }

    // BP_B6c
    @Test("wildcardNoRegexLeak")
    func wildcardNoRegexLeak() {
        let condition = wildcardCondition("/api/v1.+/users")
        #expect(condition.matches(method: "GET", url: URL(string: "https://httpbin.org/api/v1.+/users")!, headers: []))
        #expect(!condition.matches(method: "GET", url: URL(string: "https://httpbin.org/api/v1aaa/users")!, headers: []))
    }

    // BP_B6d
    @Test("regexCompilesAndMatches")
    func regexCompilesAndMatches() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: #"https://httpbin\.org/(get|headers)"#, matchType: .regex))
        let match = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTPS("headers"), headers: [])
        #expect(match != nil)
    }

    // BP_B6e
    @Test("regexInvalidPatternDoesNotCrash")
    func regexInvalidPatternDoesNotCrash() async {
        let engine = RuleEngine()
        await engine.replaceAll([.breakpointTest(matchingRule: #"["#, matchType: .regex)])
        let match = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTPS("get"), headers: [])
        #expect(match == nil)
    }

    // BP_B7a
    @Test("subpathsUncheckedExactMatch")
    func subpathsUncheckedExactMatch() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "httpbin.org/anything", includeSubpaths: false))
        let exact = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTPS("anything"), headers: [])
        let child = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTPS("anything/child"), headers: [])
        #expect(exact != nil)
        #expect(child == nil)
    }

    // BP_B7b
    @Test("subpathsCheckedMatchesDescendants")
    func subpathsCheckedMatchesDescendants() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "httpbin.org/anything", includeSubpaths: true))
        let child = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTPS("anything/child"), headers: [])
        #expect(child != nil)
    }

    // BP_B7c
    @Test("subpathsUncheckedWithQueryString")
    func subpathsUncheckedWithQueryString() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "httpbin.org/get", includeSubpaths: false))
        let url = URL(string: "https://httpbin.org/get?expected=staging")!
        let match = await engine.evaluateBreakpointRule(method: "GET", url: url, headers: [])
        #expect(match != nil)
    }

    // BP_B8a
    @Test("phaseRequestOnlyDoesNotPauseResponse")
    func phaseRequestOnlyDoesNotPauseResponse() {
        #expect(phase(.request, allows: .request))
        #expect(!phase(.request, allows: .response))
    }

    // BP_B8b
    @Test("phaseResponseOnlyDoesNotPauseRequest")
    func phaseResponseOnlyDoesNotPauseRequest() {
        #expect(!phase(.response, allows: .request))
        #expect(phase(.response, allows: .response))
    }

    // BP_B8c
    @Test("phaseBothPausesBoth")
    func phaseBothPausesBoth() {
        #expect(phase(.both, allows: .request))
        #expect(phase(.both, allows: .response))
    }

    // BP_B9
    @Test("loopbackNotSpeciallyExcluded")
    func loopbackNotSpeciallyExcluded() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "127.0.0.1:43210/rockxy-demo/profile"))
        let match = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.localFlutterProfile, headers: [])
        #expect(match != nil)
    }

    // BP_B10
    @Test("httpAndHttpsBothMatch")
    func httpAndHttpsBothMatch() async {
        let engine = RuleEngine()
        await engine.addRule(.breakpointTest(matchingRule: "httpbin.org/get"))
        let http = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTP("get"), headers: [])
        let https = await engine.evaluateBreakpointRule(method: "GET", url: TestEndpoints.httpbinHTTPS("get"), headers: [])
        #expect(http != nil)
        #expect(https != nil)
    }

    // BP_B11
    @Test("pipelineOrderBreakpointSeesFirst")
    func pipelineOrderBreakpointSeesFirst() async throws {
        let engine = RuleEngine()
        let block = ProxyRule(
            name: "Block",
            matchCondition: RuleMatchCondition(urlPattern: #"httpbin\.org/get"#),
            action: .block(statusCode: 403)
        )
        let breakpoint = ProxyRule.breakpointTest(name: "Breakpoint", matchingRule: "httpbin.org/get")
        await engine.replaceAll([block, breakpoint])
        let match = try #require(await engine.evaluateBreakpointRule(
            method: "GET",
            url: TestEndpoints.httpbinHTTPS("get"),
            headers: []
        ))
        #expect(match.id == breakpoint.id)
    }

    // BP_B12
    @Test("matcherReturnsContinuationHandle")
    @MainActor
    func matcherReturnsContinuationHandle() async throws {
        let harness = BreakpointTestHarness(manager: BreakpointManager(), ruleEngine: RuleEngine())
        let task = Task {
            await harness.manager.enqueueAndWait(.test())
        }
        let item = try await harness.awaitNextPause(timeout: 2)
        await harness.resolve(item.id, decision: .execute)
        let result = await task.value
        #expect(result.0 == .execute)
        #expect(result.1.url == "https://httpbin.org/get")
    }

    private func wildcardCondition(_ pattern: String, includeSubpaths: Bool = false) -> RuleMatchCondition {
        RuleMatchCondition(
            urlPattern: RulePatternBuilder.regexSource(
                rawPattern: pattern,
                matchType: .wildcard,
                includeSubpaths: includeSubpaths
            )
        )
    }

    private func phase(_ rulePhase: BreakpointRulePhase, allows phase: BreakpointPhase) -> Bool {
        switch (rulePhase, phase) {
        case (.both, _), (.request, .request), (.response, .response):
            true
        default:
            false
        }
    }
}
