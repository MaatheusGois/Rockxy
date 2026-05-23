import Foundation
import os

// MARK: - ProtobufSchemaFileStore

struct ProtobufSchemaFileStore {
    // MARK: Lifecycle

    init(directoryURL: URL = RockxyIdentity.current.appSupportPath("protobuf-schemas")) {
        self.directoryURL = directoryURL
    }

    // MARK: Internal

    func loadDescriptors() throws -> [ProtobufSchemaDescriptor] {
        guard FileManager.default.fileExists(atPath: descriptorsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: descriptorsURL)
        return try JSONDecoder().decode([ProtobufSchemaDescriptor].self, from: data)
    }

    func saveDescriptors(_ descriptors: [ProtobufSchemaDescriptor]) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(descriptors).write(to: descriptorsURL, options: .atomic)
        Self.logger.info("Saved \(descriptors.count) Protobuf schema descriptor(s)")
    }

    func saveSchemaData(_ data: Data, descriptorID: UUID) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: schemaDataURL(for: descriptorID), options: .atomic)
    }

    func loadSchemaData(descriptorID: UUID) throws -> Data? {
        let url = schemaDataURL(for: descriptorID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    func removeSchemaData(descriptorID: UUID) throws {
        let url = schemaDataURL(for: descriptorID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: RockxyIdentity.current.logSubsystem, category: "ProtobufDecoder")

    private let directoryURL: URL

    private var descriptorsURL: URL {
        directoryURL.appendingPathComponent("schemas.json")
    }

    private func schemaDataURL(for descriptorID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(descriptorID.uuidString).proto")
    }
}
