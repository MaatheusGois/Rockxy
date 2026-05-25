import Foundation

// MARK: - GitHubCredential

struct GitHubCredential: Codable, Equatable, Sendable {
    let accessToken: String
    let authMethod: GitHubAuthMethod
    let scopes: [String]
    let login: String?

    var metadata: GitHubAuthMetadata {
        GitHubAuthMetadata(
            method: authMethod,
            login: login,
            scopes: scopes,
            tokenSuffix: String(accessToken.suffix(4)),
            connectedAt: Date()
        )
    }
}

// MARK: - GitHubCredentialStorage

protocol GitHubCredentialStorage: Sendable {
    func save(_ credential: GitHubCredential) throws
    func load() throws -> GitHubCredential?
    func delete() throws
}

// MARK: - KeychainGitHubCredentialStorage

struct KeychainGitHubCredentialStorage: GitHubCredentialStorage {
    // MARK: Internal

    func save(_ credential: GitHubCredential) throws {
        let data = try JSONEncoder().encode(credential)
        try KeychainHelper.saveSecureData(data, service: Self.service, account: Self.account)
    }

    func load() throws -> GitHubCredential? {
        guard let data = try KeychainHelper.loadSecureData(service: Self.service, account: Self.account) else {
            return nil
        }
        return try JSONDecoder().decode(GitHubCredential.self, from: data)
    }

    func delete() throws {
        try KeychainHelper.deleteSecureData(service: Self.service, account: Self.account)
    }

    // MARK: Private

    private static let service = "\(RockxyIdentity.current.defaultsPrefix).github"
    private static let account = "gist"
}
