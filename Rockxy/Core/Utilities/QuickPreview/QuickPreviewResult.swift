import Foundation

// MARK: - QuickPreviewAction

enum QuickPreviewAction: String, CaseIterable, Sendable {
    case prettifyJSON
    case decodeBase64
    case keyValue
    case decodeJWT

    var displayName: String {
        switch self {
        case .prettifyJSON: String(localized: "Prettify JSON")
        case .decodeBase64: String(localized: "Decode Base64")
        case .keyValue: String(localized: "Display as Key-Value")
        case .decodeJWT: String(localized: "Decode JWT")
        }
    }
}

// MARK: - QuickPreviewResult

enum QuickPreviewResult: Equatable, Sendable {
    case json(title: String, text: String)
    case text(title: String, text: String)
    case keyValue(title: String, rows: [QuickPreviewKeyValueRow])
    case jwt(JWTPreview)
    case error(title: String, message: String)

    var copyText: String {
        switch self {
        case let .json(_, text),
             let .text(_, text):
            text
        case let .keyValue(_, rows):
            rows.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        case let .jwt(preview):
            preview.copyText
        case let .error(title, message):
            "\(title)\n\(message)"
        }
    }
}

// MARK: - QuickPreviewKeyValueRow

struct QuickPreviewKeyValueRow: Equatable, Identifiable, Sendable {
    let id: String
    let key: String
    let value: String

    init(key: String, value: String) {
        self.id = key
        self.key = key
        self.value = value
    }
}
