import Crypto
import Foundation
import NIOSSL
import Security
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

// MARK: - CustomCertificateImportIdentity

struct CustomCertificateImportIdentity: Equatable {
    let displayName: String
    let certificatePEM: String
    let privateKeyPEM: String

    static func fromCertificateAndPrivateKey(
        certificateData: Data,
        privateKeyData: Data,
        displayName: String
    ) throws -> Self {
        let certificate = try certificatePEM(from: certificateData)
        let privateKeyPEM = try privateKeyPEM(from: privateKeyData)
        return Self(displayName: displayName, certificatePEM: certificate, privateKeyPEM: privateKeyPEM)
    }

    static func fromPKCS12(data: Data, displayName: String, passphrase: String) throws -> Self {
        do {
            return try fromNIOSSLPKCS12(data: data, displayName: displayName, passphrase: passphrase)
        } catch let error as CustomCertificateImportError {
            throw error
        } catch {
            return try fromSecurityPKCS12(data: data, displayName: displayName, passphrase: passphrase)
        }
    }

    private static func fromNIOSSLPKCS12(data: Data, displayName: String, passphrase: String) throws -> Self {
        let bundle = try pkcs12Bundle(data: data, passphrase: passphrase)
        guard let leafCertificate = bundle.certificateChain.first else {
            throw CustomCertificateImportError.missingCertificate
        }

        let certificateDER = try leafCertificate.toDERBytes()
        let certificate = try Certificate(derEncoded: certificateDER)

        return Self(
            displayName: displayName,
            certificatePEM: try pem(certificate),
            privateKeyPEM: try privateKeyPEM(from: Data(try bundle.privateKey.derBytes))
        )
    }

    private static func fromSecurityPKCS12(data: Data, displayName: String, passphrase: String) throws -> Self {
        let identity = try secItemImportIdentity(data: data, passphrase: passphrase)
        let certificate = try certificate(from: identity.certificate)
        let privateKey: Certificate.PrivateKey
        do {
            privateKey = try Certificate.PrivateKey(identity.privateKey)
        } catch {
            throw CustomCertificateImportError.invalidPrivateKey
        }

        return Self(
            displayName: displayName,
            certificatePEM: try pem(certificate),
            privateKeyPEM: try privateKey.serializeAsPEM().pemString
        )
    }

    private static func pkcs12Bundle(data: Data, passphrase: String) throws -> NIOSSLPKCS12Bundle {
        let bytes = Array(data)
        if passphrase.isEmpty {
            do {
                return try NIOSSLPKCS12Bundle(buffer: bytes)
            } catch {
                return try NIOSSLPKCS12Bundle(buffer: bytes, passphrase: [UInt8]())
            }
        }
        return try NIOSSLPKCS12Bundle(buffer: bytes, passphrase: Array(passphrase.utf8))
    }

    private static func secItemImportIdentity(data: Data, passphrase: String) throws -> (certificate: SecCertificate, privateKey: SecKey) {
        var format = SecExternalFormat.formatPKCS12
        var itemType = SecExternalItemType.itemTypeAggregate
        let importPassphrase = passphrase as NSString
        let keyAttributes = [kSecAttrIsExtractable] as NSArray
        var keyParams = SecItemImportExportKeyParameters()
        keyParams.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        keyParams.passphrase = Unmanaged.passUnretained(importPassphrase)
        keyParams.keyAttributes = Unmanaged.passUnretained(keyAttributes)
        var importedItems: CFArray?
        let status = SecItemImport(
            data as CFData,
            "p12" as CFString,
            &format,
            &itemType,
            SecItemImportExportFlags(),
            &keyParams,
            nil,
            &importedItems
        )
        guard status == errSecSuccess, let importedItems else {
            return try secPKCS12Identity(data: data, passphrase: passphrase)
        }
        return try identity(from: importedItems)
    }

    private static func secPKCS12Identity(data: Data, passphrase: String) throws -> (certificate: SecCertificate, privateKey: SecKey) {
        var importedItems: CFArray?
        let options = [kSecImportExportPassphrase as String: passphrase] as CFDictionary
        let status = SecPKCS12Import(data as CFData, options, &importedItems)
        guard status == errSecSuccess, let importedItems else {
            throw CustomCertificateImportError.invalidPKCS12
        }
        return try identity(from: importedItems)
    }

    private static func identity(from importedItems: CFArray) throws -> (certificate: SecCertificate, privateKey: SecKey) {
        let items = importedItems as NSArray
        let rawIdentity = items.compactMap { item -> Any? in
            if CFGetTypeID(item as AnyObject) == SecIdentityGetTypeID() {
                return item
            }
            return (item as? [String: Any])?[kSecImportItemIdentity as String]
        }.first
        guard let rawIdentity else {
            throw CustomCertificateImportError.invalidPKCS12
        }

        let identityObject = rawIdentity as AnyObject
        guard CFGetTypeID(identityObject) == SecIdentityGetTypeID() else {
            throw CustomCertificateImportError.invalidPKCS12
        }
        let identity = unsafeBitCast(identityObject, to: SecIdentity.self)

        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
              let certificate else {
            throw CustomCertificateImportError.missingCertificate
        }

        var privateKey: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess,
              let privateKey else {
            throw CustomCertificateImportError.invalidPrivateKey
        }

        return (certificate, privateKey)
    }

    private static func certificate(from secCertificate: SecCertificate) throws -> Certificate {
        try Certificate(derEncoded: Array(SecCertificateCopyData(secCertificate) as Data))
    }

    private static func certificatePEM(from data: Data) throws -> String {
        if let pemString = String(data: data, encoding: .utf8),
           let certificate = try? Certificate(pemEncoded: pemString)
        {
            return try pem(certificate)
        }

        do {
            let certificate = try Certificate(derEncoded: Array(data))
            return try pem(certificate)
        } catch {
            throw CustomCertificateImportError.invalidCertificate
        }
    }

    private static func privateKeyPEM(from data: Data) throws -> String {
        if let pemString = String(data: data, encoding: .utf8),
           let privateKey = try? Certificate.PrivateKey(pemEncoded: pemString)
        {
            return try privateKey.serializeAsPEM().pemString
        }

        for discriminator in ["PRIVATE KEY", "EC PRIVATE KEY", "RSA PRIVATE KEY"] {
            let pemDocument = PEMDocument(type: discriminator, derBytes: Array(data))
            if let privateKey = try? Certificate.PrivateKey(pemDocument: pemDocument) {
                return try privateKey.serializeAsPEM().pemString
            }
        }
        throw CustomCertificateImportError.invalidPrivateKey
    }

    private static func pem(_ certificate: Certificate) throws -> String {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        return PEMDocument(type: "CERTIFICATE", derBytes: serializer.serializedBytes).pemString
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

// MARK: - CustomCertificateImportError

enum CustomCertificateImportError: LocalizedError, Equatable {
    case invalidCertificate
    case invalidPrivateKey
    case invalidPKCS12
    case missingCertificate

    var errorDescription: String? {
        switch self {
        case .invalidCertificate:
            String(localized: "The selected certificate must be a valid PEM or DER X.509 certificate.")
        case .invalidPrivateKey:
            String(localized: "The selected private key must be a valid PEM or DER private key.")
        case .invalidPKCS12:
            String(localized: "The selected P12 file could not be imported. Check that the file contains a certificate and private key, then try the correct password.")
        case .missingCertificate:
            String(localized: "The selected P12 file does not contain a certificate.")
        }
    }
}
