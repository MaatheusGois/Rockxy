import Foundation
import os

// MARK: - BlockListSettingsCodec

/// Encodes and imports Block List settings without touching non-block rules.
enum BlockListSettingsCodec {
    // MARK: Internal

    enum ImportError: LocalizedError {
        case invalidFormat
        case noRulesFound
        case invalidRegex(pattern: String, reason: String)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                String(localized: "The file is not a valid Block List settings export.")
            case .noRulesFound:
                String(localized: "No Block List rules found in the file.")
            case let .invalidRegex(pattern, reason):
                String(localized: "Invalid matching rule '\(pattern)': \(reason)")
            }
        }
    }

    static func exportRules(_ rules: [ProxyRule]) throws -> Data {
        let blockRules = rules.filter(\.isBlockRule)
        let payload = ExportPayload(version: 1, blockRules: blockRules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    static func importFromProxyman(_ data: Data) throws -> [ProxyRule] {
        if let payload = try? JSONDecoder().decode(ExportPayload.self, from: data) {
            let rules = try validate(payload.blockRules.filter(\.isBlockRule))
            guard !rules.isEmpty else {
                throw ImportError.noRulesFound
            }
            return rules
        }

        if let rules = try? JSONDecoder().decode([ProxyRule].self, from: data) {
            let blockRules = try validate(rules.filter(\.isBlockRule))
            guard !blockRules.isEmpty else {
                throw ImportError.noRulesFound
            }
            return blockRules
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw ImportError.invalidFormat
        }
        let entries = extractJSONEntries(from: json)
        let rules = try buildRules(from: entries)
        guard !rules.isEmpty else {
            throw ImportError.noRulesFound
        }
        Self.logger.info("Imported \(rules.count) Block List rules from JSON settings")
        return rules
    }

    static func importFromCharlesProxy(_ data: Data) throws -> [ProxyRule] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            throw ImportError.invalidFormat
        }
        let entries = extractPlistEntries(from: plist)
        let rules = try buildRules(from: entries)
        guard !rules.isEmpty else {
            throw ImportError.noRulesFound
        }
        Self.logger.info("Imported \(rules.count) Block List rules from Charles Proxy settings")
        return rules
    }

    // MARK: Private

    private struct ExportPayload: Codable {
        let format = "rockxy.block-list"
        let version: Int
        let blockRules: [ProxyRule]

        private enum CodingKeys: String, CodingKey {
            case format
            case version
            case blockRules
        }
    }

    private struct Entry {
        var name: String?
        var pattern: String
        var method: String?
        var matchType: RuleMatchType
        var statusCode: Int
        var isEnabled: Bool
        var includeSubpaths: Bool
    }

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "BlockListSettingsCodec"
    )

    private static func extractJSONEntries(from value: Any) -> [Entry] {
        if let strings = value as? [String] {
            return strings.compactMap { entry(pattern: $0, source: [:]) }
        }
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries.compactMap { entry(from: $0) }
        }
        guard let dictionary = value as? [String: Any] else {
            return []
        }

        let arrayKeys = ["blockRules", "rules", "entries", "locations", "location", "items"]
        for key in arrayKeys {
            if let strings = dictionary[key] as? [String] {
                return strings.compactMap { entry(pattern: $0, source: [:]) }
            }
            if let dictionaries = dictionary[key] as? [[String: Any]] {
                return dictionaries.compactMap { entry(from: $0) }
            }
        }

        return entry(from: dictionary).map { [$0] } ?? []
    }

    private static func extractPlistEntries(from value: Any) -> [Entry] {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries.compactMap { entry(from: $0) }
        }
        guard let dictionary = value as? [String: Any] else {
            return []
        }

        let arrayKeys = ["blockRules", "rules", "entries", "locations", "location", "items"]
        for key in arrayKeys {
            if let dictionaries = dictionary[key] as? [[String: Any]] {
                let entries = dictionaries.compactMap { entry(from: $0) }
                if !entries.isEmpty {
                    return entries
                }
            }
        }

        return entry(from: dictionary).map { [$0] } ?? []
    }

    private static func entry(from source: [String: Any]) -> Entry? {
        if let url = stringValue(source, keys: ["url", "urlPattern", "pattern", "matchingRule", "matching_rule"]) {
            return entry(pattern: url, source: source)
        }

        guard let host = stringValue(source, keys: ["host", "domain", "hostname"]) else {
            return nil
        }
        let path = stringValue(source, keys: ["path", "urlPath"]) ?? "/"
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let pattern = host == "*" ? "*" : "*\(host)\(normalizedPath)"
        return entry(pattern: pattern, source: source)
    }

    private static func entry(pattern rawPattern: String, source: [String: Any]) -> Entry? {
        let trimmedPattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else {
            return nil
        }

        let method = stringValue(source, keys: ["method", "httpMethod", "http_method"])?.uppercased()
        let normalizedMethod = method == "ANY" ? nil : method
        let action = stringValue(source, keys: ["action", "blockAction", "block_action"])?.lowercased() ?? ""
        let statusCode = intValue(source, keys: ["statusCode", "status", "code"]) ?? (action.contains("drop") ? 0 : 403)
        let matchText = stringValue(source, keys: ["matchType", "match_type", "type"])?.lowercased() ?? ""
        let matchType: RuleMatchType = matchText.contains("regex") ? .regex : .wildcard

        return Entry(
            name: stringValue(source, keys: ["name", "title"]),
            pattern: trimmedPattern,
            method: normalizedMethod,
            matchType: matchType,
            statusCode: statusCode,
            isEnabled: boolValue(source, keys: ["enabled", "isEnabled", "active"]) ?? true,
            includeSubpaths: boolValue(source, keys: ["includeSubpaths", "include_subpaths"]) ?? true
        )
    }

    private static func buildRules(from entries: [Entry]) throws -> [ProxyRule] {
        var seen = Set<String>()
        var rules: [ProxyRule] = []

        for entry in entries {
            let regex = RulePatternBuilder.regexSource(
                rawPattern: entry.pattern,
                matchType: entry.matchType,
                includeSubpaths: entry.includeSubpaths
            )
            let method = entry.method?.isEmpty == false ? entry.method : nil
            let key = "\(regex)|\(method ?? "ANY")|\(entry.statusCode)".lowercased()
            guard !seen.contains(key) else {
                continue
            }
            try validate(regex)
            seen.insert(key)
            let trimmedName = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            rules.append(ProxyRule(
                name: trimmedName?.isEmpty == false ? trimmedName ?? entry.pattern : entry.pattern,
                isEnabled: entry.isEnabled,
                matchCondition: RuleMatchCondition(urlPattern: regex, method: method),
                action: .block(statusCode: entry.statusCode)
            ))
        }

        return rules
    }

    private static func validate(_ rules: [ProxyRule]) throws -> [ProxyRule] {
        try rules.forEach { rule in
            if let pattern = rule.matchCondition.urlPattern {
                try validate(pattern)
            }
        }
        return rules
    }

    private static func validate(_ pattern: String) throws {
        if case let .failure(error) = RegexValidator.compile(pattern) {
            throw ImportError.invalidRegex(pattern: pattern, reason: error.localizedDescription)
        }
    }

    private static func stringValue(_ source: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = source[key] as? String {
                return value
            }
            if let value = source[key] {
                return String(describing: value)
            }
        }
        return nil
    }

    private static func intValue(_ source: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = source[key] as? Int {
                return value
            }
            if let value = source[key] as? String, let int = Int(value) {
                return int
            }
        }
        return nil
    }

    private static func boolValue(_ source: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = source[key] as? Bool {
                return value
            }
            if let value = source[key] as? String {
                return Bool(value)
            }
        }
        return nil
    }
}

private extension ProxyRule {
    var isBlockRule: Bool {
        if case .block = action {
            return true
        }
        return false
    }
}
