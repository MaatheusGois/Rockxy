import Foundation

// MARK: - GitHubGistVisibility

enum GitHubGistVisibility: String, CaseIterable, Codable {
    case secret
    case `public`

    var isPublic: Bool {
        self == .public
    }

    var title: String {
        switch self {
        case .secret:
            String(localized: "Private Gist")
        case .public:
            String(localized: "Public Gist")
        }
    }
}

// MARK: - GitHubAuthMethod

enum GitHubAuthMethod: String, Codable {
    case deviceCode
    case personalAccessToken
}

// MARK: - GitHubAuthMetadata

struct GitHubAuthMetadata: Codable, Equatable {
    let method: GitHubAuthMethod
    let login: String?
    let scopes: [String]
    let tokenSuffix: String
    let connectedAt: Date
}

// MARK: - GitHubSettingsStore

enum GitHubSettingsStore {
    // MARK: Internal

    static func loadMetadata(userDefaults: UserDefaults = .standard) -> GitHubAuthMetadata? {
        guard let data = userDefaults.data(forKey: metadataKey) else {
            return nil
        }
        return try? JSONDecoder().decode(GitHubAuthMetadata.self, from: data)
    }

    static func saveMetadata(_ metadata: GitHubAuthMetadata, userDefaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(metadata) else {
            return
        }
        userDefaults.set(data, forKey: metadataKey)
    }

    static func deleteMetadata(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: metadataKey)
    }

    static func userDefaultsContainsToken(_ token: String, userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.dictionaryRepresentation().contains { _, value in
            if let string = value as? String {
                return string.contains(token)
            }
            if let data = value as? Data,
               let string = String(data: data, encoding: .utf8) {
                return string.contains(token)
            }
            return false
        }
    }

    // MARK: Private

    private static let metadataKey = RockxyIdentity.current.defaultsKey("github.authMetadata")
}
