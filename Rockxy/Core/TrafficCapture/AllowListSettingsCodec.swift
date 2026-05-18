import Foundation
import os

// MARK: - AllowListSettingsCodec

/// Encodes and imports Allow List settings from Rockxy and compatible proxy-tool exports.
enum AllowListSettingsCodec {
    // MARK: Internal

    enum ImportError: LocalizedError {
        case invalidFormat
        case noRulesFound
        case invalidRegex(pattern: String, reason: String)
        case patternTooLong(pattern: String, limit: Int)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                String(localized: "The file is not a valid Allow List settings export.")
            case .noRulesFound:
                String(localized: "No Allow List rules found in the file.")
            case let .invalidRegex(pattern, reason):
                String(localized: "Invalid matching rule '\(pattern)': \(reason)")
            case let .patternTooLong(pattern, limit):
                String(localized: "Matching rule '\(pattern)' exceeds \(limit) characters.")
            }
        }
    }

    static func importFromProxyman(_ data: Data) throws -> [AllowListRule] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw ImportError.invalidFormat
        }
        let entries = extractJSONEntries(from: json)
        let rules = try buildRules(from: entries)
        guard !rules.isEmpty else {
            throw ImportError.noRulesFound
        }
        logger.info("Imported \(rules.count) Allow List rules from JSON settings")
        return rules
    }

    static func importFromCharlesProxy(_ data: Data) throws -> [AllowListRule] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            throw ImportError.invalidFormat
        }
        let entries = extractPlistEntries(from: plist)
        let rules = try buildRules(from: entries)
        guard !rules.isEmpty else {
            throw ImportError.noRulesFound
        }
        logger.info("Imported \(rules.count) Allow List rules from Charles Proxy settings")
        return rules
    }

    // MARK: Private

    private struct Entry {
        var name: String?
        var pattern: String
        var method: String?
        var matchType: RuleMatchType
        var isEnabled: Bool
        var includeSubpaths: Bool
    }

    private static let logger = Logger(
        subsystem: RockxyIdentity.current.logSubsystem,
        category: "AllowListSettingsCodec"
    )

    private static let maxRegexLength = 2_048

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

        let arrayKeys = [
            "allowRules",
            "allowList",
            "allowlist",
            "includeDomains",
            "domains",
            "rules",
            "entries",
            "locations",
            "location",
            "items",
        ]
        for key in arrayKeys {
            if let strings = dictionary[key] as? [String] {
                let entries = strings.compactMap { entry(pattern: $0, source: [:]) }
                if !entries.isEmpty {
                    return entries
                }
            }
            if let dictionaries = dictionary[key] as? [[String: Any]] {
                let entries = dictionaries.compactMap { entry(from: $0) }
                if !entries.isEmpty {
                    return entries
                }
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

        let arrayKeys = ["allowRules", "allowList", "allowlist", "rules", "entries", "locations", "location", "items"]
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
        if let url = stringValue(
            source,
            keys: ["url", "urlPattern", "pattern", "matchingRule", "matching_rule", "match", "value"]
        ) {
            return entry(pattern: url, source: source)
        }

        guard let rawHost = stringValue(source, keys: ["host", "domain", "hostname"]) else {
            return nil
        }
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            return nil
        }
        let path = stringValue(source, keys: ["path", "urlPath", "url_path"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/"
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let pattern = host == "*" ? "*" : "*\(host)\(normalizedPath)"
        return entry(pattern: pattern, source: source)
    }

    private static func entry(pattern rawPattern: String, source: [String: Any]) -> Entry? {
        let trimmedPattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else {
            return nil
        }

        let method = stringValue(source, keys: ["method", "httpMethod", "http_method"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let normalizedMethod = method == "ANY" ? nil : method
        let matchText = stringValue(source, keys: ["matchType", "match_type", "type"])?.lowercased() ?? ""
        let matchType: RuleMatchType = matchText.contains("regex") ? .regex : .wildcard

        return Entry(
            name: stringValue(source, keys: ["name", "title"]),
            pattern: trimmedPattern,
            method: normalizedMethod?.isEmpty == false ? normalizedMethod : nil,
            matchType: matchType,
            isEnabled: boolValue(source, keys: ["enabled", "isEnabled", "active"]) ?? true,
            includeSubpaths: boolValue(source, keys: ["includeSubpaths", "include_subpaths"]) ?? true
        )
    }

    private static func buildRules(from entries: [Entry]) throws -> [AllowListRule] {
        var seen = Set<String>()
        var rules: [AllowListRule] = []

        for entry in entries {
            try validate(entry)
            let method = entry.method?.isEmpty == false ? entry.method : nil
            let key = "\(entry.pattern)|\(method ?? "ANY")|\(entry.matchType.rawValue)|\(entry.includeSubpaths)"
                .lowercased()
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            let name = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            rules.append(AllowListRule(
                name: name?.isEmpty == false ? name ?? entry.pattern : entry.pattern,
                isEnabled: entry.isEnabled,
                rawPattern: entry.pattern,
                method: method,
                matchType: entry.matchType,
                includeSubpaths: entry.matchType == .wildcard ? entry.includeSubpaths : false
            ))
        }

        return rules
    }

    private static func validate(_ entry: Entry) throws {
        if entry.matchType == .regex, entry.pattern.count > maxRegexLength {
            throw ImportError.patternTooLong(pattern: entry.pattern, limit: maxRegexLength)
        }
        let source = RulePatternBuilder.regexSource(
            rawPattern: entry.pattern,
            matchType: entry.matchType,
            includeSubpaths: entry.includeSubpaths
        )
        do {
            _ = try NSRegularExpression(pattern: source)
        } catch {
            throw ImportError.invalidRegex(pattern: entry.pattern, reason: error.localizedDescription)
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
