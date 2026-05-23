import Foundation

// MARK: - ProtobufSchemaDecoder

nonisolated enum ProtobufSchemaDecoder {
    static func decode(
        _ data: Data,
        using descriptor: ProtobufSchemaDescriptor
    )
        throws -> ProtobufDecodedTree
    {
        _ = data
        _ = descriptor
        throw ProtobufSchemaDecodeError.notImplemented
    }
}

// MARK: - ProtobufSchemaDecodeError

enum ProtobufSchemaDecodeError: LocalizedError, Equatable {
    case notImplemented

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            String(localized: "Schema-based Protobuf decoding is not implemented in this build.")
        }
    }
}
