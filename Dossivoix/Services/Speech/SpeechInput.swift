import DossivoixCore

/// Écoute de la voix, derrière un protocole pour pouvoir la simuler.
@MainActor
protocol SpeechInput: AnyObject {
    /// Écoute courte (jamais permanente) : rend le texte reconnu, `.silence` si rien n'a été dit
    /// dans le délai, ou `.unavailable` si le micro ou la reconnaissance ne sont pas autorisés.
    func listen(_ kind: ListenKind) async -> ListenResult
    /// Interrompt l'écoute en cours (son résultat devient `.silence`).
    func cancel()
}

/// Écoute simulée : rend des réponses fixées à l'avance, puis du silence.
final class ScriptedSpeechInput: SpeechInput {
    private var answers: [ListenResult]

    init(answers: [ListenResult]) {
        self.answers = answers
    }

    func listen(_ kind: ListenKind) async -> ListenResult {
        try? await Task.sleep(for: .milliseconds(600))
        return answers.isEmpty ? .silence : answers.removeFirst()
    }

    func cancel() {}
}
