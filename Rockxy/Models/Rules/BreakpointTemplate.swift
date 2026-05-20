import Foundation

// MARK: - BreakpointTemplateKind

enum BreakpointTemplateKind: String, CaseIterable, Codable, Identifiable {
    case request
    case response

    // MARK: Internal

    var id: String {
        rawValue
    }

    var singularTitle: String {
        switch self {
        case .request: String(localized: "Request Template")
        case .response: String(localized: "Response Template")
        }
    }

    var pluralTitle: String {
        switch self {
        case .request: String(localized: "Request Templates")
        case .response: String(localized: "Response Templates")
        }
    }

    var groupTitle: String {
        pluralTitle
    }

    var defaultName: String {
        switch self {
        case .request: String(localized: "JSON Request")
        case .response: String(localized: "JSON Response")
        }
    }

    var emptyName: String {
        switch self {
        case .request: String(localized: "Untitled Request Template")
        case .response: String(localized: "Untitled Response Template")
        }
    }

    var sampleMessage: String {
        switch self {
        case .request:
            """
            GET /api/example HTTP/1.1
            Host: example.com
            Accept: application/json

            """
        case .response:
            """
            HTTP/1.1 200 OK
            Content-Type: application/json

            {"ok":true}
            """
        }
    }
}

// MARK: - BreakpointTemplate

struct BreakpointTemplate: Identifiable, Codable, Equatable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        kind: BreakpointTemplateKind,
        name: String? = nil,
        rawMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.name = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? kind.defaultName
        self.rawMessage = rawMessage ?? kind.sampleMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedKind = try container.decodeIfPresent(BreakpointTemplateKind.self, forKey: .kind) ?? .request
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = decodedKind
        name = try container.decodeIfPresent(String.self, forKey: .name)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? decodedKind.emptyName
        rawMessage = try container.decodeIfPresent(String.self, forKey: .rawMessage)?
            .nilIfEmpty ?? decodedKind.sampleMessage
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    // MARK: Internal

    let id: UUID
    let kind: BreakpointTemplateKind
    var name: String
    var rawMessage: String
    let createdAt: Date
    var updatedAt: Date

    var validation: BreakpointTemplateValidation {
        BreakpointTemplateValidator.validate(rawMessage: rawMessage, kind: kind)
    }

    var applicationPayload: BreakpointTemplateApplication? {
        BreakpointTemplateApplication(template: self)
    }

    static let defaultTemplates: [BreakpointTemplate] = [
        BreakpointTemplate(
            kind: .request,
            name: String(localized: "JSON Request"),
            rawMessage: BreakpointTemplateKind.request.sampleMessage
        ),
        BreakpointTemplate(
            kind: .response,
            name: String(localized: "JSON Response"),
            rawMessage: BreakpointTemplateKind.response.sampleMessage
        ),
    ]

    static func defaultRawMessage(for kind: BreakpointTemplateKind) -> String {
        kind.sampleMessage
    }
}

// MARK: - BreakpointTemplateValidation

enum BreakpointTemplateValidation: Equatable {
    case valid(summary: String)
    case invalid(message: String)

    // MARK: Internal

    var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }

    var message: String {
        switch self {
        case let .valid(summary): summary
        case let .invalid(message): message
        }
    }
}

// MARK: - BreakpointTemplateHeader

struct BreakpointTemplateHeader: Codable, Equatable {
    let name: String
    let value: String
}

// MARK: - BreakpointTemplateParsedMessage

enum BreakpointTemplateParsedMessage: Equatable {
    case request(BreakpointTemplateParsedRequest)
    case response(BreakpointTemplateParsedResponse)
}

struct BreakpointTemplateParsedRequest: Equatable {
    let method: String
    let target: String
    let httpVersion: String
    let headers: [BreakpointTemplateHeader]
    let body: String
}

struct BreakpointTemplateParsedResponse: Equatable {
    let httpVersion: String
    let statusCode: Int
    let reasonPhrase: String
    let headers: [BreakpointTemplateHeader]
    let body: String
}

// MARK: - BreakpointTemplateApplication

struct BreakpointTemplateApplication: Equatable {
    // MARK: Lifecycle

    init?(template: BreakpointTemplate) {
        guard case let .valid(_, parsed) = BreakpointTemplateValidator.parse(
            rawMessage: template.rawMessage,
            kind: template.kind
        ) else {
            return nil
        }
        id = template.id
        name = template.name
        kind = template.kind
        rawMessage = template.rawMessage
        parsedMessage = parsed
    }

