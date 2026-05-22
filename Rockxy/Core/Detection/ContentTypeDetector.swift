import Foundation

/// Extracts the `Content-Type` header from an HTTP message and maps it
/// to a `ContentType` enum value used throughout the app for selecting
/// the appropriate inspector plugin and body renderer.
enum ContentTypeDetector {
    static func detect(headers: [HTTPHeader], body: Data?) -> ContentType {
        let headerValue = headers.first { $0.name.lowercased() == "content-type" }?.value
        let headerType = ContentType.detect(from: headerValue)
        guard headerType == .unknown else {
            return headerType
        }
        guard let body, looksLikeJSON(body) else {
            return headerType
        }
        return .json
    }

    private static func looksLikeJSON(_ body: Data) -> Bool {
        guard let text = String(data: body.prefix(4_096), encoding: .utf8) else {
            return false
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: body)) != nil
    }
}
