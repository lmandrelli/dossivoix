import AVFoundation

/// Synthèse vocale de l'app (AVSpeechSynthesizer), en français.
///
/// - Voix : voix française par défaut du système, débit par défaut.
/// - Avec VoiceOver : `prefersAssistiveTechnologySettings` reprend la voix et le débit
///   réglés dans VoiceOver, pour que l'app « parle comme » VoiceOver.
@MainActor
final class SynthesizerSpeechOutput: NSObject, SpeechOutput {
    private let synthesizer = AVSpeechSynthesizer()
    /// Phrase en cours et son attente associée.
    private var currentUtterance: ObjectIdentifier?
    private var continuation: CheckedContinuation<Void, Never>?

    /// Langue de toutes les phrases.
    static let language = "fr-FR"

    override init() {
        super.init()
        synthesizer.delegate = self
        // On utilise la session audio de l'app (voir AudioSessionManager).
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ text: String) async {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.language)
        utterance.prefersAssistiveTechnologySettings = true

        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.currentUtterance = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finish(currentUtterance)
    }

    /// Libère l'attente de la phrase indiquée, si c'est bien la phrase en cours.
    /// (Un « annulé » tardif d'une ancienne phrase ne doit pas débloquer la suivante.)
    private func finish(_ utterance: ObjectIdentifier?) {
        guard let utterance, utterance == currentUtterance else { return }
        currentUtterance = nil
        continuation?.resume()
        continuation = nil
    }
}

extension SynthesizerSpeechOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(id) }
    }
}
