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
    static let title: LocalizedStringResource = "Start lyrics in the car"
    static let description = IntentDescription("Turns on Driving Mode with lyrics on CarPlay.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LyricsEngine.shared.startDriving()
        return .result()
    }
}

/// "Ferma testi in auto": spegne la modalità guida (per l'automazione CarPlay → Disconnessione)
struct StopDrivingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop lyrics in the car"
    static let description = IntentDescription("Turns off Driving Mode and ends the Live Activity.")

    @MainActor
    func perform() async throws -> some IntentResult {
        LyricsEngine.shared.stopDriving()
        return .result()
    }
}

struct LyricarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartDrivingIntent(),
                    phrases: ["Start lyrics in the car with \(.applicationName)"],
                    shortTitle: "Start lyrics in the car",
                    systemImageName: "car.fill")
        AppShortcut(intent: StopDrivingIntent(),
                    phrases: ["Stop lyrics in the car with \(.applicationName)"],
                    shortTitle: "Stop lyrics in the car",
                    systemImageName: "stop.fill")
        AppShortcut(intent: ResyncLyricsIntent(),
                    phrases: ["Resync lyrics in \(.applicationName)"],
                    shortTitle: "Resync widget",
                    systemImageName: "arrow.clockwise")
    }
}
