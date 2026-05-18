import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct MapLocalModelTests {
    @Test("filter matches name, method, URL, and local path")
    func filterMatchesVisibleColumns() {
        let vm = MapLocalViewModel()
        let apiRule = ProxyRule(
            name: "Users",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/users", method: "POST"),
            action: .mapLocal(filePath: "/tmp/users.json")
        )
        let assetRule = ProxyRule(
            name: "Assets",
            matchCondition: RuleMatchCondition(urlPattern: "https://cdn.example.com/.*", method: "GET"),
            action: .mapLocal(filePath: "/tmp/app.js")
        )
        vm.allRules = [apiRule, assetRule]

        vm.searchText = "post"
        #expect(vm.filteredRules.map(\.id) == [apiRule.id])

        vm.searchText = "app.js"
        #expect(vm.filteredRules.map(\.id) == [assetRule.id])
    }

    @Test("remove selected Map Local rows preserves unrelated rules")
    func removeSelectedPreservesOtherRules() async {
        await RuleTestLock.shared.acquire()
        let snapshot = await RuleEngine.shared.allRules
        await RuleEngine.shared.replaceAll([])

        let vm = MapLocalViewModel()
        let mapLocal = ProxyRule(
            name: "Local",
            matchCondition: RuleMatchCondition(urlPattern: "https://api.example.com/.*"),
            action: .mapLocal(filePath: "/tmp/local.json")
        )
        let block = ProxyRule(
            name: "Block",
            matchCondition: RuleMatchCondition(urlPattern: "https://blocked.example.com/.*"),
            action: .block(statusCode: 403)
        )
        vm.allRules = [mapLocal, block]
        vm.selectedRuleIDs = [mapLocal.id]

        vm.removeSelectedRules()

        #expect(vm.allRules.map(\.id) == [block.id])
        #expect(vm.selectedRuleIDs.isEmpty)

        await RuleEngine.shared.replaceAll(snapshot)
        await RuleTestLock.shared.release()
    }

    @Test("editor saves local file rule with method, delay, status, and preserved header condition")
    func editorCreatesRulePreservingHeaderFields() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalEditor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("response.json")

        let existing = ProxyRule(
            name: "Existing",
            isEnabled: false,
            matchCondition: RuleMatchCondition(
                urlPattern: "https://old.example.com/.*",
                method: "GET",
                headerName: "X-Debug",
                headerValue: "1"
            ),
            action: .mapLocal(filePath: fileURL.path, statusCode: 200, delayMs: 1_000),
            priority: 42
        )
        let vm = MapLocalEditorViewModel()
        vm.load(context: MapLocalEditorContext(existingRule: existing))
        vm.name = "Updated"
        vm.urlText = "https://api.example.com/v1/*"
        vm.matchType = .wildcard
        vm.method = .post
        vm.filePath = fileURL.path
        vm.delayPreset = .fiveSeconds
        vm.httpMessageText = """
        HTTP/1.1 202 Accepted
        Content-Type: application/json

        {"ok":true}
        """

        let rule = try #require(vm.makeRule())

        #expect(rule.id == existing.id)
        #expect(rule.name == "Updated")
        #expect(rule.isEnabled == false)
        #expect(rule.priority == 42)
        #expect(rule.matchCondition.method == "POST")
        #expect(rule.matchCondition.headerName == "X-Debug")
        #expect(rule.matchCondition.headerValue == "1")
        #expect(rule.matchCondition.urlPattern == #"https:\/\/api\.example\.com\/v1\/.*"#)

        if case let .mapLocal(path, statusCode, isDirectory, delayMs) = rule.action {
            #expect(path == fileURL.path)
            #expect(statusCode == 202)
            #expect(isDirectory == false)
            #expect(delayMs == 5_000)
        } else {
            Issue.record("Expected .mapLocal")
        }

        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(saved == #"{"ok":true}"#)
    }

    @Test("editor validates Local Directory target")
    func editorValidatesLocalDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RockxyTests-MapLocalDirTarget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let vm = MapLocalEditorViewModel()
        vm.load(context: .blank)
        vm.name = "Directory"
        vm.urlText = "https://assets.example.com/*"
        vm.targetMode = .localDirectory
        vm.localDirectoryEnabled = true
        vm.directoryPath = tempDir.path

        #expect(vm.isDirectoryValid)
        #expect(vm.isSaveEnabled)

        vm.directoryPath = tempDir.appendingPathComponent("missing").path
        #expect(!vm.isDirectoryValid)
        #expect(!vm.isSaveEnabled)
    }

    @Test("tool enable setter updates view model immediately")
    func toolEnableSetter() async {
        await RuleTestLock.shared.acquire()
        let vm = MapLocalViewModel(isToolEnabled: true)
        vm.setToolEnabled(false)
        #expect(vm.isToolEnabled == false)
        await RuleSyncService.setMapLocalToolEnabled(true)
        await RuleTestLock.shared.release()
    }
}
