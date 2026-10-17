import AVFoundation
import Speech
import DossivoixCore

/// Une session système, séparée des délais et autorisations pour tester les interruptions.
@MainActor
protocol SpeechRecognitionSession: AnyObject {
    var isAvailable: Bool { get }
    func start(_ kind: ListenKind, receive: @escaping @MainActor (String?, Bool, Bool) -> Void) throws
    func stop()
}

/// Écoutes courtes en français. Chaque écoute possède une génération : ni les autorisations,
/// ni les callbacks, ni les timers d'une ancienne écoute ne peuvent agir sur la suivante.
@MainActor
final class SpeechRecognitionInput: SpeechInput {
    private let session: SpeechRecognitionSession
    private let authorizeSpeech: @MainActor () async -> Bool
    private let authorizeMicrophone: @MainActor () async -> Bool
    private var generation = 0
    private var continuation: CheckedContinuation<ListenResult, Never>?
    private var latestText = ""
    private var silenceTimeout: Double = 1
    private var silenceTimer: Task<Void, Never>?
    private var deadlineTimer: Task<Void, Never>?

    init(
        session: SpeechRecognitionSession? = nil,
        authorizeSpeech: @escaping @MainActor () async -> Bool = {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        },
        authorizeMicrophone: @escaping @MainActor () async -> Bool = {
            await AVAudioApplication.requestRecordPermission()
        }
    ) {
        self.session = session ?? AppleSpeechRecognitionSession()
        self.authorizeSpeech = authorizeSpeech
        self.authorizeMicrophone = authorizeMicrophone
    }

    func listen(_ kind: ListenKind) async -> ListenResult {
        cancel()
        let current = generation
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return .silence }
            let speechAllowed = await authorizeSpeech()
            guard current == generation, !Task.isCancelled else { return .silence }
            guard speechAllowed else { return .unavailable }
            let microphoneAllowed = await authorizeMicrophone()
            guard current == generation, !Task.isCancelled else { return .silence }
            guard microphoneAllowed, session.isAvailable else { return .unavailable }

            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                latestText = ""
                let timing = kind.timing
                silenceTimeout = timing.silenceTimeout
                do {
                    try session.start(kind) { [weak self] text, isFinal, failed in
                        self?.received(text: text, isFinal: isFinal, failed: failed, generation: current)
                    }
                    guard current == generation else { return }
                    silenceTimer = timer(after: timing.initialTimeout, generation: current)
                    deadlineTimer = timer(after: timing.maxDuration, generation: current)
                } catch {
                    guard current == generation else { return }
                    Log.speech.error("Écoute impossible : \(error.localizedDescription)")
                    finish(.unavailable)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                self.cancel()
            }
        }
    }

    func cancel() { finish(.silence) }

    private func received(text: String?, isFinal: Bool, failed: Bool, generation current: Int) {
        guard current == generation, continuation != nil else { return }
        if let text, !text.isEmpty, text != latestText {
            latestText = text
            silenceTimer?.cancel()
            silenceTimer = timer(after: silenceTimeout, generation: current)
        }
        if isFinal || failed { finishWithLatestText() }
    }

    private func timer(after seconds: Double, generation current: Int) -> Task<Void, Never> {
        Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, current == self.generation, !Task.isCancelled else { return }
            self.finishWithLatestText()
        }
    }

    private func finishWithLatestText() {
        finish(latestText.isEmpty ? .silence : .text(latestText))
    }

    private func finish(_ result: ListenResult) {
        // Invalider les callbacks avant de demander l'annulation au framework.
        generation += 1
        let waiting = continuation
        continuation = nil
        silenceTimer?.cancel()
        deadlineTimer?.cancel()
        silenceTimer = nil
        deadlineTimer = nil
        session.stop()
        latestText = ""
        waiting?.resume(returning: result)
    }
}

/// Accès aux frameworks Apple. L'audio n'est pas enregistré par Dossivoix ; le service
/// peut traiter l'audio chez Apple si la reconnaissance sur l'appareil n'est pas disponible.
@MainActor
private final class AppleSpeechRecognitionSession: SpeechRecognitionSession {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasInputTap = false
    private struct Unavailable: Error {}

    var isAvailable: Bool { recognizer?.isAvailable == true }

    func start(_ kind: ListenKind, receive: @escaping @MainActor (String?, Bool, Bool) -> Void) throws {
        guard let recognizer else { throw Unavailable() }
        let request = SFSpeechAudioBufferRecognitionRequest()
        self.request = request
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        switch kind {
        case .name:
            request.taskHint = .dictation
        case .answer:
            request.taskHint = .confirmation
            request.contextualStrings = ["oui", "non", "recommencer", "annuler", "encore", "écrire", "remplacer"]
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Unavailable() }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        hasInputTap = true
        engine.prepare()
        try engine.start()
        task = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in receive(text, isFinal, failed) }
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        // Ne pas initialiser l'entrée audio avant que l'utilisateur autorise le micro.
        if hasInputTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
