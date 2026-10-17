import UIKit

/// Réglages de la cohabitation avec VoiceOver, à ajuster après les essais sur iPhone.
enum VoiceSettings {
    /// Avec VoiceOver actif :
    /// - false (par défaut) : l'app parle elle-même, avec la voix et le débit de VoiceOver.
    ///   Fin de phrase fiable, donc enchaînement parole → écoute fiable.
    /// - true : l'app confie ses phrases à VoiceOver (annonces). À essayer en cas de conflit.
    static let usesVoiceOverAnnouncements = false

    /// Avec VoiceOver actif, la feuille NFC d'iOS est déjà lue par VoiceOver :
    /// on ne répète pas « Approchez l'étiquette » pour éviter deux voix en même temps.
    static let skipsApproachPromptWithVoiceOver = true
}

/// Choisit, à chaque phrase, entre la synthèse de l'app et les annonces VoiceOver,
/// selon que VoiceOver est actif ou non à ce moment-là.
@MainActor
final class AdaptiveSpeechOutput: SpeechOutput {
    private let synthesizer: SpeechOutput
    private let announcer: SpeechOutput
    private let isVoiceOverRunning: @MainActor () -> Bool

    init(
        synthesizer: SpeechOutput,
        announcer: SpeechOutput,
        isVoiceOverRunning: @escaping @MainActor () -> Bool
    ) {
        self.synthesizer = synthesizer
        self.announcer = announcer
        self.isVoiceOverRunning = isVoiceOverRunning
    }

    /// Version réelle : synthèse de l'app et annonces VoiceOver.
    static func live() -> AdaptiveSpeechOutput {
        AdaptiveSpeechOutput(
            synthesizer: SynthesizerSpeechOutput(),
            announcer: VoiceOverAnnouncer(),
            isVoiceOverRunning: { UIAccessibility.isVoiceOverRunning }
        )
    }

    private var current: SpeechOutput {
        VoiceSettings.usesVoiceOverAnnouncements && isVoiceOverRunning() ? announcer : synthesizer
    }

    func speak(_ text: String) async {
        await current.speak(text)
    }

    func stop() {
        synthesizer.stop()
        announcer.stop()
    }
}
