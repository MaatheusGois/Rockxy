import Foundation

extension WebSocketFrameData {
    func protobufHeuristicTree() -> ProtobufDecodedTree? {
        ProtobufHeuristicDecoder.decode(payload)
    }

    func protobufSchemaTree(using descriptor: ProtobufSchemaDescriptor) throws -> ProtobufDecodedTree {
        try ProtobufSchemaDecoder.decode(payload, using: descriptor)
    }
}
