import AVFoundation
import Speech
import DossivoixCore

/// Reconnaissance vocale en français (SFSpeechRecognizer), sur l'iPhone quand c'est possible.
///
/// - La fin de la réponse est détectée automatiquement : après un court silence suivant
///   la dernière parole (`ListenTiming.silenceTimeout`).
/// - Sans parole dans le délai initial, l'écoute s'arrête (`.silence`).
/// - Rien n'est enregistré : l'audio n'est utilisé que pendant l'écoute.
@MainActor
final class SpeechRecognitionInput: SpeechInput {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let engine = AVAudioEngine()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<ListenResult, Never>?
    /// Meilleur texte reconnu jusqu'ici.
    private var latestText = ""
    private var silenceTimeout: Double = 1
    private var silenceTimer: Task<Void, Never>?
    private var deadlineTimer: Task<Void, Never>?

    /// Mots attendus dans les réponses courtes : aident la reconnaissance.
    private static let answerHints = ["oui", "non", "recommencer", "annuler", "encore", "écrire", "remplacer"]

    func listen(_ kind: ListenKind) async -> ListenResult {
        cancel()
        guard await Self.isAuthorized(), let recognizer, recognizer.isAvailable else {
            return .unavailable
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            do {
                try start(kind, with: recognizer)
            } catch {
                Log.speech.error("Écoute impossible : \(error.localizedDescription)")
                finish(.unavailable)
            }
        }
    }

    func cancel() {
        finish(.silence)
    }

    // MARK: - Autorisations

    /// Demande (la première fois) l'autorisation de reconnaissance vocale puis celle du micro.
    private static func isAuthorized() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Écoute

    private struct NoMicrophone: Error {}

    private func start(_ kind: ListenKind, with recognizer: SFSpeechRecognizer) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        switch kind {
        case .name:
            request.taskHint = .dictation
        case .answer:
            request.taskHint = .confirmation
            request.contextualStrings = Self.answerHints
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw NoMicrophone() }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()

        self.request = request
        latestText = ""
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                self?.received(text: text, isFinal: isFinal, failed: failed)
            }
        }

        let timing = kind.timing
        silenceTimeout = timing.silenceTimeout
        // Personne ne parle : on arrête après le délai initial.
        silenceTimer = timer(after: timing.initialTimeout)
        // Durée maximale, même si la personne parle encore.
        deadlineTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timing.maxDuration))
            guard !Task.isCancelled else { return }
            self?.finishWithLatestText()
        }
    }

    private func received(text: String?, isFinal: Bool, failed: Bool) {
        guard continuation != nil else { return }
        if let text, !text.isEmpty, text != latestText {
            latestText = text
            // Nouvelle parole : le compte à rebours de silence repart de zéro.
            silenceTimer?.cancel()
            silenceTimer = timer(after: silenceTimeout)
        }
        if isFinal || failed {
            finishWithLatestText()
        }
    }

    private func timer(after seconds: Double) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finishWithLatestText()
        }
    }

    private func finishWithLatestText() {
        finish(latestText.isEmpty ? .silence : .text(latestText))
    }

    /// Arrête le micro et rend le résultat, une seule fois.
    private func finish(_ result: ListenResult) {
        silenceTimer?.cancel()
        deadlineTimer?.cancel()
        silenceTimer = nil
        deadlineTimer = nil
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
    }
}
