import ActivityKit
import Foundation

/// Live Activity dei testi: aggiornata in tempo reale dall'app in modalità guida.
struct LyricsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var current: String
        var next: String?
        var isPlaying: Bool
        var message: String?
    }
}