    // MARK: Internal

    let id: UUID
    let name: String
    let kind: BreakpointTemplateKind
    let rawMessage: String
    let parsedMessage: BreakpointTemplateParsedMessage

    func applying(to draft: BreakpointRequestData) -> BreakpointRequestData {
        var next = draft
        switch parsedMessage {
        case let .request(request):
            next.method = request.method
            next.url = request.target
            next.headers = request.headers.map { EditableHeader(name: $0.name, value: $0.value) }
            next.body = request.body
            next.phase = .request
        case let .response(response):
            next.statusCode = response.statusCode
            next.headers = response.headers.map { EditableHeader(name: $0.name, value: $0.value) }
            next.body = response.body
            next.phase = .response
        }
        return next
    }
}

// MARK: - BreakpointTemplateValidator

enum BreakpointTemplateValidator {
    // MARK: Internal

    static func validate(rawMessage: String, kind: BreakpointTemplateKind) -> BreakpointTemplateValidation {
        switch parse(rawMessage: rawMessage, kind: kind) {
        case let .valid(summary, _):
            .valid(summary: summary)
        case let .invalid(message):
            .invalid(message: message)
        }
    }

    static func parse(rawMessage: String, kind: BreakpointTemplateKind) -> ParseResult {
        let normalized = normalize(rawMessage)
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .invalid(String(localized: "Message is empty."))
        }

        let split = splitHeadAndBody(normalized)
        var headerLines = split.head.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let startLine = headerLines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !startLine.isEmpty else
        {
            return .invalid(String(localized: "Missing HTTP start line."))
        }
        headerLines.removeFirst()

        switch kind {
        case .request:
            return parseRequest(startLine: startLine, headerLines: headerLines, body: split.body)
        case .response:
            return parseResponse(startLine: startLine, headerLines: headerLines, body: split.body)
        }
    }

    // MARK: Private

    enum ParseResult: Equatable {
        case valid(summary: String, parsed: BreakpointTemplateParsedMessage)
        case invalid(String)
    }

    private static func parseRequest(
        startLine: String,
        headerLines: [String],
        body: String
    )
        -> ParseResult
    {
        let parts = startLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3 else {
            return .invalid(String(localized: "Request line must be METHOD target HTTP/version."))
        }
        let method = parts[0].uppercased()
        guard method.range(of: #"^[A-Z]+$"#, options: .regularExpression) != nil else {
            return .invalid(String(localized: "Request method must contain only letters."))
        }
        guard parts[2].hasPrefix("HTTP/") else {
            return .invalid(String(localized: "Request line must end with an HTTP version."))
        }
        guard !parts[1].isEmpty else {
            return .invalid(String(localized: "Request target is empty."))
        }

        let headers = parseHeaders(headerLines)
        guard case let .valid(parsedHeaders) = headers else {
            if case let .invalid(message) = headers {
                return .invalid(message)
            }
            return .invalid(String(localized: "Invalid headers."))
        }
        if let jsonError = validateJSONBodyIfNeeded(body, headers: parsedHeaders) {
            return .invalid(jsonError)
        }

        let parsed = BreakpointTemplateParsedRequest(
            method: method,
            target: parts[1],
            httpVersion: parts[2],
            headers: parsedHeaders,
            body: body
        )
        return .valid(
            summary: String(localized: "Valid request message"),
            parsed: .request(parsed)
        )
    }

    private static func parseResponse(
        startLine: String,
        headerLines: [String],
        body: String
    )
        -> ParseResult
    {
        let parts = startLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else {
            return .invalid(String(localized: "Response line must be HTTP/version status."))
        }
        guard parts[0].hasPrefix("HTTP/") else {
            return .invalid(String(localized: "Response line must start with an HTTP version."))
        }
        guard let statusCode = Int(parts[1]), (100...999).contains(statusCode) else {
            return .invalid(String(localized: "Response status must be a three-digit code."))
        }

        let headers = parseHeaders(headerLines)
        guard case let .valid(parsedHeaders) = headers else {
            if case let .invalid(message) = headers {
                return .invalid(message)
            }
            return .invalid(String(localized: "Invalid headers."))
        }
        if let jsonError = validateJSONBodyIfNeeded(body, headers: parsedHeaders) {
            return .invalid(jsonError)
        }

        let parsed = BreakpointTemplateParsedResponse(
            httpVersion: parts[0],
            statusCode: statusCode,
            reasonPhrase: parts.count == 3 ? parts[2] : "",
            headers: parsedHeaders,
            body: body
        )
        return .valid(
            summary: String(localized: "Valid response message"),
            parsed: .response(parsed)
        )
    }

    private static func parseHeaders(_ lines: [String]) -> HeaderParseResult {
        var headers: [BreakpointTemplateHeader] = []
        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                return .invalid(String(localized: "Header lines must contain a colon."))
            }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: colon)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                return .invalid(String(localized: "Header name is empty."))
            }
            guard name.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
                return .invalid(String(localized: "Header names cannot contain spaces."))
            }
            headers.append(BreakpointTemplateHeader(name: name, value: value))
        }
        return .valid(headers)
    }

    private static func validateJSONBodyIfNeeded(
        _ body: String,
        headers: [BreakpointTemplateHeader]
    )
        -> String?
    {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty,
              headers.contains(where: {
                  $0.name.caseInsensitiveCompare("content-type") == .orderedSame
                      && $0.value.localizedCaseInsensitiveContains("json")
              }),
              let data = trimmedBody.data(using: .utf8)
        else {
            return nil
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data)
            return nil
        } catch {
            return String(localized: "Invalid JSON body: \(error.localizedDescription)")
        }
    }

    private static func normalize(_ rawMessage: String) -> String {
        rawMessage
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func splitHeadAndBody(_ message: String) -> (head: String, body: String) {
        guard let separator = message.range(of: "\n\n") else {
            return (message, "")
        }
        let head = String(message[..<separator.lowerBound])
        let body = String(message[separator.upperBound...])
        return (head, body)
    }

    private enum HeaderParseResult {
        case valid([BreakpointTemplateHeader])
        case invalid(String)
    }
}

