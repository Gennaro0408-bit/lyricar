import Foundation
import CryptoKit
import AuthenticationServices
import SwiftUI

/// Login Spotify con OAuth Authorization Code + PKCE (nessun client secret nell'app)
enum SpotifyLogin {
    static func login(using session: WebAuthenticationSession) async throws {
        let verifier = randomString(length: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = randomString(length: 16)

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: Config.spotifyClientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Config.redirectURI),
            .init(name: "scope", value: Config.scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
            .init(name: "show_dialog", value: "true"), // permette di scegliere l'account giusto
        ]

        // Sessione "effimera": non riusa l'account Spotify aperto in Safari
        let callback = try await session.authenticate(
            using: comps.url!,
            callbackURLScheme: Config.callbackScheme,
            preferredBrowserSession: .ephemeral
        )

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            throw NSError(domain: "Spotify", code: 1, userInfo: [NSLocalizedDescriptionKey: "Login annullato (\(err))"])
        }
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw SpotifyError.badResponse
        }

        _ = try await SpotifyAPI.requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Config.redirectURI,
            "client_id": Config.spotifyClientID,
            "code_verifier": verifier,
        ])
    }

    private static func randomString(length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars.randomElement(using: &rng)! })
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
