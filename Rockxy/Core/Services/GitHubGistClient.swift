import Foundation

// MARK: - GistPublishResult

struct GistPublishResult: Codable, Equatable, Sendable {
    let id: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case id
        case htmlURL = "html_url"
    }
}

// MARK: - GitHubGistClient

struct GitHubGistClient: Sendable {
    // MARK: Lifecycle

    init(httpClient: any GitHubHTTPDataLoading = URLSession.shared) {
        self.httpClient = httpClient
    }

    // MARK: Internal

    enum ClientError: LocalizedError, Equatable {
        case unauthorized
        case forbidden
        case validationFailed(String)
        case unexpectedStatus(Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                String(localized: "GitHub rejected the saved token. Reconnect GitHub in Settings.")
            case .forbidden:
                String(localized: "The saved GitHub token does not have permission to create Gists.")
            case let .validationFailed(message):
                message
            case let .unexpectedStatus(status):
                String(localized: "GitHub returned HTTP \(status).")
            case .invalidResponse:
                String(localized: "GitHub returned an unexpected response.")
            }
        }
    }

    func createGist(payload: GistPublishPayload, accessToken: String) async throws -> GistPublishResult {
        var request = URLRequest(url: URL(string: "https://api.github.com/gists")!) // swiftlint:disable:this force_unwrapping
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.httpBody = try JSONEncoder().encode(payload.createRequest)

        let (data, response) = try await httpClient.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 201:
            return try JSONDecoder().decode(GistPublishResult.self, from: data)
        case 401:
            throw ClientError.unauthorized
        case 403:
            throw ClientError.forbidden
        case 422:
            throw ClientError.validationFailed(Self.validationMessage(from: data))
        default:
            throw ClientError.unexpectedStatus(httpResponse.statusCode)
        }
    }

    // MARK: Private

    private struct ErrorResponse: Decodable {
        let message: String?
    }

    private let httpClient: any GitHubHTTPDataLoading

    private static func validationMessage(from data: Data) -> String {
        if let response = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           let message = response.message,
           !message.isEmpty {
            return message
        }
        return String(localized: "GitHub could not validate the Gist payload.")
    }
}
