import Foundation

enum Config {
    /// Client ID dell'app creata su developer.spotify.com (da Config/Local.xcconfig)
    static let spotifyClientID = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
    /// Schema dell'URL di ritorno dal login (da Config/*.xcconfig → CALLBACK_SCHEME)
    static let callbackScheme = Bundle.main.object(forInfoDictionaryKey: "CallbackScheme") as? String ?? "lyricar"
    static var redirectURI: String { "\(callbackScheme)://callback" }
    static let scopes = "user-read-currently-playing user-read-playback-state"

    /// Deve coincidere con l'App Group negli entitlements di app e widget
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? ""
    static let widgetKind = "LyricsWidget"
}

/// Impostazioni condivise tra app e widget
enum SharedSettings {
    static let defaults = UserDefaults(suiteName: Config.appGroup) ?? .standard

    /// Correzione della sincronia per singolo brano, in millisecondi (positivo = testo in anticipo).
    /// Per brano e non globale: una versione diversa del testo non deve spostare tutte le altre canzoni.
    static func offset(for trackID: String) -> Int {
        (defaults.dictionary(forKey: "trackOffsets") as? [String: Int])?[trackID] ?? 0
    }

    static func setOffset(_ ms: Int, for trackID: String) {
        var all = (defaults.dictionary(forKey: "trackOffsets") as? [String: Int]) ?? [:]
        all[trackID] = ms == 0 ? nil : ms
        defaults.set(all, forKey: "trackOffsets")
    }

    static func resetAllOffsets() {
        defaults.removeObject(forKey: "trackOffsets")
        defaults.removeObject(forKey: "offsetMs") // vecchio offset globale
    }
}

extension SharedSettings {
    /// Avvia la modalità guida automaticamente all'apertura dell'app
    static var autoStart: Bool {
        get { defaults.object(forKey: "autoStart") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoStart") }
    }
}
