import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Entry

struct LyricEntry: TimelineEntry {
    enum State { case line, idle, paused, noLyrics, error }

    var date: Date
    var state: State
    var title: String = ""
    var artist: String = ""
    var current: String = ""
    var next: String? = nil
    var message: String = ""
}

// MARK: - Provider

struct LyricsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LyricEntry {
        LyricEntry(date: .now, state: .line, title: String(localized: "Title"), artist: String(localized: "Artist"),
                   current: String(localized: "The song's lyrics"), next: String(localized: "appear here"))
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        Task { completion(await buildTimeline().entries.first ?? placeholder(in: context)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricEntry>) -> Void) {
        Task { completion(await buildTimeline()) }
    }

    /// Una entry per ogni riga del testo, datata all'istante in cui va mostrata:
    /// iOS le fa scorrere da solo senza consumare aggiornamenti del widget.
    private func buildTimeline() async -> Timeline<LyricEntry> {
        let now = Date()
        do {
            guard let np = try await SpotifyAPI.currentlyPlaying() else {
                return Timeline(entries: [LyricEntry(date: now, state: .idle, message: String(localized: "Nothing playing"))],
                                policy: .after(now.addingTimeInterval(15 * 60)))
            }
            let base = LyricEntry(date: now, state: .line, title: np.track.name, artist: np.track.artist)

            guard np.isPlaying else {
                var e = base; e.state = .paused; e.message = String(localized: "Paused")
                return Timeline(entries: [e], policy: .after(now.addingTimeInterval(5 * 60)))
            }

            let lyrics = try? await LyricsService.lyrics(for: np.track)
            let lines = lyrics?.synced ?? []
            let songEnd = np.songEnd.addingTimeInterval(1)

            guard !lines.isEmpty else {
                var e = base; e.state = .noLyrics
                e.message = lyrics?.instrumental == true ? String(localized: "♪ Instrumental") : String(localized: "No synced lyrics available")
                return Timeline(entries: [e], policy: .after(songEnd))
            }

            let offset = Double(SharedSettings.offset(for: np.track.id)) / 1000
            var entries: [LyricEntry] = []
            // Intro prima della prima riga
            if let first = lines.first, first.time > 0 {
                var e = base; e.date = np.songStart; e.current = "♪"; e.next = first.text
                entries.append(e)
            }
            for (i, line) in lines.enumerated() {
                var e = base
                e.date = np.songStart.addingTimeInterval(line.time - offset)
                e.current = line.text.isEmpty ? "♪" : line.text
                e.next = lines[safe: i + 1]?.text
                entries.append(e)
            }

            // Tieni solo l'ultima riga già passata (quella attuale) e le successive
            let lastPast = entries.lastIndex { $0.date <= now } ?? 0
            entries = Array(entries[lastPast...])
            entries[0].date = now

            return Timeline(entries: entries, policy: .after(songEnd))
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? String(localized: "Network error")
            return Timeline(entries: [LyricEntry(date: now, state: .error, message: msg)],
                            policy: .after(now.addingTimeInterval(10 * 60)))
        }
    }
}

// MARK: - Vista

struct LyricsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LyricEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                if !entry.title.isEmpty {
                    Text("\(entry.title) · \(entry.artist)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button(intent: ResyncLyricsIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            switch entry.state {
            case .line:
                Text(entry.current)
                    .font(.system(size: family == .systemSmall ? 22 : 26, weight: .bold, design: .rounded))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.opacity)
                if let next = entry.next, !next.isEmpty {
                    Text(next)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(family == .systemSmall ? 1 : 2)
                }
            default:
                Label(entry.message, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var icon: String {
        switch entry.state {
        case .paused: "pause.fill"
        case .idle: "music.note"
        case .noLyrics: "text.badge.xmark"
        case .error: "exclamationmark.triangle"
        case .line: "music.note"
        }
    }
}

// MARK: - Widget

struct LyricsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Config.widgetKind, provider: LyricsProvider()) { entry in
            LyricsWidgetView(entry: entry)
        }
        .configurationDisplayName("Spotify Lyrics")
        .description("The lyrics of the song that's playing, line by line.")
        .supportedFamilies([.systemSmall, .systemMedium]) // systemSmall è il formato di CarPlay
    }
}

@main
struct LyricsWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyricsLiveActivity()
        LyricsWidget()
    }
}
