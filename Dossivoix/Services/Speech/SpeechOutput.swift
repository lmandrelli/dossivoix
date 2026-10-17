/// Parole de l'app, derrière un protocole pour pouvoir la simuler.
@MainActor
protocol SpeechOutput: AnyObject {
    /// Prononce le texte et ne rend la main qu'une fois la phrase terminée (ou interrompue).
    /// Indispensable pour ne jamais ouvrir le micro pendant que l'app parle.
    func speak(_ text: String) async
    /// Coupe immédiatement la parole en cours.
    func stop()
}

/// Parole simulée : mémorise les phrases, sans aucun son.
final class SilentSpeechOutput: SpeechOutput {
    private(set) var spokenTexts: [String] = []

    func speak(_ text: String) async {
        spokenTexts.append(text)
    }

    func stop() {}
}
