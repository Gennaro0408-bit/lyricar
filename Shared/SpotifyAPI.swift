import Foundation

struct Track: Equatable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let durationMs: Int
}

struct NowPlaying {
    let track: Track
    let progressMs: Int
    let isPlaying: Bool
    /// Momento in cui è stata fatta la richiesta (per calcolare l'inizio del brano)
    let fetchedAt: Date

    /// Istante (stimato) in cui il brano è iniziato
    var songStart: Date { fetchedAt.addingTimeInterval(-Double(progressMs) / 1000) }
    var songEnd: Date { songStart.addingTimeInterval(Double(track.durationMs) / 1000) }
}

enum SpotifyError: Error, LocalizedError {
    case notLoggedIn, http(Int), badResponse

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: String(localized: "Sign in to Spotify from the Lyricar app")
        case .http(403): String(localized: "Account not authorized: add it under User Management on the Spotify dashboard")
        case .http(let c): String(localized: "Spotify error (\(c))")
        case .badResponse: String(localized: "Invalid response from Spotify")
        }
    }
}

enum SpotifyAPI {
    // MARK: Token

    /// Scambia/aggiorna il token sull'endpoint OAuth di Spotify (PKCE, niente client secret)
    static func requestToken(_ params: [String: String]) async throws -> SpotifyTokens {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let code = (resp as? HTTPURLResponse)?.statusCode else { throw SpotifyError.badResponse }
        guard code == 200 else { throw SpotifyError.http(code) }

        struct Resp: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        let tokens = SpotifyTokens(
            accessToken: r.access_token,
            refreshToken: r.refresh_token ?? params["refresh_token"] ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(r.expires_in - 60))
        )
        TokenStore.save(tokens)
        return tokens
    }

    static func validAccessToken() async throws -> String {
        guard let tokens = TokenStore.load() else { throw SpotifyError.notLoggedIn }
        if tokens.expiresAt > Date() { return tokens.accessToken }
        let refreshed = try await requestToken([
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": Config.spotifyClientID,
        ])
        return refreshed.accessToken
    }

    // MARK: Riproduzione

    /// Brano in riproduzione, oppure nil se non sta suonando niente
    static func currentlyPlaying() async throws -> NowPlaying? {
        let token = try await validAccessToken()
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let sent = Date()
        let (data, resp) = try await URLSession.shared.data(for: req)
        let received = Date()
        guard let code = (resp as? HTTPURLResponse)?.statusCode else { throw SpotifyError.badResponse }
        if code == 204 { return nil }
        guard code == 200 else { throw SpotifyError.http(code) }

        struct Resp: Decodable {
            struct Item: Decodable {
                struct Artist: Decodable { let name: String }
                struct Album: Decodable { let name: String }
                let id: String?
                let name: String
                let duration_ms: Int
                let artists: [Artist]?
                let album: Album?
            }
            let is_playing: Bool
            let progress_ms: Int?
            let item: Item?
        }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        guard let item = r.item else { return nil } // es. pubblicità o podcast

        let track = Track(
            id: item.id ?? "\(item.name)-\(item.duration_ms)",
            name: item.name,
            artist: item.artists?.first?.name ?? "",
            album: item.album?.name ?? "",
            durationMs: item.duration_ms
        )
        // Usiamo il punto medio della richiesta per compensare la latenza di rete
        let mid = sent.addingTimeInterval(received.timeIntervalSince(sent) / 2)
        return NowPlaying(track: track, progressMs: r.progress_ms ?? 0, isPlaying: r.is_playing, fetchedAt: mid)
    }
}
