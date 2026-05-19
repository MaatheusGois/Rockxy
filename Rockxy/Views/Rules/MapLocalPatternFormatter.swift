import Foundation

// MARK: - MapLocalPatternFormatter

enum MapLocalPatternFormatter {
    static func wildcardToRegex(_ pattern: String) -> String {
        var result = ""
        for char in pattern {
            switch char {
            case "*":
                result += ".*"
            case "?":
                result += "."
            default:
                result += NSRegularExpression.escapedPattern(for: String(char))
            }
        }
        return result
    }

    static func readablePattern(_ pattern: String) -> String {
        pattern
            .trimmingCharacters(in: CharacterSet(charactersIn: "^$"))
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\."#, with: ".")
            .replacingOccurrences(of: ".*", with: "*")
            .trimmingCharacters(in: CharacterSet(charactersIn: "^$"))
    }

    static func prefersWildcardPresentation(_ pattern: String) -> Bool {
        pattern.contains(".*") || pattern.contains("\\.") || pattern.contains("\\/")
    }
}
