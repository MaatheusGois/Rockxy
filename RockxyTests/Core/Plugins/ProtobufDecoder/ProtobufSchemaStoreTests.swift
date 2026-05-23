import Foundation
@testable import Rockxy
import Testing

// MARK: - ProtobufSchemaStoreTests

@MainActor
@Suite("ProtobufSchemaStore")
struct ProtobufSchemaStoreTests {
    // MARK: Internal

    @Test("rejects schema upload under DefaultAppPolicy")
    func defaultRejectsUpload() {
        let store = makeStore(policy: DefaultAppPolicy())
        #expect(!store.canUploadSchema)
        #expect(store.schemasLimit == 0)
        #expect(throws: AppPolicyViolation.protobufSchemaUploadUnavailable) {
            try store.uploadSchema(
                data: Data("syntax = \"proto3\";".utf8),
                fileName: "test.proto",
                hostPattern: "*.example.com"
            )
        }
    }

    @Test("persists schema descriptors when policy allows")
    func persistenceWhenAllowed() throws {
        let directory = temporaryDirectory()
        let store = makeStore(policy: ProtobufPermissivePolicy(), directory: directory)
        let descriptor = try store.uploadSchema(
            data: Data("syntax = \"proto3\";".utf8),
            fileName: "test.proto",
            hostPattern: "*.example.com",
            defaultMessageType: "Message"
        )

        let reloaded = makeStore(policy: ProtobufPermissivePolicy(), directory: directory)
        #expect(reloaded.schemas.count == 1)
        #expect(reloaded.schemas.first?.id == descriptor.id)
        #expect(reloaded.schemas.first?.hostPattern == "*.example.com")
    }

    @Test("enforces file size and schema count")
    func limits() throws {
        let store = makeStore(policy: OneSchemaPolicy())
        let data = Data("syntax = \"proto3\";".utf8)
        _ = try store.uploadSchema(data: data, fileName: "one.proto", hostPattern: "*.example.com")
        #expect(throws: AppPolicyViolation.protobufSchemaLimitReached(limit: 1)) {
            try store.uploadSchema(data: data, fileName: "two.proto", hostPattern: "*.example.com")
        }

        let sizeStore = makeStore(policy: ProtobufPermissivePolicy())
        #expect(throws: ProtobufSchemaStoreError.fileTooLarge) {
            try sizeStore.uploadSchema(
                data: Data(repeating: 0x00, count: ProxyLimits.maxProtobufSchemaFileSize + 1),
                fileName: "huge.proto",
                hostPattern: "*.example.com"
            )
        }
    }

    // MARK: Private

    private func makeStore(
        policy: any AppPolicy,
        directory: URL? = nil
    )
        -> ProtobufSchemaStore
    {
        ProtobufSchemaStore(
            policy: policy,
            fileStore: ProtobufSchemaFileStore(directoryURL: directory ?? temporaryDirectory())
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Rockxy.ProtobufSchemaStoreTests.\(UUID().uuidString)", isDirectory: true)
    }
}

// MARK: - OneSchemaPolicy

private struct OneSchemaPolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 10
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
    let upstreamProxyAllowsSOCKS5 = true
    let upstreamProxyAllowsAuthentication = true
    let maxUpstreamProxyBypassEntries = 100
    let protobufDecodingAllowsSchemaUpload = true
    let maxProtobufSchemas = 1
}

// MARK: - ProtobufPermissivePolicy

private struct ProtobufPermissivePolicy: AppPolicy {
    let maxWorkspaceTabs = 8
    let maxDomainFavorites = 5
    let maxActiveRulesPerTool = 10
    let maxEnabledScripts = 10
    let maxLiveHistoryEntries = 1_000
    let upstreamProxyAllowsSOCKS5 = true
    let upstreamProxyAllowsAuthentication = true
    let maxUpstreamProxyBypassEntries = 100
    let protobufDecodingAllowsSchemaUpload = true
    let maxProtobufSchemas = 100
}
