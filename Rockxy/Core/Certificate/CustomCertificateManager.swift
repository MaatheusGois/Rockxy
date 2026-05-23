import Crypto
import Foundation
import NIOSSL
import SwiftASN1
import X509

// MARK: - CustomCertificateKind

enum CustomCertificateKind: String, Codable, CaseIterable, Equatable {
    case root
    case server
    case client
}

// MARK: - CustomCertificateMetadata

struct CustomCertificateMetadata: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: CustomCertificateKind
    var displayName: String
    var hostPattern: String?
    var certificatePEM: String
    var keychainAccount: String
    var createdAt: Date
    var notValidBefore: Date?
    var notValidAfter: Date?
    var fingerprintSHA256: String?
}

// MARK: - CustomTLSIdentity

struct CustomTLSIdentity: Sendable {
    let certificateChainPEM: [String]
    let privateKeyPEM: String

    var certificateSources: [NIOSSLCertificateSource] {
        get throws {
            try certificateChainPEM.map { pem in
                try .certificate(NIOSSLCertificate(bytes: Array(pem.utf8), format: .pem))
            }
        }
    }

    var privateKeySource: NIOSSLPrivateKeySource {
        get throws {
            try .privateKey(NIOSSLPrivateKey(bytes: Array(privateKeyPEM.utf8), format: .pem))
        }
    }
}

// MARK: - SecureDataStore

protocol SecureDataStore: Sendable {
    func save(_ data: Data, account: String) throws
    func load(account: String) throws -> Data?
    func delete(account: String) throws
}

struct KeychainSecureDataStore: SecureDataStore {
    func save(_ data: Data, account: String) throws {
        try KeychainHelper.saveSecureData(data, service: service, account: account)
    }

    func load(account: String) throws -> Data? {
        try KeychainHelper.loadSecureData(service: service, account: account)
    }

    func delete(account: String) throws {
        try KeychainHelper.deleteSecureData(service: service, account: account)
    }

    private let service = RockxyIdentity.current.defaultsKey("CustomCertificates")
}

// MARK: - CustomCertificateManager

final class CustomCertificateManager: @unchecked Sendable {
    static let shared = CustomCertificateManager()

    init(
        storageURL: URL = RockxyIdentity.current.sharedSupportDirectory()
            .appendingPathComponent("Certificates", isDirectory: true)
            .appendingPathComponent("custom-certificates.json"),
        secureStore: any SecureDataStore = KeychainSecureDataStore()
    ) {
        self.storageURL = storageURL
        self.secureStore = secureStore
        loadFromDisk()
    }

