import CoreLocation

/// Secondo sistema per restare attivi in background, come i navigatori.
/// A differenza dell'audio silenzioso non viene interrotto dalle telefonate.
/// La posizione non viene salvata né inviata da nessuna parte.
@MainActor
final class LocationKeepAlive {
    private let manager = CLLocationManager()
    private var session: CLBackgroundActivitySession?
    private var updates: Task<Void, Never>?
    var onEvent: ((String) -> Void)?

    var isAuthorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    /// Va chiamato con l'app in primo piano (iOS lo richiede per avviare la sessione)
    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        guard session == nil else { return }
        session = CLBackgroundActivitySession()
        updates = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    if Task.isCancelled { break }
                    if update.authorizationDenied || update.authorizationDeniedGlobally {
                        self?.onEvent?("permesso posizione negato")
                    }
                }
            } catch {
                self?.onEvent?("errore posizione: \(error.localizedDescription)")
            }
        }
        onEvent?("sessione posizione avviata")
    }

    func stop() {
        updates?.cancel(); updates = nil
        session?.invalidate(); session = nil
    }
}
