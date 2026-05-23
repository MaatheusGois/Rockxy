import Foundation

// MARK: - ProtobufHeuristicDecoder

nonisolated enum ProtobufHeuristicDecoder {
    // MARK: Internal

    static func decode(
        _ data: Data,
        maxDepth: Int = ProxyLimits.maxProtobufDecodeDepth,
        maxNodes: Int = ProxyLimits.maxProtobufDecodeNodes
    )
        -> ProtobufDecodedTree?
    {
        guard !data.isEmpty else {
            return nil
        }
        var nodeCount = 0
        var cursor = Cursor(data: data)
        guard let fields = parseFields(
            cursor: &cursor,
            depth: 0,
            maxDepth: maxDepth,
            maxNodes: maxNodes,
            nodeCount: &nodeCount
        ), cursor.isAtEnd else {
            return nil
        }
        return ProtobufDecodedTree(fields: fields)
    }

    // MARK: Private

    private struct Cursor {
        // MARK: Lifecycle

        init(data: Data) {
            self.data = data
            self.index = data.startIndex
        }

        // MARK: Internal

        let data: Data
        var index: Data.Index

        var isAtEnd: Bool {
            index >= data.endIndex
        }

        var remaining: Int {
            data.distance(from: index, to: data.endIndex)
        }

        mutating func readByte() -> UInt8? {
            guard !isAtEnd else {
                return nil
            }
            let byte = data[index]
            index = data.index(after: index)
            return byte
        }

        mutating func readData(length: Int) -> Data? {
            guard length >= 0, remaining >= length else {
                return nil
            }
            let end = data.index(index, offsetBy: length)
            let slice = data[index ..< end]
            index = end
            return Data(slice)
        }
    }

    private static func parseFields(
        cursor: inout Cursor,
        depth: Int,
        maxDepth: Int,
        maxNodes: Int,
        nodeCount: inout Int
    )
        -> [ProtobufDecodedField]?
    {
        var fields: [ProtobufDecodedField] = []
        while !cursor.isAtEnd {
            let fieldStart = cursor.index
            guard let tagValue = readVarint(cursor: &cursor),
                  let tag = ProtobufWireType.decodeTag(tagValue) else
            {
                return nil
            }
            nodeCount += 1
            guard nodeCount <= maxNodes else {
                return nil
            }

            let value: ProtobufDecodedValue
            switch tag.wireType {
            case .varint:
                guard let decoded = readVarint(cursor: &cursor) else {
                    return nil
                }
                value = .varint(decoded)
            case .fixed64:
                guard let raw = cursor.readData(length: 8) else {
                    return nil
                }
                value = .fixed64(raw.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian })
            case .lengthDelimited:
                guard let length = readVarint(cursor: &cursor),
                      length <= UInt64(Int.max),
                      let raw = cursor.readData(length: Int(length)) else
                {
                    return nil
                }
                value = bestGuessLengthDelimitedValue(
                    raw,
                    depth: depth,
                    maxDepth: maxDepth,
                    maxNodes: maxNodes,
                    nodeCount: &nodeCount
                )
            case .fixed32:
                guard let raw = cursor.readData(length: 4) else {
                    return nil
                }
                value = .fixed32(raw.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
            case .startGroup,
                 .endGroup:
                return nil
            }

            let rawBytes = Data(cursor.data[fieldStart ..< cursor.index])
            fields.append(ProtobufDecodedField(
                fieldNumber: tag.fieldNumber,
                wireType: tag.wireType,
                value: value,
                rawBytes: rawBytes
            ))
        }
        return fields
    }

    private static func bestGuessLengthDelimitedValue(
        _ data: Data,
        depth: Int,
        maxDepth: Int,
        maxNodes: Int,
        nodeCount: inout Int
    )
        -> ProtobufDecodedValue
    {
        if depth < maxDepth, !data.isEmpty {
            var nestedCursor = Cursor(data: data)
            let startingNodes = nodeCount
            if let fields = parseFields(
                cursor: &nestedCursor,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxNodes: maxNodes,
                nodeCount: &nodeCount
            ), nestedCursor.isAtEnd, !fields.isEmpty {
                return .message(ProtobufDecodedTree(fields: fields))
            }
            nodeCount = startingNodes
        }

        if let string = String(data: data, encoding: .utf8), string.unicodeScalars.allSatisfy(isRenderableScalar) {
            return .string(string)
        }
        return .bytes(data)
    }

    private static func readVarint(cursor: inout Cursor) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0 ..< 10 {
            guard let byte = cursor.readByte() else {
                return nil
            }
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return value
            }
            shift += 7
        }
        return nil
    }

    private static func isRenderableScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D || scalar.value >= 0x20
    }
}
