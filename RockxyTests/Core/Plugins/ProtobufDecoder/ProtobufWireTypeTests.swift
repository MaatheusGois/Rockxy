import Foundation
@testable import Rockxy
import Testing

@Suite("ProtobufWireType")
struct ProtobufWireTypeTests {
    @Test("encodes and decodes tags")
    func tagRoundTrip() {
        for wireType in ProtobufWireType.allCases {
            let tag = ProtobufWireType.encodeTag(fieldNumber: 15, wireType: wireType)
            let decoded = ProtobufWireType.decodeTag(tag)
            #expect(decoded?.fieldNumber == 15)
            #expect(decoded?.wireType == wireType)
        }
    }

    @Test("rejects invalid field zero")
    func invalidFieldZero() {
        #expect(ProtobufWireType.decodeTag(0) == nil)
    }
}
