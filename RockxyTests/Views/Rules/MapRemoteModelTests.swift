import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct MapRemoteModelTests {
    @Test("filter matches name, method, rule, and destination")
    func filterMatchesVisibleColumns() {
        let vm = MapRemoteWindowViewModel()
        let usersRule = ProxyRule(
            name: "Users",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/users/.*", method: "POST"),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com", path: "/users"))
        )
        let assetsRule = ProxyRule(
            name: "Assets",
            matchCondition: RuleMatchCondition(urlPattern: "https://cdn.example.com/.*", method: "GET"),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "assets-dev.example.com"))
        )
        vm.allRules = [usersRule, assetsRule]

        vm.searchText = "post"
        #expect(vm.filteredRules.map(\.id) == [usersRule.id])

        vm.searchText = "assets-dev"
        #expect(vm.filteredRules.map(\.id) == [assetsRule.id])
    }

    @Test("visible Map Remote row labels match the management table")
    func visibleRowLabelsMatchManagementTable() {
        let vm = MapRemoteWindowViewModel()
        let pattern = MapLocalPatternFormatter.wildcardToRegex("https://localhost:3000/v1/*")
        let rule = ProxyRule(
            name: "Untitled",
            matchCondition: RuleMatchCondition(urlPattern: pattern),
            action: .mapRemote(configuration: MapRemoteConfiguration(
                scheme: "https",
                host: "api.production.com",
                path: "/v2/api",
                query: "id=123"
            ))
        )

        #expect(vm.methodLabel(for: rule) == "ANY")
        #expect(vm.matchingRuleLabel(for: rule) == "Wildcard: https://localhost:3000/v1/*")
        #expect(vm.destinationLabel(for: rule) == "https://api.production.com/v2/api?id=123")
    }

    @Test("remove selected Map Remote rows preserves unrelated rules")
    func removeSelectedPreservesOtherRules() async {
        await RuleTestLock.shared.acquire()
        let snapshot = await RuleEngine.shared.allRules
        await RuleEngine.shared.replaceAll([])

        let vm = MapRemoteWindowViewModel()
        let mapRemote = ProxyRule(
            name: "Remote",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*"),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com"))
        )
        let block = ProxyRule(
            name: "Block",
            matchCondition: RuleMatchCondition(urlPattern: "https://blocked.example.com/.*"),
            action: .block(statusCode: 403)
        )
        vm.allRules = [mapRemote, block]
        vm.selectedRuleIDs = [mapRemote.id]

        vm.removeSelectedRules()

        #expect(vm.allRules.map(\.id) == [block.id])
        #expect(vm.selectedRuleIDs.isEmpty)

        await RuleEngine.shared.replaceAll(snapshot)
        await RuleTestLock.shared.release()
    }

    @Test("duplicate selected Map Remote rule keeps behavior and selects the copy")
    func duplicateSelectedRule() {
        let vm = MapRemoteWindowViewModel()
        let rule = ProxyRule(
            name: "Remote",
            isEnabled: true,
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*", method: "PATCH"),
            action: .mapRemote(configuration: MapRemoteConfiguration(host: "staging.example.com")),
            priority: 7
        )
        vm.allRules = [rule]
        vm.selectedRuleIDs = [rule.id]

        vm.duplicateSelectedRule()

        #expect(vm.allRules.count == 2)
        let copy = vm.allRules[1]
        #expect(copy.id != rule.id)
        #expect(copy.name == "Remote Copy")
        #expect(copy.matchCondition == rule.matchCondition)
        #expect(copy.priority == 7)
        #expect(vm.selectedRuleIDs == [copy.id])
    }

    @Test("tool enable setter updates view model immediately")
    func toolEnableSetter() async {
        await RuleTestLock.shared.acquire()
        let vm = MapRemoteWindowViewModel(isToolEnabled: true)
        vm.setToolEnabled(false)
        #expect(vm.isToolEnabled == false)
        await RuleSyncService.setMapRemoteToolEnabled(true)
        await RuleTestLock.shared.release()
    }

    @Test("editor saves rule with method, wildcard pattern, destination, and advanced flags")
    func editorCreatesRule() throws {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Remote"
        vm.urlText = "https://localhost:3000/v1/*"
        vm.method = .post
        vm.matchType = .wildcard
        vm.destScheme = "https"
        vm.destHost = "api.production.com"
        vm.destPort = "443"
        vm.destPath = "v2/api"
        vm.destQuery = "id=123"
        vm.preserveOriginalURL = true
        vm.preserveHost = true

        let rule = try #require(vm.makeRule())

        #expect(rule.name == "Remote")
        #expect(rule.matchCondition.method == "POST")
        #expect(rule.matchCondition.urlPattern == #"https:\/\/localhost:3000\/v1\/.*"#)
        if case let .mapRemote(config) = rule.action {
            #expect(config.scheme == "https")
            #expect(config.host == "api.production.com")
            #expect(config.port == 443)
            #expect(config.path == "/v2/api")
            #expect(config.query == "id=123")
            #expect(config.preserveOriginalURL)
            #expect(config.preserveHostHeader)
        } else {
            Issue.record("Expected .mapRemote")
        }
    }

    @Test("editor parses pasted destination URL into components")
    func editorParsesDestinationURL() {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)

        vm.tryParseDestinationURL("https://api.production.com:8443/v2/api?id=123")

        #expect(vm.destScheme == "https")
        #expect(vm.destHost == "api.production.com")
        #expect(vm.destPort == "8443")
        #expect(vm.destPath == "v2/api")
        #expect(vm.destQuery == "id=123")
    }

    @Test("editor loads existing rule with stable identity and flags")
    func editorLoadsExistingRule() {
        let existing = ProxyRule(
            name: "Existing",
            isEnabled: false,
            matchCondition: RuleMatchCondition(
                urlPattern: MapLocalPatternFormatter.wildcardToRegex("https://api.example.com/v1/*"),
                method: "DELETE",
                headerName: "X-Debug",
                headerValue: "1"
            ),
            action: .mapRemote(configuration: MapRemoteConfiguration(
                scheme: "http",
                host: "staging.example.com",
                port: 8_080,
                path: "/v2",
                query: "debug=true",
                preserveOriginalURL: true,
                preserveHostHeader: true
            )),
            priority: 42
        )
        let vm = MapRemoteEditorViewModel()
        vm.load(context: MapRemoteEditorContext(existingRule: existing))

        #expect(vm.existingID == existing.id)
        #expect(vm.name == "Existing")
        #expect(vm.method == .delete)
        #expect(vm.matchType == .wildcard)
        #expect(vm.urlText == "https://api.example.com/v1/*")
        #expect(vm.destScheme == "http")
        #expect(vm.destHost == "staging.example.com")
        #expect(vm.destPort == "8080")
        #expect(vm.destPath == "v2")
        #expect(vm.destQuery == "debug=true")
        #expect(vm.preserveOriginalURL)
        #expect(vm.preserveHost)
    }

    @Test("editor validation requires destination and valid port")
    func editorValidation() {
        let vm = MapRemoteEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Remote"
        vm.urlText = "https://api.example.com/*"

        #expect(!vm.isSaveEnabled)

        vm.destHost = "staging.example.com"
        #expect(vm.isSaveEnabled)

        vm.destPort = "abc"
        #expect(!vm.isSaveEnabled)

        vm.destPort = "70000"
        #expect(!vm.isSaveEnabled)
    }
}
