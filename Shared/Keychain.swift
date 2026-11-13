import Foundation
import Security

/// Token Spotify salvati nel Keychain, condivisi con il widget tramite App Group.
struct SpotifyTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum TokenStore {
    private static let service = "com.macchinalyrics.spotify"
    private static let account = "tokens"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: Config.appGroup,
        ]
    }

    static func load() -> SpotifyTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
    }

    static func save(_ tokens: SpotifyTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        // Leggibile dal widget anche a iPhone bloccato (dopo il primo sblocco)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
