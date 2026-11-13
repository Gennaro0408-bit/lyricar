import SwiftUI
import WidgetKit
import AuthenticationServices

struct ContentView: View {
    @ObservedObject private var engine = LyricsEngine.shared
    @Environment(\.webAuthenticationSession) private var webAuth
    @Environment(\.scenePhase) private var scenePhase
    @State private var loginError: String?

    var body: some View {
        NavigationStack {
            Group {
                if engine.loggedIn { player } else { login }
            }
            .navigationTitle("Lyricar")
            .toolbar {
                if engine.loggedIn {
                    Menu {
                        Button("Aggiorna widget", systemImage: "arrow.clockwise") {
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                        Button("Esci da Spotify", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            engine.logout()
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            engine.setForeground(phase == .active)
        }
    }

    // MARK: Login

    private var login: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Collega il tuo account Spotify per vedere i testi su CarPlay.")
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
                Text("Accedi con Spotify").bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            if let loginError {
                Text(loginError).font(.footnote).foregroundStyle(.red)
            }
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
                    Label("Modalità guida", systemImage: "car.fill")
                }
                .tint(.green)
                Toggle("Avvia all'apertura dell'app", isOn: $engine.autoStart)
            } footer: {
                Text(engine.drivingMode
                     ? "Attiva: i testi restano sincronizzati su CarPlay anche con l'app chiusa. Si spegne da sola dopo 15 minuti senza musica."
                     : "Accendila prima di partire: mostra i testi su CarPlay tramite una Live Activity.")
            }

            Section {
                if let np = engine.nowPlaying {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(np.track.name).font(.headline)
                        Text(np.track.artist).foregroundStyle(.secondary)
                        if !np.isPlaying { Text("In pausa").font(.caption).foregroundStyle(.orange) }
                    }
                } else {
                    Text(engine.status.isEmpty ? "Caricamento…" : engine.status)
                        .foregroundStyle(.secondary)
                }
            }

            if !engine.lines.isEmpty {
                Section("Testo") {
                    let i = engine.currentIndex
                    VStack(alignment: .leading, spacing: 8) {
                        Text(i.flatMap { engine.lines[safe: $0]?.text }.flatMap { $0.isEmpty ? nil : $0 } ?? "♪")
                            .font(.title2.bold())
                        Text(engine.lines[safe: (i ?? -1) + 1]?.text ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .animation(.easeInOut, value: i)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
                }
            } else if engine.nowPlaying != nil, !engine.lyricsNote.isEmpty {
                Section { Text(engine.lyricsNote).foregroundStyle(.secondary) }
            }

            if engine.nowPlaying != nil {
                Section {
                    Stepper(value: $engine.offsetMs, in: -3000...3000, step: 250) {
                        LabeledContent("Offset", value: "\(engine.offsetMs > 0 ? "+" : "")\(engine.offsetMs) ms")
                    }
                    if engine.offsetMs != 0 {
                        Button("Azzera offset di questo brano", systemImage: "arrow.uturn.backward") {
                            engine.offsetMs = 0
                        }
                    }
                } header: {
                    Text("Sincronia di questo brano")
                } footer: {
                    Text("Vale solo per la canzone in riproduzione. Testo in ritardo → aumenta; in anticipo → diminuisci.")
                }
            }

            Section("Automazioni consigliate (app Comandi)") {
                Label("CarPlay → Connessione → \"Avvia testi in auto\"", systemImage: "car")
                Label("CarPlay → Disconnessione → \"Ferma testi in auto\"", systemImage: "car.side.arrowtriangle.down")
            }
            .font(.footnote)

            Section {
                NavigationLink("Diagnostica") { DiagnosticsView() }
                Button("Azzera gli offset di tutti i brani", role: .destructive) {
                    engine.resetAllOffsets()
                }
            }
        }
        .refreshable { await engine.forcePoll() }
    }
}
