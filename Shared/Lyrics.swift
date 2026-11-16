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
            // v2: la cache precedente può contenere testi di versioni sbagliate
            .appendingPathComponent("Library/Caches/lyrics-v2", isDirectory: true)
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

        let exact = try await fetchExact(track)
        let found = (try? await search(track)) ?? []
        var result = pick(exact: exact, found: found, for: track) ?? exact
        if let r = result, !r.synced.isEmpty, !fits(r.synced, track) {
            // Meglio nessun testo sincronizzato che un testo sfasato
            result = Lyrics(synced: [], plain: r.plain, instrumental: r.instrumental, sourceDuration: r.sourceDuration)
        }
        if let result, let url = cacheURL(for: track) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(result).write(to: url)
        }
        return result
    }

    /// Su LRCLIB la durata dichiarata non è affidabile: un testo con righe oltre la fine del brano
    /// su Spotify è di un'altra versione
    static func fits(_ lines: [LyricLine], _ t: Track) -> Bool {
        guard let last = lines.last else { return false }
        return last.time <= Double(t.durationMs) / 1000 + 1
    }

    /// Sceglie la sincronizzazione per la durata del brano su Spotify. Su LRCLIB una sincronizzazione
    /// viene spesso copiata su versioni di durata diversa (es. senza l'intro): se compare più su
    /// versioni di durata diversa che su questa, è una copia e si scarta.
    static func pick(exact: Lyrics?, found: [Lyrics], for t: Track) -> Lyrics? {
        let target = Double(t.durationMs) / 1000
        func near(_ l: Lyrics) -> Bool { abs((l.sourceDuration ?? target) - target) < 5 }
        func sameSync(_ a: Lyrics, _ b: Lyrics) -> Bool {
            guard let a0 = a.synced.first, let a1 = a.synced.last,
                  let b0 = b.synced.first, let b1 = b.synced.last else { return false }
            return abs(a0.time - b0.time) < 0.5 && abs(a1.time - b1.time) < 0.5
        }
        let candidates = ([exact].compactMap { $0 } + found).filter { near($0) && fits($0.synced, t) }
        let native = candidates.filter { c in
            let same = found.filter { sameSync($0, c) }
            let nearCount = same.filter(near).count
            return nearCount >= same.count - nearCount
        }
        // A parità di durata vince il primo, cioè la ricerca esatta
        return (native.isEmpty ? candidates : native)
            .min { abs(($0.sourceDuration ?? target) - target) < abs(($1.sourceDuration ?? target) - target) }
    }

    /// "Te - Remastered 2011" / "Te (feat. X)" → "te", per confrontare i titoli
    static func baseTitle(_ s: String) -> String {
        var s = s
        if let r = s.range(of: " - ") { s = String(s[..<r.lowerBound]) }
        if let r = s.range(of: #"\s*[\(\[](feat|ft|with)\b.*$"#, options: [.regularExpression, .caseInsensitive]) {
            s = String(s[..<r.lowerBound])
        }
        return s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    private struct Record: Decodable {
        let trackName: String?
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

    /// Tutte le versioni con lo stesso titolo (anche di durata diversa: servono a `pick` per riconoscere le copie)
    private static func search(_ t: Track) async throws -> [Lyrics] {
        let (data, code) = try await get("search", [
            .init(name: "track_name", value: baseTitle(t.name)),
            .init(name: "artist_name", value: t.artist),
        ])
        guard code == 200, let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        let title = baseTitle(t.name)
        return records.filter { baseTitle($0.trackName ?? "") == title }.map(\.lyrics)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
