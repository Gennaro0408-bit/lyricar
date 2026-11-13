import SwiftUI
import WidgetKit
import AuthenticationServices

struct ContentView: View {
    @ObservedObject private var engine = LyricsEngine.shared
    @Environment(\.webAuthenticationSession) private var webAuth
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var loginError: String?

    var body: some View {
        NavigationStack {
            Group {
                if engine.loggedIn { player } else { login }
            }
            .navigationTitle("Lyricar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Language", systemImage: "globe") { openLanguageSettings() }
                        if engine.loggedIn {
                            Button("Refresh widget", systemImage: "arrow.clockwise") {
                                WidgetCenter.shared.reloadAllTimelines()
                            }
                            Button("Sign out of Spotify", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                engine.logout()
                            }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            engine.setForeground(phase == .active)
        }
    }

    /// iOS gestisce la lingua per app in Impostazioni → Lyricar → Lingua
    private func openLanguageSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    /// Nome della lingua in uso, scritto in quella lingua (es. "Italiano", "English")
    private var currentLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    // MARK: Login

    private var login: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Connect your Spotify account to see lyrics on CarPlay.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                Task {
                    do {
                        try await SpotifyLogin.login(using: webAuth)
                        engine.loggedIn = true
                        loginError = nil
                        WidgetCenter.shared.reloadAllTimelines()
                        engine.setForeground(true)
                    } catch {
                        loginError = error.localizedDescription
                    }
                }
            } label: {
                Text("Sign in with Spotify").bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            if let loginError {
                Text(loginError).font(.footnote).foregroundStyle(.red)
            }
            Button {
                openLanguageSettings()
            } label: {
                Label("Language: \(currentLanguageName)", systemImage: "globe")
                    .font(.footnote)
            }
            .padding(.top, 8)
        }
        .padding(24)
    }

    // MARK: Player

    private var player: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { engine.drivingMode },
                    set: { $0 ? engine.startDriving() : engine.stopDriving() })) {
                    Label("Driving Mode", systemImage: "car.fill")
                }
                .tint(.green)
                Toggle("Start when the app opens", isOn: $engine.autoStart)
            } footer: {
                if engine.drivingMode {
                    Text("On: lyrics stay in sync on CarPlay even with the app closed. Turns off by itself after 15 minutes without music once CarPlay is disconnected.")
                } else {
                    Text("Turn it on before you drive: it shows the lyrics on CarPlay through a Live Activity.")
                }
            }

            Section {
                if let np = engine.nowPlaying {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: np.track.name).font(.headline)
                        Text(verbatim: np.track.artist).foregroundStyle(.secondary)
                        if !np.isPlaying { Text("Paused").font(.caption).foregroundStyle(.orange) }
                    }
                } else if engine.status.isEmpty {
                    Text("Loading…").foregroundStyle(.secondary)
                } else {
                    Text(verbatim: engine.status).foregroundStyle(.secondary)
                }
            }

            if !engine.lines.isEmpty {
                Section("Lyrics") {
                    let i = engine.currentIndex
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: i.flatMap { engine.lines[safe: $0]?.text }.flatMap { $0.isEmpty ? nil : $0 } ?? "♪")
                            .font(.title2.bold())
                        Text(verbatim: engine.lines[safe: (i ?? -1) + 1]?.text ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .animation(.easeInOut, value: i)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
                }
            } else if engine.nowPlaying != nil, !engine.lyricsNote.isEmpty {
                Section { Text(verbatim: engine.lyricsNote).foregroundStyle(.secondary) }
            }

            if engine.nowPlaying != nil {
                Section {
                    Stepper(value: $engine.offsetMs, in: -3000...3000, step: 250) {
                        LabeledContent("Offset", value: "\(engine.offsetMs > 0 ? "+" : "")\(engine.offsetMs) ms")
                    }
                    if engine.offsetMs != 0 {
                        Button("Reset this song's offset", systemImage: "arrow.uturn.backward") {
                            engine.offsetMs = 0
                        }
                    }
                } header: {
                    Text("Sync for this song")
                } footer: {
                    Text("Applies only to the song that's playing. Lyrics late → increase; early → decrease.")
                }
            }

            Section("Suggested automations (Shortcuts app)") {
                Label("CarPlay → Connects → “Start lyrics in the car”", systemImage: "car")
                Label("CarPlay → Disconnects → “Stop lyrics in the car”", systemImage: "car.side.arrowtriangle.down")
            }
            .font(.footnote)

            Section {
                Button {
                    openLanguageSettings()
                } label: {
                    LabeledContent {
                        Text(verbatim: currentLanguageName)
                    } label: {
                        Label("Language", systemImage: "globe")
                    }
                }
                .foregroundStyle(.primary)
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
                Button("Reset offsets for all songs", role: .destructive) {
                    engine.resetAllOffsets()
                }
            } footer: {
                Text("To switch between English and Italian, tap Language and choose it under “Preferred Language”.")
            }
        }
        .refreshable { await engine.forcePoll() }
    }
}
