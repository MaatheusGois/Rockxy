import Foundation

// MARK: - QuickPreviewDetector

enum QuickPreviewDetector {
    static let maxSelectionBytes = 256 * 1_024

    static func availableActions(for selection: String) -> [QuickPreviewAction] {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= maxSelectionBytes else
        {
            return []
        }

        var actions: [QuickPreviewAction] = []
        if isJSONObject(trimmed) {
            actions.append(.prettifyJSON)
        }
        if JWTPreviewDecoder.looksLikeJWT(trimmed) {
            actions.append(.decodeJWT)
        }
        if decodeBase64(trimmed) != nil {
            actions.append(.decodeBase64)
        }
        if !parseKeyValueRows(trimmed).isEmpty {
            actions.append(.keyValue)
        }
        return actions
    }

    static func preview(selection: String, action: QuickPreviewAction) -> QuickPreviewResult {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .error(title: String(localized: "No Selection"), message: String(localized: "Select text to preview."))
        }
        guard trimmed.utf8.count <= maxSelectionBytes else {
            return .error(
                title: String(localized: "Selection Too Large"),
                message: String(localized: "Selections over 256 KB are not previewed.")
            )
        }

        switch action {
        case .prettifyJSON:
            return prettifyJSON(trimmed)
        case .decodeBase64:
            return base64Preview(trimmed)
        case .keyValue:
            return keyValuePreview(trimmed)
        case .decodeJWT:
            return JWTPreviewDecoder.decode(trimmed)
        }
    }

    static func prettifyJSON(_ text: String) -> QuickPreviewResult {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: prettyData, encoding: .utf8)
        else {
            return .error(title: String(localized: "Invalid JSON"), message: String(localized: "Selection is not valid JSON."))
        }
        return .json(title: "JSON", text: pretty)
    }

    static func decodeBase64(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            trimmed,
            base64URLToBase64(trimmed),
        ]
        for candidate in candidates {
            var padded = candidate
            let remainder = padded.count % 4
            if remainder > 0 {
                padded.append(String(repeating: "=", count: 4 - remainder))
            }
            if let data = Data(base64Encoded: padded),
               let decoded = String(data: data, encoding: .utf8),
               !decoded.isEmpty
            {
                return decoded
            }
        }
        return nil
    }

    static func parseKeyValueRows(_ text: String) -> [QuickPreviewKeyValueRow] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        if trimmed.contains("&") {
            let rows = trimmed.split(separator: "&").compactMap { pair -> QuickPreviewKeyValueRow? in
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let key = parts.first, !key.isEmpty else {
                    return nil
                }
                let value = parts.count > 1 ? String(parts[1]) : ""
                return QuickPreviewKeyValueRow(key: decodeFormComponent(String(key)), value: decodeFormComponent(value))
            }
            if !rows.isEmpty {
                return rows
            }
        }

        return trimmed
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> QuickPreviewKeyValueRow? in
                let string = String(line)
                let separatorRange = string.range(of: ":") ?? string.range(of: "=")
                guard let separatorRange else {
                    return nil
                }
                let key = string[..<separatorRange.lowerBound].trimmingCharacters(in: .whitespaces)
                let value = string[separatorRange.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else {
                    return nil
                }
                return QuickPreviewKeyValueRow(key: key, value: value)
            }
    }

    private static func base64Preview(_ text: String) -> QuickPreviewResult {
        guard let decoded = decodeBase64(text) else {
            return .error(
                title: String(localized: "Invalid Base64"),
                message: String(localized: "Selection could not be decoded as Base64.")
            )
        }
        return .text(title: String(localized: "Decoded Base64"), text: decoded)
    }

    private static func keyValuePreview(_ text: String) -> QuickPreviewResult {
        let rows = parseKeyValueRows(text)
        guard !rows.isEmpty else {
            return .error(
                title: String(localized: "No Key-Value Pairs"),
                message: String(localized: "Selection does not contain key-value pairs.")
            )
        }
        return .keyValue(title: String(localized: "Key-Value"), rows: rows)
    }

    private static func isJSONObject(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return false
        }
        return JSONSerialization.isValidJSONObject(object)
    }

    private static func base64URLToBase64(_ text: String) -> String {
        text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
    }

    private static func decodeFormComponent(_ text: String) -> String {
        text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? text
    }
}
