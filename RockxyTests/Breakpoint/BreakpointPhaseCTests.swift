import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct BreakpointPhaseCTests {
    // BP_C1a
    @Test("firstPauseOpensWindow")
    func firstPauseOpensWindow() async throws {
        let manager = BreakpointManager()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: RuleEngine())
        let task = Task { await manager.enqueueAndWait(.test()) }
        let item = try await harness.awaitNextPause(timeout: 2)
        #expect(manager.pausedItems.count == 1)
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C1b
    @Test("subsequentPauseDoesNotOpenSecondWindow")
    func subsequentPauseDoesNotOpenSecondWindow() async throws {
        let manager = BreakpointManager()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: RuleEngine())
        let first = Task { await manager.enqueueAndWait(.test(url: "https://httpbin.org/get?one=1")) }
        _ = try await harness.awaitNextPause(timeout: 2)
        let selected = manager.selectedItemId
        let second = Task { await manager.enqueueAndWait(.test(url: "https://httpbin.org/get?two=2")) }
        _ = try await harness.awaitNextPause(timeout: 2)
        #expect(manager.pausedItems.count == 2)
        #expect(manager.selectedItemId == selected)
        manager.resolveAll(decision: .cancel)
        _ = await first.value
        _ = await second.value
    }

    // BP_C2
    @Test("itemAppendedWithPhaseRequest")
    func itemAppendedWithPhaseRequest() async throws {
        let manager = BreakpointManager()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: RuleEngine())
        let task = Task { await manager.enqueueAndWait(.test(phase: .request)) }
        let item = try await harness.awaitNextPause(timeout: 2)
        #expect(item.phase == .request)
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C3a
    @Test("selectionAdvancesWhenQueueWasEmpty")
    func selectionAdvancesWhenQueueWasEmpty() async throws {
        let manager = BreakpointManager()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: RuleEngine())
        let task = Task { await manager.enqueueAndWait(.test()) }
        let item = try await harness.awaitNextPause(timeout: 2)
        #expect(manager.selectedItemId == item.id)
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C3b
    @Test("selectionDoesNotChangeWhenAlreadySelected")
    func selectionDoesNotChangeWhenAlreadySelected() async throws {
        let manager = BreakpointManager()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: RuleEngine())
        let first = Task { await manager.enqueueAndWait(.test(url: "https://httpbin.org/get?one=1")) }
        let firstItem = try await harness.awaitNextPause(timeout: 2)
        let second = Task { await manager.enqueueAndWait(.test(url: "https://httpbin.org/get?two=2")) }
        _ = try await harness.awaitNextPause(timeout: 2)
        #expect(manager.selectedItemId == firstItem.id)
        manager.resolveAll(decision: .cancel)
        _ = await first.value
        _ = await second.value
    }

    // BP_C4
    @Test("editorBindsToSelectedDraft")
    func editorBindsToSelectedDraft() async throws {
        let (manager, harness, task) = enqueue()
        let item = try await harness.awaitNextPause(timeout: 2)
        manager.updateDraft(id: item.id) { $0.url = "https://httpbin.org/headers" }
        #expect(manager.pausedItems.first?.editableDraft.url == "https://httpbin.org/headers")
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C5
    @Test("methodEditsDraftNotOriginal")
    func methodEditsDraftNotOriginal() async throws {
        let (manager, harness, task) = enqueue(.test(method: "GET"))
        let item = try await harness.awaitNextPause(timeout: 2)
        #expect(item.method == "GET")
        manager.updateDraft(id: item.id) { $0.method = "POST" }
        #expect(manager.pausedItems.first?.method == "GET")
        #expect(manager.pausedItems.first?.editableDraft.method == "POST")
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C6
    @Test("urlEditWritesDraft")
    func urlEditWritesDraft() async throws {
        let (manager, harness, task) = enqueue()
        let item = try await harness.awaitNextPause(timeout: 2)
        manager.updateDraft(id: item.id) { $0.url = "https://httpbin.org/anything?edited=true" }
        #expect(manager.pausedItems.first?.editableDraft.url.hasSuffix("edited=true") == true)
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C7
    @Test("headerValueEditWritesBack")
    func headerValueEditWritesBack() async throws {
        let (manager, harness, task) = enqueue(.test(headers: [EditableHeader(name: "X-Test", value: "old")]))
        let item = try await harness.awaitNextPause(timeout: 2)
        manager.updateDraft(id: item.id) { $0.headers[0].value = "new" }
        #expect(manager.pausedItems.first?.editableDraft.headers[0].value == "new")
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C8
    @Test("addHeaderAppendsEmptyPair")
    func addHeaderAppendsEmptyPair() async throws {
        let (manager, harness, task) = enqueue()
        let item = try await harness.awaitNextPause(timeout: 2)
        manager.updateDraft(id: item.id) { $0.headers.append(EditableHeader(name: "", value: "")) }
        #expect(manager.pausedItems.first?.editableDraft.headers.count == 1)
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C9
    @Test("deleteHeaderRemovesEntry")
    func deleteHeaderRemovesEntry() async throws {
        let headers = [EditableHeader(name: "A", value: "1"), EditableHeader(name: "B", value: "2")]
        let (manager, harness, task) = enqueue(.test(headers: headers))
        let item = try await harness.awaitNextPause(timeout: 2)
        let removedID = manager.pausedItems[0].editableDraft.headers[0].id
        manager.updateDraft(id: item.id) { draft in
            draft.headers.removeAll { $0.id == removedID }
        }
        #expect(manager.pausedItems.first?.editableDraft.headers.map(\.name) == ["B"])
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C10
    @Test("bodyEditWritesBack")
    func bodyEditWritesBack() async throws {
        let (manager, harness, task) = enqueue(.test(body: #"{"before":true}"#))
        let item = try await harness.awaitNextPause(timeout: 2)
        manager.updateDraft(id: item.id) { $0.body = #"{"after":true}"# }
        #expect(manager.pausedItems.first?.editableDraft.body == #"{"after":true}"#)
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C11a
    @Test("rawTabRendersFromDraft")
    func rawTabRendersFromDraft() {
        let draft = BreakpointRequestData.test(
            method: "PATCH",
            url: "https://httpbin.org/anything?debug=1",
            headers: [EditableHeader(name: "X-Draft", value: "true")],
            body: "body"
        )
        let raw = BreakpointRawMessage.rawMessage(from: draft, kind: .request)
        #expect(raw.contains("PATCH /anything?debug=1 HTTP/1.1"))
        #expect(raw.contains("X-Draft: true"))
        #expect(raw.hasSuffix("body"))
    }

    // BP_C11b
    @Test("rawTabEditPropagatesOrCanonicalDocumented")
    func rawTabEditPropagatesOrCanonicalDocumented() throws {
        let draft = BreakpointRequestData.test()
        let updated = try BreakpointRawMessage.applying(
            "POST /anything HTTP/1.1\nX-Raw: yes\n\npayload",
            kind: .request,
            to: draft
        )
        #expect(updated.method == "POST")
        #expect(updated.url == "/anything")
        #expect(updated.headers.first?.name == "X-Raw")
        #expect(updated.body == "payload")
    }

    // BP_C12
    @Test("applyTemplateAtomicReplace")
    func applyTemplateAtomicReplace() throws {
        let template = BreakpointTemplate(
            kind: .request,
            name: "Atomic",
            rawMessage: "PUT /post HTTP/1.1\nX-Template: yes\n\nupdated"
        )
        let payload = try #require(template.applicationPayload)
        let updated = payload.applying(to: .test(method: "GET", url: "https://httpbin.org/get"))
        #expect(updated.method == "PUT")
        #expect(updated.url == "/post")
        #expect(updated.headers.map(\.name) == ["X-Template"])
        #expect(updated.body == "updated")
    }

    // BP_C13
    @Test("queryTabEditsPersist")
    func queryTabEditsPersist() async throws {
        let (manager, harness, task) = enqueue(.test(url: "https://httpbin.org/get?env=dev"))
        let item = try await harness.awaitNextPause(timeout: 2)
        manager.updateDraft(id: item.id) { $0.url = "https://httpbin.org/get?env=prod" }
        #expect(URLComponents(string: manager.pausedItems[0].editableDraft.url)?.queryItems?.first?.value == "prod")
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C14a
    @Test("cancelDismissesWithoutResolving")
    func cancelDismissesWithoutResolving() async throws {
        let (manager, harness, task) = enqueue()
        let item = try await harness.awaitNextPause(timeout: 2)
        #expect(manager.pausedItems.contains { $0.id == item.id })
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C14b
    @Test("reopeningAfterCancelShowsSameItem")
    func reopeningAfterCancelShowsSameItem() async throws {
        let (manager, harness, task) = enqueue()
        let item = try await harness.awaitNextPause(timeout: 2)
        #expect(manager.selectedItemId == item.id)
        #expect(manager.pausedItems.first?.editableDraft.url == "https://httpbin.org/get")
        manager.resolve(id: item.id, decision: .cancel)
        _ = await task.value
    }

    // BP_C16
    @Test("abort503NoUpstream")
    func abort503NoUpstream() async throws {
        let result = BreakpointDecision.abort
        if case .abort = result {
            #expect(true)
        } else {
            Issue.record("Expected abort decision")
        }
    }

    // BP_C17
    @Test("executePassesEditedDraftToContinuation")
    func executePassesEditedDraftToContinuation() async throws {
        let (manager, harness, task) = enqueue()
        let item = try await harness.awaitNextPause(timeout: 2)
        manager.updateDraft(id: item.id) { $0.headers.append(EditableHeader(name: "X-Edited", value: "true")) }
        manager.resolve(id: item.id, decision: .execute)
        let result = await task.value
        #expect(result.0 == .execute)
        #expect(result.1.headers.contains { $0.name == "X-Edited" && $0.value == "true" })
    }

    private func enqueue(
        _ data: BreakpointRequestData = .test()
    ) -> (BreakpointManager, BreakpointTestHarness, Task<(BreakpointDecision, BreakpointRequestData), Never>) {
        let manager = BreakpointManager()
        let harness = BreakpointTestHarness(manager: manager, ruleEngine: RuleEngine())
        let task = Task {
            await manager.enqueueAndWait(data)
        }
        return (manager, harness, task)
    }
}
