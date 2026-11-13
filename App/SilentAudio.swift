import AVFoundation

/// Mantiene l'app attiva in background riproducendo silenzio mixato con Spotify.
/// Non interrompe e non modifica l'audio di Spotify (opzione .mixWithOthers).
final class SilentAudio {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var observers: [NSObjectProtocol] = []
    private(set) var isRunning = false
    var onEvent: ((String) -> Void)?

    /// Riavvia il motore se iOS l'ha fermato
    func ensureRunning() {
        guard isRunning, !engine.isRunning else { return }
        onEvent?("motore fermo, riavvio")
        try? AVAudioSession.sharedInstance().setActive(true)
        restartEngine()
    }

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        if source == nil {
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
            let node = AVAudioSourceNode(format: format) { _, _, _, bufferList in
                for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            source = node
            observe()
        }
        isRunning = true
        restartEngine()
    }

    func stop() {
        isRunning = false
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func restartEngine() {
        guard isRunning, !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
    }

    private func observe() {
        let nc = NotificationCenter.default
        // Dopo un'interruzione (telefonata, Siri…) riparte
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            self?.onEvent?(type == .began ? "interruzione iniziata" : "interruzione finita")
            guard type == .ended else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            self?.restartEngine()
        })
        // Cambio di uscita audio (collegamento/scollegamento CarPlay)
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.onEvent?("uscita audio cambiata (\(AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "?"))")
            self?.restartEngine()
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            try? AVAudioSession.sharedInstance().setActive(true)
            self?.restartEngine()
        })
    }
}
