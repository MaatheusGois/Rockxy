import Foundation

// MARK: - HostPatternMatcher

nonisolated enum HostPatternMatcher {
    static func matches(pattern: String, host: String) -> Bool {
        matches(host: host, pattern: pattern, extendedWildcards: false)
    }

    static func matches(host: String, pattern: String, extendedWildcards: Bool = true) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty, !normalizedPattern.isEmpty else {
            return false
        }

        if !extendedWildcards {
            if normalizedPattern.hasPrefix("*.") {
                let suffix = String(normalizedPattern.dropFirst(1))
                return normalizedHost.hasSuffix(suffix) && normalizedHost.count > suffix.count
            }
            return normalizedHost == normalizedPattern
        }

        let regex = "^" + NSRegularExpression.escapedPattern(for: normalizedPattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"
        return normalizedHost.range(of: regex, options: .regularExpression) != nil
    }

    static func isValid(pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 255 else {
            return false
        }
        guard trimmed.unicodeScalars.allSatisfy({ scalar in
            scalar.value >= 0x21 && scalar.value != 0x7F && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }) else {
            return false
        }
        return true
    }

    static func isLocalhost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "localhost"
            || normalized == "127.0.0.1"
            || normalized.hasPrefix("127.")
            || normalized == "::1"
            || normalized == "[::1]"
            || normalized.hasSuffix(".localhost")
    }
}
