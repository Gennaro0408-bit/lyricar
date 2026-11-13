import AppIntents
import WidgetKit

/// Ricarica il widget dei testi: usato dal pulsante ↻ e dai Comandi
/// (es. automazione "Quando si connette CarPlay → Risincronizza testi").
struct ResyncLyricsIntent: AppIntent {
    static let title: LocalizedStringResource = "Risincronizza testi"
    static let description = IntentDescription("Aggiorna il widget con il brano Spotify in riproduzione.")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: Config.widgetKind)
        return .result()
    }
}
