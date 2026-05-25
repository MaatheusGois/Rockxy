import Foundation
@testable import Rockxy
import Testing

struct JWTPreviewDecoderTests {
    @Test("Decodes bearer JWT and marks signature as not verified")
    func decodesBearerJWT() throws {
        let token = makeToken(
            header: ["alg": "HS256", "typ": "JWT"],
            payload: [
                "iss": "rockxy",
                "sub": "user-1",
                "aud": ["mac", "proxy"],
                "exp": 2_000_000_000,
                "iat": 1_700_000_000,
            ],
            signature: "signature"
        )

        let preview = try JWTPreviewDecoder.decodePreview("Bearer \(token)", now: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(preview.headerText.contains(#""alg" : "HS256""#))
        #expect(preview.payloadText.contains(#""sub" : "user-1""#))
        #expect(preview.claims.issuer == "rockxy")
        #expect(preview.claims.audience == "mac, proxy")
        #expect(preview.warnings.contains { $0.message == "Decoded only. Signature not verified." })
        #expect(preview.copyText.contains("Signature:"))
    }

    @Test("Tolerates Base64URL segments without padding")
    func decodesUnpaddedBase64URL() throws {
        let token = makeToken(
            header: ["alg": "HS256"],
            payload: ["sub": "padding-test"],
            signature: "abc"
        )

        let preview = try JWTPreviewDecoder.decodePreview(token)

        #expect(preview.payloadText.contains("padding-test"))
    }

    @Test("Rejects malformed segment counts")
    func rejectsMalformedSegmentCounts() {
        #expect(throws: JWTPreviewError.invalidSegmentCount) {
            _ = try JWTPreviewDecoder.decodePreview("one.two")
        }
    }

    @Test("Rejects invalid JSON payload")
    func rejectsInvalidJSONPayload() {
        let token = [
            base64URL(#"{"alg":"HS256"}"#),
            base64URL("not-json"),
            "signature",
        ].joined(separator: ".")

        #expect(throws: JWTPreviewError.invalidJSON("payload")) {
            _ = try JWTPreviewDecoder.decodePreview(token)
        }
    }

    @Test("Flags expired, future nbf, alg none, and empty signature")
    func flagsJWTWarnings() throws {
        let token = makeToken(
            header: ["alg": "none"],
            payload: [
                "exp": 1_000,
                "nbf": 3_000,
                "iat": 900,
            ],
            signature: ""
        )

        let preview = try JWTPreviewDecoder.decodePreview(token, now: Date(timeIntervalSince1970: 2_000))
        let messages = preview.warnings.map(\.message)

        #expect(messages.contains("Header uses alg: none."))
        #expect(messages.contains("Signature segment is empty."))
        #expect(messages.contains("Token is expired."))
        #expect(messages.contains("Token is not valid yet."))
    }
}

private func makeToken(header: [String: Any], payload: [String: Any], signature: String) -> String {
    [
        base64URL(jsonString(header)),
        base64URL(jsonString(payload)),
        signature,
    ].joined(separator: ".")
}

private func jsonString(_ object: [String: Any]) -> String {
    do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    } catch {
        preconditionFailure("JWT test fixture must be JSON-serializable: \(error)")
    }
}

private func base64URL(_ string: String) -> String {
    Data(string.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
