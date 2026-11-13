import SwiftUI
import AppIntents

@main
struct LyricarApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// "Avvia testi in auto": apre l'app e accende la modalità guida (per l'automazione CarPlay)
struct StartDrivingIntent: AppIntent {
    static let title: LocalizedStringResource = "Avvia testi in auto"
    static let description = IntentDescription("Avvia la modalità guida con i testi su CarPlay.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LyricsEngine.shared.startDriving()
        return .result()
    }
}

/// "Ferma testi in auto": spegne la modalità guida (per l'automazione CarPlay → Disconnessione)
struct StopDrivingIntent: AppIntent {
    static let title: LocalizedStringResource = "Ferma testi in auto"
    static let description = IntentDescription("Termina la modalità guida e la Live Activity.")

    @MainActor
    func perform() async throws -> some IntentResult {
        LyricsEngine.shared.stopDriving()
        return .result()
    }
}

struct LyricarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartDrivingIntent(),
                    phrases: ["Avvia testi in auto con \(.applicationName)"],
                    shortTitle: "Avvia testi in auto",
                    systemImageName: "car.fill")
        AppShortcut(intent: StopDrivingIntent(),
                    phrases: ["Ferma testi in auto con \(.applicationName)"],
                    shortTitle: "Ferma testi in auto",
                    systemImageName: "stop.fill")
        AppShortcut(intent: ResyncLyricsIntent(),
                    phrases: ["Risincronizza testi in \(.applicationName)"],
                    shortTitle: "Risincronizza widget",
                    systemImageName: "arrow.clockwise")
    }
}
