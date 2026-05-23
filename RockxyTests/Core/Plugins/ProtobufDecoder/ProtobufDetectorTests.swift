import Foundation
@testable import Rockxy
import Testing

@Suite("ProtobufDetector")
struct ProtobufDetectorTests {
    @Test("detects valid Protobuf and rejects common non-Protobuf payloads")
    func detection() {
        var valid = Data()
        valid.append(varintTag(field: 1, wire: .varint))
        valid.append(varint(42))

        #expect(ProtobufDetector.isLikelyProtobuf(valid))
        #expect(!ProtobufDetector.isLikelyProtobuf(Data()))
        #expect(!ProtobufDetector.isLikelyProtobuf(Data("{\"hello\":true}".utf8)))
        #expect(!ProtobufDetector.isLikelyProtobuf(Data("plain text".utf8)))
        #expect(!ProtobufDetector.isLikelyProtobuf(Data([0xFF, 0xFF, 0xFF])))
    }
}
