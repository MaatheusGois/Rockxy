import Foundation

// MARK: - JWTPreviewDecoder

enum JWTPreviewDecoder {
    private static let bearerPrefix = "bearer "

    static func decode(_ input: String, now: Date = Date()) -> QuickPreviewResult {
        do {
            let preview = try decodePreview(input, now: now)
            return .jwt(preview)
        } catch let error as JWTPreviewError {
            return .error(title: String(localized: "Invalid JWT"), message: error.localizedDescription)
        } catch {
            return .error(title: String(localized: "Invalid JWT"), message: error.localizedDescription)
        }
    }

    static func decodePreview(_ input: String, now: Date = Date()) throws -> JWTPreview {
        let token = normalizedToken(input)
        let segments = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard segments.count == 3 else {
            throw JWTPreviewError.invalidSegmentCount
        }

        let headerData = try base64URLDecode(segments[0], segmentName: "header")
        let payloadData = try base64URLDecode(segments[1], segmentName: "payload")
        let signature = segments[2]

        let headerObject = try jsonObject(from: headerData, segmentName: "header")
        let payloadObject = try jsonObject(from: payloadData, segmentName: "payload")
        let headerText = prettyJSON(headerObject) ?? String(data: headerData, encoding: .utf8) ?? ""
        let payloadText = prettyJSON(payloadObject) ?? String(data: payloadData, encoding: .utf8) ?? ""

        let claims = JWTClaims(object: payloadObject)
        let warnings = warnings(header: headerObject, claims: claims, signature: signature, now: now)

        return JWTPreview(
            headerText: headerText,
            payloadText: payloadText,
            signaturePreview: signature.isEmpty ? String(localized: "Empty signature") : signature,
            claims: claims,
            warnings: warnings
        )
    }

    static func looksLikeJWT(_ input: String) -> Bool {
        let token = normalizedToken(input)
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else {
            return false
        }
        return segments[0].contains { $0 == "e" || $0 == "E" }
    }

    static func normalizedToken(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix(bearerPrefix) {
            return String(trimmed.dropFirst(bearerPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    static func base64URLDecode(_ input: String, segmentName: String = "value") throws -> Data {
        var value = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder > 0 {
            value.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: value) else {
            throw JWTPreviewError.invalidBase64(segmentName)
        }
        return data
    }

    private static func jsonObject(from data: Data, segmentName: String) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw JWTPreviewError.invalidJSON(segmentName)
        }
    }

    private static func prettyJSON(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func warnings(
        header: Any,
        claims: JWTClaims,
        signature: String,
        now: Date
    )
        -> [JWTPreviewWarning]
    {
        var warnings: [JWTPreviewWarning] = [
            JWTPreviewWarning(
                severity: .info,
                message: String(localized: "Decoded only. Signature not verified.")
            ),
        ]

        if let headerObject = header as? [String: Any],
           let algorithm = headerObject["alg"] as? String,
           algorithm.caseInsensitiveCompare("none") == .orderedSame
        {
            warnings.append(JWTPreviewWarning(
                severity: .warning,
                message: String(localized: "Header uses alg: none.")
            ))
        }

        if signature.isEmpty {
            warnings.append(JWTPreviewWarning(
                severity: .warning,
                message: String(localized: "Signature segment is empty.")
            ))
        }

        if let expiration = claims.exp, expiration <= now {
            warnings.append(JWTPreviewWarning(
                severity: .warning,
                message: String(localized: "Token is expired.")
            ))
        }

        if let notBefore = claims.nbf, notBefore > now {
            warnings.append(JWTPreviewWarning(
                severity: .warning,
                message: String(localized: "Token is not valid yet.")
            ))
        }

        return warnings
    }
}

// MARK: - JWTPreview

struct JWTPreview: Equatable, Sendable {
    let headerText: String
    let payloadText: String
    let signaturePreview: String
    let claims: JWTClaims
    let warnings: [JWTPreviewWarning]

    var copyText: String {
        [
            "Header:",
            headerText,
            "",
            "Payload:",
            payloadText,
            "",
            "Signature:",
            signaturePreview,
            "",
            warnings.map(\.message).joined(separator: "\n"),
        ]
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - JWTClaims

struct JWTClaims: Equatable, Sendable {
    let issuer: String?
    let subject: String?
    let audience: String?
    let expiration: String?
    let notBefore: String?
    let issuedAt: String?
    let exp: Date?
    let nbf: Date?
    let iat: Date?

    init(object: Any) {
        let dict = object as? [String: Any] ?? [:]
        issuer = dict["iss"].map(Self.displayValue)
        subject = dict["sub"].map(Self.displayValue)
        audience = dict["aud"].map(Self.displayValue)
        exp = Self.dateValue(dict["exp"])
        nbf = Self.dateValue(dict["nbf"])
        iat = Self.dateValue(dict["iat"])
        expiration = exp.map(Self.dateString)
        notBefore = nbf.map(Self.dateString)
        issuedAt = iat.map(Self.dateString)
    }

    var summaryRows: [QuickPreviewKeyValueRow] {
        [
            ("iss", issuer),
            ("sub", subject),
            ("aud", audience),
            ("exp", expiration),
            ("nbf", notBefore),
            ("iat", issuedAt),
        ]
        .compactMap { key, value in
            value.map { QuickPreviewKeyValueRow(key: key, value: $0) }
        }
    }

    private static func dateValue(_ value: Any?) -> Date? {
        switch value {
        case let number as NSNumber:
            Date(timeIntervalSince1970: number.doubleValue)
        case let string as String:
            Double(string).map(Date.init(timeIntervalSince1970:))
        default:
            nil
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func displayValue(_ value: Any) -> String {
        if let array = value as? [Any] {
            return array.map(displayValue).joined(separator: ", ")
        }
        if let dict = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8)
        {
            return text
        }
        return "\(value)"
    }
}

// MARK: - JWTPreviewWarning

struct JWTPreviewWarning: Equatable, Sendable {
    enum Severity: Equatable, Sendable {
        case info
        case warning
    }

    let severity: Severity
    let message: String
}

// MARK: - JWTPreviewError

enum JWTPreviewError: LocalizedError, Equatable {
    case invalidSegmentCount
    case invalidBase64(String)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .invalidSegmentCount:
            String(localized: "Expected header.payload.signature.")
        case let .invalidBase64(segment):
            String(localized: "Could not decode the \(segment) segment as Base64URL.")
        case let .invalidJSON(segment):
            String(localized: "The \(segment) segment is not valid JSON.")
        }
    }
}
