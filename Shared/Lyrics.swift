import Foundation

struct LyricLine: Codable, Equatable {
    /// Secondi dall'inizio del brano
    let time: TimeInterval
    let text: String
}

struct Lyrics: Codable {
    let synced: [LyricLine]   // vuoto se non disponibili
    let plain: String?
    let instrumental: Bool
    /// Durata (s) della versione su LRCLIB: se diversa da Spotify il testo può essere sfasato
    var sourceDuration: Double? = nil
}

// MARK: - Parser LRC

enum LRCParser {
    /// Converte un testo LRC ("[01:23.45] riga") in righe ordinate per tempo
    static func parse(_ lrc: String) -> [LyricLine] {
        let regex = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)
        var lines: [LyricLine] = []

        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue } // tag di metadati o righe vuote
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)

            // Una riga può avere più timestamp: [00:12.00][01:30.00] ritornello
            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                lines.append(LyricLine(time: min * 60 + sec, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}

// MARK: - LRCLIB (lrclib.net)

enum LyricsService {
    private static var cacheDir: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Config.appGroup)?
            .appendingPathComponent("Library/Caches/lyrics", isDirectory: true)
    }

    private static func cacheURL(for track: Track) -> URL? {
        let safe = track.id.replacingOccurrences(of: "/", with: "_")
        return cacheDir?.appendingPathComponent("\(safe).json")
    }

    static func lyrics(for track: Track) async throws -> Lyrics? {
        if let url = cacheURL(for: track),
           let data = try? Data(contentsOf: url),
           let cached = try? JSONDecoder().decode(Lyrics.self, from: data) {
            return cached
        }

        var result = try await fetchExact(track)
        if result == nil || result?.synced.isEmpty == true, let alt = try await fetchSearch(track) { result = alt }
        if let result, let url = cacheURL(for: track) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(result).write(to: url)
        }
        return result
    }

    private struct Record: Decodable {
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
        let duration: Double?

        var lyrics: Lyrics {
            Lyrics(synced: syncedLyrics.map(LRCParser.parse) ?? [],
                   plain: plainLyrics,
                   instrumental: instrumental ?? false,
                   sourceDuration: duration)
        }
    }

    private static func get(_ path: String, _ items: [URLQueryItem]) async throws -> (Data, Int) {
        var comps = URLComponents(string: "https://lrclib.net/api/\(path)")!
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.setValue("Lyricar 1.0 (https://github.com/Gennaro0408-bit/lyricar)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Ricerca esatta per titolo/artista/album/durata
    private static func fetchExact(_ t: Track) async throws -> Lyrics? {
        let (data, code) = try await get("get", [
            .init(name: "track_name", value: t.name),
            .init(name: "artist_name", value: t.artist),
            .init(name: "album_name", value: t.album),
            .init(name: "duration", value: String(t.durationMs / 1000)),
        ])
        guard code == 200 else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data).lyrics
    }

    /// Ricerca più permissiva: sceglie il risultato sincronizzato con la durata più vicina
    private static func fetchSearch(_ t: Track) async throws -> Lyrics? {
        let (data, code) = try await get("search", [
            .init(name: "track_name", value: t.name),
            .init(name: "artist_name", value: t.artist),
        ])
        guard code == 200, let records = try? JSONDecoder().decode([Record].self, from: data) else { return nil }
        let target = Double(t.durationMs) / 1000
        let best = records
            .filter { $0.syncedLyrics != nil && abs(($0.duration ?? target) - target) < 5 }
            .min { abs(($0.duration ?? 0) - target) < abs(($1.duration ?? 0) - target) }
        return (best ?? records.first)?.lyrics
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
