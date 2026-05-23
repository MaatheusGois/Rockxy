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
    @State private var selectedProtocol: ExternalProxyProtocolSelection = .http
    @State private var isEnabled = false
    @State private var host = ""
    @State private var port = "8080"
    @State private var pacURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var usesAuthentication = false
    @State private var bypassText = ""
    @State private var bypassLocalhost = true
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false
    @State private var showHelp = false

    private var httpServerLabel: String {
        switch selectedProtocol {
        case .https:
            String(localized: "HTTPS Proxy Server:")
        case .automatic,
             .http,
             .socks5:
            String(localized: "HTTP Proxy Server:")
        }
    }

    private var httpServerPlaceholder: String {
        switch selectedProtocol {
        case .https:
            String(localized: "HTTPS Proxy Server:")
        case .automatic,
             .http,
             .socks5:
            String(localized: "HTTP Proxy Server:")
        }
    }

    private var protocolList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Select a protocol to configure:"))
                .font(.system(size: 13))

            VStack(spacing: 0) {
                ForEach(ExternalProxyProtocolSelection.allCases) { row in
                    Button {
                        select(row)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: checkboxSymbol(for: row))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(
                                    selectedProtocol == row ? Color.white : Color(nsColor: .tertiaryLabelColor)
                                )
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
                    .font(.system(size: 15))
                TextField(String(localized: "http://my-server.com/proxy.pac"), text: $pacURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 470)
                Text(
                    String(
                        localized: "If your network administrator provided you with the address of an automatic proxy configuration (.pac) file, enter it above."
                    )
                )
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        case .http,
             .https:
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    labeledTextField(httpServerLabel, placeholder: httpServerPlaceholder, text: $host)
                    labeledTextField(String(localized: "Port:"), placeholder: "8080", text: $port, width: 96)
                }

                Toggle(String(localized: "Proxy server requires password"), isOn: $usesAuthentication)
                    .toggleStyle(.checkbox)
                    .disabled(!store.canEnableAuthentication)

                if !store.canEnableAuthentication {
                    PolicyLockNotice(
                        title: String(localized: "Authentication unavailable"),
                        message: String(
                            localized: "Authentication is available in the Rockxy Pro. Credentials are not saved."
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
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        case .socks5:
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "SOCKS Proxy Server"))
                        .font(.system(size: 15))
                    HStack(spacing: 8) {
                        TextField(String(localized: "127.0.0.1"), text: $host)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 390)
                            .disabled(!store.canSelectSOCKS5)
                        Text(":")
                            .font(.system(size: 17, weight: .semibold))
                        TextField(String(localized: "8080"), text: $port)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 86)
                            .disabled(!store.canSelectSOCKS5)
                    }
                }

                Toggle(String(localized: "Proxy Server requires password"), isOn: $usesAuthentication)
                    .toggleStyle(.checkbox)
                    .disabled(true)

                HStack(spacing: 12) {
                    Text(String(localized: "Username:"))
                        .foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    TextField("", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                }

                HStack(spacing: 12) {
                    Text(String(localized: "Password:"))
                        .foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    SecureField("", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                }

                Text(String(localized: "SOCKS Proxy has not supported Authentication yet."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                if !store.canSelectSOCKS5 {
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

    private func labeledTextField(
        _ title: String,
        placeholder: String? = nil,
        text: Binding<String>,
        width: CGFloat? = nil
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
            TextField(placeholder ?? title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private func select(_ row: ExternalProxyProtocolSelection) {
        selectedProtocol = row
        if row == .socks5, host.isEmpty {
            host = "127.0.0.1"
        }
        if port.isEmpty {
            port = "8080"
        }
        statusMessage = nil
        statusIsError = false
    }

    private func rowForeground(_ row: ExternalProxyProtocolSelection) -> Color {
        if selectedProtocol == row {
            return .white
        }
        return .primary
    }

    private func checkboxSymbol(for row: ExternalProxyProtocolSelection) -> String {
        selectedProtocol == row ? "checkmark.square.fill" : "square.fill"
    }

    private func loadDraft() {
        let configuration = store.configuration
        selectedProtocol = ExternalProxyProtocolSelection(configuration.type)
        isEnabled = configuration.isEnabled
        host = configuration.host
        port = "\(configuration.port)"
        username = configuration.username ?? ""
        usesAuthentication = configuration.hasCredentials
        bypassText = configuration.bypassHostPatterns.joined(separator: ", ")
        bypassLocalhost = configuration.bypassLocalhost
    }

    private func makeDraft() -> ExternalProxySettingsDraft {
        ExternalProxySettingsDraft(
            isEnabled: isEnabled,
            selectedProtocol: selectedProtocol,
            host: host,
            portText: port,
            pacURL: pacURL,
            usesAuthentication: usesAuthentication,
            username: username,
            password: password,
            bypassText: bypassText,
            bypassLocalhost: bypassLocalhost
        )
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
        let draft = makeDraft()
        let configuration = try draft.configuration()
        let credentials = draft.credentials()
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
