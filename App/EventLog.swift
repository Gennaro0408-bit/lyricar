import Foundation

/// Registro diagnostico su file (Documents/diagnostica.log), leggibile dall'app e via Xcode/devicectl.
enum EventLog {
    private static let queue = DispatchQueue(label: "lyricar.eventlog")
    private static let maxBytes = 512 * 1024

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diagnostica.log")
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        queue.async {
            let url = fileURL
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size > maxBytes,
               let data = try? Data(contentsOf: url) {
                // Tieni solo la seconda metà del file
                try? data.suffix(maxBytes / 2).write(to: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    static func read() -> String {
        queue.sync { (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "" }
    }

    static func clear() {
        queue.sync { try? FileManager.default.removeItem(at: fileURL) }
    }
}
