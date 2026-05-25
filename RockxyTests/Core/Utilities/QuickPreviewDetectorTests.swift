import Foundation
@testable import Rockxy
import Testing

struct QuickPreviewDetectorTests {
    @Test("Detects JSON, Base64, JWT, and key-value preview actions")
    func detectsAvailableActions() {
        #expect(QuickPreviewDetector.availableActions(for: #"{"name":"Rockxy"}"#).contains(.prettifyJSON))
        #expect(QuickPreviewDetector.availableActions(for: "SGVsbG8=").contains(.decodeBase64))
        #expect(QuickPreviewDetector.availableActions(for: "a=1&b=hello+mac").contains(.keyValue))

        let jwt = [
            base64URL(#"{"alg":"HS256"}"#),
            base64URL(#"{"sub":"123"}"#),
            "signature",
        ].joined(separator: ".")
        #expect(QuickPreviewDetector.availableActions(for: "Bearer \(jwt)").contains(.decodeJWT))
    }

    @Test("Prettifies JSON without mutating the source")
    func prettifiesJSON() throws {
        let result = QuickPreviewDetector.preview(selection: #"{"b":2,"a":1}"#, action: .prettifyJSON)
        guard case let .json(_, text) = result else {
            Issue.record("Expected JSON result")
            return
        }

        #expect(text.contains(#""a" : 1"#))
        #expect(text.contains(#""b" : 2"#))
    }

    @Test("Decodes Base64URL text with padding tolerance")
    func decodesBase64URL() throws {
        let result = QuickPreviewDetector.preview(selection: "SGVsbG8td29ybGQ", action: .decodeBase64)
        guard case let .text(_, text) = result else {
            Issue.record("Expected text result")
            return
        }

        #expect(text == "Hello-world")
    }

    @Test("Parses query and header-style key-value selections")
    func parsesKeyValueRows() {
        let queryRows = QuickPreviewDetector.parseKeyValueRows("name=Rockxy&lang=Swift+macOS")
        let headerRows = QuickPreviewDetector.parseKeyValueRows("Host: api.example.com\nAccept=application/json")

        #expect(queryRows == [
            QuickPreviewKeyValueRow(key: "name", value: "Rockxy"),
            QuickPreviewKeyValueRow(key: "lang", value: "Swift macOS"),
        ])
        #expect(headerRows == [
            QuickPreviewKeyValueRow(key: "Host", value: "api.example.com"),
            QuickPreviewKeyValueRow(key: "Accept", value: "application/json"),
        ])
    }

    @Test("Rejects oversized selections")
    func rejectsOversizedSelections() {
        let selection = String(repeating: "a", count: QuickPreviewDetector.maxSelectionBytes + 1)

        #expect(QuickPreviewDetector.availableActions(for: selection).isEmpty)
        guard case let .error(title, _) = QuickPreviewDetector.preview(selection: selection, action: .decodeBase64) else {
            Issue.record("Expected oversized-selection error")
            return
        }
        #expect(title == "Selection Too Large")
    }
}

private func base64URL(_ string: String) -> String {
    Data(string.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
