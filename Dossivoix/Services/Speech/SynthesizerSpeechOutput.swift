import AVFoundation

/// Synthèse vocale de l'app (AVSpeechSynthesizer), en français.
///
/// - Voix : la meilleure voix française installée sur l'iPhone (premium, sinon améliorée,
///   sinon la voix par défaut), débit par défaut. Les voix améliorées et premium, bien plus
///   naturelles, se téléchargent gratuitement dans Réglages → Accessibilité → Contenu énoncé
///   → Voix → Français ; une app ne peut pas les télécharger elle-même.
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
        utterance.voice = Self.bestVoice()
        utterance.prefersAssistiveTechnologySettings = true

        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.currentUtterance = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
    }

    /// Meilleure voix française installée : premium, sinon améliorée, sinon la voix par défaut.
    /// Recherchée à chaque phrase, pour profiter d'une voix téléchargée pendant que l'app tourne.
    /// Les voix « fantaisie » et la Voix personnelle sont écartées.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let defaultVoice = AVSpeechSynthesisVoice(language: language)
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == language
                && !$0.voiceTraits.contains(.isNoveltyVoice)
                && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        for quality in [AVSpeechSynthesisVoiceQuality.premium, .enhanced] {
            let matches = candidates.filter { $0.quality == quality }
            // À qualité égale, on garde la voix par défaut du système si elle en fait partie.
            if let voice = matches.first(where: { $0.identifier == defaultVoice?.identifier }) ?? matches.first {
                return voice
            }
        }
        return defaultVoice
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
