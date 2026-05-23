import SwiftUI

// MARK: - ExternalProxySettingsView

struct ExternalProxySettingsView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(String(localized: "Enable External Proxy Tool"), isOn: $isEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 15, weight: .medium))

            HStack(alignment: .top, spacing: 28) {
                protocolList
                configurationPanel
            }

            bypassSection

            if let statusMessage {
                StatusDisclosure(message: statusMessage, isError: statusIsError)
            }

            HStack {
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Upstream Proxy Help"))

                Spacer()

                Button(String(localized: "Test Connection")) {
                    testConnection()
                }
                .disabled(isTesting || !isEnabled)

                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Done")) {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 900)
        .onAppear(perform: loadDraft)
        .alert(String(localized: "Upstream Proxy"), isPresented: $showHelp) {
            Button(String(localized: "OK")) {}
        } message: {
            Text(
                String(
                    localized: "HTTP and HTTPS upstream proxy are available. SOCKS5, authentication, and bypass entry count are controlled by the app policy."
                )
            )
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var store = UpstreamProxyStore.shared
    @State private var selectedProtocol: ExternalProxyProtocolRow = .http
    @State private var isEnabled = false
    @State private var host = ""
    @State private var port = "8080"
    @State private var username = ""
    @State private var password = ""
    @State private var usesAuthentication = false
    @State private var bypassText = ""
    @State private var bypassLocalhost = true
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false
    @State private var showHelp = false

    private var protocolList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Select a protocol to configure:"))
                .font(.system(size: 13))

            VStack(spacing: 0) {
                ForEach(ExternalProxyProtocolRow.allCases) { row in
                    Button {
                        select(row)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: checkboxSymbol(for: row))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(row.isEnabled(in: store) ? .primary : .tertiary)
                                .frame(width: 18)

                            Text(row.displayName)
                                .font(.system(size: 14, weight: selectedProtocol == row ? .semibold : .regular))
                                .lineLimit(1)

                            if row == .socks5, !store.canSelectSOCKS5 {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .foregroundStyle(rowForeground(row))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(selectedProtocol == row ? Color.accentColor : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .disabled(!row.isEnabled(in: store))
                }
            }
            .frame(width: 350, height: 230, alignment: .top)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }

    @ViewBuilder private var configurationPanel: some View {
        switch selectedProtocol {
        case .automatic:
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Proxy Configuration URL:"))
                    .font(.system(size: 13))
                TextField(String(localized: "http://my-server.com/proxy.pac"), text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                Text(String(localized: "Automatic proxy configuration is not supported by this Upstream Proxy build."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        case .http,
             .https,
             .socks5:
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    labeledTextField(
                        String(localized: "\(selectedProtocol.proxyType?.displayName ?? "HTTP") Proxy Server:"),
                        text: $host
                    )
                    labeledTextField(String(localized: "Port:"), text: $port, width: 96)
                }

                Toggle(String(localized: "Proxy server requires password"), isOn: $usesAuthentication)
                    .toggleStyle(.checkbox)
                    .disabled(!store.canEnableAuthentication)

                if !store.canEnableAuthentication {
                    PolicyLockNotice(
                        title: String(localized: "Authentication unavailable"),
                        message: String(
                            localized: "Credentials are rejected by the current app policy before they are saved."
                        )
                    )
                } else if usesAuthentication {
                    HStack(spacing: 12) {
                        labeledTextField(String(localized: "Username:"), text: $username)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Password:"))
                                .font(.system(size: 12))
                            SecureField(String(localized: "Password"), text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if selectedProtocol == .socks5, !store.canSelectSOCKS5 {
                    PolicyLockNotice(
                        title: String(localized: "SOCKS5 unavailable"),
                        message: String(localized: "SOCKS5 upstream proxy is disabled by the current app policy.")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var bypassSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Bypass List for External Proxies:"))
                    .font(.system(size: 13))
                Spacer()
                Text(String(localized: "\(store.bypassEntriesUsed) of \(store.bypassEntriesLimit) used"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $bypassText)
                .font(.system(size: 13, design: .monospaced))
                .frame(height: 88)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))

            Text(
                String(
                    localized: "Support wildcard (* and ?). Separate by comma. Community baseline allows 3 bypass entries."
                )
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            Toggle(String(localized: "Always bypass external proxies for localhost"), isOn: $bypassLocalhost)
                .toggleStyle(.checkbox)
        }
    }

    private func labeledTextField(_ title: String, text: Binding<String>, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private func select(_ row: ExternalProxyProtocolRow) {
        guard row.isEnabled(in: store) else {
            statusMessage = row.lockMessage
            statusIsError = true
            return
        }
        selectedProtocol = row
    }

    private func rowForeground(_ row: ExternalProxyProtocolRow) -> Color {
        if selectedProtocol == row {
            return .white
        }
        return row.isEnabled(in: store) ? .primary : .secondary
    }

    private func checkboxSymbol(for row: ExternalProxyProtocolRow) -> String {
        selectedProtocol == row ? "checkmark.square.fill" : "square.fill"
    }

    private func loadDraft() {
        let configuration = store.configuration
        selectedProtocol = ExternalProxyProtocolRow(configuration.type, canSelectSOCKS5: store.canSelectSOCKS5)
        isEnabled = configuration.isEnabled
        host = configuration.host
        port = "\(configuration.port)"
        username = configuration.username ?? ""
        usesAuthentication = configuration.hasCredentials
        bypassText = configuration.bypassHostPatterns.joined(separator: ", ")
        bypassLocalhost = configuration.bypassLocalhost
    }

    private func makeConfiguration() throws -> UpstreamProxyConfiguration {
        guard let type = selectedProtocol.proxyType else {
            throw UpstreamProxyConfigurationError.hostInvalid
        }
        let parsedPort = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return UpstreamProxyConfiguration(
            isEnabled: isEnabled,
            type: type,
            host: host,
            port: parsedPort,
            hasCredentials: usesAuthentication,
            username: usesAuthentication ? username : nil,
            bypassHostPatterns: parsedBypassPatterns(),
            bypassLocalhost: bypassLocalhost
        )
    }

    private func parsedBypassPatterns() -> [String] {
        bypassText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func saveAndDismiss() {
        do {
            try saveDraft()
            dismiss()
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func saveDraft() throws {
        let configuration = try makeConfiguration()
        let credentials = usesAuthentication ? UpstreamProxyCredentials(username: username, password: password) : nil
        try store.saveConfiguration(configuration, credentials: credentials)
        statusMessage = String(localized: "External Proxy settings saved.")
        statusIsError = false
    }

    private func testConnection() {
        Task {
            isTesting = true
            defer { isTesting = false }
            do {
                try saveDraft()
                let result = await store.testConnection()
                switch result {
                case let .success(testResult):
                    statusMessage = testResult.displayMessage
                    statusIsError = false
                case let .failure(error):
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
        }
    }
}

// MARK: - ExternalProxyProtocolRow

private enum ExternalProxyProtocolRow: CaseIterable, Identifiable {
    case automatic
    case http
    case https
    case socks5

    // MARK: Lifecycle

    init(_ type: UpstreamProxyType, canSelectSOCKS5: Bool) {
        switch type {
        case .http:
            self = .http
        case .https:
            self = .https
        case .socks5:
            self = canSelectSOCKS5 ? .socks5 : .http
        }
    }

    // MARK: Internal

    var id: String {
        displayName
    }

    var displayName: String {
        switch self {
        case .automatic:
            String(localized: "Automatic Proxy Configuration")
        case .http:
            String(localized: "Web Proxy (HTTP)")
        case .https:
            String(localized: "Secure Web Proxy (HTTPS)")
        case .socks5:
            String(localized: "SOCKS Proxy")
        }
    }

    var proxyType: UpstreamProxyType? {
        switch self {
        case .automatic:
            nil
        case .http:
            .http
        case .https:
            .https
        case .socks5:
            .socks5
        }
    }

    var lockMessage: String {
        switch self {
        case .automatic:
            String(localized: "Automatic proxy configuration is not supported.")
        case .socks5:
            String(localized: "SOCKS5 upstream proxy is unavailable in this build.")
        case .http,
             .https:
            ""
        }
    }

    @MainActor
    func isEnabled(in store: UpstreamProxyStore) -> Bool {
        switch self {
        case .automatic:
            false
        case .socks5:
            store.canSelectSOCKS5
        case .http,
             .https:
            true
        }
    }
}

// MARK: - StatusDisclosure

private struct StatusDisclosure: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(isError ? .primary : .secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - PolicyLockNotice

struct PolicyLockNotice: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension UpstreamProxyTestResult {
    var displayMessage: String {
        let milliseconds = duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000
        let typeName = negotiatedType?.displayName ?? String(localized: "Direct")
        return String(localized: "Connected to \(targetHost):\(targetPort) through \(typeName) in \(milliseconds) ms.")
    }
}
