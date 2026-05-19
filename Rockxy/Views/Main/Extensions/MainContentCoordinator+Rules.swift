import Foundation
import os

// Extends `MainContentCoordinator` with rules behavior for the main workspace.

// MARK: - MainContentCoordinator + Rules

/// Coordinator extension for proxy rule management (block, map, breakpoint, throttle).
/// Delegates to `RulePolicyGate` which enforces per-category quotas before
/// forwarding to `RuleSyncService`.
extension MainContentCoordinator {
    // MARK: - Rule Management

    func addRule(_ rule: ProxyRule) {
        let gate = RulePolicyGate.shared
        ruleMutationTask = Task {
            let accepted = await gate.addRule(rule)
            if !accepted {
                Self.logger.info("Rule add rejected — quota reached for \(rule.action.toolCategory)")
                activeToast = ToastMessage(
                    style: .error,
                    text: String(localized: "Rule limit reached for this category")
                )
            }
        }
    }

    func removeRule(id: UUID) {
        let gate = RulePolicyGate.shared
        ruleMutationTask = Task { await gate.removeRule(id: id) }
    }

    func toggleRule(id: UUID) {
        let gate = RulePolicyGate.shared
        ruleMutationTask = Task {
            let accepted = await gate.toggleRule(id: id)
            if !accepted {
                Self.logger.info("Rule toggle rejected — quota reached")
                activeToast = ToastMessage(
                    style: .error,
                    text: String(localized: "Rule limit reached for this category")
                )
            }
        }
    }

    func createBreakpointRule(for transaction: HTTPTransaction) {
        let context = BreakpointEditorContextBuilder.fromTransaction(transaction)
        BreakpointEditorContextStore.shared.setPending(context)
        NotificationCenter.default.post(name: .openBreakpointRulesWindow, object: nil)
    }
}
