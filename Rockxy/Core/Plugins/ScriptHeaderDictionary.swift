import Foundation

enum ScriptHeaderDictionary {
    static func storage(from headers: [HTTPHeader]) -> [String: String] {
        Dictionary(headers.map { ($0.name, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    static func exposed(from storage: [String: String]) -> [String: String] {
        var result = storage
        for (name, value) in storage {
            result[name.lowercased()] = value
            result[canonicalName(name)] = value
        }
        return result
    }

    static func storage(fromJavaScript dictionary: [String: String], original: [String: String] = [:]) -> [String: String] {
        let originalByLower = Dictionary(
            original.map { ($0.key.lowercased(), (name: $0.key, value: $0.value)) },
            uniquingKeysWith: { _, last in last }
        )
        let grouped = Dictionary(grouping: dictionary.map { (name: $0.key, value: $0.value) }) {
            $0.name.lowercased()
        }

        var collapsed: [String: String] = [:]
        for (lowerName, entries) in grouped {
            if let originalEntry = originalByLower[lowerName],
               entries.allSatisfy({ $0.value == originalEntry.value })
            {
                collapsed[originalEntry.name] = originalEntry.value
                continue
            }

            let originalValue = originalByLower[lowerName]?.value
            let changedEntries = entries.filter { entry in
                guard let originalValue else {
                    return false
                }
                return entry.value != originalValue
            }
            let candidates = changedEntries.isEmpty ? entries : changedEntries
            let selected = candidates.max { lhs, rhs in
                score(lhs.name, lowerName: lowerName, originalName: originalByLower[lowerName]?.name)
                    < score(rhs.name, lowerName: lowerName, originalName: originalByLower[lowerName]?.name)
            } ?? entries[0]
            collapsed[selected.name] = selected.value
        }
        return collapsed
    }

    private static func canonicalName(_ name: String) -> String {
        name.split(separator: "-", omittingEmptySubsequences: false)
            .map { part in
                guard let first = part.first else {
                    return ""
                }
                return first.uppercased() + part.dropFirst().lowercased()
            }
            .joined(separator: "-")
    }

    private static func score(_ name: String, lowerName: String, originalName: String?) -> Int {
        if name == canonicalName(name) {
            return 3
        }
        if let originalName, name == originalName {
            return 2
        }
        if name == lowerName {
            return 1
        }
        return 0
    }
}
