import Foundation
import Observation
import os

// MARK: - ProtobufSchemaStore

@MainActor @Observable
final class ProtobufSchemaStore {
    // MARK: Lifecycle

    init(
        policy: any AppPolicy = DefaultAppPolicy(),
        fileStore: ProtobufSchemaFileStore = ProtobufSchemaFileStore()
    ) {
        self.policy = policy
        self.fileStore = fileStore
        self.schemas = (try? fileStore.loadDescriptors()) ?? []
    }

    // MARK: Internal

    static let shared = ProtobufSchemaStore()

    private(set) var schemas: [ProtobufSchemaDescriptor]

    var canUploadSchema: Bool {
        policy.protobufDecodingAllowsSchemaUpload && schemas.count < policy.maxProtobufSchemas
    }

    var schemasUsed: Int {
        schemas.count
    }

    var schemasLimit: Int {
        policy.maxProtobufSchemas
    }

    @discardableResult
    func uploadSchema(
        data: Data,
        fileName: String,
        hostPattern: String,
        urlPattern: String? = nil,
        defaultMessageType: String? = nil
    )
        throws -> ProtobufSchemaDescriptor
    {
        guard policy.protobufDecodingAllowsSchemaUpload else {
            throw AppPolicyViolation.protobufSchemaUploadUnavailable
        }
        guard schemas.count < policy.maxProtobufSchemas else {
            throw AppPolicyViolation.protobufSchemaLimitReached(limit: policy.maxProtobufSchemas)
        }
        guard data.count <= ProxyLimits.maxProtobufSchemaFileSize else {
            throw ProtobufSchemaStoreError.fileTooLarge
        }
        guard HostPatternMatcher.isValid(pattern: hostPattern) else {
            throw ProtobufSchemaStoreError.invalidHostPattern(hostPattern)
        }

        let descriptor = ProtobufSchemaDescriptor(
            fileName: fileName,
            parsedMessageNames: [],
            hostPattern: hostPattern,
            urlPattern: urlPattern,
            defaultMessageType: defaultMessageType
        )
        var updated = schemas
        updated.append(descriptor)
        try fileStore.saveSchemaData(data, descriptorID: descriptor.id)
        try fileStore.saveDescriptors(updated)
        schemas = updated
        Self.logger.info("Uploaded Protobuf schema descriptor")
        return descriptor
    }

    func removeSchema(id: UUID) throws {
        var updated = schemas
        updated.removeAll { $0.id == id }
        try fileStore.removeSchemaData(descriptorID: id)
        try fileStore.saveDescriptors(updated)
        schemas = updated
    }

    func reload() {
        schemas = (try? fileStore.loadDescriptors()) ?? []
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProtobufDecoder")

    private let policy: any AppPolicy
    private let fileStore: ProtobufSchemaFileStore
}

// MARK: - ProtobufSchemaStoreError

enum ProtobufSchemaStoreError: LocalizedError, Equatable {
    case fileTooLarge
    case invalidHostPattern(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            String(localized: "Protobuf schema file must be 1 MB or smaller.")
        case let .invalidHostPattern(pattern):
            String(localized: "Protobuf schema host pattern is invalid: \(pattern)")
        }
    }
}
