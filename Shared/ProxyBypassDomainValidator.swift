import Foundation

enum ProxyBypassDomainValidator {
    static func isValid(_ domain: String) -> Bool {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == domain, trimmed.count <= 253 else {
            return false
        }

        return trimmed.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && allowedScalars.contains(scalar)
        }
    }

    private static let allowedScalars = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_*:[]"
    )
}
