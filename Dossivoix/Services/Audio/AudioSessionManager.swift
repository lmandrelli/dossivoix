import AVFoundation

/// Contrôle de la session audio, derrière un protocole pour pouvoir la simuler.
@MainActor
protocol AudioSessionControlling: AnyObject {
    /// À appeler au début d'un parcours (lecture ou écriture).
    func activate()
    /// À appeler à la fin d'un parcours : rend la main aux autres apps (musique…).
    func deactivate()
}

/// Session audio simulée.
final class SilentAudioSession: AudioSessionControlling {
    func activate() {}
    func deactivate() {}
}

/// Session audio unique pour tout le parcours : `.playAndRecord`.
///
/// Une seule catégorie pour parler et écouter évite les changements de configuration
/// (lents et sources de coupures) entre une question et la réponse. La règle
/// « jamais parler et écouter en même temps » est assurée par le coordinateur :
/// la synthèse est arrêtée avant chaque écoute.
@MainActor
final class AudioSessionManager: AudioSessionControlling {
    private let session = AVAudioSession.sharedInstance()
    private var isActive = false

    func activate() {
        guard !isActive else { return }
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                // Haut-parleur (et non l'écouteur du téléphone), écouteurs Bluetooth acceptés,
                // et la musique éventuelle baisse pendant que l'app parle.
                options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers]
            )
            try session.setActive(true)
            isActive = true
        } catch {
            Log.audio.error("Activation de la session audio impossible : \(error.localizedDescription)")
        }
    }

    func deactivate() {
        guard isActive else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Log.audio.error("Désactivation de la session audio impossible : \(error.localizedDescription)")
        }
        isActive = false
    }
}
