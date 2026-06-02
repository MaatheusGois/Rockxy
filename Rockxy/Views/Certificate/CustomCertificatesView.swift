import AppKit
import Security
import SecurityInterface
import SwiftASN1
import SwiftUI
import UniformTypeIdentifiers
import X509

// MARK: - CustomCertificatesView

struct CustomCertificatesView: View {
    @State private var selectedTab = Tab.root
    @State private var rootEntries: [CustomCertificateMetadata] = []
    @State private var serverEntries: [CustomCertificateMetadata] = []
    @State private var clientEntries: [CustomCertificateMetadata] = []
    @State private var defaultRootCertificate: CertificatePreviewItem?
    @State private var defaultRootSnapshot: RootCAStatusSnapshot?
    @State private var isLoadingDefaultRoot = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Picker(String(localized: "Certificate Type"), selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 560)
            .padding(.top, 20)

            content
                .padding(28)

            Spacer(minLength: 0)
            bottomBar
        }
        .frame(minWidth: 900, minHeight: 540)
        .task {
            reload()
            await refreshDefaultRootCertificate()
        }
        .alert(String(localized: "Custom Certificate Failed"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "certificate")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(localized: "Custom Certificates"))
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .root:
            RootCertificateTab(
                entries: rootEntries,
                defaultRootCertificate: defaultRootCertificate,
                defaultRootSnapshot: defaultRootSnapshot,
                isLoadingDefaultRoot: isLoadingDefaultRoot
            )
        case .server:
            CertificateListTab(
                title: String(localized: "Config Server Certificates used when establishing SSL connections to clients"),
                subtitle: String(localized: "Suitable for apps that use certificate pinning."),
                entries: serverEntries,
                firstColumnTitle: String(localized: "Host"),
                emptyMessage: String(localized: "No custom server certificates have been imported.")
            )
        case .client:
            CertificateListTab(
                title: String(localized: "Config Client Certificates used when establishing SSL connections to selected servers"),
                subtitle: String(localized: "Suitable for upstream services that require mutual TLS."),
                entries: clientEntries,
                firstColumnTitle: String(localized: "Host"),
                emptyMessage: String(localized: "No client certificates have been imported.")
            )
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(selectedTab == .root ? String(localized: "Revert") : String(localized: "Delete")) {
                deleteSelectedKind()
            }
                .buttonStyle(.bordered)
                .disabled(currentEntries.isEmpty)

            Button(String(localized: "How to generate self-signed certificates")) {
                if let helpURL = URL(string: "https://docs.rockxy.io/features/custom-certificates") {
                    NSWorkspace.shared.open(helpURL)
                }
            }
            .buttonStyle(.bordered)

            Spacer()

            if let helpURL = URL(string: "https://docs.rockxy.io/features/custom-certificates") {
                HelpLink(destination: helpURL)
            }

            Button(String(localized: "Preview")) {
                previewCurrentCertificate()
            }
                .buttonStyle(.bordered)
                .disabled(currentPreviewItem == nil)

            Menu {
                switch selectedTab {
                case .root:
                    Button(String(localized: "Import P12...")) {
                        importPKCS12Certificate(kind: .root)
                    }
                case .server, .client:
                    Button(String(localized: "Import PEM / DER...")) {
                        importPEMOrDERCertificate(kind: selectedTab.kind)
                    }
                    Divider()
                    Button(String(localized: "Import P12...")) {
                        importPKCS12Certificate(kind: selectedTab.kind)
                    }
                }
            } label: {
                Text(String(localized: "Import"))
            }
            .menuStyle(.button)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
    }

    private var currentEntries: [CustomCertificateMetadata] {
        switch selectedTab {
        case .root:
            rootEntries
        case .server:
            serverEntries
        case .client:
            clientEntries
        }
    }

    private var currentPreviewItem: CertificatePreviewItem? {
        switch selectedTab {
        case .root:
            if let customRoot = rootEntries.last.flatMap({ try? CertificatePreviewItem(metadata: $0) }) {
                return customRoot
            }
            return defaultRootCertificate
        case .server:
            return serverEntries.last.flatMap { try? CertificatePreviewItem(metadata: $0) }
        case .client:
            return clientEntries.last.flatMap { try? CertificatePreviewItem(metadata: $0) }
        }
    }

    private func reload() {
        rootEntries = CustomCertificateManager.shared.metadata(kind: .root)
        serverEntries = CustomCertificateManager.shared.metadata(kind: .server)
        clientEntries = CustomCertificateManager.shared.metadata(kind: .client)
    }

    private func deleteSelectedKind() {
        do {
            try CustomCertificateManager.shared.deleteAll(kind: selectedTab.kind)
            reload()
            Task { await refreshDefaultRootCertificate() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPEMOrDERCertificate(kind: CustomCertificateKind) {
        do {
            guard let certificateURL = chooseFile(
                title: String(localized: "Choose Certificate PEM or DER"),
                allowedContentTypes: CertificateImportFileType.certificateTypes
            ),
                let privateKeyURL = chooseFile(
                    title: String(localized: "Choose Private Key PEM or DER"),
                    allowedContentTypes: CertificateImportFileType.privateKeyTypes
                ) else {
                return
            }
            let identity = try CustomCertificateImportIdentity.fromCertificateAndPrivateKey(
                certificateData: Data(contentsOf: certificateURL),
                privateKeyData: Data(contentsOf: privateKeyURL),
                displayName: certificateURL.deletingPathExtension().lastPathComponent
            )
            try importIdentity(identity, kind: kind)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPKCS12Certificate(kind: CustomCertificateKind) {
        do {
            guard let pkcs12URL = chooseFile(
                title: String(localized: "Choose P12 Certificate"),
                allowedContentTypes: CertificateImportFileType.pkcs12Types
            ),
                let passphrase = promptPKCS12Passphrase() else {
                return
            }
            let identity = try CustomCertificateImportIdentity.fromPKCS12(
                data: Data(contentsOf: pkcs12URL),
                displayName: pkcs12URL.deletingPathExtension().lastPathComponent,
                passphrase: passphrase
            )
            try importIdentity(identity, kind: kind)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importIdentity(_ identity: CustomCertificateImportIdentity, kind: CustomCertificateKind) throws {
        switch kind {
        case .root:
            try CustomCertificateManager.shared.importRoot(
                displayName: identity.displayName,
                certificatePEM: identity.certificatePEM,
                privateKeyPEM: identity.privateKeyPEM
            )
            selectedTab = .root
        case .server:
            guard let hostPattern = promptHostPattern(
                title: String(localized: "Server Certificate Host"),
                message: String(localized: "Enter the host or wildcard pattern this server certificate should match.")
            ) else {
                return
            }
            try CustomCertificateManager.shared.importServerIdentity(
                hostPattern: hostPattern,
                displayName: identity.displayName,
                certificatePEM: identity.certificatePEM,
                privateKeyPEM: identity.privateKeyPEM
            )
            selectedTab = .server
        case .client:
            guard let hostPattern = promptHostPattern(
                title: String(localized: "Client Certificate Host"),
                message: String(localized: "Enter the upstream host or wildcard pattern that should receive this client identity.")
            ) else {
                return
            }
            try CustomCertificateManager.shared.importClientIdentity(
                hostPattern: hostPattern,
                displayName: identity.displayName,
                certificatePEM: identity.certificatePEM,
                privateKeyPEM: identity.privateKeyPEM
            )
            selectedTab = .client
        }

        reload()
        Task { await refreshDefaultRootCertificate() }
    }

    private func refreshDefaultRootCertificate() async {
        isLoadingDefaultRoot = true
        defer { isLoadingDefaultRoot = false }

        do {
            try await CertificateManager.shared.ensureRootCA()
            defaultRootSnapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: false)
            let material = try await CertificateManager.shared.exportMaterial()
            guard let certificate = material.certificate else {
                defaultRootCertificate = nil
                return
            }
            defaultRootCertificate = try CertificatePreviewItem(
                certificate: certificate,
                displayName: String(localized: "Rockxy Default Root Certificate"),
                fingerprintSHA256: defaultRootSnapshot?.fingerprintSHA256
            )
        } catch {
            defaultRootSnapshot = await CertificateManager.shared.rootCAStatusSnapshot(performValidation: false)
            defaultRootCertificate = nil
        }
    }

    private func previewCurrentCertificate() {
        guard let item = currentPreviewItem else {
            return
        }

        let panel = SFCertificatePanel.shared()
        panel?.runModal(for: item.secTrust, showGroup: true)
    }

    private func chooseFile(title: String, allowedContentTypes: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedContentTypes
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func promptPKCS12Passphrase() -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "P12 Password")
        alert.informativeText = String(localized: "Enter the password for this P12 file. Leave it empty if the file has no password.")
        alert.addButton(withTitle: String(localized: "Import"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = String(localized: "Password")
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return field.stringValue
    }

    private func promptHostPattern(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "Continue"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "api.example.com or *.example.com"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private enum Tab: CaseIterable, Identifiable {
        case root
        case server
        case client

        var id: Self { self }

        var title: String {
            switch self {
            case .root:
                String(localized: "Root Certificate")
            case .server:
                String(localized: "Server Certificates")
            case .client:
                String(localized: "Client Certificates")
            }
        }

        var kind: CustomCertificateKind {
            switch self {
            case .root:
                .root
            case .server:
                .server
            case .client:
                .client
            }
        }
    }
}

// MARK: - CertificateImportFileType

private enum CertificateImportFileType {
    static let certificateTypes = extensions(["pem", "der", "cer", "crt"])
    static let privateKeyTypes = extensions(["pem", "key", "der"])
    static let pkcs12Types = extensions(["p12", "pfx"])

    private static func extensions(_ values: [String]) -> [UTType] {
        values.map { UTType(filenameExtension: $0) ?? .data }
    }
}

// MARK: - RootCertificateTab

private struct RootCertificateTab: View {
    let entries: [CustomCertificateMetadata]
    let defaultRootCertificate: CertificatePreviewItem?
    let defaultRootSnapshot: RootCAStatusSnapshot?
    let isLoadingDefaultRoot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rootTitle)
                    .font(.title3)
                Text(String(localized: "This certificate is used for generating proxy certificates during SSL handshakes to clients and servers."))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                Image(systemName: "certificate.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.yellow)
                    .symbolRenderingMode(.hierarchical)

                if isLoadingDefaultRoot, entries.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Loading certificate details..."))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(activeTitle)
                            .font(.headline)

                        if let certificate = activeCertificate {
                            Text(validityLine(prefix: String(localized: "Not Valid Before:"), date: certificate.notValidBefore))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text(validityLine(prefix: String(localized: "Not Valid After:"), date: certificate.notValidAfter))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let fingerprint = certificate.fingerprintSHA256 {
                                Text(String(localized: "SHA-256: \(fingerprint)"))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                        } else {
                            Text(String(localized: "No generated root certificate details are available yet."))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Label(statusText, systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
            }
            .padding(18)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let certificate = activeCertificate {
                certificateSummary(certificate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeCertificate: CertificatePreviewItem? {
        if let entry = entries.last {
            return try? CertificatePreviewItem(metadata: entry)
        }
        return defaultRootCertificate
    }

    private var activeTitle: String {
        activeCertificate?.displayName ?? String(localized: "Rockxy Default Root Certificate")
    }

    private var statusText: String {
        if !entries.isEmpty {
            return String(localized: "Custom Root Active")
        }
        if defaultRootSnapshot?.isInstalledInKeychain == true,
           defaultRootSnapshot?.isSystemTrustValidated == true
        {
            return String(localized: "Installed & Trusted")
        }
        return String(localized: "Default Root Active")
    }

    private func certificateSummary(_ certificate: CertificatePreviewItem) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            if let commonName = certificate.commonName {
                summaryRow(label: String(localized: "Common Name"), value: commonName)
            }
            summaryRow(label: String(localized: "Subject"), value: certificate.subjectSummary)
            summaryRow(label: String(localized: "Issuer"), value: certificate.issuerSummary)
        }
        .font(.caption)
        .padding(.horizontal, 6)
    }

    private func summaryRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var rootTitle: String {
        if entries.isEmpty {
            String(localized: "Rockxy is using the Default Rockxy Root Certificate")
        } else {
            String(localized: "Rockxy is using a Custom Root Certificate")
        }
    }

    private func validityLine(prefix: String, date: Date?) -> String {
        let value = date?.formatted(date: .complete, time: .shortened) ?? String(localized: "Unknown")
        return "\(prefix) \(value)"
    }
}

// MARK: - CertificateListTab

private struct CertificateListTab: View {
    let title: String
    let subtitle: String
    let entries: [CustomCertificateMetadata]
    let firstColumnTitle: String
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3)
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            Table(entries) {
                TableColumn(firstColumnTitle) { entry in
                    Text(entry.hostPattern ?? "—")
                }
                TableColumn(String(localized: "Certificates")) { entry in
                    Text(entry.displayName)
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(emptyMessage, systemImage: "certificate")
                }
            }
            .frame(minHeight: 280)
        }
    }
}

// MARK: - CertificatePreviewItem

struct CertificatePreviewItem {
    let displayName: String
    let notValidBefore: Date?
    let notValidAfter: Date?
    let fingerprintSHA256: String?
    let commonName: String?
    let subjectSummary: String
    let issuerSummary: String
    let secCertificate: SecCertificate
    let secTrust: SecTrust

    init(metadata: CustomCertificateMetadata) throws {
        try self.init(
            certificate: Certificate(pemEncoded: metadata.certificatePEM),
            displayName: metadata.displayName,
            fingerprintSHA256: metadata.fingerprintSHA256
        )
    }

    init(
        certificate: Certificate,
        displayName: String?,
        fingerprintSHA256: String?
    ) throws {
        self.displayName = displayName ?? Self.commonName(from: certificate.subject) ?? String(localized: "Certificate")
        notValidBefore = certificate.notValidBefore
        notValidAfter = certificate.notValidAfter
        self.fingerprintSHA256 = fingerprintSHA256 ?? Self.fingerprint(certificate)
        commonName = Self.commonName(from: certificate.subject)
        subjectSummary = Self.summary(from: certificate.subject)
        issuerSummary = Self.summary(from: certificate.issuer)
        secCertificate = try Self.secCertificate(from: certificate)
        secTrust = try Self.secTrust(for: secCertificate)
    }

    private static func secCertificate(from certificate: Certificate) throws -> SecCertificate {
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        let data = Data(serializer.serializedBytes)
        guard let secCertificate = SecCertificateCreateWithData(nil, data as CFData) else {
            throw CustomCertificatePreviewError.invalidCertificate
        }
        return secCertificate
    }

    private static func secTrust(for certificate: SecCertificate) throws -> SecTrust {
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, policy, &trust)
        guard status == errSecSuccess, let trust else {
            throw CustomCertificatePreviewError.invalidCertificate
        }
        return trust
    }

    private static func fingerprint(_ certificate: Certificate) -> String? {
        var serializer = DER.Serializer()
        guard (try? certificate.serialize(into: &serializer)) != nil else {
            return nil
        }
        return KeychainHelper.computeFingerprintSHA256(Data(serializer.serializedBytes))
    }

    private static func commonName(from name: DistinguishedName) -> String? {
        for relativeDistinguishedName in name {
            for attribute in relativeDistinguishedName where attribute.type == ASN1ObjectIdentifier.NameAttributes.commonName {
                return String(describing: attribute.value)
            }
        }
        return nil
    }

    private static func summary(from name: DistinguishedName) -> String {
        let values = rows(from: name).map(\.value)
        return values.isEmpty ? String(describing: name) : values.joined(separator: ", ")
    }

    private static func rows(from name: DistinguishedName) -> [CertificateNameRow] {
        name.flatMap { relativeDistinguishedName in
            relativeDistinguishedName.map { attribute in
                CertificateNameRow(label: label(for: attribute.type), value: String(describing: attribute.value))
            }
        }
    }

    private static func label(for oid: ASN1ObjectIdentifier) -> String {
        switch oid {
        case ASN1ObjectIdentifier.NameAttributes.commonName:
            String(localized: "Common Name")
        case ASN1ObjectIdentifier.NameAttributes.countryName:
            String(localized: "Country or Region")
        case ASN1ObjectIdentifier.NameAttributes.localityName:
            String(localized: "Locality")
        case ASN1ObjectIdentifier.NameAttributes.organizationName:
            String(localized: "Organization")
        case ASN1ObjectIdentifier.NameAttributes.organizationalUnitName:
            String(localized: "Organizational Unit")
        case ASN1ObjectIdentifier.NameAttributes.stateOrProvinceName:
            String(localized: "State/Province")
        default:
            String(describing: oid)
        }
    }
}

private struct CertificateNameRow: Identifiable {
    let label: String
    let value: String

    var id: String { "\(label)-\(value)" }
}

private enum CustomCertificatePreviewError: LocalizedError {
    case invalidCertificate

    var errorDescription: String? {
        switch self {
        case .invalidCertificate:
            String(localized: "The certificate could not be converted for preview.")
        }
    }
}
