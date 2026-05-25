import Foundation
@testable import Rockxy
import Testing

// MARK: - GitHubGistClientTests

struct GitHubGistClientTests {
    @Test("Creates POST gists request with bearer auth and secret default")
    func createsGistRequestShape() async throws {
        let expectedURL = URL(string: "https://api.github.com/gists")!
        let client = GitHubGistClient(httpClient: MockGitHubHTTPClient { request in
            #expect(request.url == expectedURL)
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")

            let body = try #require(request.httpBody)
            let decoded = try JSONDecoder().decode(GitHubGistCreateRequest.self, from: body)
            #expect(decoded.public == false)
            #expect(decoded.files["README.md"]?.content == "hello")

            return (
                #"{"id":"abc","html_url":"https://gist.github.com/me/abc"}"#.data(using: .utf8)!,
                HTTPURLResponse(url: expectedURL, statusCode: 201, httpVersion: nil, headerFields: nil)!
            )
        })

        let result = try await client.createGist(
            payload: GistPublishPayload(
                description: "test",
                isPublic: false,
                files: ["README.md": "hello"],
                warnings: []
            ),
            accessToken: "token"
        )

        #expect(result.id == "abc")
        #expect(result.htmlURL.absoluteString == "https://gist.github.com/me/abc")
    }

    @Test("Maps auth and validation failures")
    func mapsGitHubErrors() async {
        let url = URL(string: "https://api.github.com/gists")!
        let payload = GistPublishPayload(description: "test", isPublic: false, files: ["README.md": "hello"], warnings: [])
        let client = GitHubGistClient(httpClient: MockGitHubHTTPClient { _ in
            (
                #"{"message":"Validation Failed"}"#.data(using: .utf8)!,
                HTTPURLResponse(url: url, statusCode: 422, httpVersion: nil, headerFields: nil)!
            )
        })

        do {
            _ = try await client.createGist(payload: payload, accessToken: "token")
            Issue.record("Expected validation failure")
        } catch let error as GitHubGistClient.ClientError {
            #expect(error == .validationFailed("Validation Failed"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

// MARK: - MockGitHubHTTPClient

private struct MockGitHubHTTPClient: GitHubHTTPDataLoading {
    let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request)
    }
}
