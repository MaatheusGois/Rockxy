import Foundation
@testable import Rockxy
import Testing

@Suite(.serialized)
@MainActor
struct ProtobufMappingRuleStoreTests {
    @Test("add, persist, reload, toggle, duplicate, and delete mapping rules")
    func mappingRuleLifecycle() throws {
        let suiteName = "protobuf.mapping.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProtobufMappingRuleStore(userDefaults: defaults)
        let rule = ProtobufMappingRule(
            urlPattern: "/v1/*",
            method: .post,
            messageType: "api.v1.Message",
            payloadEncoding: .singleMessage
        )

        try store.addRule(rule)

        #expect(store.rules == [rule])
        #expect(store.selectedRuleID == rule.id)

        let reloaded = ProtobufMappingRuleStore(userDefaults: defaults)
        #expect(reloaded.rules == [rule])

        reloaded.toggleRule(id: rule.id)
        #expect(reloaded.rules.first?.isEnabled == false)

        reloaded.duplicateSelectedRule()
        #expect(reloaded.rules.count == 1)

        reloaded.selectedRuleID = rule.id
        reloaded.duplicateSelectedRule()
        #expect(reloaded.rules.count == 2)
        #expect(reloaded.rules[1].id != rule.id)
        #expect(reloaded.rules[1].urlPattern == "/v1/*")
        #expect(reloaded.rules[1].messageType == "api.v1.Message")

        reloaded.removeSelectedRule()
        #expect(reloaded.rules.count == 1)
    }

    @Test("validation rejects empty rule and invalid message type")
    func validation() throws {
        #expect(throws: ProtobufMappingRuleValidationError.emptyPattern) {
            try ProtobufMappingRuleStore.validate(ProtobufMappingRule(urlPattern: "   "))
        }

        #expect(throws: ProtobufMappingRuleValidationError.invalidMessageType) {
            try ProtobufMappingRuleStore.validate(ProtobufMappingRule(
                urlPattern: "/v1/*",
                messageType: "api.Message<Bad>"
            ))
        }

        try ProtobufMappingRuleStore.validate(ProtobufMappingRule(
            urlPattern: "/v1/*",
            messageType: "api.v1.Message_Name$Nested"
        ))
    }

    @Test("schema label falls back when mapping has no schema")
    func schemaNameFallback() throws {
        let suiteName = "protobuf.mapping.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProtobufMappingRuleStore(userDefaults: defaults)
        let schema = ProtobufSchemaDescriptor(fileName: "service.proto", hostPattern: "*")

        #expect(store.schemaName(for: nil, schemas: [schema]) == "Not selected")
        #expect(store.schemaName(for: UUID(), schemas: [schema]) == "Not selected")
        #expect(store.schemaName(for: schema.id, schemas: [schema]) == "service.proto")
    }
}
