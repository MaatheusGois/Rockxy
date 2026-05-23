import Foundation

// MARK: - RuleMatchType

/// Shared match type for URL pattern matching across all rule editors (Block List, Breakpoint, etc.).
enum RuleMatchType: String, Codable, CaseIterable, Identifiable {
    case wildcard = "Use Wildcard"
    case regex = "Use Regex"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        rawValue
    }
}
