import DossivoixCore

/// Écoute de la voix, derrière un protocole pour pouvoir la simuler.
@MainActor
protocol SpeechInput: AnyObject {
    /// Écoute bornée : dictée à fin explicite, ou réponse courte. Une dictée coupée
    /// rend `.paused` avec la transcription reçue, sans valider le contenu.
    func listen(_ kind: ListenKind, onReady: @escaping @MainActor () async -> Void) async -> ListenResult
    /// Interrompt l'écoute en cours (son résultat devient `.silence`).
    var currentText: String { get }
    func finishDictation()
    func cancel()
}

extension SpeechInput {
    func listen(_ kind: ListenKind) async -> ListenResult {
        await listen(kind, onReady: {})
    }
    var currentText: String { "" }
    func finishDictation() {}
}

/// Écoute simulée : rend des réponses fixées à l'avance, puis du silence.
final class ScriptedSpeechInput: SpeechInput {
    private var answers: [ListenResult]

    init(answers: [ListenResult]) {
        self.answers = answers
    }

    func listen(_ kind: ListenKind, onReady: @escaping @MainActor () async -> Void) async -> ListenResult {
        await onReady()
        guard !Task.isCancelled else { return .silence }
        try? await Task.sleep(for: .milliseconds(2500)) // durée réaliste d'une réponse
        return answers.isEmpty ? .silence : answers.removeFirst()
    }

    func cancel() {}
}