// MARK: - BreakpointRawMessage

enum BreakpointRawMessage {
    // MARK: Internal

    enum Error: Swift.Error {
        case invalid(String)
    }

    static func validation(for rawMessage: String, kind: BreakpointTemplateKind) -> BreakpointTemplateValidation {
        BreakpointTemplateValidator.validate(rawMessage: rawMessage, kind: kind)
    }

    static func rawMessage(from draft: BreakpointRequestData, kind: BreakpointTemplateKind) -> String {
        let headers = draft.headers
            .filter { !$0.name.isEmpty }
            .map { "\($0.name): \($0.value)" }
            .joined(separator: "\n")

        switch kind {
        case .request:
            return join(
                startLine: "\(draft.method) \(requestTarget(from: draft.url)) HTTP/1.1",
                headers: headers,
                body: draft.body
            )
        case .response:
            return join(
                startLine: "HTTP/1.1 \(draft.statusCode) \(reasonPhrase(for: draft.statusCode))",
                headers: headers,
                body: draft.body
            )
        }
    }

    static func applying(
        _ rawMessage: String,
        kind: BreakpointTemplateKind,
        to draft: BreakpointRequestData
    ) throws -> BreakpointRequestData {
        switch BreakpointTemplateValidator.parse(rawMessage: rawMessage, kind: kind) {
        case let .valid(_, parsed):
            return apply(parsed, to: draft)
        case let .invalid(message):
            throw Error.invalid(message)
        }
    }

    // MARK: Private

    private static func apply(
        _ parsed: BreakpointTemplateParsedMessage,
        to draft: BreakpointRequestData
    )
        -> BreakpointRequestData
    {
        var next = draft
        switch parsed {
        case let .request(request):
            next.method = request.method
            next.url = request.target
            next.headers = request.headers.map { EditableHeader(name: $0.name, value: $0.value) }
            next.body = request.body
            next.phase = .request
        case let .response(response):
            next.statusCode = response.statusCode
            next.headers = response.headers.map { EditableHeader(name: $0.name, value: $0.value) }
            next.body = response.body
            next.phase = .response
        }
        return next
    }

    private static func join(startLine: String, headers: String, body: String) -> String {
        if headers.isEmpty {
            return "\(startLine)\n\n\(body)"
        }
        return "\(startLine)\n\(headers)\n\n\(body)"
    }

    private static func requestTarget(from urlString: String) -> String {
        guard let components = URLComponents(string: urlString) else {
            return urlString.isEmpty ? "/" : urlString
        }
        let path = components.path.isEmpty ? "/" : components.path
        if let query = components.query, !query.isEmpty {
            return "\(path)?\(query)"
        }
        return path
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 301: "Moved Permanently"
        case 302: "Found"
        case 304: "Not Modified"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        default: ""
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
