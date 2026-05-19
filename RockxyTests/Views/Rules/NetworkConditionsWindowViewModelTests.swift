import Foundation
@testable import Rockxy
import Testing

// MARK: - NetworkConditionsWindowViewModelTests

@MainActor
struct NetworkConditionsWindowViewModelTests {
    @Test
    func filteringMatchesNameHostAndPresetWhileIgnoringOtherRuleTypes() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let apiRule = networkRule(name: "3G API Slowdown", host: "api.proxyman.com", preset: .threeG)
        let checkoutRule = networkRule(name: "Checkout EDGE", host: "shop.example.com", preset: .edge)
        let blockRule = ProxyRule(
            name: "Blocked API",
            matchCondition: RuleMatchCondition(urlPattern: ".*api.proxyman.com.*"),
            action: .block(statusCode: 403)
        )
        seed(viewModel, rules: [apiRule, checkoutRule, blockRule])

        viewModel.searchText = "edge"
        #expect(viewModel.filteredRules.map(\.id) == [checkoutRule.id])

        viewModel.searchText = "proxyman"
        #expect(viewModel.filteredRules.map(\.id) == [apiRule.id])
    }

    @Test
    func toggleRuleEnforcesSingleActiveNetworkConditionOptimistically() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let activeRule = networkRule(name: "3G", host: "api.example.com", preset: .threeG, isEnabled: true)
        let inactiveRule = networkRule(name: "WiFi", host: "local.example.com", preset: .wifi, isEnabled: false)
        seed(viewModel, rules: [activeRule, inactiveRule])

        viewModel.toggleRule(id: inactiveRule.id)

        #expect(viewModel.allRules.first { $0.id == activeRule.id }?.isEnabled == false)
        #expect(viewModel.allRules.first { $0.id == inactiveRule.id }?.isEnabled == true)
        #expect(viewModel.activeCount == 1)
    }

    @Test
    func duplicateAndRemoveSelectedRuleUpdateSelection() throws {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let rule = networkRule(name: "Checkout EDGE", host: "shop.example.com", preset: .edge)
        seed(viewModel, rules: [rule])
        viewModel.selectedRuleID = rule.id

        viewModel.duplicateSelectedRule()

        #expect(viewModel.networkConditionRules.count == 2)
        let copy = try #require(viewModel.selectedRule)
        #expect(copy.id != rule.id)
        #expect(copy.name == "Copy of Checkout EDGE")
        #expect(copy.isEnabled == false)

        viewModel.removeSelectedRule()

        #expect(viewModel.networkConditionRules.count == 1)
        #expect(viewModel.selectedRuleID == nil)
    }

    @Test
    func disablingToolPreservesRuleEnabledStateAndPausesStatus() {
        let viewModel = NetworkConditionsWindowViewModel(commitChanges: false, isToolEnabled: true)
        let rule = networkRule(name: "3G API", host: "api.example.com", preset: .threeG, isEnabled: true)
        seed(viewModel, rules: [rule])

        viewModel.setToolEnabled(false)

        #expect(viewModel.allRules.first { $0.id == rule.id }?.isEnabled == true)
        #expect(viewModel.statusLabel(for: rule).0 == "Paused")
    }

    @Test
    func hostScopedPatternMatchesHTTPHTTPSAndOptionalPort() throws {
        let pattern = NetworkConditionsPatternFormatter.hostScopedPattern(from: "api.example.com")
        let regex = try NSRegularExpression(pattern: pattern)
        let condition = RuleMatchCondition(urlPattern: pattern)

        #expect(condition.matches(
            method: "GET",
            url: try #require(URL(string: "http://api.example.com/v1/users")),
            headers: [],
            compiledPattern: regex
        ))
        #expect(condition.matches(
            method: "GET",
            url: try #require(URL(string: "https://api.example.com:8443/v1/users")),
            headers: [],
            compiledPattern: regex
        ))
        #expect(!condition.matches(
            method: "GET",
            url: try #require(URL(string: "https://other.example.com/v1/users")),
            headers: [],
            compiledPattern: regex
        ))
    }

    @Test
    func hostScopedPatternRespectsExplicitPort() throws {
        let pattern = NetworkConditionsPatternFormatter.hostScopedPattern(from: "api.example.com:8443")
        let regex = try NSRegularExpression(pattern: pattern)
        let condition = RuleMatchCondition(urlPattern: pattern)

        #expect(condition.matches(
            method: "GET",
            url: try #require(URL(string: "https://api.example.com:8443/v1/users")),
            headers: [],
            compiledPattern: regex
        ))
        #expect(!condition.matches(
            method: "GET",
            url: try #require(URL(string: "https://api.example.com:9443/v1/users")),
            headers: [],
            compiledPattern: regex
        ))
    }

    private func seed(_ viewModel: NetworkConditionsWindowViewModel, rules: [ProxyRule]) {
        viewModel.handleRulesDidChange(Notification(name: .rulesDidChange, object: rules))
    }

    private func networkRule(
        name: String,
        host: String,
        preset: NetworkConditionPreset,
        isEnabled: Bool = true
    ) -> ProxyRule {
        ProxyRule(
            name: name,
            isEnabled: isEnabled,
            matchCondition: RuleMatchCondition(urlPattern: ".*\(NSRegularExpression.escapedPattern(for: host)).*"),
            action: .networkCondition(preset: preset, delayMs: preset.defaultLatencyMs)
        )
    }
}
