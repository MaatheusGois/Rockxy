@testable import Rockxy
import Testing

// MARK: - ExportScopeTests

struct ExportScopeTests {
    @Test("OpenAPI context disables scopes with no eligible requests")
    func disablesIneligibleOpenAPIScopes() {
        let context = ExportScopeContext(
            format: .openAPIYAML,
            allCount: 3,
            filteredCount: 2,
            selectedCount: 1,
            eligibleAllCount: 2,
            eligibleFilteredCount: 0,
            eligibleSelectedCount: 0,
            initialScope: .all
        )

        #expect(context.isEnabled(.all))
        #expect(!context.isEnabled(.filtered))
        #expect(!context.isEnabled(.selected))
        #expect(context.label(for: .all) == "All Captured Requests")
    }

    @Test("HAR context preserves transaction copy")
    func harContextLabels() {
        let context = ExportScopeContext(
            format: .har,
            allCount: 3,
            filteredCount: 3,
            selectedCount: 0,
            eligibleAllCount: 3,
            eligibleFilteredCount: 3,
            eligibleSelectedCount: 0,
            initialScope: .all
        )

        #expect(context.label(for: .all) == "All Transactions")
        #expect(!context.isEnabled(.filtered))
        #expect(!context.isEnabled(.selected))
    }
}
