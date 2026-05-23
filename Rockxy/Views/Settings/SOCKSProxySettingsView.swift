import SwiftUI

// MARK: - SOCKSProxySettingsView

struct SOCKSProxySettingsView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(String(localized: "Enable SOCKS Proxy"), isOn: $isEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 15, weight: .medium))
                .disabled(!store.canSelectSOCKS5)

            Text(String(localized: "Compatible with SOCKS 5"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Text(String(localized: "SOCKS Proxy Host:"))
                        .frame(width: 150, alignment: .trailing)
                    TextField(String(localized: "proxy.example.com"), text: $host)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .disabled(!store.canSelectSOCKS5)
                }

                HStack(spacing: 14) {
                    Text(String(localized: "SOCKS Proxy Port:"))
                        .frame(width: 150, alignment: .trailing)
                    TextField(String(localized: "1080"), text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .disabled(!store.canSelectSOCKS5)
                }

                Divider()

                if store.canSelectSOCKS5 {
                    Text(String(localized: "SOCKS5 uses domain-name targets so the upstream proxy resolves DNS."))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    PolicyLockNotice(
                        title: String(localized: "SOCKS5 unavailable"),
                        message: String(localized: "SOCKS5 upstream proxy is disabled by the current app policy.")
                    )
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
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

                Spacer()

                Button(String(localized: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Done")) {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!store.canSelectSOCKS5)
            }
        }
        .padding(28)
        .frame(width: 760)
        .onAppear(perform: loadDraft)
        .alert(String(localized: "SOCKS Proxy"), isPresented: $showHelp) {
            Button(String(localized: "OK")) {}
        } message: {
            Text(
                String(
                    localized: "This window configures the SOCKS5 variant of Upstream Proxy. The same store and policy gates are used by External Proxy Settings."
                )
            )
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var store = UpstreamProxyStore.shared
    @State private var isEnabled = false
    @State private var host = ""
    @State private var port = "1080"
    @State private var errorMessage: String?
    @State private var showHelp = false

    private func loadDraft() {
        let configuration = store.configuration
        if configuration.type == .socks5 {
            isEnabled = configuration.isEnabled
            host = configuration.host
            port = "\(configuration.port)"
        }
    }

    private func saveAndDismiss() {
        do {
            let configuration = UpstreamProxyConfiguration(
                isEnabled: isEnabled,
                type: .socks5,
                host: host,
                port: Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
                bypassHostPatterns: store.configuration.bypassHostPatterns,
                bypassLocalhost: store.configuration.bypassLocalhost
            )
            try store.saveConfiguration(configuration)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
