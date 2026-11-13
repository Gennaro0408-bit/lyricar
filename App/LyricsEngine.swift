import Foundation
import ActivityKit
import WidgetKit
import AVFoundation

/// Motore dei testi: interroga Spotify, calcola la riga corrente in tempo reale
/// e, in modalità guida, aggiorna la Live Activity (visibile su CarPlay) restando attivo in background.
@MainActor
final class LyricsEngine: ObservableObject {
    static let shared = LyricsEngine()

    @Published var loggedIn = TokenStore.load() != nil
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var lyricsNote = ""
    @Published private(set) var status = ""
    @Published private(set) var drivingMode = false
    /// Offset del brano in riproduzione (salvato per brano)
    @Published var offsetMs = 0 {
        didSet {
            guard let id = nowPlaying?.track.id, offsetMs != SharedSettings.offset(for: id) else { return }
            SharedSettings.setOffset(offsetMs, for: id)
            EventLog.log("Offset \(offsetMs) ms for «\(nowPlaying?.track.name ?? "")»")
            reloadWidget()
        }
    }
    @Published var autoStart = SharedSettings.autoStart {
        didSet { SharedSettings.autoStart = autoStart }
    }

    private var songStart: Date?
    private var loop: Task<Void, Never>?
    private var isForeground = false
    private var activity: Activity<LyricsActivityAttributes>?
    private var lastState: LyricsActivityAttributes.ContentState?
    private var idleSince: Date?
    private let keepAlive = SilentAudio()
    private let locationKeepAlive = LocationKeepAlive()

    private var lastPollOK = Date()
    private var lastActivityAttempt = Date.distantPast
    private var activityObserver: Task<Void, Never>?

    init() {
        // L'offset globale della versione precedente spostava tutte le canzoni: azzeralo una volta
        if SharedSettings.defaults.object(forKey: "offsetMs") != nil {
            SharedSettings.resetAllOffsets()
            EventLog.log("Old global offset reset")
        }
        keepAlive.onEvent = { EventLog.log("Audio: \($0)") }
        locationKeepAlive.onEvent = { EventLog.log("Location: \($0)") }
    }

    func resetAllOffsets() {
        SharedSettings.resetAllOffsets()
        offsetMs = 0
        EventLog.log("All offsets reset")
        reloadWidget()
    }

    private let pollInterval: TimeInterval = 3
    private let idleTimeout: TimeInterval = 15 * 60 // modalità guida si spegne dopo 15 min senza musica

    // MARK: Ciclo di vita

    func setForeground(_ foreground: Bool) {
        if foreground != isForeground { EventLog.log(foreground ? "App in foreground" : "App in background") }
        isForeground = foreground
        if foreground {
            if autoStart && loggedIn && !drivingMode { startDriving() }
            if drivingMode { locationKeepAlive.start() } // es. permesso concesso dopo il primo avvio
            runLoop()
        } else if !drivingMode {
            loop?.cancel(); loop = nil
        }
    }

    func startDriving() {
        guard loggedIn else { return }
        EventLog.log("▶︎ Driving Mode ON")
        drivingMode = true
        keepAlive.start()
        locationKeepAlive.start()
        startActivity()
        runLoop()
    }

    func stopDriving() {
        if drivingMode { EventLog.log("■ Driving Mode OFF") }
        drivingMode = false
        keepAlive.stop()
        locationKeepAlive.stop()
        endActivities()
        if !isForeground { loop?.cancel(); loop = nil }
    }

    func logout() {
        stopDriving()
        TokenStore.clear()
        loggedIn = false
        nowPlaying = nil
        lines = []
        reloadWidget()
    }

    func forcePoll() async { await poll() }

