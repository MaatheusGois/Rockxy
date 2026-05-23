import Foundation

// MARK: - ProtobufPayloadEncoding

enum ProtobufPayloadEncoding: String, Codable, CaseIterable, Identifiable {
    case auto
    case singleMessage
    case delimitedList

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .auto:
            String(localized: "Auto")
        case .singleMessage:
            String(localized: "Single Message")
        case .delimitedList:
            String(localized: "Delimited List")
        }
    }
}

// MARK: - ProtobufMappingRule

struct ProtobufMappingRule: Codable, Equatable, Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        urlPattern: String,
        method: HTTPMethodFilter = .any,
        matchType: RuleMatchType = .wildcard,
        includeSubpaths: Bool = true,
        schemaID: UUID? = nil,
        messageType: String = "",
        requestMessageType: String? = nil,
        responseMessageType: String? = nil,
        payloadEncoding: ProtobufPayloadEncoding = .auto
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.urlPattern = urlPattern
        self.method = method
        self.matchType = matchType
        self.includeSubpaths = includeSubpaths
        self.schemaID = schemaID
        self.messageType = messageType
        self.requestMessageType = requestMessageType
        self.responseMessageType = responseMessageType
        self.payloadEncoding = payloadEncoding
    }

    // MARK: Internal

    let id: UUID
    var isEnabled: Bool
    var urlPattern: String
    var method: HTTPMethodFilter
    var matchType: RuleMatchType
    var includeSubpaths: Bool
    var schemaID: UUID?
    var messageType: String
    var requestMessageType: String?
    var responseMessageType: String?
    var payloadEncoding: ProtobufPayloadEncoding
}

// MARK: - ProtobufMappingRuleValidationError

enum ProtobufMappingRuleValidationError: LocalizedError, Equatable {
    case emptyPattern
    case invalidMessageType

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .emptyPattern:
            String(localized: "Matching rule cannot be empty.")
        case .invalidMessageType:
            String(localized: "Message type can only contain letters, numbers, underscores, periods, and dollar signs.")
        }
    }
}
