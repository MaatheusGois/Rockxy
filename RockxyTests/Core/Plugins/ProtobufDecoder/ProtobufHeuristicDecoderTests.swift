import Foundation
@testable import Rockxy
import Testing

// MARK: - ProtobufHeuristicDecoderTests

@Suite("ProtobufHeuristicDecoder")
struct ProtobufHeuristicDecoderTests {
    @Test("decodes varint, string, fixed32, and fixed64 fields")
    func decodesScalarFields() throws {
        var data = Data()
        data.append(varintTag(field: 1, wire: .varint))
        data.append(varint(150))
        data.append(varintTag(field: 2, wire: .lengthDelimited))
        data.append(varint(5))
        data.append(Data("hello".utf8))
        data.append(varintTag(field: 3, wire: .fixed32))
        data.append(contentsOf: [0x78, 0x56, 0x34, 0x12])
        data.append(varintTag(field: 4, wire: .fixed64))
        data.append(contentsOf: [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])

        let tree = try #require(ProtobufHeuristicDecoder.decode(data))
        #expect(tree.fields.count == 4)
        #expect(tree.fields[0].value == .varint(150))
        #expect(tree.fields[1].value == .string("hello"))
        #expect(tree.fields[2].value == .fixed32(0x12345678))
        #expect(tree.fields[3].value == .fixed64(0x0102030405060708))
    }

    @Test("detects nested length-delimited messages")
    func nestedMessage() throws {
        var nested = Data()
        nested.append(varintTag(field: 1, wire: .varint))
        nested.append(varint(7))

        var data = Data()
        data.append(varintTag(field: 1, wire: .lengthDelimited))
        data.append(varint(UInt64(nested.count)))
        data.append(nested)

        let tree = try #require(ProtobufHeuristicDecoder.decode(data))
        guard case let .message(child) = tree.fields[0].value else {
            Issue.record("Expected nested message")
            return
        }
        #expect(child.fields.first?.value == .varint(7))
    }

    @Test("fails closed for malformed input and limits")
    func malformedAndLimits() {
        #expect(ProtobufHeuristicDecoder.decode(Data([0x08, 0x80])) == nil)
        #expect(ProtobufHeuristicDecoder.decode(Data([0x0B])) == nil)

        var data = Data()
        data.append(varintTag(field: 1, wire: .varint))
        data.append(varint(1))
        #expect(ProtobufHeuristicDecoder.decode(data, maxNodes: 0) == nil)

        var nested = Data()
        nested.append(varintTag(field: 1, wire: .varint))
        nested.append(varint(1))
        var wrapper = Data()
        wrapper.append(varintTag(field: 1, wire: .lengthDelimited))
        wrapper.append(varint(UInt64(nested.count)))
        wrapper.append(nested)
        let decoded = ProtobufHeuristicDecoder.decode(wrapper, maxDepth: 0)
        #expect(decoded?.fields.first?.value == .bytes(nested))
    }
}

func varintTag(field: Int, wire: ProtobufWireType) -> Data {
    varint(ProtobufWireType.encodeTag(fieldNumber: field, wireType: wire))
}

func varint(_ value: UInt64) -> Data {
    var remaining = value
    var bytes: [UInt8] = []
    repeat {
        var byte = UInt8(remaining & 0x7F)
        remaining >>= 7
        if remaining != 0 {
            byte |= 0x80
        }
        bytes.append(byte)
    } while remaining != 0
    return Data(bytes)
}
