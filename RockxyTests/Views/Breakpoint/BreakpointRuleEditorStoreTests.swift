import Foundation
@testable import Rockxy
import Testing

@MainActor
struct BreakpointRuleEditorStoreTests {
    @Test("openNew stores quick-create context and clears editing rule")
    func openNewStoresQuickCreateContext() {
        let store = BreakpointRuleEditorStore.shared
        let baseline = store.draftVersion
        let context = BreakpointEditorContextBuilder.fromDomain("example.com")
        var didSave = false

        store.openNew(context: context) { _, _, _, _, _, _, _ in
            didSave = true
        }

        store.onSave?("", "", .any, .wildcard, true, true, true)

        #expect(store.editorContext?.sourceHost == "example.com")
        #expect(store.editingRule == nil)
        #expect(store.draftVersion == baseline &+ 1)
        #expect(didSave)
    }

    @Test("openExisting stores editing rule and clears quick-create context")
    func openExistingStoresEditingRule() {
        let store = BreakpointRuleEditorStore.shared
        let baseline = store.draftVersion
        let rule = ProxyRule(
            name: "Edit me",
            matchCondition: RuleMatchCondition(urlPattern: "https://example.com/.*"),
            action: .breakpoint(phase: .both)
        )

        store.openExisting(rule) { _, _, _, _, _, _, _ in }

        #expect(store.editingRule?.id == rule.id)
        #expect(store.editorContext == nil)
        #expect(store.draftVersion == baseline &+ 1)
    }
}
