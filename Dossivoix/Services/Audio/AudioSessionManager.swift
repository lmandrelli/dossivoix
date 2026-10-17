import AVFoundation

/// Contrôle de la session audio, derrière un protocole pour pouvoir la simuler.
@MainActor
protocol AudioSessionControlling: AnyObject {
    /// À appeler au début d'un parcours (lecture ou écriture), avant de parler.
    func activate() async
    /// À appeler à la fin d'un parcours : rend la main aux autres apps (musique…).
    func deactivate()
}

/// Session audio simulée.
final class SilentAudioSession: AudioSessionControlling {
    func activate() async {}
    func deactivate() {}
}

/// Session audio unique pour tout le parcours : `.playAndRecord`.
///
/// Une seule catégorie pour parler et écouter évite les changements de configuration
/// (lents et sources de coupures) entre une question et la réponse. La règle
/// « jamais parler et écouter en même temps » est assurée par le coordinateur :
/// la synthèse est arrêtée avant chaque écoute.
///
/// L'activation peut prendre du temps : elle se fait sur une file dédiée (pas sur le thread
/// de l'interface), une file série pour que activations et désactivations restent dans l'ordre.
@MainActor
final class AudioSessionManager: AudioSessionControlling {
    private let queue = DispatchQueue(label: "work.lmandrelli.dossivoix.audio-session")
    private var isActive = false

    func activate() async {
        guard !isActive else { return }
        isActive = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(
                        .playAndRecord,
                        mode: .default,
                        // Haut-parleur (et non l'écouteur du téléphone), écouteurs Bluetooth acceptés,
                        // et la musique éventuelle baisse pendant que l'app parle.
                        options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers]
                    )
                    try session.setActive(true)
                } catch {
                    Log.audio.error("Activation de la session audio impossible : \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        queue.async {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                Log.audio.error("Désactivation de la session audio impossible : \(error.localizedDescription)")
            }
        }
    }
}
