import Foundation

// MARK: - GistPublishOptions

struct GistPublishOptions: Equatable, Sendable {
    var visibility: GitHubGistVisibility = .secret
    var redactSensitiveData: Bool = true
    var openInBrowser: Bool = true
    var copyURLToClipboard: Bool = false
    var askBeforePublishing: Bool = true
}

// MARK: - GistPublishPayload

struct GistPublishPayload: Equatable, Sendable {
    let description: String
    let isPublic: Bool
    let files: [String: String]
    let warnings: [String]

    var createRequest: GitHubGistCreateRequest {
        GitHubGistCreateRequest(
            description: description,
            public: isPublic,
            files: files.mapValues { GitHubGistCreateRequest.FileContent(content: $0) }
        )
    }
}

// MARK: - GitHubGistCreateRequest

struct GitHubGistCreateRequest: Codable, Equatable {
    struct FileContent: Codable, Equatable {
        let content: String
    }

    let description: String
    let `public`: Bool
    let files: [String: FileContent]
}

// MARK: - GistPublishPayloadBuilder

struct GistPublishPayloadBuilder {
    // MARK: Internal

    enum PayloadError: LocalizedError, Equatable {
        case emptySelection
        case fileTooLarge(String, Int)
        case payloadTooLarge(Int)
        case serializationFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptySelection:
                String(localized: "Select at least one request before publishing to Gist.")
            case let .fileTooLarge(name, size):
                String(localized: "\(name) is \(Self.byteCount(size)), which is larger than the 10 MB per-file limit.")
            case let .payloadTooLarge(size):
                String(localized: "The Gist payload is \(Self.byteCount(size)), which is larger than the 25 MB limit.")
            case let .serializationFailed(message):
                message
            }
        }

        private static func byteCount(_ count: Int) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
        }
    }

    func build(
        transactions: [HTTPTransaction],
        options: GistPublishOptions,
        publishDate: Date = Date()
    )
        throws -> GistPublishPayload
    {
        guard !transactions.isEmpty else {
            throw PayloadError.emptySelection
        }

        let redactor = SensitiveDataRedactor(isEnabled: options.redactSensitiveData)
        let sanitizedTransactions = transactions.map { redactor.redactTransaction($0) }
        let description = "Rockxy captured traffic (\(transactions.count) request\(transactions.count == 1 ? "" : "s"))"

        var files: [String: String] = [
            "README.md": readme(
                transactions: sanitizedTransactions,
                options: options,
                publishDate: publishDate
            ),
        ]

        do {
            let harData = try HARExporter().export(transactions: sanitizedTransactions)
            files["rockxy-selected.har"] = String(data: harData, encoding: .utf8) ?? harData.base64EncodedString()
        } catch {
            throw PayloadError.serializationFailed(error.localizedDescription)
        }

        for (index, transaction) in sanitizedTransactions.enumerated() {
            files[transactionFilename(index: index, transaction: transaction)] = transactionText(transaction)
        }

        if let webSocketJSON = try webSocketFramesJSON(
            from: transactions,
            redactor: redactor
        ) {
            files["websocket-frames.json"] = webSocketJSON
        }

        let warnings = try validate(files: files)
        return GistPublishPayload(
            description: description,
            isPublic: options.visibility.isPublic,
            files: files,
            warnings: warnings
        )
    }

    // MARK: Private

    private static let warningFileSize = 1 * 1_024 * 1_024
    private static let maxFileSize = 10 * 1_024 * 1_024
    private static let maxPayloadSize = 25 * 1_024 * 1_024

    private func readme(
        transactions: [HTTPTransaction],
        options: GistPublishOptions,
        publishDate: Date
    )
        -> String
    {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let rows = transactions.enumerated().map { index, transaction in
            let status = transaction.response.map { "\($0.statusCode)" } ?? "-"
            return "| \(index + 1) | \(transaction.request.method) | \(transaction.request.url.absoluteString) | \(status) |"
        }
        .joined(separator: "\n")

        return """
        # Rockxy Gist Export

        - Rockxy version: \(version)
        - Published: \(ISO8601DateFormatter().string(from: publishDate))
        - Request count: \(transactions.count)
        - Visibility: \(options.visibility == .public ? "Public" : "Secret")
        - Redaction: \(options.redactSensitiveData ? "Enabled" : "Disabled")

        | # | Method | URL | Status |
        |---:|---|---|---|
        \(rows)
        """
    }

    private func transactionFilename(index: Int, transaction: HTTPTransaction) -> String {
        let rawName = "\(index + 1)-\(transaction.request.method)-\(transaction.request.host)\(transaction.request.path)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = String(rawName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return "\(sanitized.isEmpty ? "transaction-\(index + 1)" : sanitized).txt"
    }

    private func transactionText(_ transaction: HTTPTransaction) -> String {
        var lines: [String] = []
        lines.append("\(transaction.request.method) \(transaction.request.url.absoluteString) \(transaction.request.httpVersion)")
        lines.append("")
        lines.append("Request Headers")
        lines.append(contentsOf: transaction.request.headers.map { "\($0.name): \($0.value)" })
        lines.append("")
        lines.append("Request Body")
        lines.append(bodyText(transaction.request.body, contentType: transaction.request.contentType))
        lines.append("")

        if let response = transaction.response {
            lines.append("Response")
            lines.append("\(response.statusCode) \(response.statusMessage)")
            lines.append("")
            lines.append("Response Headers")
            lines.append(contentsOf: response.headers.map { "\($0.name): \($0.value)" })
            lines.append("")
            lines.append("Response Body")
            lines.append(bodyText(response.body, contentType: response.contentType))
        } else {
            lines.append("Response")
            lines.append("No response captured.")
        }

        return lines.joined(separator: "\n")
    }

    private func bodyText(_ body: Data?, contentType: ContentType?) -> String {
        guard let body, !body.isEmpty else {
            return "(empty)"
        }
        if let text = String(data: body, encoding: .utf8),
           contentType.map({ [.json, .xml, .html, .text, .form].contains($0) }) ?? true {
            return text
        }
        return "(binary body, base64)\n\(body.base64EncodedString())"
    }

    private func webSocketFramesJSON(
        from transactions: [HTTPTransaction],
        redactor: SensitiveDataRedactor
    )
        throws -> String?
    {
        let entries = transactions.flatMap { transaction -> [[String: Any]] in
            guard let connection = transaction.webSocketConnection else {
                return []
            }
            return connection.frames.map { frame in
                let payload = String(data: frame.payload, encoding: .utf8)
                    .map { redactor.redactBodyText($0, contentType: .text) }
                    ?? frame.payload.base64EncodedString()
                return [
                    "transactionId": transaction.id.uuidString,
                    "url": redactor.redactURL(transaction.request.url).absoluteString,
                    "timestamp": ISO8601DateFormatter().string(from: frame.timestamp),
                    "direction": frame.direction.rawValue,
                    "opcode": frame.opcode.rawValue,
                    "isFinal": frame.isFinal,
                    "payload": payload,
                ] as [String: Any]
            }
        }
        guard !entries.isEmpty else {
            return nil
        }
        let data = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)
    }

    private func validate(files: [String: String]) throws -> [String] {
        var totalSize = 0
        var warnings: [String] = []
        for (name, content) in files {
            let size = content.data(using: .utf8)?.count ?? 0
            totalSize += size
            if size > Self.maxFileSize {
                throw PayloadError.fileTooLarge(name, size)
            }
            if size > Self.warningFileSize {
                warnings.append("\(name) is larger than 1 MB.")
            }
        }
        if totalSize > Self.maxPayloadSize {
            throw PayloadError.payloadTooLarge(totalSize)
        }
        return warnings.sorted()
    }
}
