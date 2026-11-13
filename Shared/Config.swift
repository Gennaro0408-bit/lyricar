import Foundation

enum Config {
    /// Client ID incorporato in fase di build (Config/Local.xcconfig); vuoto nelle .ipa pubbliche
    static let builtInClientID = (Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? "")
        .trimmingCharacters(in: .whitespaces)

    /// Client ID in uso: quello incorporato oppure quello inserito dall'utente al primo avvio
    static var spotifyClientID: String {
        builtInClientID.isEmpty ? SharedSettings.customClientID : builtInClientID
    }
    /// Schema dell'URL di ritorno dal login (da Config/*.xcconfig → CALLBACK_SCHEME)
    static let callbackScheme = Bundle.main.object(forInfoDictionaryKey: "CallbackScheme") as? String ?? "lyricar"
    static var redirectURI: String { "\(callbackScheme)://callback" }
    static let scopes = "user-read-currently-playing user-read-playback-state"

    /// App Group condiviso da app e widget. Strumenti come AltStore/SideStore riscrivono Bundle ID
    /// e App Group per l'account di chi installa, quindi si prova anche "group.<bundle id dell'app>"
    /// e si usa il primo a cui l'app ha davvero accesso. Vuoto = nessun gruppo (il widget non vede il login).
    static let appGroup: String = {
        var base = Bundle.main.bundleIdentifier ?? ""
        if base.hasSuffix(".widget") { base = String(base.dropLast(".widget".count)) }
        let candidates = [Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String, "group.\(base)"]
        return candidates.compactMap { $0 }.first {
            !$0.isEmpty && FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        } ?? ""
    }()
    static let widgetKind = "LyricsWidget"
}

/// Impostazioni condivise tra app e widget
enum SharedSettings {
    static let defaults = Config.appGroup.isEmpty ? .standard : (UserDefaults(suiteName: Config.appGroup) ?? .standard)

    /// Client ID inserito dall'utente (usato quando l'app non ne ha uno incorporato)
    static var customClientID: String {
        get { defaults.string(forKey: "spotifyClientID") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "spotifyClientID") }
    }

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
