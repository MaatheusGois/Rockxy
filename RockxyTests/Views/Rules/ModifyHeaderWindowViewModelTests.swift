import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct ModifyHeaderWindowViewModelTests {
    @Test("new editor operation defaults to Set so existing header values are replaced")
    func newOperationDefaultsToSet() {
        let operation = EditableHeaderOperation()

        #expect(operation.type == .replace)
        #expect(operation.type.editorLabel == "Set")
    }

    @Test("saveRule waits for persistence path and reloads saved Modify Header rule")
    func saveRulePersistsBeforeReturning() async throws {
        await withSharedRuleStateRestored {
            let viewModel = ModifyHeaderWindowViewModel()
            let operation = EditableHeaderOperation(
                type: .replace,
                headerName: "Authorization",
                headerValue: "Bearer demo-access-token"
            )

            let accepted = await viewModel.saveRule(
                existingRule: nil,
                ruleName: "Profile Auth",
                urlPattern: "127.0.0.1:43210/rockxy-demo/profile",
                httpMethod: .any,
                matchType: .wildcard,
                includeSubpaths: false,
                operations: [operation]
            )

            #expect(accepted)
            let loaded = await RuleEngine.shared.allRules.filter { rule in
                if case .modifyHeader = rule.action {
                    return true
                }
                return false
            }
            #expect(loaded.count == 1)
            #expect(viewModel.modifyHeaderRules.map(\.id) == loaded.map(\.id))

            guard let saved = loaded.first else {
                Issue.record("Expected saved Modify Header rule")
                return
            }
            #expect(saved.name == "Profile Auth")
            #expect(saved.matchCondition.method == nil)
            #expect(saved.matchCondition.urlPattern == #"127\.0\.0\.1:43210\/rockxy-demo\/profile($|[?#])"#)

            if case let .modifyHeader(operations) = saved.action {
                #expect(operations.count == 1)
                #expect(operations[0].type == .replace)
                #expect(operations[0].headerName == "Authorization")
                #expect(operations[0].headerValue == "Bearer demo-access-token")
                #expect(operations[0].phase == .request)
            } else {
                Issue.record("Expected Modify Header action")
            }
        }
    }

    // MARK: Private

    private func withSharedRuleStateRestored(_ body: () async -> Void) async {
        await RuleTestLock.shared.acquire()
        let rulesSnapshot = await RuleEngine.shared.allRules
        let gateSnapshot = RulePolicyGate.shared

        RulePolicyGate.shared = RulePolicyGate(policy: DefaultAppPolicy())
        await RuleSyncService.replaceAllRules([])
        await body()

        await RuleSyncService.replaceAllRules(rulesSnapshot)
        RulePolicyGate.shared = gateSnapshot
        await RuleTestLock.shared.release()
    }
}