    private func runLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            var lastPoll = Date.distantPast
            while !Task.isCancelled {
                guard let self else { return }
                if Date().timeIntervalSince(lastPoll) >= self.pollInterval {
                    lastPoll = Date()
                    await self.poll()
                }
                self.tick()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    // MARK: Spotify

    private func poll() async {
        guard loggedIn else { return }
        // Controlli di salute: un buco tra due letture indica che iOS ha sospeso l'app
        let gap = Date().timeIntervalSince(lastPollOK)
        if gap > 15 { EventLog.log("⚠️ No updates for \(Int(gap)) s (app suspended?)") }
        if drivingMode { keepAlive.ensureRunning() }
        if drivingMode, activity == nil || activity?.activityState != .active,
           Date().timeIntervalSince(lastActivityAttempt) > 60 {
            lastActivityAttempt = Date()
            EventLog.log("⚠️ Live Activity not active (\(String(describing: activity?.activityState))), recreating it")
            startActivity()
        }
        do {
            let np = try await SpotifyAPI.currentlyPlaying()
            lastPollOK = Date()
            guard let np else {
                nowPlaying = nil
                status = String(localized: "Nothing playing on Spotify")
                markIdle()
                return
            }
            status = ""
            let previous = nowPlaying
            nowPlaying = np

            if np.track.id != previous?.track.id {
                songStart = np.songStart
                offsetMs = SharedSettings.offset(for: np.track.id)
                lines = []
                lyricsNote = String(localized: "Looking for lyrics…")
                let lyrics = try? await LyricsService.lyrics(for: np.track)
                guard nowPlaying?.track.id == np.track.id else { return }
                lines = lyrics?.synced ?? []
                lyricsNote = lines.isEmpty
                    ? (lyrics?.instrumental == true ? String(localized: "♪ Instrumental") : String(localized: "No synced lyrics available"))
                    : ""
                let spotifyDur = Double(np.track.durationMs) / 1000
                let diff = lyrics?.sourceDuration.map { $0 - spotifyDur }
                EventLog.log("♪ «\(np.track.name)» – \(np.track.artist) | pos \(np.progressMs / 1000)s | lines \(lines.count)"
                    + (diff.map { String(format: " | lyrics duration %+.1fs", $0) } ?? "")
                    + (offsetMs != 0 ? " | offset \(offsetMs) ms" : ""))
                if let diff, abs(diff) > 2 {
                    EventLog.log("⚠️ Lyrics found are for a version with a different duration: they may be out of sync")
                }
                reloadWidget()
            } else if np.isPlaying, previous?.isPlaying == true, let s = songStart {
                let drift = np.songStart.timeIntervalSince(s)
                if abs(drift) > 1.0 {
                    EventLog.log(String(format: "Re-aligning by %+.1fs (skip/seek or delay)", -drift))
                    songStart = np.songStart      // salto/riavvolgimento
                    reloadWidget()
                } else {
                    songStart = s.addingTimeInterval(drift * 0.3) // smorza il rumore di rete
                }
            } else {
                songStart = np.songStart          // pausa o ripresa
                if np.isPlaying != previous?.isPlaying {
                    EventLog.log(np.isPlaying ? "Resumed" : "Paused")
                    reloadWidget()
                }
            }

            if np.isPlaying { idleSince = nil } else { markIdle() }
        } catch {
            EventLog.log("Spotify error: \(error.localizedDescription)")
            status = error.localizedDescription
            if case SpotifyError.notLoggedIn = error { loggedIn = false }
        }
    }

    private func markIdle() {
        // Finché l'iPhone è collegato a CarPlay non spegnere: la musica può ripartire
        if AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.portType == .carAudio }) {
            idleSince = nil
            return
        }
        idleSince = idleSince ?? Date()
        if drivingMode, let since = idleSince, Date().timeIntervalSince(since) > idleTimeout {
            EventLog.log("No music for 15 min and CarPlay disconnected: stopping")
            stopDriving()
        }
    }

    // MARK: Riga corrente

    private func tick() {
        guard let np = nowPlaying else {
            currentIndex = nil
            pushActivity(.init(title: "", artist: "", current: "", next: nil, isPlaying: false,
                               message: status.isEmpty ? String(localized: "Nothing playing") : status))
            return
        }
        let offset = Double(offsetMs) / 1000
        let elapsed = np.isPlaying
            ? Date().timeIntervalSince(songStart ?? np.songStart) + offset
            : Double(np.progressMs) / 1000 + offset
        let idx = lines.lastIndex { $0.time <= elapsed }
        if idx != currentIndex { currentIndex = idx }

        var state = LyricsActivityAttributes.ContentState(
            title: np.track.name, artist: np.track.artist,
            current: "", next: nil, isPlaying: np.isPlaying, message: nil)
        if lines.isEmpty {
            state.message = lyricsNote.isEmpty ? "♪" : lyricsNote
        } else {
            let text = idx.map { lines[$0].text } ?? ""
            state.current = text.isEmpty ? "♪" : text
            state.next = lines[safe: (idx ?? -1) + 1]?.text
        }
        pushActivity(state)
    }

    // MARK: Live Activity

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = String(localized: "Turn on Live Activities for Lyricar in Settings")
            return
        }
        endActivities()
        let initial = LyricsActivityAttributes.ContentState(
            title: "", artist: "", current: "", next: nil, isPlaying: false, message: String(localized: "Starting…"))
        do {
            let a = try Activity.request(
                attributes: LyricsActivityAttributes(),
                content: .init(state: initial, staleDate: nil),
                pushType: nil)
            activity = a
            lastState = initial
            EventLog.log("Live Activity started")
            activityObserver?.cancel()
            activityObserver = Task {
                for await state in a.activityStateUpdates {
                    EventLog.log("Live Activity → \(state)")
                }
            }
        } catch {
            EventLog.log("⚠️ Live Activity not started: \(error.localizedDescription)")
        }
    }

    private func endActivities() {
        activityObserver?.cancel()
        activity = nil
        lastState = nil
        for a in Activity<LyricsActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func pushActivity(_ state: LyricsActivityAttributes.ContentState) {
        guard drivingMode, let activity, state != lastState else { return }
        lastState = state
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    private func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: Config.widgetKind)
    }
}
