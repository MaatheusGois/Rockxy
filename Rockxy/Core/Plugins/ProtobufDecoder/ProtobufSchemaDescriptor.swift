import Foundation

// MARK: - ProtobufSchemaDescriptor

struct ProtobufSchemaDescriptor: Codable, Equatable, Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        fileName: String,
        parsedMessageNames: [String] = [],
        hostPattern: String,
        urlPattern: String? = nil,
        defaultMessageType: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.parsedMessageNames = parsedMessageNames
        self.hostPattern = hostPattern
        self.urlPattern = urlPattern
        self.defaultMessageType = defaultMessageType
    }

    // MARK: Internal

    let id: UUID
    var fileName: String
    var parsedMessageNames: [String]
    var hostPattern: String
    var urlPattern: String?
    var defaultMessageType: String?
}
