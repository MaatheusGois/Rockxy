import Foundation
import Observation
import os

// MARK: - ProtobufMappingRuleStore

@MainActor @Observable
final class ProtobufMappingRuleStore {
    // MARK: Lifecycle

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.rules = Self.loadRules(from: userDefaults)
    }

    // MARK: Internal

    private(set) var rules: [ProtobufMappingRule]

    var selectedRuleID: UUID?

    var selectedRule: ProtobufMappingRule? {
        guard let selectedRuleID else {
            return nil
        }
        return rules.first { $0.id == selectedRuleID }
    }

    static func validate(_ rule: ProtobufMappingRule) throws {
        guard !rule.urlPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProtobufMappingRuleValidationError.emptyPattern
        }
        try validateMessageType(rule.messageType)
        try validateMessageType(rule.requestMessageType ?? "")
        try validateMessageType(rule.responseMessageType ?? "")
    }

    func addRule(_ rule: ProtobufMappingRule) throws {
        try Self.validate(rule)
        rules.append(rule)
        selectedRuleID = rule.id
        persist()
    }

    func updateRule(_ rule: ProtobufMappingRule) throws {
        try Self.validate(rule)
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }
        rules[index] = rule
        selectedRuleID = rule.id
        persist()
    }

    func removeSelectedRule() {
        guard let selectedRuleID else {
            return
        }
        removeRule(id: selectedRuleID)
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        if selectedRuleID == id {
            selectedRuleID = nil
        }
        persist()
    }

    func duplicateSelectedRule() {
        guard let selectedRule else {
            return
        }
        var copy = selectedRule
        copy = ProtobufMappingRule(
            isEnabled: selectedRule.isEnabled,
            urlPattern: selectedRule.urlPattern,
            method: selectedRule.method,
            matchType: selectedRule.matchType,
            includeSubpaths: selectedRule.includeSubpaths,
            schemaID: selectedRule.schemaID,
            messageType: selectedRule.messageType,
            requestMessageType: selectedRule.requestMessageType,
            responseMessageType: selectedRule.responseMessageType,
            payloadEncoding: selectedRule.payloadEncoding
        )
        rules.append(copy)
        selectedRuleID = copy.id
        persist()
    }

    func toggleRule(id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }
        rules[index].isEnabled.toggle()
        persist()
    }

    func schemaName(for id: UUID?, schemas: [ProtobufSchemaDescriptor]) -> String {
        guard let id,
              let schema = schemas.first(where: { $0.id == id }) else
        {
            return String(localized: "Not selected")
        }
        return schema.fileName
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProtobufDecoder")
    private static let userDefaultsKey = "protobuf.mappingRules.v1"

    private let userDefaults: UserDefaults

    private static func loadRules(from userDefaults: UserDefaults) -> [ProtobufMappingRule] {
        guard let data = userDefaults.data(forKey: userDefaultsKey),
              let rules = try? JSONDecoder().decode([ProtobufMappingRule].self, from: data) else
        {
            return []
        }
        return rules
    }

    private static func validateMessageType(_ value: String) throws {
        guard !value.isEmpty else {
            return
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.$"))
        if value.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw ProtobufMappingRuleValidationError.invalidMessageType
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(rules)
            userDefaults.set(data, forKey: Self.userDefaultsKey)
        } catch {
            Self.logger.error("Failed to persist Protobuf mapping rules: \(error.localizedDescription)")
        }
    }
}
