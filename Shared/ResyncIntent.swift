import AppIntents
import WidgetKit

/// Ricarica il widget dei testi: usato dal pulsante ↻ e dai Comandi
/// (es. automazione "Quando si connette CarPlay → Risincronizza testi").
struct ResyncLyricsIntent: AppIntent {
    static let title: LocalizedStringResource = "Resync lyrics"
    static let description = IntentDescription("Refreshes the widget with the song playing on Spotify.")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: Config.widgetKind)
        return .result()
    }
}