    func metadata(kind: CustomCertificateKind? = nil) -> [CustomCertificateMetadata] {
        lock.withLock {
            entries
                .filter { kind == nil || $0.kind == kind }
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    @discardableResult
    func importRoot(
        displayName: String,
        certificatePEM: String,
        privateKeyPEM: String
    ) throws -> CustomCertificateMetadata {
        try importIdentity(kind: .root, hostPattern: nil, displayName: displayName, certificatePEM: certificatePEM, privateKeyPEM: privateKeyPEM)
    }

    @discardableResult
    func importServerIdentity(
        hostPattern: String,
        displayName: String,
        certificatePEM: String,
        privateKeyPEM: String
    ) throws -> CustomCertificateMetadata {
        try importIdentity(kind: .server, hostPattern: hostPattern, displayName: displayName, certificatePEM: certificatePEM, privateKeyPEM: privateKeyPEM)
    }

    @discardableResult
    func importClientIdentity(
        hostPattern: String,
        displayName: String,
        certificatePEM: String,
        privateKeyPEM: String
    ) throws -> CustomCertificateMetadata {
        try importIdentity(kind: .client, hostPattern: hostPattern, displayName: displayName, certificatePEM: certificatePEM, privateKeyPEM: privateKeyPEM)
    }

    func activeRootIssuer() throws -> (certificate: Certificate, privateKey: Certificate.PrivateKey)? {
        guard let entry = metadata(kind: .root).last else {
            return nil
        }
        guard let keyData = try secureStore.load(account: entry.keychainAccount),
              let privateKeyPEM = String(data: keyData, encoding: .utf8) else {
            throw CustomCertificateError.missingPrivateKey
        }
        return (
            certificate: try Certificate(pemEncoded: entry.certificatePEM),
            privateKey: try Certificate.PrivateKey(pemEncoded: privateKeyPEM)
        )
    }

    func serverIdentity(for host: String) -> CustomTLSIdentity? {
        identity(for: host, kind: .server)
    }

    func clientIdentity(for host: String) -> CustomTLSIdentity? {
        identity(for: host, kind: .client)
    }

    func delete(id: UUID) throws {
        let removed: CustomCertificateMetadata? = lock.withLock {
            guard let index = entries.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            return entries.remove(at: index)
        }
        if let removed {
            try secureStore.delete(account: removed.keychainAccount)
            try persist()
        }
    }

    func deleteAll(kind: CustomCertificateKind? = nil) throws {
        let removed: [CustomCertificateMetadata] = lock.withLock {
            let removed = entries.filter { kind == nil || $0.kind == kind }
            entries.removeAll { kind == nil || $0.kind == kind }
            return removed
        }
        for entry in removed {
            try secureStore.delete(account: entry.keychainAccount)
        }
        try persist()
    }

    private let storageURL: URL
    private let secureStore: any SecureDataStore
    private let lock = NSLock()
    private var entries: [CustomCertificateMetadata] = []

    private func importIdentity(
        kind: CustomCertificateKind,
        hostPattern: String?,
        displayName: String,
        certificatePEM: String,
        privateKeyPEM: String
    ) throws -> CustomCertificateMetadata {
        let certificate = try Certificate(pemEncoded: certificatePEM)
        let privateKey = try Certificate.PrivateKey(pemEncoded: privateKeyPEM)
        guard certificate.publicKey.subjectPublicKeyInfoBytes == privateKey.publicKey.subjectPublicKeyInfoBytes else {
            throw CustomCertificateError.invalidCertificateKeyPair
        }

        if kind != .root {
            try validateTLSIdentity(certificatePEM: certificatePEM, privateKeyPEM: privateKeyPEM)
        }

        let keychainAccount = "custom-certificate.\(kind.rawValue).\(UUID().uuidString)"
        try secureStore.save(Data(privateKeyPEM.utf8), account: keychainAccount)

        let entry = CustomCertificateMetadata(
            id: UUID(),
            kind: kind,
            displayName: displayName,
            hostPattern: hostPattern?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            certificatePEM: certificatePEM,
            keychainAccount: keychainAccount,
            createdAt: Date(),
            notValidBefore: certificate.notValidBefore,
            notValidAfter: certificate.notValidAfter,
            fingerprintSHA256: Self.fingerprint(certificate)
        )

        lock.withLock {
            entries.removeAll {
                $0.kind == kind && $0.hostPattern == entry.hostPattern
            }
            entries.append(entry)
        }
        try persist()
        return entry
    }

    private func identity(for host: String, kind: CustomCertificateKind) -> CustomTLSIdentity? {
        let normalizedHost = host.lowercased()
        let match = lock.withLock {
            entries.last { entry in
                guard entry.kind == kind, let pattern = entry.hostPattern else {
                    return false
                }
                return HostPatternMatcher.matches(pattern: pattern, host: normalizedHost)
            }
        }

        guard let match,
              let keyData = try? secureStore.load(account: match.keychainAccount),
              let privateKeyPEM = String(data: keyData, encoding: .utf8) else {
            return nil
        }
        return CustomTLSIdentity(certificateChainPEM: [match.certificatePEM], privateKeyPEM: privateKeyPEM)
    }

    private func validateTLSIdentity(certificatePEM: String, privateKeyPEM: String) throws {
        let certificate = try NIOSSLCertificate(bytes: Array(certificatePEM.utf8), format: .pem)
        let privateKey = try NIOSSLPrivateKey(bytes: Array(privateKeyPEM.utf8), format: .pem)
        _ = try NIOSSLContext(configuration: TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(certificate)],
            privateKey: .privateKey(privateKey)
        ))
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([CustomCertificateMetadata].self, from: data) else {
            return
        }
        lock.withLock {
            entries = decoded
        }
    }

    private func persist() throws {
        let snapshot = lock.withLock { entries }
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: storageURL, options: .atomic)
    }

    private static func fingerprint(_ certificate: Certificate) -> String? {
        var serializer = DER.Serializer()
        guard (try? certificate.serialize(into: &serializer)) != nil else {
            return nil
        }
        return KeychainHelper.computeFingerprintSHA256(Data(serializer.serializedBytes))
    }
}

// MARK: - CustomCertificateError

enum CustomCertificateError: LocalizedError, Equatable {
    case invalidCertificateKeyPair
    case missingPrivateKey

    var errorDescription: String? {
        switch self {
        case .invalidCertificateKeyPair:
            String(localized: "The certificate and private key do not belong to the same identity.")
        case .missingPrivateKey:
            String(localized: "The private key for this certificate could not be found in Keychain.")
        }
    }
}
